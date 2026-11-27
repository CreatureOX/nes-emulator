from libc.stdint cimport uint8_t, uint16_t, uint32_t
import numpy as np
cimport numpy as np

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HORIZONTAL, VERTICAL


cdef class MapperRambo1(Mapper):
    """
    Tengen RAMBO-1 mapper (mapper 64).

    Three 8 KiB switchable PRG windows plus a fixed last bank; CHR is either
    the MMC3 2 KiB/1 KiB layout, eight independent 1 KiB banks, or either of
    those with the two halves swapped. The IRQ counter runs from PPU A12
    edges or from a 4-CPU-cycle prescaler. No PRG RAM or bus conflict.
    Ref: NESdev wiki "RAMBO-1", Banks, Registers and IRQ counter operation.
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        # The base constructor calls reset(), so the register file must exist
        # before the banks are published to it.
        self.reg = np.zeros(16, dtype=np.uint8)
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "064"

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        """Resolve three 8 KiB PRG windows and the fixed reset vector bank."""
        cdef CPUReadMapping mapping = CPUReadMapping()
        cdef uint32_t pages = self.PRG_banks * 2
        cdef uint32_t page
        cdef uint8_t slot

        if pages == 0 or addr < 0x8000:
            return mapping
        slot = (addr - 0x8000) >> 13
        if slot == 3:
            page = pages - 1
        elif (self.bank_select & 0x40) == 0:
            if slot == 0:
                page = self.reg[6]
            elif slot == 1:
                page = self.reg[7]
            else:
                page = self.reg[0x0F]
        elif slot == 0:
            page = self.reg[0x0F]
        elif slot == 1:
            page = self.reg[6]
        else:
            page = self.reg[7]
        mapping.success = True
        mapping.addr = (page % pages) * 0x2000 + (addr & 0x1FFF)
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        """Decode bank select/data, mirroring, and the two IRQ mode registers."""
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if addr < 0x8000:
            return mapping
        if addr <= 0x9FFF:
            if (addr & 1) == 0:
                self.bank_select = data
            else:
                self.reg[self.bank_select & 0x0F] = data
        elif addr <= 0xBFFF:
            if (addr & 1) == 0:
                self.mirroring = HORIZONTAL if (data & 1) else VERTICAL
        elif addr <= 0xDFFF:
            if (addr & 1) == 0:
                self.irq_latch = data
            else:
                self.irq_cycle_mode = (data & 1) != 0
                self.irq_counter = 0
                self.irq_reload_request = True
                self.prescaler = 0
        elif (addr & 1) == 0:
            self.irq_enabled = False
            self.irq_pending = False
        else:
            self.irq_enabled = True
        return mapping

    cdef uint8_t _chr_bank(self, uint16_t addr):
        """Pick the register feeding one 1 KiB CHR window."""
        cdef uint8_t window = (addr >> 10) & 0x07
        cdef bint inverted = (self.bank_select & 0x80) != 0
        cdef bint full_1k = (self.bank_select & 0x20) != 0

        if not inverted:
            if window == 0:
                return self.reg[0] if full_1k else (self.reg[0] & 0xFE)
            if window == 1:
                return self.reg[8] if full_1k else ((self.reg[0] & 0xFE) | 1)
            if window == 2:
                return self.reg[1] if full_1k else (self.reg[1] & 0xFE)
            if window == 3:
                return self.reg[9] if full_1k else ((self.reg[1] & 0xFE) | 1)
            return self.reg[window - 2]
        if window < 4:
            return self.reg[window + 2]
        if window == 4:
            return self.reg[0] if full_1k else (self.reg[0] & 0xFE)
        if window == 5:
            return self.reg[8] if full_1k else ((self.reg[0] & 0xFE) | 1)
        if window == 6:
            return self.reg[1] if full_1k else (self.reg[1] & 0xFE)
        return self.reg[9] if full_1k else ((self.reg[1] & 0xFE) | 1)

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        """Clock A12 in scanline mode, then translate one CHR window."""
        cdef PPUReadMapping mapping = PPUReadMapping()
        cdef uint32_t chr_banks = self.CHR_banks * 8

        self.a12_notify(addr)
        if addr >= 0x2000:
            return mapping
        mapping.success = True
        if chr_banks == 0:
            mapping.addr = addr
        else:
            mapping.addr = (self._chr_bank(addr) % chr_banks) * 0x0400 + (addr & 0x03FF)
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        """Allow CHR RAM boards; RAMBO-1 carts otherwise carry CHR ROM."""
        cdef PPUWriteMapping mapping = PPUWriteMapping()
        self.a12_notify(addr)
        if self.CHR_banks == 0:
            mapping.success = True
            mapping.addr = addr
        return mapping

    cdef void a12_notify(self, uint16_t addr):
        """A12 rises once per rendered scanline on the pattern address bus."""
        cdef bint a12
        if addr >= 0x2000:
            return
        a12 = ((addr >> 12) & 1) != 0
        if a12 and not self.a12_prev and not self.irq_cycle_mode:
            self._clock_irq()
        self.a12_prev = a12

    cdef void audio_clock(self, int cycles):
        """The APU clocks every CPU cycle; RAMBO-1 divides by four here."""
        if not self.irq_cycle_mode:
            return
        self.prescaler += 1
        if self.prescaler >= 4:
            self.prescaler = 0
            self._clock_irq()

    cdef void _clock_irq(self):
        """A write to $C001 forces a reload before the normal counter rules."""
        if self.irq_reload_request:
            self.irq_counter = self.irq_latch
            self.irq_reload_request = False
        elif self.irq_counter == 0:
            self.irq_counter = self.irq_latch
        else:
            self.irq_counter -= 1
        if self.irq_counter == 0 and self.irq_enabled:
            self.irq_pending = True

    cdef void reset(self):
        """Power-on: mode 0 windows, RF on the penultimate bank, IRQ masked."""
        cdef uint32_t last = self.PRG_banks * 2
        cdef int i

        self.bank_select = 0
        for i in range(16):
            self.reg[i] = 0
        if last > 0:
            self.reg[0x0F] = last - 2 if last >= 2 else 0
        self.mirroring = VERTICAL
        self.irq_latch = 0
        self.irq_counter = 0
        self.irq_enabled = False
        self.irq_pending = False
        self.irq_reload_request = False
        self.irq_cycle_mode = False
        self.prescaler = 0
        self.a12_prev = 0

    cdef uint8_t mirror(self):
        return self.mirroring

    cdef bint irq_line(self):
        return self.irq_pending
