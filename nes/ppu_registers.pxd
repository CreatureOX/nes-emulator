from libc.stdint cimport uint8_t, uint16_t

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
    cdef:
        uint8_t nametable_x
        uint8_t nametable_y
        uint8_t increment_mode
        uint8_t pattern_sprite
        uint8_t pattern_background
        uint8_t sprite_size
        uint8_t slave_mode
        uint8_t enable_nmi

    cdef void reset(self)

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
    cdef:
        uint8_t greyscale
        uint8_t render_background_left
        uint8_t render_sprites_left
        uint8_t render_background
        uint8_t render_sprites
        uint8_t enhance_red
        uint8_t enhance_green
        uint8_t enhance_blue

    cdef void reset(self)

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
    cdef:
        uint8_t unused
        uint8_t sprite_overflow
        uint8_t sprite_zero_hit
        uint8_t vertical_blank

    cdef void reset(self)

cdef class LoopRegister:
    '''
    yyy NN YYYYY XXXXX
    ||| || ||||| +++++-- coarse X scroll
    ||| || +++++-------- coarse Y scroll
    ||| ++-------------- nametable select
    +++----------------- fine Y scroll
    '''
    cdef:
        uint16_t coarse_x
        uint16_t coarse_y
        uint16_t nametable_x
        uint16_t nametable_y
        uint16_t fine_y
        uint16_t unused

    cdef void reset(self)