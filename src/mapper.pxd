from libc.stdint cimport uint8_t, uint16_t, uint32_t


cdef class Mapper:
    cdef uint8_t nPRGBanks
    cdef uint8_t nCHRBanks

    cdef (bint, uint32_t) mapReadByCPU(self, uint16_t)
    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t)
    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t)
    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t)
    cdef void reset(self)

cdef class Mapper000(Mapper):
    pass
      