from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class Mapper180(Mapper):
    """Crazy Climber's inverted UxROM latch and its CHR RAM window."""
    cdef uint8_t prg_bank
