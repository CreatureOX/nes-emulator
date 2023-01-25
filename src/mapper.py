from typing import Tuple
from numpy import uint16, uint32, uint8


class Mirror:
    HARDWARE = 0
    HORIZONTAL = 1
    VERTICAL = 2
    ONESCREEN_LO = 3
    ONESCREEN_HI = 4

class Mapper:
    nPRGBanks: uint8
    nCHRBanks: uint8

    def __init__(self, prgBanks: uint8, chrBanks: uint8) -> None:
        self.nPRGBanks = prgBanks
        self.nCHRBanks = chrBanks

    def mapReadByCPU(self, addr: uint16) -> Tuple[bool, uint32, uint8]:
        pass

    def mapWriteByCPU(self, addr: uint16, data: uint8) -> Tuple[bool, uint32]:
        pass

    def mapReadByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        pass

    def mapWriteByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        pass

    def reset(self):
        pass

    def mirror(self) -> uint8:
        return Mirror.HARDWARE

    def irqState(self) -> bool:
        pass

    def irqClear(self):
        pass

    def scanline(self):
        pass

class Mapper000(Mapper):
    def mapReadByCPU(self, addr: uint16) -> Tuple[bool, uint32, uint8]:
        if 0x8000 <= addr <= 0xFFFF:
            return (True, addr & (0x7FFF if self.nPRGBanks > 1 else 0x3FFF), 0)
        return (False, addr, 0)

    def mapWriteByCPU(self, addr: uint16, data: uint8) -> Tuple[bool, uint32]:
        if 0x8000 <= addr <= 0xFFFF:
            return (True, addr & (0x7FFF if self.nPRGBanks > 1 else 0x3FFF))
        return (False, addr)

    def mapReadByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if 0x0000 <= addr <= 0x1FFF:
            return (True, addr)
        return (False, addr)

    def mapWriteByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if 0x0000 <= addr <= 0x1FFF:
            if self.nCHRBanks == 0:
                return (True, addr)
        return (False, addr)
    
class Mapper001(Mapper):
    def __init__(self, prgBanks: uint8, chrBanks: uint8) -> None:
        super().__init__(prgBanks, chrBanks)
        self.vRAMStatic = [0x00 for _ in range(32 * 1024)] 
        self.nCHRBankSelect4Lo, self.nCHRBankSelect4Hi, self.nCHRBankSelect8 = 0x00, 0x00, 0x00
        self.nPRGBankSelect16Lo, self.nPRGBankSelect16Hi, self.nPRGBankSelect32 = 0x00, 0x00, 0x00
        self.nLoadRegister, self.nLoadRegisterCount, self.nControlRegister = 0x00, 0x00, 0x00  
        self.mirrormode = Mirror.HORIZONTAL

    def mapReadByCPU(self, addr: uint16) -> Tuple[bool, uint32, uint8]:
        if 0x6000 <= addr <= 0x7FFF:
            mapped_addr = 0xFFFFFFFF
            data = self.vRAMStatic[addr & 0x1FFF]
            return (True, mapped_addr, data)
        if addr >= 0x8000:
            if self.nControlRegister & 0b01000 != 0:
                if 0x8000 <= addr <= 0xBFFF:
                    mapped_addr = self.nPRGBankSelect16Lo * 0x4000 + addr & 0x3FFF
                    return (True, mapped_addr, 0)
                if 0xC000 <= addr <= 0xFFFF:
                    mapped_addr = self.nPRGBankSelect16Hi * 0x4000 + addr & 0x3FFF
                    return (True, mapped_addr, 0)
            else:
                mapped_addr = self.nPRGBankSelect32 * 0x8000 + addr & 0x7FFF
                return (True, mapped_addr, 0)
        return (False, 0, 0)
    
    def mapWriteByCPU(self, addr: uint16, data: uint8) -> Tuple[bool, uint32]:
        if 0x6000 <= addr <= 0x7FFF:
            mapped_addr = 0xFFFFFFFF
            self.vRAMStatic[addr & 0x1FFF] = data 
            return (True, mapped_addr)
        if addr >= 0x8000:
            if data & 0x80 != 0:
                self.nLoadRegister = 0x00
                self.nLoadRegisterCount = 0
                self.nControlRegister = self.nControlRegister | 0x0C
            else:
                self.nLoadRegister >>= 1
                self.nLoadRegister |= (data & 0x01) << 4
                self.nLoadRegisterCount += 1
                if self.nLoadRegisterCount == 5:
                    nTargetRegister: uint8 = (addr >> 13) & 0x03
                    if nTargetRegister == 0:
                        self.nControlRegister = self.nLoadRegister & 0X1F
                        switch = self.nControlRegister & 0x03
                        if switch == 0:
                            self.mirrormode = Mirror.ONESCREEN_LO
                        elif switch == 1:
                            self.mirrormode = Mirror.ONESCREEN_HI
                        elif switch == 2:
                            self.mirrormode = Mirror.VERTICAL
                        elif switch == 3:
                            self.mirrormode = Mirror.HORIZONTAL
                    elif nTargetRegister == 1:
                        if self.nControlRegister & 0b10000 != 0:
                            self.nCHRBankSelect4Lo = self.nLoadRegister & 0x1F
                        else:
                            self.nCHRBankSelect8 = self.nLoadRegister & 0x1E
                    elif nTargetRegister == 2:
                        if self.nControlRegister & 0b10000 != 0:
                            self.nCHRBankSelect4Hi = self.nLoadRegister & 0x1F
                    elif nTargetRegister == 3:
                        nPRGMode: uint8 = (self.nControlRegister >> 2) & 0x03
                        if nPRGMode == 0 or nPRGMode == 1:
                            self.nPRGBankSelect32 = (self.nLoadRegister & 0x0E) >> 1
                        elif nPRGMode == 2:
                            self.nPRGBankSelect16Lo = 0
                            self.nPRGBankSelect16Hi = self.nLoadRegister & 0x0F
                        elif nPRGMode == 3:
                            self.nPRGBankSelect16Lo = self.nLoadRegister & 0x0F
                            self.nPRGBankSelect16Hi = self.nPRGBanks - 1
                    self.nLoadRegister = 0x00
                    self.nLoadRegisterCount = 0
        return (False, 0)                       

    def mapReadByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if addr < 0x2000:
            if self.nCHRBanks == 0:
                return (True, addr)
            else:
                if self.nControlRegister & 0b10000 > 0:
                    if 0x0000 <= addr <= 0x0FFF:
                        return (True, self.nCHRBankSelect4Lo * 0x1000 + addr & 0x0FFF)
                    if 0x1000 <= addr <= 0x1FFF:
                        return (True, self.nCHRBankSelect4Hi * 0x1000 + addr & 0x0FFF)
                else:
                    return (True, self.nCHRBankSelect8 * 0x2000 + addr & 0x1FFF)
        else:
            return (False, 0x00)
        
    def mapWriteByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if addr < 0x2000:
            if self.nCHRBanks == 0:
                return (True, addr)
            return (True, 0)
        else:
            return (False, 0)
        
    def reset(self):
        self.nControlRegister, self.nLoadRegister, self.nLoadRegisterCount = 0x1C, 0x00, 0x00 
        self.nCHRBankSelect8, self.nCHRBankSelect4Lo, self.nCHRBankSelect4Hi = 0x00, 0x00, 0x00
        self.nCHRBankSelect32, self.nCHRBankSelect16Lo, self.nCHRBankSelect16Hi = 0x00, 0x00, self.nCHRBanks - 1

    def mirror(self) -> uint8:
        return self.mirrormode

class Mapper002(Mapper):
    def __init__(self, prgBanks: uint8, chrBanks: uint8) -> None:
        super().__init__(prgBanks, chrBanks)
        self.nPRGBankSelectLo, self.nPRGBankSelectHi = 0x00, 0x00

    def mapReadByCPU(self, addr: uint16) -> Tuple[bool, uint32, uint8]:
        if 0x8000 <= addr <= 0xBFFF:
            return (True, self.nPRGBankSelectLo * 0x4000 + addr & 0x3FFF, 0)
        if 0xC000 <= addr <= 0xFFFF:
            return (True, self.nPRGBankSelectHi * 0x4000 + addr & 0x3FFF, 0)
        return (False, addr, 0)

    def mapWriteByCPU(self, addr: uint16, data: uint8) -> Tuple[bool, uint32]:
        if 0x8000 <= addr <= 0xFFFF:
            self.nPRGBankSelectLo = data & 0x0F
        return (False, addr)

    def mapReadByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if addr < 0x2000:
            return (True, addr)
        else:
            return (False, addr)

    def mapWriteByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if addr < 0x2000:
            if self.nCHRBanks == 0:
                return (True, addr)
        return (False, addr)

    def reset(self):
        self.nPRGBankSelectLo, self.nPRGBankSelectHi = 0, self.nPRGBanks - 1

class Mapper003(Mapper):
    def __init__(self, prgBanks: uint8, chrBanks: uint8) -> None:
        super().__init__(prgBanks, chrBanks)
        self.nCHRBankSelect = 0x00

    def mapReadByCPU(self, addr: uint16) -> Tuple[bool, uint32, uint8]:
        if 0x8000 <= addr <= 0xFFFF:
            if self.nPRGBanks == 1:
                mapped_addr = addr & 0x3FFF
            if self.nPRGBanks == 2:
                mapped_addr = addr & 0x7FFF
            return (True, mapped_addr, 0)
        else:
            return (False, addr, 0)
        
    def mapWriteByCPU(self, addr: uint16, data: uint8) -> Tuple[bool, uint32]:
        mapped_addr = 0
        if 0x8000 <= addr <= 0xFFFF:
            self.nCHRBankSelect = data & 0x03
            mapped_addr = addr 
        return (False, mapped_addr)
    
    def mapReadByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if addr < 0x2000:
            return (True, self.nCHRBankSelect * 0x2000 + addr)
        else:
            return (False, 0)
        
    def mapWriteByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        return (False, 0)
    
    def reset(self):
        self.nCHRBankSelect = 0

class Mapper004(Mapper):
    def __init__(self, prgBanks: uint8, chrBanks: uint8) -> None:
        super().__init__(prgBanks, chrBanks)
        self.targetRegister: uint8 = 0x00
        self.PRGBankMode = False
        self.CHRInversion = False
        self.mirrormode = Mirror.HORIZONTAL

        self.register, self.CHRBank, self.PRGBank = [0 for _ in range(8)], [0 for _ in range(8)], [0 for _ in range(4)]
        self.IRQActive, self.IRQEnable, self.IRQUpdate, self.IRQCounter, self.IRQReload = False, False, False, 0x0000, 0x0000
        self.RAMStatic = []

    def mapReadByCPU(self, addr: uint16) -> Tuple[bool, uint32, uint8]:
        if 0x6000 <= addr <= 0x7FFF:
            return (True, 0xFFFFFFFF, self.RAMStatic[addr & 0x1FFF])
        if 0x8000 <= addr <= 0x9FFF:
            return (True, self.PRGBank[0] + addr & 0x1FFF, 0)
        if 0xA000 <= addr <= 0xBFFF:
            return (True, self.PRGBank[1] + addr & 0x1FFF, 0)
        if 0xC000 <= addr <= 0xDFFF:
            return (True, self.PRGBank[2] + addr & 0x1FFF, 0)        
        if 0xE000 <= addr <= 0xFFFF:
            return (True, self.PRGBank[3] + addr & 0x1FFF, 0)
        return (False, addr, 0)
    
    def mapWriteByCPU(self, addr: uint16, data: uint8) -> Tuple[bool, uint32]:
        if 0x6000 <= addr <= 0x7FFF:
            self.RAMStatic[addr & 0x1FFF] = data
            return (True, 0xFFFFFFFF)
        if 0x8000 <= addr <= 0x9FFF:
            if addr & 0x0001 == 0:
                self.targetRegister = data & 0x07
                self.PRGBankMode = data & 0x40
                self.CHRInversion = data & 0x80
            else:
                self.register[self.targetRegister] = data
                if self.CHRInversion:
                    self.CHRBank[0] = self.register[2] * 0x4000
                    self.CHRBank[1] = self.register[3] * 0x4000
                    self.CHRBank[2] = self.register[4] * 0x4000
                    self.CHRBank[3] = self.register[5] * 0x4000
                    self.CHRBank[4] = (self.register[0] & 0xFE) * 0x4000
                    self.CHRBank[5] = self.register[0] * 0x4000 + 0x0400
                    self.CHRBank[6] = (self.register[1] & 0xFE) * 0x4000
                    self.CHRBank[7] = self.register[1] * 0x4000 + 0x0400
                else:
                    self.CHRBank[0] = (self.register[0] & 0xFE) * 0x4000
                    self.CHRBank[1] = self.register[0] * 0x4000 + 0x0400
                    self.CHRBank[2] = (self.register[1] & 0xFE) * 0x4000
                    self.CHRBank[3] = self.register[1] * 0x4000 + 0x0400       
                    self.CHRBank[4] = self.register[2] * 0x4000
                    self.CHRBank[5] = self.register[3] * 0x4000
                    self.CHRBank[6] = self.register[4] * 0x4000
                    self.CHRBank[7] = self.register[5] * 0x4000
                if self.PRGBankMode:
                    self.PRGBank[2] = (self.register[6] & 0x3F) * 0x2000
                    self.PRGBank[0] = (self.nPRGBanks * 2 - 2) * 0x2000
                else:
                    self.PRGBank[0] = (self.register[6] & 0x3F) * 0x2000
                    self.PRGBank[2] = (self.nPRGBanks * 2 - 2) * 0x2000   
                self.PRGBank[1] = (self.register[7] & 0x3F) * 0x2000
                self.PRGBank[3] = (self.nPRGBanks * 2 - 1) * 0x2000    
            return (False, 0)                      
        if 0xA000 <= addr <= 0xBFFF:
            if addr & 0x0001 == 0:
                if data & 0x01 != 0:
                    self.mirrormode = Mirror.HORIZONTAL
                else:
                    self.mirrormode = Mirror.VERTICAL
            else:
                pass
            return (False, 0)
        if 0xC000 <= addr <= 0xDFFF:
            if addr & 0x0001 == 0:
                self.IRQReload = data
            else:
                self.IRQCounter = 0x0000
            return (False, 0)     
        if 0xE000 <= addr <= 0xFFFF:
            if addr & 0x0001 == 0:
                self.IRQEnable = False
                self.IRQActive = False
            else:
                self.IRQEnable = True
            return (False, 0)
        
    def mapReadByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if 0x0000 <= addr <= 0x03FF:
            return (True, self.CHRBank[0] + addr & 0x03FF)
        if 0x0400 <= addr <= 0x07FF:
            return (True, self.CHRBank[1] + addr & 0x03FF)
        if 0x0800 <= addr <= 0x0BFF:
            return (True, self.CHRBank[2] + addr & 0x03FF)
        if 0x0C00 <= addr <= 0x0FFF:
            return (True, self.CHRBank[3] + addr & 0x03FF) 
        if 0x1000 <= addr <= 0x13FF:
            return (True, self.CHRBank[4] + addr & 0x03FF)
        if 0x1400 <= addr <= 0x17FF:
            return (True, self.CHRBank[5] + addr & 0x03FF)
        if 0x1800 <= addr <= 0x1BFF:
            return (True, self.CHRBank[6] + addr & 0x03FF)        
        if 0x1C00 <= addr <= 0x1FFF:
            return (True, self.CHRBank[7] + addr & 0x03FF) 
        return (False, 0)
    
    def mapWriteByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        return (False, 0)
    
    def reset(self):
        self.targetRegister = 0x00
        self.PRGBankMode = False
        self.CHRInversion = False
        self.mirrormode = Mirror.HORIZONTAL

        self.IRQActive = False
        self.IRQEnable = False
        self.IRQUpdate = False
        self.IRQCounter = 0x0000
        self.IRQReload = 0X0000

        for i in range(4):
            self.PRGBank[i] = 0
        for i in range(8):
            self.CHRBank[i] = 0
            self.register[i] = 0
        self.PRGBank[0] = 0 * 0x2000
        self.PRGBank[1] = 1 * 0x2000
        self.PRGBank[2] = (self.nPRGBanks * 2 - 2) * 0x2000
        self.PRGBank[3] = (self.nPRGBanks * 2 - 1) * 0x2000

    def irqState(self) -> bool:
        return self.IRQActive
    
    def irqClear(self):
        self.IRQActive = False

    def scanline(self):
        if self.IRQCounter == 0:
            self.IRQCounter = self.IRQReload
        else:
            self.IRQCounter -= 1
        if self.IRQCounter == 0 and self.IRQEnable:
            self.IRQActive = True

    def mirror(self) -> uint8:
        return self.mirrormode
        
class Mapper066(Mapper):
    def __init__(self, prgBanks: uint8, chrBanks: uint8) -> None:
        super().__init__(prgBanks, chrBanks)
        self.CHRBankSelect, self.PRGBankSelect = 0x00, 0x00

    def mapReadByCPU(self, addr: uint16) -> Tuple[bool, uint32, uint8]:
        if 0x8000 <= addr <= 0xFFFF:
            return (True, self.PRGBankSelect * 0x8000 + addr & 0x7FFF, 0)
        else:
            return (False, 0, 0)
        
    def mapWriteByCPU(self, addr: uint16, data: uint8) -> Tuple[bool, uint32]:
        if 0x8000 <= addr <= 0xFFFF:
            self.CHRBankSelect = data & 0x03
            self.PRGBankSelect = (data & 0x30) >> 4
        return (False, 0)
    
    def mapReadByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if addr < 0x2000:
            return (True, self.CHRBankSelect * 0x2000 + addr)
        else:
            return (False, 0)
        
    def mapWriteByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        return (False, 0)
    
    def reset(self):
        self.CHRBankSelect, self.PRGBankSelect = 0x00, 0x00
        