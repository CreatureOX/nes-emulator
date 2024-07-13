from libc.stdint cimport uint8_t, uint16_t

from nes.mapper.mirror cimport *


cdef class Mapper:
    def __init__(self, uint8_t PRG_banks, uint8_t CHR_banks):
        self.PRG_banks = PRG_banks
        self.CHR_banks = CHR_banks

        self.reset()

    @staticmethod
    def instance(PRG_banks: uint8_t, CHR_banks: uint8_t):
        return Mapper(PRG_banks, CHR_banks)

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr):
        pass

    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t addr, uint8_t data):
        pass

    cdef PPUReadMapping mapReadByPPU(self, uint16_t addr):
        pass

    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t addr):
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
