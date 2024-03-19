from libc.stdint cimport uint8_t, uint16_t, int16_t
from numpy cimport ndarray

from bus cimport CPUBus
from cartridge cimport Cartridge
from mirror cimport *

import cython


cdef uint8_t flipbyte(uint8_t b)

cdef class Status:
    '''
    7  bit  0
    ---- ----
    VSO. ....
    |||| ||||
    |||+-++++- PPU open bus. Returns stale PPU bus contents.
    ||+------- Sprite overflow. The intent was for this flag to be set
    ||         whenever more than eight sprites appear on a scanline, but a
    ||         hardware bug causes the actual behavior to be more complicated
    ||         and generate false positives as well as false negatives; see
    ||         PPU sprite evaluation. This flag is set during sprite
    ||         evaluation and cleared at dot 1 (the second dot) of the
    ||         pre-render line.
    |+-------- Sprite 0 Hit.  Set when a nonzero pixel of sprite 0 overlaps
    |          a nonzero background pixel; cleared at dot 1 of the pre-render
    |          line.  Used for raster timing.
    +--------- Vertical blank has started (0: not in vblank; 1: in vblank).
               Set at dot 1 of line 241 (the line *after* the post-render
               line); cleared after reading $2002 and at dot 1 of the
               pre-render line.    
    '''
    cdef uint8_t value

cdef class Mask:
    '''
    7  bit  0
    ---- ----
    BGRs bMmG
    |||| ||||
    |||| |||+- Greyscale (0: normal color, 1: produce a greyscale display)
    |||| ||+-- 1: Show background in leftmost 8 pixels of screen, 0: Hide
    |||| |+--- 1: Show sprites in leftmost 8 pixels of screen, 0: Hide
    |||| +---- 1: Show background
    |||+------ 1: Show sprites
    ||+------- Emphasize red (green on PAL/Dendy)
    |+-------- Emphasize green (red on PAL/Dendy)
    +--------- Emphasize blue    
    '''
    cdef uint8_t value

cdef class Controller:
    '''
        7  bit  0
    ---- ----
    VPHB SINN
    |||| ||||
    |||| ||++- Base nametable address
    |||| ||    (0 = $2000; 1 = $2400; 2 = $2800; 3 = $2C00)
    |||| |+--- VRAM address increment per CPU read/write of PPUDATA
    |||| |     (0: add 1, going across; 1: add 32, going down)
    |||| +---- Sprite pattern table address for 8x8 sprites
    ||||       (0: $0000; 1: $1000; ignored in 8x16 mode)
    |||+------ Background pattern table address (0: $0000; 1: $1000)
    ||+------- Sprite size (0: 8x8 pixels; 1: 8x16 pixels – see PPU OAM#Byte 1)
    |+-------- PPU master/slave select
    |          (0: read backdrop from EXT pins; 1: output color on EXT pins)
    +--------- Generate an NMI at the start of the
               vertical blanking interval (0: off; 1: on)
    '''
    cdef uint8_t value

cdef class LoopRegister:
    '''
    yyy NN YYYYY XXXXX
    ||| || ||||| +++++-- coarse X scroll
    ||| || +++++-------- coarse Y scroll
    ||| ++-------------- nametable select
    +++----------------- fine Y scroll
    '''
    cdef uint16_t value

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
    cdef uint8_t[240][256][3] spriteScreen
    cdef list spriteNameTable
    cdef list spritePatternTable

    cdef Controller PPUCTRL
    cdef Mask PPUMASK
    cdef Status PPUSTATUS
    cdef uint8_t OAM_ADDR
    cdef public uint8_t[2048] OAM

    # Current VRAM address (15 bits)
    cdef LoopRegister v

    # Temporary VRAM address (15 bits); 
    # can also be thought of as the address of the top left onscreen tile.
    cdef LoopRegister t

    # Fine X scroll (3 bits)
    cdef uint8_t x

    # First or second write toggle (1 bit)
    cdef uint8_t w

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
    cpdef uint8_t[:,:,:] getPalette(self)
    cdef void reset(self)

    cdef void incrementScrollX(self)
    cdef void incrementScrollY(self)
    cdef void transferAddressX(self)
    cdef void transferAddressY(self)
    cdef void loadBackgroundShifters(self)
    @cython.locals(i=int)
    cdef void updateShifters(self)
    cdef void clock(self) except *
