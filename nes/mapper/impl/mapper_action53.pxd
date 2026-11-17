from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapper cimport Mapper


cdef class MapperAction53(Mapper):
    cdef uint8_t selected_reg
    cdef uint8_t chr_bank
    cdef uint8_t inner_bank
    cdef uint8_t mode
    cdef uint8_t outer_bank
    cdef uint8_t mirror_bit
    cdef bint mode_written
    cdef bint started

    cdef uint32_t _prg_bank(self, uint16_t addr)
