from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class MapperColorDreams(Mapper):
    cdef uint8_t bank_register
