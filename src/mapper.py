from typing import Tuple
from numpy import uint16, uint32, uint8


class Mapper:
    nPRGBanks: uint8
    nCHRBanks: uint8

    def __init__(self, prgBanks: uint8, chrBanks: uint8) -> None:
        self.nPRGBanks = prgBanks
        self.nCHRBanks = chrBanks

    def mapReadByCPU(self, addr: uint16) -> Tuple[bool, uint32]:
        pass

    def mapWriteByCPU(self, addr: uint16) -> Tuple[bool, uint32]:
        pass

    def mapReadByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        pass

    def mapWriteByPPU(self, addr: uint16) -> Tuple[bool, uint32]:
        pass

    def reset(self):
        pass

class Mapper000(Mapper):
    def mapReadByCPU(self, addr: uint16) -> Tuple[bool, uint32]:
        if 0x8000 <= addr <= 0xFFFF:
            return (True, addr & (0x7FFF if self.nPRGBanks > 1 else 0x3FFF))
        return (False, addr)

    def mapWriteByCPU(self, addr: uint16) -> Tuple[bool, uint32]:
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
