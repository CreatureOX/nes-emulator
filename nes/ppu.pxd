from libc.stdint cimport uint8_t, uint16_t, int16_t
from numpy cimport ndarray

from bus cimport CPUBus
from cartridge cimport Cartridge
from mirror cimport *
from ppu_registers cimport Controller, Mask, Status, LoopRegister

import cython

cdef uint8_t Y, ID, ATTRIBUTE, X

cdef class PPU2C02:
    cdef uint8_t[2][4096] patternTable
    cdef uint8_t[2][1024] nameTable
    cdef uint8_t[32] paletteTable

    cdef list palettePanel
    cdef uint8_t[240][256][3] spriteScreen
    cdef list spriteNameTable
    cdef list spritePatternTable

    cdef Status PPUSTATUS
    cdef Mask PPUMASK
    cdef Controller PPUCTRL
    cdef LoopRegister vram_addr
    cdef LoopRegister tram_addr

    cdef uint8_t fine_x

    cdef uint8_t address_latch
    cdef uint8_t ppu_data_buffer

    cdef public int16_t scanline, cycle

    cdef uint8_t background_next_tile_id
    cdef uint8_t background_next_tile_attribute
    cdef uint8_t background_next_tile_lsb, background_next_tile_msb
    cdef uint16_t background_shifter_pattern_lo, background_shifter_pattern_hi
    cdef uint16_t background_shifter_attribute_lo, background_shifter_attribute_hi

    cdef public uint8_t[64][4] OAM

    cdef uint8_t OAMADDR

    cdef uint8_t[8][4] secondary_OAM
    cdef uint8_t sprite_count
    cdef uint8_t[8] sprite_shifter_pattern_lo
    cdef uint8_t[8] sprite_shifter_pattern_hi

    cdef bint eval_sprite0
    cdef bint render_sprite0
    cdef bint foreground_priority

    cdef Cartridge cartridge

    cdef public bint nmi

    cdef public bint frame_complete

    cdef CPUBus bus

    cdef int screenWidth
    cdef int screenHeight

    cdef void connectCartridge(self, Cartridge)
    cpdef uint8_t[:,:,:] getScreen(self)

    @cython.locals(data=uint8_t)
    cdef uint8_t readByCPU(self, uint16_t, bint)
    cdef void writeByCPU(self, uint16_t, uint8_t)
    @cython.locals(success=bint, data=uint8_t)
    cdef uint8_t readByPPU(self, uint16_t)
    @cython.locals(success=bint)
    cdef void writeByPPU(self, uint16_t, uint8_t)

    cdef void setPalettePanel(self)
    @cython.locals(color=uint8_t)
    cdef tuple getColorFromPaletteTable(self, uint8_t, uint8_t)
    cpdef uint8_t[:,:,:] getPatternTable(self, uint8_t, uint8_t)
    cdef void reset(self)

    cdef void incrementScrollX(self)
    cdef void incrementScrollY(self)
    cdef void transferAddressX(self)
    cdef void transferAddressY(self)
    cdef void loadBackgroundShifters(self)

    cdef void update_background_shifters(self)
    cdef void update_sprite_shifters(self)
    @cython.locals(i=int)
    cdef void updateShifters(self)
    cdef void clock(self) except *

    cdef void eval_background(self)
    cdef uint8_t fetch_background(self, uint16_t)
    cdef uint8_t fetch_background_tile(self)
    cdef uint8_t fetch_background_attribute(self)

    cdef void eval_sprites(self)
    cdef void fetch_sprites(self)
    cdef void fetch_sprite(self, int)
    
    cdef tuple draw_background(self)
    cdef tuple draw_sprites(self)
    cdef tuple draw_by_rule(self, uint8_t, uint8_t, uint8_t, uint8_t) 