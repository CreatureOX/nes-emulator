from libc.stdint cimport uint8_t

from mapper cimport Mapper


cdef class MapperGxROM(Mapper):
    cdef uint8_t CHR_bank_select
    cdef uint8_t PRG_bank_select
