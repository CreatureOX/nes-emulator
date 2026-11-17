from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class MapperVRC2a(Mapper):
    cdef uint8_t prg_bank_0
    cdef uint8_t prg_bank_1
    cdef uint8_t chr_select[8]
    cdef uint8_t mirror_control
    cdef bint mirror_written
