from libc.stdint cimport uint8_t

from mapper cimport Mapper


cdef class MapperUxROM(Mapper):
    cdef uint8_t PRG_bank_select_lo
    cdef uint8_t PRG_bank_select_hi
