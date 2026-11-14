from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class MapperBNROM(Mapper):
    cdef uint8_t prg_bank
