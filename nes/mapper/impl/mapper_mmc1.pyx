from libc.stdint cimport uint8_t, uint16_t, UINT32_MAX
import numpy as np
cimport numpy as np

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping
from nes.mapper.mirror cimport HORIZONTAL, VERTICAL, ONESCREEN_LO, ONESCREEN_HI


cdef class MapperMMC1(Mapper):
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "001"

        self.RAM_static = np.zeros(32768).astype(np.uint8)
        self.CHR_bank_select_4_lo, self.CHR_bank_select_4_hi, self.CHR_bank_select_8 = 0x00, 0x00, 0x00
        self.PRG_bank_select_16_lo, self.PRG_bank_select_16_hi, self.PRG_bank_select_32 = 0x00, 0x00, 0x00
        self.load_register, self.load_register_count, self.control_register = 0x00, 0x00, 0x00  
        self.mirrormode = HORIZONTAL

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
        cdef CPUReadMapping mapping = CPUReadMapping()

        if 0x6000 <= addr <= 0x7FFF:
            mapping.success = True
            mapping.addr = UINT32_MAX
            mapping.data = self.RAM_static[addr & 0x1FFF]
        if addr >= 0x8000:
            if self.control_register & 0b01000 != 0:
                if 0x8000 <= addr <= 0xBFFF:
                    mapping.success = True
                    mapping.addr = self.PRG_bank_select_16_lo * 0x4000 + (addr & 0x3FFF)
                if 0xC000 <= addr <= 0xFFFF:
                    mapping.success = True
                    mapping.addr = self.PRG_bank_select_16_hi * 0x4000 + (addr & 0x3FFF)
            else:
                mapping.success = True
                mapping.addr = self.PRG_bank_select_32 * 0x8000 + (addr & 0x7FFF)
        return mapping
    
    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef CPUWriteMapping mapping = CPUWriteMapping()

        if 0x6000 <= addr <= 0x7FFF:
            mapping.success = True
            mapping.addr = UINT32_MAX
            self.RAM_static[addr & 0x1FFF] = data 
        if addr >= 0x8000:
            if data & 0x80 != 0:
                self.load_register = 0x00
                self.load_register_count = 0
                self.control_register = self.control_register | 0x0C
            else:
                self.load_register >>= 1
                self.load_register |= (data & 0x01) << 4
                self.load_register_count += 1
                if self.load_register_count == 5:
                    target_register = (addr >> 13) & 0x03
                    if target_register == 0:
                        self.control_register = self.load_register & 0x1F
                        switch = self.control_register & 0x03
                        if switch == 0:
                            self.mirrormode = ONESCREEN_LO
                        elif switch == 1:
                            self.mirrormode = ONESCREEN_HI
                        elif switch == 2:
                            self.mirrormode = VERTICAL
                        elif switch == 3:
                            self.mirrormode = HORIZONTAL
                    elif target_register == 1:
                        if self.control_register & 0b10000 != 0:
                            self.CHR_bank_select_4_lo = self.load_register & 0x1F
                        else:
                            self.CHR_bank_select_8 = self.load_register & 0x1E
                    elif target_register == 2:
                        if self.control_register & 0b10000 != 0:
                            self.CHR_bank_select_4_hi = self.load_register & 0x1F
                    elif target_register == 3:
                        PRG_mode = (self.control_register >> 2) & 0x03
                        if PRG_mode == 0 or PRG_mode == 1:
                            self.PRG_bank_select_32 = (self.load_register & 0x0E) >> 1
                        elif PRG_mode == 2:
                            self.PRG_bank_select_16_lo = 0
                            self.PRG_bank_select_16_hi = self.load_register & 0x0F
                        elif PRG_mode == 3:
                            self.PRG_bank_select_16_lo = self.load_register & 0x0F
                            self.PRG_bank_select_16_hi = self.PRG_banks - 1
                    self.load_register = 0x00
                    self.load_register_count = 0
        return mapping                     

    cdef PPUReadMapping mapReadByPPU(self, uint16_t addr):
        cdef PPUReadMapping mapping = PPUReadMapping()

        if addr < 0x2000:
            if self.CHR_banks == 0:
                mapping.success = True
                mapping.addr = addr
            else:
                if self.control_register & 0b10000 > 0:
                    if 0x0000 <= addr <= 0x0FFF:
                        mapping.success = True
                        mapping.addr = self.CHR_bank_select_4_lo * 0x1000 + addr & 0x0FFF
                    if 0x1000 <= addr <= 0x1FFF:
                        mapping.success = True
                        mapping.addr = self.CHR_bank_select_4_hi * 0x1000 + addr & 0x0FFF
                else:
                    mapping.success = True
                    mapping.addr = self.CHR_bank_select_8 * 0x2000 + addr & 0x1FFF
        return mapping
        
    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t addr):
        cdef PPUWriteMapping mapping = PPUWriteMapping()

        if addr < 0x2000:
            mapping.success = True
            if self.CHR_banks == 0:
                mapping.addr = addr
        return mapping
        
    cdef void reset(self):
        self.control_register, self.load_register, self.load_register_count = 0x1C, 0x00, 0x00 
        self.CHR_bank_select_4_lo, self.CHR_bank_select_4_hi, self.CHR_bank_select_8, = 0x00, 0x00, 0x00
        self.PRG_bank_select_32, self.PRG_bank_select_16_lo, self.PRG_bank_select_16_hi = 0x00, 0x00, self.PRG_banks - 1

    cdef uint8_t mirror(self):
        return self.mirrormode
