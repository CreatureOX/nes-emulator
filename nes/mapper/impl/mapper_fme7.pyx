from libc.stdint cimport uint8_t, uint16_t, uint32_t, UINT32_MAX
import numpy as np
cimport numpy as np

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HORIZONTAL, VERTICAL, ONESCREEN_LO, ONESCREEN_HI


cdef class MapperFME7(Mapper):
    """
    Sunsoft FME-7 mapper (mapper 69, 5A/5B without expansion audio).

    A command byte at $8000-$9FFF selects one of sixteen parameter slots
    written at $A000-$BFFF: eight 1 KiB CHR banks, four 8 KiB PRG banks,
    nametable arrangement and a 16-bit CPU-cycle IRQ countdown. Slot $08
    can route $6000-$7FFF to the board's 8 KiB PRG RAM. No bus conflict.
    Ref: NESdev wiki "Sunsoft FME-7", Registers, Commands and IRQ Operation.
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        # The base constructor calls reset(), so both register files must
        # exist before the banks are published to them.
        self.reg = np.zeros(16, dtype=np.uint8)
        self.RAM_static = np.zeros(0x2000, dtype=np.uint8)
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "069"

    cdef object sram(self):
        '''Battery-backed 8 KB PRG RAM at $6000-$7FFF.'''
        return np.asarray(self.RAM_static)

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr):
        """Resolve the $6000 ROM/RAM slot, three PRG windows and a fixed tail."""
        cdef CPUReadMapping mapping = CPUReadMapping()
        cdef uint32_t pages = self.PRG_banks * 2
        cdef uint8_t slot
        cdef uint32_t bank

        if addr < 0x6000:
            return mapping
        if addr <= 0x7FFF:
            slot = self.reg[8]
            if (slot & 0x40) != 0:
                if (slot & 0x80) != 0:
                    mapping.success = True
                    mapping.addr = UINT32_MAX
                    mapping.data = self.RAM_static[
                        ((slot & 0x1F) * 0x2000 + (addr - 0x6000)) & 0x1FFF]
                return mapping
            bank = slot & 0x1F
        elif addr <= 0x9FFF:
            bank = self.reg[9]
        elif addr <= 0xBFFF:
            bank = self.reg[0x0A]
        elif addr <= 0xDFFF:
            bank = self.reg[0x0B]
        else:
            bank = pages - 1
        if pages == 0:
            return mapping
        mapping.success = True
        mapping.addr = (bank % pages) * 0x2000 + (addr & 0x1FFF)
        return mapping

    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data):
        """Write PRG RAM or invoke the selected command with a parameter."""
        cdef CPUWriteMapping mapping = CPUWriteMapping()
        cdef uint8_t slot

        if addr < 0x6000:
            return mapping
        if addr <= 0x7FFF:
            slot = self.reg[8]
            if (slot & 0x40) != 0 and (slot & 0x80) != 0:
                mapping.success = True
                mapping.addr = UINT32_MAX
                self.RAM_static[
                    ((slot & 0x1F) * 0x2000 + (addr - 0x6000)) & 0x1FFF] = data
            return mapping
        if addr <= 0x9FFF:
            self.command = data & 0x0F
            return mapping
        if addr > 0xBFFF:
            return mapping

        self.reg[self.command] = data
        if self.command == 0x0C:
            # Ref: NESdev wiki "Sunsoft FME-7", Nametable Arrangement.
            if (data & 0x03) == 0:
                self.mirroring = VERTICAL
            elif (data & 0x03) == 1:
                self.mirroring = HORIZONTAL
            elif (data & 0x03) == 2:
                self.mirroring = ONESCREEN_LO
            else:
                self.mirroring = ONESCREEN_HI
        elif self.command == 0x0D:
            # Every write to the IRQ control command acknowledges a pending
            # IRQ before the new enable bits take effect.
            self.irq_pending = False
            self.irq_enabled = (data & 0x01) != 0
            self.irq_counter_enabled = (data & 0x80) != 0
        elif self.command == 0x0E:
            self.irq_counter = (self.irq_counter & 0xFF00) | data
        elif self.command == 0x0F:
            self.irq_counter = (self.irq_counter & 0x00FF) | (<uint16_t>data << 8)
        return mapping

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr):
        """Translate one 1 KiB CHR window."""
        cdef PPUReadMapping mapping = PPUReadMapping()
        cdef uint32_t chr_banks = self.CHR_banks * 8

        if addr >= 0x2000:
            return mapping
        mapping.success = True
        if chr_banks == 0:
            mapping.addr = addr
        else:
            mapping.addr = (self.reg[(addr >> 10) & 0x07] % chr_banks) * 0x0400 + (addr & 0x03FF)
        return mapping

    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr):
        """Allow CHR RAM boards; FME-7 carts otherwise carry CHR ROM."""
        cdef PPUWriteMapping mapping = PPUWriteMapping()
        if self.CHR_banks == 0:
            mapping.success = True
            mapping.addr = addr
        return mapping

    cdef void audio_clock(self, int cycles):
        """A 16-bit counter decrements once per CPU cycle and wraps into IRQ."""
        if not self.irq_counter_enabled:
            return
        if self.irq_counter == 0:
            self.irq_pending = True
        self.irq_counter -= 1

    cdef void reset(self):
        """Power-on: bank 0 windows, vertical nametables, IRQ masked."""
        cdef int i
        self.command = 0
        for i in range(16):
            self.reg[i] = 0
        self.mirroring = VERTICAL
        self.irq_counter = 0
        self.irq_enabled = False
        self.irq_counter_enabled = False
        self.irq_pending = False

    cdef uint8_t mirror(self):
        return self.mirroring

    cdef bint irq_line(self):
        # Command $D bit 0 is the CPU-facing IRQ enable; the counter may keep
        # running while the line is masked.
        return self.irq_pending and self.irq_enabled
