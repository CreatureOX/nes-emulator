from libc.stdint cimport uint8_t, uint16_t, int16_t
from numpy cimport ndarray

from bus cimport CPUBus
from cartridge cimport Cartridge
from mapper cimport Mirror

import cython


cdef uint8_t flipbyte(uint8_t b)

cdef class Status:
    cdef uint8_t reg

    cdef void set_reg(self,uint8_t)
    cdef uint8_t get_reg(self)

    cdef void set_unused(self,uint8_t)
    cdef uint8_t get_unused(self)
    cdef void set_sprite_overflow(self,uint8_t)
    cdef uint8_t get_sprite_overflow(self)
    cdef void set_sprite_zero_hit(self,uint8_t)
    cdef uint8_t get_sprite_zero_hit(self)
    cdef void set_vertical_blank(self,uint8_t)
    cdef uint8_t get_vertical_blank(self)

cdef class Mask:
    cdef uint8_t reg

    cdef void set_reg(self,uint8_t)
    cdef uint8_t get_reg(self)

    cdef void set_grayscale(self,uint8_t)
    cdef uint8_t get_grayscale(self)
    cdef void set_render_background_left(self,uint8_t)
    cdef uint8_t get_render_background_left(self)
    cdef void set_render_sprites_left(self,uint8_t)
    cdef uint8_t get_render_sprites_left(self)
    cdef void set_render_background(self,uint8_t)
    cdef uint8_t get_render_background(self)
    cdef void set_render_sprites(self,uint8_t)
    cdef uint8_t get_render_sprites(self)
    cdef void set_enhance_red(self,uint8_t)
    cdef uint8_t get_enhance_red(self)
    cdef void set_enhance_green(self,uint8_t)
    cdef uint8_t get_enhance_green(self)
    cdef void set_enhance_blue(self,uint8_t)
    cdef uint8_t get_enhance_blue(self)

cdef class PPUCTRL:
    cdef uint8_t reg
    
    cdef void set_reg(self,uint8_t)
    cdef uint8_t get_reg(self)    

    cdef void set_nametable_x(self,uint8_t)
    cdef uint8_t get_nametable_x(self)
    cdef void set_nametable_y(self,uint8_t)
    cdef uint8_t get_nametable_y(self)
    cdef void set_increment_mode(self,uint8_t)
    cdef uint8_t get_increment_mode(self)
    cdef void set_pattern_sprite(self,uint8_t)
    cdef uint8_t get_pattern_sprite(self)
    cdef void set_pattern_background(self,uint8_t)
    cdef uint8_t get_pattern_background(self)
    cdef void set_sprite_size(self,uint8_t)
    cdef uint8_t get_sprite_size(self)
    cdef void set_slave_mode(self,uint8_t)
    cdef uint8_t get_slave_mode(self)
    cdef void set_enable_nmi(self,uint8_t)
    cdef uint8_t get_enable_nmi(self)

cdef class LoopRegister:
    cdef uint16_t reg
    
    cdef void set_reg(self,uint16_t)
    cdef uint16_t get_reg(self)  

    cdef void set_coarse_x(self,uint16_t)
    cdef uint16_t get_coarse_x(self)
    cdef void set_coarse_y(self,uint16_t)
    cdef uint16_t get_coarse_y(self)
    cdef void set_nametable_x(self,uint16_t)
    cdef uint16_t get_nametable_x(self)
    cdef void set_nametable_y(self,uint16_t)
    cdef uint16_t get_nametable_y(self)
    cdef void set_fine_y(self,uint16_t)
    cdef uint16_t get_fine_y(self)
    cdef void set_unused(self,uint16_t)
    cdef uint16_t get_unused(self)

cdef uint8_t Y 
cdef uint8_t ID
cdef uint8_t ATTRIBUTE
cdef uint8_t X 

cdef uint8_t offset(uint8_t,uint8_t)

cdef class PPU2C02:
    cdef uint8_t[2][4096] patternTable
    cdef uint8_t[2][1024] nameTable
    cdef uint8_t[32] paletteTable

    cdef list palettePanel
    cdef ndarray spriteScreen
    cdef list spriteNameTable
    cdef list spritePatternTable

    cdef Status status
    cdef Mask mask
    cdef PPUCTRL control
    cdef LoopRegister vram_addr
    cdef LoopRegister tram_addr

    cdef uint8_t fine_x

    cdef uint8_t address_latch
    cdef uint8_t ppu_data_buffer

    cdef int16_t scanline
    cdef int16_t cycle

    cdef uint8_t background_next_tile_id
    cdef uint8_t background_next_tile_attribute
    cdef uint8_t background_next_tile_lsb
    cdef uint8_t background_next_tile_msb
    cdef uint16_t background_shifter_pattern_lo
    cdef uint16_t background_shifter_pattern_hi
    cdef uint16_t background_shifter_attribute_lo
    cdef uint16_t background_shifter_attribute_hi

    cdef public uint8_t[2048] pOAM

    cdef uint8_t oam_addr

    cdef uint8_t[256] pSpriteScanline
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
    cpdef uint8_t[:,:,:] getScreen(self)

    @cython.locals(data=uint8_t)
    cpdef uint8_t readByCPU(self, uint16_t, bint)
    cpdef void writeByCPU(self, uint16_t, uint8_t)
    @cython.locals(success=bint, data=uint8_t)
    cpdef uint8_t readByPPU(self, uint16_t)
    @cython.locals(success=bint)
    cpdef void writeByPPU(self, uint16_t, uint8_t)

    cdef void setPalettePanel(self)
    @cython.locals(color=uint8_t)
    cdef tuple getColorFromPaletteTable(self, uint8_t, uint8_t)
    @cython.locals(tileY=uint16_t,tileX=uint16_t,offset=uint16_t, \
    tile_lsb=uint8_t,tile_msb=uint8_t,pixel=uint8_t)
    cpdef uint8_t[:,:,:] getPatternTable(self, uint8_t, uint8_t)
    cpdef void reset(self)

    cdef void incrementScrollX(self)
    cdef void incrementScrollY(self)
    cdef void transferAddressX(self)
    cdef void transferAddressY(self)
    cdef void loadBackgroundShifters(self)
    @cython.locals(i=int)
    cdef void updateShifters(self)
    @cython.locals(i=int, v=uint16_t, nOAMEntry=uint8_t, \
    diff=int16_t, diff_compare=int, \
    sprite_pattern_bits_lo=uint8_t, sprite_pattern_bits_hi=uint8_t, \
    sprite_pattern_addr_lo=uint16_t, sprite_pattern_addr_hi=uint16_t, \
    background_pixel=uint8_t, background_palette=uint8_t, bit_mux=uint16_t, \
    background_pixel_0=uint8_t, background_pixel_1=uint8_t, background_pixel=uint8_t, \
    background_palette_0=uint8_t, background_palette_1=uint8_t, background_palette=uint8_t, \
    foreground_pixel=uint8_t, foreground_palette=uint8_t, foreground_priority=uint8_t, \
    foreground_pixel_lo=uint8_t, foreground_pixel_hi=uint8_t, \
    pixel=uint8_t, palette=uint8_t)
    cpdef void clock(self) except *
