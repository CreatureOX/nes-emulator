from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class Mapper078(Mapper):
    """Irem 74HC161/32 latch and the NES 2.0 board variant selector."""
    cdef uint8_t bank_select
    cdef uint8_t submapper

    cdef void set_submapper(self, uint8_t submapper)
