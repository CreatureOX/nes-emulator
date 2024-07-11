from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class MapperMMC1(Mapper):
    cdef uint8_t CHR_bank_select_4_lo
    cdef uint8_t CHR_bank_select_4_hi
    cdef uint8_t CHR_bank_select_8

    cdef uint8_t PRG_bank_select_16_lo
    cdef uint8_t PRG_bank_select_16_hi
    cdef uint8_t PRG_bank_select_32

    cdef uint8_t load_register
    cdef uint8_t load_register_count
    cdef uint8_t control_register

    cdef uint8_t mirrormode

    cdef uint8_t[:] RAM_static
