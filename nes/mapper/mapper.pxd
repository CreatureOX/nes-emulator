from libc.stdint cimport uint8_t, int8_t, uint16_t, uint32_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping

# Context for a PPU data-bus fetch, so a board can tell a background
# pattern read from a sprite pattern read at the same PPU address.
cdef enum:
    PPU_FETCH_OTHER = 0
    PPU_FETCH_BACKGROUND = 1
    PPU_FETCH_SPRITE = 2


cdef class Mapper:
    cdef str mapper_no

    cdef uint8_t PRG_banks
    cdef uint8_t CHR_banks

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr)
    cdef CPUWriteMapping map_cpu_write(self, uint16_t, uint8_t)
    cdef PPUReadMapping map_ppu_read(self, uint16_t)
    cdef PPUWriteMapping map_ppu_write(self, uint16_t)

    cdef void reset(self)

    cdef uint8_t mirror(self)

    cdef int8_t nametable_source(self, uint16_t addr)
    cdef uint8_t nametable_read(self, uint16_t addr)
    cdef void nametable_write(self, uint16_t addr, uint8_t data)
    cdef void ppu_fetch_kind(self, uint8_t kind)

    cdef uint32_t chr_ram_size(self)

    cdef bint irq_line(self)

    cdef void scanline(self)

    cdef void a12_notify(self, uint16_t addr)
