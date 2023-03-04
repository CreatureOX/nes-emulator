from libc.stdint cimport uint8_t, uint16_t, uint32_t, UINT32_MAX
import numpy as np
cimport numpy as np

from mirror cimport *


cdef class Mapper:
    def __init__(self, uint8_t prgBanks, uint8_t chrBanks):
        self.PRGBanks = prgBanks
        self.CHRBanks = chrBanks

        self.reset()

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

    cdef bint irqState(self):
        return False

    cdef void irqClear(self):
        pass

    cdef void scanline(self):
        pass

cdef class Mapper000(Mapper):
    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        if 0x8000 <= addr <= 0xFFFF:
            return (True, addr & (0x7FFF if self.PRGBanks > 1 else 0x3FFF), 0)
        return (False, addr, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        if 0x8000 <= addr <= 0xFFFF:
            return (True, addr & (0x7FFF if self.PRGBanks > 1 else 0x3FFF))
        return (False, addr)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        if 0x0000 <= addr <= 0x1FFF:
            return (True, addr)
        return (False, addr)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        if 0x0000 <= addr <= 0x1FFF:
            if self.CHRBanks == 0:
                return (True, addr)
        return (False, addr)

cdef class Mapper001(Mapper):
    def __init__(self, uint8_t prgBanks, uint8_t chrBanks):
        super().__init__(prgBanks, chrBanks)
        self.RAMStatic = np.zeros(32768).astype(np.uint8)
        self.CHRBankSelect4Lo, self.CHRBankSelect4Hi, self.CHRBankSelect8 = 0x00, 0x00, 0x00
        self.PRGBankSelect16Lo, self.PRGBankSelect16Hi, self.PRGBankSelect32 = 0x00, 0x00, 0x00
        self.loadRegister, self.loadRegisterCount, self.controlRegister = 0x00, 0x00, 0x00  
        self.mirrormode = HORIZONTAL

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if 0x6000 <= addr <= 0x7FFF:
            mapped_addr = UINT32_MAX
            data = self.RAMStatic[addr & 0x1FFF]
            return (True, mapped_addr, data)
        if addr >= 0x8000:
            if self.controlRegister & 0b01000 != 0:
                if 0x8000 <= addr <= 0xBFFF:
                    mapped_addr = self.PRGBankSelect16Lo * 0x4000 + (addr & 0x3FFF)
                    return (True, mapped_addr, 0)
                if 0xC000 <= addr <= 0xFFFF:
                    mapped_addr = self.PRGBankSelect16Hi * 0x4000 + (addr & 0x3FFF)
                    return (True, mapped_addr, 0)
            else:
                mapped_addr = self.PRGBankSelect32 * 0x8000 + (addr & 0x7FFF)
                return (True, mapped_addr, 0)
        return (False, 0, 0)
    
    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef uint8_t targetRegister, PRGMode, switch
        cdef uint32_t mapped_addr

        if 0x6000 <= addr <= 0x7FFF:
            mapped_addr = UINT32_MAX
            self.RAMStatic[addr & 0x1FFF] = data 
            return (True, mapped_addr)
        if addr >= 0x8000:
            if data & 0x80 != 0:
                self.loadRegister = 0x00
                self.loadRegisterCount = 0
                self.controlRegister = self.controlRegister | 0x0C
            else:
                self.loadRegister >>= 1
                self.loadRegister |= (data & 0x01) << 4
                self.loadRegisterCount += 1
                if self.loadRegisterCount == 5:
                    targetRegister = (addr >> 13) & 0x03
                    if targetRegister == 0:
                        self.controlRegister = self.loadRegister & 0x1F
                        switch = self.controlRegister & 0x03
                        if switch == 0:
                            self.mirrormode = ONESCREEN_LO
                        elif switch == 1:
                            self.mirrormode = ONESCREEN_HI
                        elif switch == 2:
                            self.mirrormode = VERTICAL
                        elif switch == 3:
                            self.mirrormode = HORIZONTAL
                    elif targetRegister == 1:
                        if self.controlRegister & 0b10000 != 0:
                            self.CHRBankSelect4Lo = self.loadRegister & 0x1F
                        else:
                            self.CHRBankSelect8 = self.loadRegister & 0x1E
                    elif targetRegister == 2:
                        if self.controlRegister & 0b10000 != 0:
                            self.CHRBankSelect4Hi = self.loadRegister & 0x1F
                    elif targetRegister == 3:
                        PRGMode = (self.controlRegister >> 2) & 0x03
                        if PRGMode == 0 or PRGMode == 1:
                            self.PRGBankSelect32 = (self.loadRegister & 0x0E) >> 1
                        elif PRGMode == 2:
                            self.PRGBankSelect16Lo = 0
                            self.PRGBankSelect16Hi = self.loadRegister & 0x0F
                        elif PRGMode == 3:
                            self.PRGBankSelect16Lo = self.loadRegister & 0x0F
                            self.PRGBankSelect16Hi = self.PRGBanks - 1
                    self.loadRegister = 0x00
                    self.loadRegisterCount = 0
        return (False, 0)                       

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        if addr < 0x2000:
            if self.CHRBanks == 0:
                return (True, addr)
            else:
                if self.controlRegister & 0b10000 > 0:
                    if 0x0000 <= addr <= 0x0FFF:
                        return (True, self.CHRBankSelect4Lo * 0x1000 + addr & 0x0FFF)
                    if 0x1000 <= addr <= 0x1FFF:
                        return (True, self.CHRBankSelect4Hi * 0x1000 + addr & 0x0FFF)
                else:
                    return (True, self.CHRBankSelect8 * 0x2000 + addr & 0x1FFF)
        else:
            return (False, 0x00)
        
    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        if addr < 0x2000:
            if self.CHRBanks == 0:
                return (True, addr)
            return (True, 0)
        else:
            return (False, 0)
        
    cdef void reset(self):
        self.controlRegister, self.loadRegister, self.loadRegisterCount = 0x1C, 0x00, 0x00 
        self.CHRBankSelect4Lo, self.CHRBankSelect4Hi, self.CHRBankSelect8, = 0x00, 0x00, 0x00
        self.PRGBankSelect32, self.PRGBankSelect16Lo, self.PRGBankSelect16Hi = 0x00, 0x00, self.PRGBanks - 1

    cdef uint8_t mirror(self):
        return self.mirrormode    

cdef class Mapper002(Mapper):
    def __init__(self, uint8_t prgBanks, uint8_t chrBanks):
        super().__init__(prgBanks, chrBanks)
        self.PRGBankSelectLo, self.PRGBankSelectHi = 0x00, 0x00

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if addr >= 0x8000 and addr <= 0xBFFF:
            mapped_addr = self.PRGBankSelectLo * 0x4000 + (addr & 0x3FFF)
            return (True, mapped_addr, 0)
        if addr >= 0xC000 and addr <= 0xFFFF:
            mapped_addr = self.PRGBankSelectHi * 0x4000 + (addr & 0x3FFF)
            return (True, mapped_addr, 0)
        return (False, 0, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        if addr >= 0x8000 and addr <= 0xFFFF:
            self.PRGBankSelectLo = data & 0x0F
        return (False, 0)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        if addr < 0x2000:
            return (True, addr)
        return (False, addr)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        if addr < 0x2000:
            if self.CHRBanks == 0:
                return (True, addr)
        return (False, addr)

    cdef void reset(self):
        self.PRGBankSelectLo, self.PRGBankSelectHi = 0, self.PRGBanks - 1

cdef class Mapper003(Mapper):
    def __init__(self, uint8_t prgBanks, uint8_t chrBanks):
        super().__init__(prgBanks, chrBanks)
        self.CHRBankSelect = 0x00    

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if addr >= 0x8000 and addr <= 0xFFFF:
            if self.PRGBanks == 1:
                mapped_addr = addr & 0x3FFF
            if self.PRGBanks == 2:
                mapped_addr = addr & 0x7FFF
            return (True, mapped_addr, 0)
        else:
            return (False, 0, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef uint32_t mapped_addr = 0

        if addr >= 0x8000 and addr <= 0xFFFF:
            self.CHRBankSelect = data & 0x03
            mapped_addr = addr
        return (False, mapped_addr)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        if addr < 0x2000:
            return (True, self.CHRBankSelect * 0x2000 + addr)
        return (False, 0)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        return (False, 0)

    cdef void reset(self):
        self.CHRBankSelect = 0

cdef class Mapper004(Mapper):
    def __init__(self, uint8_t prgBanks, uint8_t chrBanks):
        super().__init__(prgBanks, chrBanks)
        self.targetRegister = 0x00  
        self.PRGBankMode = False
        self.CHRInversion = False
        self.mirrormode = HORIZONTAL

        self.register = [0,0,0,0,0,0,0,0]
        self.CHRBank = [0,0,0,0,0,0,0,0]
        self.PRGBank = [0,0,0,0]

        self.IRQActive = False
        self.IRQEnable = False
        self.IRQUpdate = False
        self.IRQCounter = 0x0000
        self.IRQReload = 0x0000

        self.RAMStatic = np.zeros(32768).astype(np.uint8)

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if addr >= 0x6000 and addr <= 0x7FFF:
            mapped_addr = 0xFFFFFFFF
            data = self.RAMStatic[addr & 0x1FFF]
            return (True, mapped_addr, data)
        if addr >= 0x8000 and addr <= 0x9FFF:
            mapped_addr = self.PRGBank[0] + (addr & 0x1FFF)
            return (True, mapped_addr, 0)
        if addr >= 0xA000 and addr <= 0xBFFF:
            mapped_addr = self.PRGBank[1] + (addr & 0x1FFF)
            return (True, mapped_addr, 0)
        if addr >= 0xC000 and addr <= 0xDFFF:
            mapped_addr = self.PRGBank[2] + (addr & 0x1FFF)
            return (True, mapped_addr, 0)
        if addr >= 0xE000 and addr <= 0xFFFF:
            mapped_addr = self.PRGBank[3] + (addr & 0x1FFF)
            return (True, mapped_addr, 0)
        return (False, 0, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        cdef uint32_t mapped_addr = 0

        if addr >= 0x6000 and addr <= 0x7FFF:
            mapped_addr = 0xFFFFFFFF
            self.RAMStatic[addr & 0x1FFF] = data
            return (True, mapped_addr)
        if addr >= 0x8000 and addr <= 0x9FFF:
            if addr & 0x0001 == 0:
                self.targetRegister = data & 0x07
                self.PRGBankMode = data & 0x40
                self.CHRInversion = data & 0x80
            else:
                self.register[self.targetRegister] = data
                if self.CHRInversion:
                    self.CHRBank[0] = self.register[2] * 0x0400
                    self.CHRBank[1] = self.register[3] * 0x0400
                    self.CHRBank[2] = self.register[4] * 0x0400
                    self.CHRBank[3] = self.register[5] * 0x0400
                    self.CHRBank[4] = (self.register[0] & 0xFE) * 0x0400
                    self.CHRBank[5] = self.register[0] & 0x0400 + 0x0400
                    self.CHRBank[6] = (self.register[1] & 0xFE) * 0x0400
                    self.CHRBank[7] = self.register[1] & 0x0400 + 0x0400
                else:
                    self.CHRBank[0] = (self.register[0] & 0xFE) * 0x0400
                    self.CHRBank[1] = self.register[0] & 0x0400 + 0x0400
                    self.CHRBank[2] = (self.register[1] & 0xFE) * 0x0400
                    self.CHRBank[3] = self.register[1] & 0x0400 + 0x0400
                    self.CHRBank[4] = self.register[2] * 0x0400
                    self.CHRBank[5] = self.register[3] * 0x0400
                    self.CHRBank[6] = self.register[4] * 0x0400
                    self.CHRBank[7] = self.register[5] * 0x0400
                if self.PRGBankMode:
                    self.PRGBank[2] = (self.register[6] & 0x3F) * 0x2000
                    self.PRGBank[0] = (self.PRGBanks * 2 -2) * 0x2000
                else:
                    self.PRGBank[0] = (self.register[6] & 0x3F) * 0x2000
                    self.PRGBank[2] = (self.PRGBanks * 2 -2) * 0x2000  
                self.PRGBank[1] = (self.register[7] & 0x3F) * 0x2000
                self.PRGBank[3] = (self.PRGBanks * 2 -1) * 0x2000     
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
                self.IRQReload = data
            else:
                self.IRQCounter = 0x0000
            return (False, mapped_addr)
        if addr >= 0xE000 and addr <= 0xFFFF:
            if addr & 0x0001 == 0:
                self.IRQEnable = False
                self.IRQActive = False
            else:
                self.IRQEnable = True
            return (False, mapped_addr)

        return (False, mapped_addr)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        cdef uint32_t mapped_addr = 0x00000000

        if addr >= 0x0000 and addr <= 0x03FF:
            mapped_addr = self.CHRBank[0] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x0400 and addr <= 0x07FF:
            mapped_addr = self.CHRBank[1] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x0800 and addr <= 0x0BFF:
            mapped_addr = self.CHRBank[2] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x0C00 and addr <= 0x0FFF:
            mapped_addr = self.CHRBank[3] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x0100 and addr <= 0x13FF:
            mapped_addr = self.CHRBank[4] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x1400 and addr <= 0x17FF:
            mapped_addr = self.CHRBank[5] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x1800 and addr <= 0x1BFF:
            mapped_addr = self.CHRBank[6] + (addr & 0x03FF)
            return (True, mapped_addr)
        if addr >= 0x1C00 and addr <= 0x1FFF:
            mapped_addr = self.CHRBank[7] + (addr & 0x03FF)
            return (True, mapped_addr)

        return (False, mapped_addr)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        return (False, 0)

    cdef void reset(self):
        self.targetRegister = 0x00
        self.PRGBankMode = False
        self.CHRInversion = False
        self.mirrormode = HORIZONTAL

        self.IRQActive = False
        self.IRQEnable = False
        self.IRQUpdate = False
        self.IRQCounter = 0x0000
        self.IRQReload = 0x0000

        for i in range(4):
            self.PRGBank[i] = 0
        for i in range(8):
            self.CHRBank[i] = 0
            self.register[i] = 0

        self.PRGBank[0] = 0 * 0x2000
        self.PRGBank[1] = 1 * 0x2000
        self.PRGBank[2] = (self.PRGBanks * 2 - 2) * 0x2000
        self.PRGBank[3] = (self.PRGBanks * 2 - 1) * 0x2000

    cdef uint8_t mirror(self):
        return self.mirrormode  

    cdef bint irqState(self):
        return self.IRQActive

    cdef void irqClear(self):
        self.IRQActive = False

    cdef void scanline(self):
        if self.IRQCounter == 0:
            self.IRQCounter = self.IRQReload
        else:
            self.IRQCounter -= 1
        if self.IRQCounter == 0 and self.IRQEnable:
            self.IRQActive = True

cdef class Mapper066(Mapper):
    def __init__(self, uint8_t prgBanks, uint8_t chrBanks):
        super().__init__(prgBanks, chrBanks)
        self.CHRBankSelect = 0x00
        self.PRGBankSelect = 0x00    
            
    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        cdef uint8_t data
        cdef uint32_t mapped_addr

        if addr >= 0x8000 and addr <= 0xFFFF:
            mapped_addr = self.PRGBankSelect * 0x8000 + (addr & 0x7FFF)
            return (True, mapped_addr, 0)
        else:
            return (False, 0, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        if addr >= 0x8000 and addr <= 0xFFFF:
            self.CHRBankSelect = data & 0x03
            self.PRGBankSelect = (data & 0x30) >> 4
        return (False, 0)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        cdef uint32_t mapped_addr

        if addr < 0x2000:
            mapped_addr = self.CHRBankSelect * 0x2000 + addr
            return (True, mapped_addr)
        else:
            return (False, 0)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        return (False, 0)

    cdef void reset(self):
        self.CHRBankSelect, self.PRGBankSelect = 0, 0
