import numpy as np
cimport numpy as np

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HORIZONTAL, VERTICAL


cdef class MapperMMC3(Mapper):
    """
    MMC3 mapper (mapper 4 /TxROM).
    
    Feature-rich mapper with 6-bit PRG bank select, 8-channel CHR banking,
    scanline-based IRQ generation, and multiple mirroring options.
    """
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "004"
        
        self.target_register = 0x00  
        self.PRG_bank_mode = False
        self.CHR_inversion = False
        self.mirrormode = HORIZONTAL

        self.register = [0,0,0,0,0,0,0,0]
        self.CHR_bank = [0,0,0,0,0,0,0,0]
        self.PRG_bank = [0,0,0,0]

        self.IRQ_active = False
        self.IRQ_enable = False
        self.IRQ_update = False
        self.IRQ_counter = 0x0000
        self.IRQ_reload = 0x0000
        self.a12_prev = 0

        self.RAM_static = np.zeros(32 * 1024).astype(np.uint8)

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
        """Map CPU read to PRG ROM or SRAM."""
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x6000 <= addr <= 0x7FFF:
            mapping.success = True
            mapping.addr = 0xFFFFFFFF
            mapping.data = self.RAM_static[addr & 0x1FFF]
        if 0x8000 <= addr <= 0x9FFF:
            mapping.success = True
            mapping.addr = self.PRG_bank[0] + (addr & 0x1FFF)
        if 0xA000 <= addr <= 0xBFFF:
            mapping.success = True
            mapping.addr = self.PRG_bank[1] + (addr & 0x1FFF)
        if 0xC000 <= addr <= 0xDFFF:
            mapping.success = True
            mapping.addr = self.PRG_bank[2] + (addr & 0x1FFF)
        if 0xE000 <= addr <= 0xFFFF:
            mapping.success = True
            mapping.addr = self.PRG_bank[3] + (addr & 0x1FFF)
        return mapping

    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x6000 <= addr <= 0x7FFF:
            mapping.success = True
            mapping.addr = 0xFFFFFFFF
            self.RAM_static[addr & 0x1FFF] = data
        if 0x8000 <= addr <= 0x9FFF:
            if addr & 0x0001 == 0:
                self.target_register = data & 0x07
                self.PRG_bank_mode = data & 0x40
                self.CHR_inversion = data & 0x80
            else:
                self.register[self.target_register] = data
                if self.CHR_inversion > 0:
                    self.CHR_bank[0] = self.register[2] * 0x0400
                    self.CHR_bank[1] = self.register[3] * 0x0400
                    self.CHR_bank[2] = self.register[4] * 0x0400
                    self.CHR_bank[3] = self.register[5] * 0x0400
                    self.CHR_bank[4] = (self.register[0] & 0xFE) * 0x0400
                    self.CHR_bank[5] = self.register[0] * 0x0400 + 0x0400
                    self.CHR_bank[6] = (self.register[1] & 0xFE) * 0x0400
                    self.CHR_bank[7] = self.register[1] * 0x0400 + 0x0400
                else:
                    self.CHR_bank[0] = (self.register[0] & 0xFE) * 0x0400
                    self.CHR_bank[1] = self.register[0] * 0x0400 + 0x0400
                    self.CHR_bank[2] = (self.register[1] & 0xFE) * 0x0400
                    self.CHR_bank[3] = self.register[1] * 0x0400 + 0x0400
                    self.CHR_bank[4] = self.register[2] * 0x0400
                    self.CHR_bank[5] = self.register[3] * 0x0400
                    self.CHR_bank[6] = self.register[4] * 0x0400
                    self.CHR_bank[7] = self.register[5] * 0x0400
        
                if self.PRG_bank_mode > 0:
                    self.PRG_bank[2] = (self.register[6] & 0x3F) * 0x2000
                    self.PRG_bank[0] = (self.PRG_banks * 2 - 2) * 0x2000
                else:
                    self.PRG_bank[0] = (self.register[6] & 0x3F) * 0x2000
                    self.PRG_bank[2] = (self.PRG_banks * 2 - 2) * 0x2000  
                self.PRG_bank[1] = (self.register[7] & 0x3F) * 0x2000
                self.PRG_bank[3] = (self.PRG_banks * 2 - 1) * 0x2000
        if 0xA000 <= addr <= 0xBFFF:
            if addr & 0x0001 == 0:
                if data & 0x01 > 0:
                    self.mirrormode = HORIZONTAL
                else:
                    self.mirrormode = VERTICAL
        if 0xC000 <= addr <= 0xDFFF:
            if addr & 0x0001 == 0:
                self.IRQ_reload = data
            else:
                self.IRQ_counter = 0x0000
        if 0xE000 <= addr <= 0xFFFF:
            if addr & 0x0001 == 0:
                self.IRQ_enable = False
                self.IRQ_active = False
            else:
                self.IRQ_enable = True

        return mapping

    cdef PPUReadMapping mapReadByPPU(self, uint16_t addr):
        cdef PPUReadMapping mapping = PPUReadMapping()

        # MMC3 IRQ is clocked by a rising edge of the PPU A12 address line,
        # not by scanlines. Detect that edge here: every PPU bus access
        # (CHR/nametable/VRAM fetches and $2007 accesses) flows through this
        # method with the full PPU address, so A12 is observable.
        self.a12_notify(addr)

        if 0x0000 <= addr <= 0x03FF:
            mapping.success = True
            mapping.addr = self.CHR_bank[0] + (addr & 0x03FF)
        if 0x0400 <= addr <= 0x07FF:
            mapping.success = True
            mapping.addr = self.CHR_bank[1] + (addr & 0x03FF)
        if 0x0800 <= addr <= 0x0BFF:
            mapping.success = True
            mapping.addr = self.CHR_bank[2] + (addr & 0x03FF)
        if 0x0C00 <= addr <= 0x0FFF:
            mapping.success = True
            mapping.addr = self.CHR_bank[3] + (addr & 0x03FF)
        if 0x1000 <= addr <= 0x13FF:
            mapping.success = True
            mapping.addr = self.CHR_bank[4] + (addr & 0x03FF)
        if 0x1400 <= addr <= 0x17FF:
            mapping.success = True
            mapping.addr = self.CHR_bank[5] + (addr & 0x03FF)
        if 0x1800 <= addr <= 0x1BFF:
            mapping.success = True
            mapping.addr = self.CHR_bank[6] + (addr & 0x03FF)
        if 0x1C00 <= addr <= 0x1FFF:
            mapping.success = True
            mapping.addr = self.CHR_bank[7] + (addr & 0x03FF)

        return mapping

    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t addr):
        cdef PPUWriteMapping mapping = PPUWriteMapping()
        # Same A12 edge detection as the read path (covers $2007 writes).
        self.a12_notify(addr)
        return mapping

    cdef void reset(self):
        self.target_register = 0x00
        self.PRG_bank_mode = False
        self.CHR_inversion = False
        self.mirrormode = HORIZONTAL

        self.IRQ_active = False
        self.IRQ_enable = False
        self.IRQ_update = False
        self.IRQ_counter = 0x0000
        self.IRQ_reload = 0x0000
        self.a12_prev = 0

        for i in range(4):
            self.PRG_bank[i] = 0
        for i in range(8):
            self.CHR_bank[i] = 0
            self.register[i] = 0

        self.PRG_bank[0] = 0 * 0x2000
        self.PRG_bank[1] = 1 * 0x2000
        self.PRG_bank[2] = (self.PRG_banks * 2 - 2) * 0x2000
        self.PRG_bank[3] = (self.PRG_banks * 2 - 1) * 0x2000

    cdef uint8_t mirror(self):
        return self.mirrormode  

    cdef bint IRQ_state(self):
        return self.IRQ_active

    cdef void IRQ_clear(self):
        self.IRQ_active = False

    cdef void a12_notify(self, uint16_t addr):
        # MMC3 IRQ counter is clocked on the rising edge of the (filtered) PPU
        # A12 line. A12 is bit 12 of the CHR/pattern address bus ($0000-$1FFF).
        #
        # The MMC3's A12 input is the *cartridge CHR address* line, so only
        # pattern-range accesses ($0000-$1FFF) drive it. Nametable/attribute/
        # VRAM accesses ($2000+) are PPU-internal and are ignored here. This is
        # exactly the effect of the hardware A12 filter (which keeps A12 "low"
        # through all nametable/BG fetches and lets it rise once per scanline
        # during sprite fetches), yielding ~241 clocks per frame instead of
        # dozens of spurious edges.
        #
        # Manual clocking via $2006/$2007 (blargg mmc3_irq_tests) also reaches
        # this hook: writing $2006 changes VRAM_addr and the PPU presents its
        # bit 12 on the bus, so a 0->1 transition here clocks the counter.
        if addr >= 0x2000:
            return
        cdef bint a12 = (addr >> 12) & 0x01
        if a12 and not self.a12_prev:
            self._clock_irq()
        self.a12_prev = a12

    cdef void _clock_irq(self):
        # MMC3 (Sharp / "normal" revision) counter model:
        #   - if counter == 0 -> reload from the $C000 latch value
        #   - otherwise      -> decrement
        #   - if counter == 0 and IRQs enabled ($E001) -> assert the IRQ line
        if self.IRQ_counter == 0:
            self.IRQ_counter = self.IRQ_reload
        else:
            self.IRQ_counter -= 1
        if self.IRQ_counter == 0 and self.IRQ_enable:
            self.IRQ_active = True