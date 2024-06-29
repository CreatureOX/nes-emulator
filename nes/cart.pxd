from libc.stdint cimport uint8_t, uint16_t, uint32_t

from mapper cimport Mapper
from bus cimport CPUBus


cdef class Header:
    cdef bytes trainer

cdef class Cartridge:
    cdef uint32_t PRG_ROM_bytes
    cdef uint32_t CHR_ROM_bytes

    cdef uint8_t[:] PRG_ROM_data
    cdef uint8_t[:] CHR_ROM_data

    cdef CPUBus bus    
    cdef Mapper mapper
    cdef uint8_t mirror_mode

    cdef void connect_bus(self, CPUBus)
    cdef void reset(self)
    cdef uint8_t mapper_no(self)

    cdef (bint, uint8_t) readByCPU(self, uint16_t)
    cdef bint writeByCPU(self, uint16_t, uint8_t)
    cdef (bint, uint8_t) readByPPU(self, uint16_t)
    cdef bint writeByPPU(self, uint16_t, uint8_t)
