from libc.stdint cimport uint8_t, uint16_t

from bus cimport CPUBus
from mirror cimport *
from mapper cimport Mapper
from mapper_factory cimport MapperFactory


cdef class Header:
    cdef str name
    cdef uint8_t prg_rom_chunks
    cdef uint8_t chr_rom_chunks
    cdef uint8_t mapper1
    cdef uint8_t mapper2
    cdef uint8_t prg_ram_size
    cdef uint8_t tv_system1
    cdef uint8_t tv_system2
    cdef str unused

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
