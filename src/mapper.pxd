from libc.stdint cimport uint8_t, uint16_t, uint32_t


cdef class Mirror:
    pass

cdef class Mapper:
    cdef uint8_t nPRGBanks
    cdef uint8_t nCHRBanks

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t)
    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t, uint8_t)
    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t)
    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t)
    cdef void reset(self)
    cdef Mirror mirror(self)
    cdef bint irqState(self)
    cdef void irqClear(self)
    cdef void scanline(self)

cdef class Mapper000(Mapper):
    pass

cdef class Mapper001(Mapper):
    pass

cdef class Mapper002(Mapper):
    pass

cdef class Mapper003(Mapper):
    pass

cdef class Mapper004(Mapper):
    pass
      
cdef class Mapper066(Mapper):
    pass
