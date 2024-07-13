from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class MapperINES003(Mapper):
    cdef uint8_t CHR_bank_select
