from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class MapperCPROM(Mapper):
    """CPROM's only live register is the 2-bit CHR RAM page at $1000-$1FFF."""
    cdef uint8_t chr_bank_select
