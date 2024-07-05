import numpy as np
cimport numpy as np

from mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping
from mirror cimport HORIZONTAL, VERTICAL


cdef class MapperMMC3(Mapper):
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

        self.RAM_static = np.zeros(32 * 1024).astype(np.uint8)

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
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

    cdef void scanline(self):
        if self.IRQ_counter == 0:
            self.IRQ_counter = self.IRQ_reload
        else:
            self.IRQ_counter -= 1
        if self.IRQ_counter == 0 and self.IRQ_enable:
            self.IRQ_active = True
