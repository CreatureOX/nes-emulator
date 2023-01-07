from libc.stdint cimport uint8_t, uint16_t
from numpy cimport ndarray

from bus cimport CPUBus
from cartridge cimport Cartridge, HORIZONTAL, VERTICAL

import cython


cdef uint8_t flipbyte(uint8_t b)

cdef class PPU2C02:
    cdef uint8_t[2][4096] patternTable
    cdef uint8_t[2][1024] nameTable
    cdef uint8_t[32] paletteTable

    cdef list palettePanel
    cdef ndarray spriteScreen
    cdef list spriteNameTable
    cdef list spritePatternTable

    cdef object status
    cdef object mask
    cdef object control
    cdef object vram_addr
    cdef object tram_addr

    cdef uint8_t fine_x

    cdef uint8_t address_latch
    cdef uint8_t ppu_data_buffer

    cdef uint16_t scanline
    cdef uint16_t cycle

    cdef uint8_t background_next_tile_id
    cdef uint8_t background_next_tile_attribute
    cdef uint8_t background_next_tile_lsb
    cdef uint8_t background_next_tile_msb
    cdef uint16_t background_shifter_pattern_lo
    cdef uint16_t background_shifter_pattern_hi
    cdef uint16_t background_shifter_attribute_lo
    cdef uint16_t background_shifter_attribute_hi

    cdef object OAM
    cdef object pOAM

    cdef uint8_t oam_addr

    cdef object spriteScanline
    cdef uint8_t sprite_count
    cdef uint8_t[8] sprite_shifter_pattern_lo
    cdef uint8_t[8] sprite_shifter_pattern_hi

    cdef bint bSpriteZeroHitPossible
    cdef bint bSpriteZeroBeingRendered

    cdef Cartridge cartridge

    cdef public bint nmi

    cdef public bint frame_complete

    cdef CPUBus bus

    cdef int screenWidth
    cdef int screenHeight

    cpdef void connectCartridge(self, Cartridge)
    cpdef ndarray getScreen(self)

    @cython.locals(data=uint8_t)
    cpdef uint8_t readByCPU(self, uint16_t, bint)
    cpdef void writeByCPU(self, uint16_t, uint8_t)
    @cython.locals(success=bint, data=uint8_t)
    cpdef uint8_t readByPPU(self, uint16_t)
    @cython.locals(success=bint)
    cpdef void writeByPPU(self, uint16_t, uint8_t)

    cdef void setPalettePanel(self)
    cdef tuple getColorFromPaletteTable(self, uint8_t, uint8_t)
    cpdef void reset(self)

    cdef void incrementScrollX(self)
    cdef void incrementScrollY(self)
    cdef void transferAddressX(self)
    cdef void transferAddressY(self)
    cdef void loadBackgroundShifters(self)
    cdef void updateShifters(self)
    @cython.locals(v=uint16_t, nOAMEntry=uint8_t, \
    diff=uint16_t, diff_compare=int, \
    sprite_pattern_bits_lo=uint8_t, sprite_pattern_bits_hi=uint8_t, \
    sprite_pattern_addr_lo=uint16_t, sprite_pattern_addr_hi=uint16_t, \
    background_pixel=uint8_t, background_palette=uint8_t, bit_mux=uint16_t, \
    background_pixel_0=uint8_t, background_pixel_1=uint8_t, background_pixel=uint8_t, \
    background_palette_0=uint8_t, background_palette_1=uint8_t, background_palette=uint8_t, \
    foreground_pixel=uint8_t, foreground_palette=uint8_t, foreground_priority=uint8_t, \
    foreground_pixel_lo=uint8_t, foreground_pixel_hi=uint8_t, \
    pixel=uint8_t, palette=uint8_t)
    cpdef void clock(self) except *
