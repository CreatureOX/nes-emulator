from libc.stdint cimport uint8_t, uint16_t, uint32_t, UINT32_MAX
import numpy as np
cimport numpy as np

from mirror cimport *


cdef class Mapper:
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        self.PRG_banks = PRG_banks
        self.CHR_banks = CHR_banks

        self.reset()

    @staticmethod
    def instance(PRG_banks: uint8_t, CHR_banks: uint8_t):
        return Mapper(PRG_banks, CHR_banks)

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        pass

    cdef (bint, uint32_t) mapWriteByCPU(self, addr: uint16_t, data: uint8_t):
        pass

    cdef (bint, uint32_t) mapReadByPPU(self, addr: uint16_t):
        pass

    cdef (bint, uint32_t) mapWriteByPPU(self, addr: uint16_t):
        pass

    cdef void reset(self):
        pass

    cdef uint8_t mirror(self):
        return HARDWARE

    cdef bint IRQ_state(self):
        return False

    cdef void IRQ_clear(self):
        pass

    cdef void scanline(self):
        pass

cdef class MapperNROM(Mapper):
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "000"

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        if 0x8000 <= addr <= 0xFFFF:
            return (True, addr & (0x7FFF if self.PRG_banks > 1 else 0x3FFF), 0)
        return (False, addr, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        if 0x8000 <= addr <= 0xFFFF:
            return (True, addr & (0x7FFF if self.PRG_banks > 1 else 0x3FFF))
        return (False, addr)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        if 0x0000 <= addr <= 0x1FFF:
            return (True, addr)
        return (False, addr)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        if 0x0000 <= addr <= 0x1FFF:
            if self.CHR_banks == 0:
                return (True, addr)
        return (False, addr)

cdef class MapperMMC1(Mapper):

    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "001"

        self.RAM_static = np.zeros(32768).astype(np.uint8)
        self.CHR_bank_select_4_lo, self.CHR_bank_select_4_hi, self.CHR_bank_select_8 = 0x00, 0x00, 0x00
        self.PRG_bank_select_16_lo, self.PRG_bank_select_16_hi, self.PRG_bank_select_32 = 0x00, 0x00, 0x00
        self.load_register, self.load_register_count, self.control_register = 0x00, 0x00, 0x00  
        self.mirrormode = HORIZONTAL

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if 0x6000 <= addr <= 0x7FFF:
            mapped_addr = UINT32_MAX
            data = self.RAM_static[addr & 0x1FFF]
            return (True, mapped_addr, data)
        if addr >= 0x8000:
            if self.control_register & 0b01000 != 0:
                if 0x8000 <= addr <= 0xBFFF:
                    mapped_addr = self.PRG_bank_select_16_lo * 0x4000 + (addr & 0x3FFF)
                    return (True, mapped_addr, 0)
                if 0xC000 <= addr <= 0xFFFF:
                    mapped_addr = self.PRG_bank_select_16_hi * 0x4000 + (addr & 0x3FFF)
                    return (True, mapped_addr, 0)
            else:
                mapped_addr = self.PRG_bank_select_32 * 0x8000 + (addr & 0x7FFF)
                return (True, mapped_addr, 0)
        return (False, 0, 0)
    
    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef uint8_t target_register, PRG_mode, switch
        cdef uint32_t mapped_addr

        if 0x6000 <= addr <= 0x7FFF:
            mapped_addr = UINT32_MAX
            self.RAM_static[addr & 0x1FFF] = data 
            return (True, mapped_addr)
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
        return (False, 0)                       

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        if addr < 0x2000:
            if self.CHR_banks == 0:
                return (True, addr)
            else:
                if self.control_register & 0b10000 > 0:
                    if 0x0000 <= addr <= 0x0FFF:
                        return (True, self.CHR_bank_select_4_lo * 0x1000 + addr & 0x0FFF)
                    if 0x1000 <= addr <= 0x1FFF:
                        return (True, self.CHR_bank_select_4_hi * 0x1000 + addr & 0x0FFF)
                else:
                    return (True, self.CHR_bank_select_8 * 0x2000 + addr & 0x1FFF)
        else:
            return (False, 0x00)
        
    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        if addr < 0x2000:
            if self.CHR_banks == 0:
                return (True, addr)
            return (True, 0)
        else:
            return (False, 0)
        
    cdef void reset(self):
        self.control_register, self.load_register, self.load_register_count = 0x1C, 0x00, 0x00 
        self.CHR_bank_select_4_lo, self.CHR_bank_select_4_hi, self.CHR_bank_select_8, = 0x00, 0x00, 0x00
        self.PRG_bank_select_32, self.PRG_bank_select_16_lo, self.PRG_bank_select_16_hi = 0x00, 0x00, self.PRG_banks - 1

    cdef uint8_t mirror(self):
        return self.mirrormode

cdef class MapperUxROM(Mapper):
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "002"

        self.PRG_bank_select_lo, self.PRG_bank_select_hi = 0x00, 0x00

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if addr >= 0x8000 and addr <= 0xBFFF:
            mapped_addr = self.PRG_bank_select_lo * 0x4000 + (addr & 0x3FFF)
            return (True, mapped_addr, 0)
        if addr >= 0xC000 and addr <= 0xFFFF:
            mapped_addr = self.PRG_bank_select_hi * 0x4000 + (addr & 0x3FFF)
            return (True, mapped_addr, 0)
        return (False, 0, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        if addr >= 0x8000 and addr <= 0xFFFF:
            self.PRG_bank_select_lo = data & 0x0F
        return (False, 0)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        if addr < 0x2000:
            return (True, addr)
        return (False, addr)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        if addr < 0x2000:
            if self.CHR_banks == 0:
                return (True, addr)
        return (False, addr)

    cdef void reset(self):
        self.PRG_bank_select_lo, self.PRG_bank_select_hi = 0, self.PRG_banks - 1

cdef class MapperINES003(Mapper):
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "003"
        
        self.CHR_bank_select = 0x00    

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if addr >= 0x8000 and addr <= 0xFFFF:
            if self.PRG_banks == 1:
                mapped_addr = addr & 0x3FFF
            if self.PRG_banks == 2:
                mapped_addr = addr & 0x7FFF
            return (True, mapped_addr, 0)
        else:
            return (False, 0, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef uint32_t mapped_addr = 0

        if addr >= 0x8000 and addr <= 0xFFFF:
            self.CHR_bank_select = data & 0x03
            mapped_addr = addr
        return (False, mapped_addr)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        if addr < 0x2000:
            return (True, self.CHR_bank_select * 0x2000 + addr)
        return (False, 0)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        return (False, 0)

    cdef void reset(self):
        self.CHR_bank_select = 0

cdef class MapperMMC3(Mapper):
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "004"
        
        self.targe_register = 0x00  
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

        self.RAM_static = np.zeros(32768).astype(np.uint8)

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if addr >= 0x6000 and addr <= 0x7FFF:
            mapped_addr = 0xFFFFFFFF
            data = self.RAM_static[addr & 0x1FFF]
            return (True, mapped_addr, data)
        if addr >= 0x8000 and addr <= 0x9FFF:
            mapped_addr = self.PRG_bank[0] + (addr & 0x1FFF)
            return (True, mapped_addr, 0)
        if addr >= 0xA000 and addr <= 0xBFFF:
            mapped_addr = self.PRG_bank[1] + (addr & 0x1FFF)
            return (True, mapped_addr, 0)
        if addr >= 0xC000 and addr <= 0xDFFF:
            mapped_addr = self.PRG_bank[2] + (addr & 0x1FFF)
            return (True, mapped_addr, 0)
        if addr >= 0xE000 and addr <= 0xFFFF:
            mapped_addr = self.PRG_bank[3] + (addr & 0x1FFF)
            return (True, mapped_addr, 0)
        return (False, 0, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef uint32_t mapped_addr = 0

        if addr >= 0x6000 and addr <= 0x7FFF:
            mapped_addr = 0xFFFFFFFF
            self.RAM_static[addr & 0x1FFF] = data
            return (True, mapped_addr)
        if addr >= 0x8000 and addr <= 0x9FFF:
            if addr & 0x0001 == 0:
                self.target_register = data & 0x07
                self.PRG_bank_mode = data & 0x40
                self.CHR_inversion = data & 0x80
            else:
                self.register[self.target_register] = data
                if self.CHR_inversion:
                    self.CHR_bank[0] = self.register[2] * 0x0400
                    self.CHR_bank[1] = self.register[3] * 0x0400
                    self.CHR_bank[2] = self.register[4] * 0x0400
                    self.CHR_bank[3] = self.register[5] * 0x0400
                    self.CHR_bank[4] = (self.register[0] & 0xFE) * 0x0400
                    self.CHR_bank[5] = self.register[0] & 0x0400 + 0x0400
                    self.CHR_bank[6] = (self.register[1] & 0xFE) * 0x0400
                    self.CHR_bank[7] = self.register[1] & 0x0400 + 0x0400
                else:
                    self.CHR_bank[0] = (self.register[0] & 0xFE) * 0x0400
                    self.CHR_bank[1] = self.register[0] & 0x0400 + 0x0400
                    self.CHR_bank[2] = (self.register[1] & 0xFE) * 0x0400
                    self.CHR_bank[3] = self.register[1] & 0x0400 + 0x0400
                    self.CHR_bank[4] = self.register[2] * 0x0400
                    self.CHR_bank[5] = self.register[3] * 0x0400
                    self.CHR_bank[6] = self.register[4] * 0x0400
                    self.CHR_bank[7] = self.register[5] * 0x0400
                if self.PRG_bank_mode:
                    self.PRG_bank[2] = (self.register[6] & 0x3F) * 0x2000
                    self.PRG_bank[0] = (self.PRG_banks * 2 -2) * 0x2000
                else:
                    self.PRG_bank[0] = (self.register[6] & 0x3F) * 0x2000
                    self.PRG_bank[2] = (self.PRG_banks * 2 -2) * 0x2000  
                self.PRG_bank[1] = (self.register[7] & 0x3F) * 0x2000
                self.PRG_bank[3] = (self.PRG_banks * 2 -1) * 0x2000     
            return (False, mapped_addr)
        if addr >= 0xA000 and addr <= 0xBFFF:
            if addr & 0x0001 == 0:
                if data & 0x01 != 0:
                    self.mirrormode = HORIZONTAL
                else:
                    self.mirrormode = VERTICAL
            else:
                pass   
            return (False, mapped_addr)
        if addr >= 0xC000 and addr <= 0xDFFF:
            if addr & 0x0001 == 0:
                self.IRQ_reload = data
            else:
                self.IRQ_counter = 0x0000
            return (False, mapped_addr)
        if addr >= 0xE000 and addr <= 0xFFFF:
            if addr & 0x0001 == 0:
                self.IRQ_enable = False
                self.IRQ_active = False
            else:
                self.IRQ_enable = True
            return (False, mapped_addr)

        return (False, mapped_addr)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        cdef uint32_t mapped_addr = 0x00000000

        if addr >= 0x0000 and addr <= 0x03FF:
            mapped_addr = self.CHR_bank[0] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x0400 and addr <= 0x07FF:
            mapped_addr = self.CHR_bank[1] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x0800 and addr <= 0x0BFF:
            mapped_addr = self.CHR_bank[2] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x0C00 and addr <= 0x0FFF:
            mapped_addr = self.CHR_bank[3] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x0100 and addr <= 0x13FF:
            mapped_addr = self.CHR_bank[4] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x1400 and addr <= 0x17FF:
            mapped_addr = self.CHR_bank[5] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x1800 and addr <= 0x1BFF:
            mapped_addr = self.CHR_bank[6] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x1C00 and addr <= 0x1FFF:
            mapped_addr = self.CHR_bank[7] + (addr & 0x03FF)
            return (True, mapped_addr)

        return (False, mapped_addr)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        return (False, 0)

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

cdef class MapperGxROM(Mapper):    
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        super().__init__(PRG_banks, CHR_banks)
        self.mapper_no = "066"

        self.CHR_bank_select = 0x00
        self.PRG_bank_select = 0x00    
            
    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if addr >= 0x8000 and addr <= 0xFFFF:
            mapped_addr = self.PRG_bank_select * 0x8000 + (addr & 0x7FFF)
            return (True, mapped_addr, 0)
        else:
            return (False, 0, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        if addr >= 0x8000 and addr <= 0xFFFF:
            self.CHR_bank_select = data & 0x03
            self.PRG_bank_select = (data & 0x30) >> 4
        return (False, 0)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        cdef uint32_t mapped_addr

        if addr < 0x2000:
            mapped_addr = self.CHR_bank_select * 0x2000 + addr
            return (True, mapped_addr)
        else:
            return (False, 0)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        return (False, 0)

    cdef void reset(self):
        self.CHR_bank_select, self.PRG_bank_select = 0, 0
