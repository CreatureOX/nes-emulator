from libc.stdint cimport uint8_t, uint16_t

from cartridge_header cimport Header
from bus cimport CPUBus
from mirror cimport *
from mapper cimport Mapper
from mapper_factory cimport MapperFactory


cdef class Cartridge:
    cdef Header header
    cdef bytes trainer
    cdef uint8_t[:] PRGMemory
    cdef uint8_t[:] CHRMemory
    cdef bytes playChoiceINSTMemory
    cdef bytes playChoicePMemory

    cdef Mapper mapper 
    cdef int mirror
    cdef CPUBus bus

    cdef (bint, uint8_t) readByCPU(self, uint16_t)
    cdef bint writeByCPU(self, uint16_t, uint8_t)
    cdef (bint, uint8_t) readByPPU(self, uint16_t)
    cdef bint writeByPPU(self, uint16_t, uint8_t)
    cdef void connectBus(self, CPUBus)
    cdef void reset(self)
    cdef uint8_t getMirror(self)
    cdef Mapper getMapper(self)
