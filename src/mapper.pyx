from libc.stdint cimport uint8_t, uint16_t, uint32_t


cdef class Mirror:
    HARDWARE = 0
    HORIZONTAL = 1
    VERTICAL = 2
    ONESCREEN_LO = 3
    ONESCREEN_HI = 4

cdef class Mapper:
    def __init__(self, uint8_t prgBanks, uint8_t chrBanks):
        self.nPRGBanks = prgBanks
        self.nCHRBanks = chrBanks

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
        return Mirror.HARDWARE

    cdef bint irqState(self):
        pass

    cdef void irqClear(self):
        pass

    cdef void scanline(self):
        pass

cdef class Mapper000(Mapper):
    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t addr):
        if 0x8000 <= addr <= 0xFFFF:
            return (True, addr & (0x7FFF if self.nPRGBanks > 1 else 0x3FFF), 0)
        return (False, addr, 0)

    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t addr, uint8_t data):
        if 0x8000 <= addr <= 0xFFFF:
            return (True, addr & (0x7FFF if self.nPRGBanks > 1 else 0x3FFF))
        return (False, addr)

    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t addr):
        if 0x0000 <= addr <= 0x1FFF:
            return (True, addr)
        return (False, addr)

    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t addr):
        if 0x0000 <= addr <= 0x1FFF:
            if self.nCHRBanks == 0:
                return (True, addr)
        return (False, addr)
    