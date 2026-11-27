from libc.stdint cimport uint8_t, int8_t, uint16_t

from nes.mapper.impl.mapper_mmc3 cimport MapperMMC3
from nes.mapper.mapping cimport PPUReadMapping


cdef class Mapper118(MapperMMC3):
    """TKSROM/TLSROM: MMC3 banking with CHR A16 wired to CIRAM A10."""

    cdef PPUReadMapping map_ppu_read(self, uint16_t addr)
    cdef uint8_t mirror(self)
    cdef int8_t nametable_source(self, uint16_t addr)
