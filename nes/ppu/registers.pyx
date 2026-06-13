"""
PPU register structures for status, mask, control, and VRAM addressing.
"""

cdef class Status:
    """
    PPU Status Register ($2002).
    
    Contains VBL flag, sprite zero hit, and sprite overflow information.
    Reading this register clears the VBL flag and address latch.
    """
    def __init__(self) -> None:
        self.reset()

    cdef void reset(self):
        """Reset all status flags."""
        self.unused = 0
        self.sprite_overflow = 0
        self.sprite_zero_hit = 0
        self.vertical_blank = 0

    @property
    def value(self):
        """Get raw register value."""
        return (self.vertical_blank << 7) | \
            (self.sprite_zero_hit << 6) | \
            (self.sprite_overflow << 5) | \
            self.unused       

    @value.setter
    def value(self, long value):
        """Set register value and parse individual flags."""
        value &= 0xFF
        self.unused = value & 0b11111
        self.sprite_overflow = (value & 0b100000) >> 5
        self.sprite_zero_hit = (value & 0b1000000) >> 6
        self.vertical_blank = (value & 0b10000000) >> 7

cdef class Mask:
    """
    PPU Mask Register ($2001).
    
    Controls rendering of backgrounds, sprites, and color enhancement.
    """
    def __init__(self) -> None:
        self.reset()

    cdef void reset(self):
        """Reset all mask flags."""
        self.greyscale = 0
        self.render_background_left = 0
        self.render_sprites_left = 0
        self.render_background = 0
        self.render_sprites = 0
        self.enhance_red = 0
        self.enhance_green = 0
        self.enhance_blue = 0   

    @property
    def value(self):
        """Get raw register value."""
        return (self.enhance_blue << 7) | \
            (self.enhance_green << 6) | \
            (self.enhance_red << 5) | \
            (self.render_sprites << 4) | \
            (self.render_background << 3) | \
            (self.render_sprites_left << 2) | \
            (self.render_background_left << 1) | \
            self.greyscale

    @value.setter
    def value(self, long value):
        """Set register value and parse individual flags."""
        value &= 0xFFFF
        self.greyscale = value & 0b1
        self.render_background_left = (value & 0b10) >> 1
        self.render_sprites_left = (value & 0b100) >> 2
        self.render_background = (value & 0b1000) >> 3
        self.render_sprites = (value & 0b10000) >> 4
        self.enhance_red = (value & 0b100000) >> 5
        self.enhance_green = (value & 0b1000000) >> 6
        self.enhance_blue = (value & 0b10000000) >> 7 

cdef class Controller:
    """
    PPU Control Register ($2000).
    
    Controls nametable selection, PPU address increment mode,
    sprite and background pattern selection, and NMI generation.
    """
    def __init__(self) -> None:
        self.reset()

    cdef void reset(self):
        """Reset all control flags."""
        self.nametable_x = 0
        self.nametable_y = 0
        self.increment_mode = 0
        self.pattern_sprite = 0
        self.pattern_background = 0
        self.sprite_size = 0
        self.slave_mode = 0
        self.enable_nmi = 0

    @property
    def value(self):
        """Get raw register value."""
        return (self.enable_nmi << 7) | \
            (self.slave_mode << 6) | \
            (self.sprite_size << 5) | \
            (self.pattern_background << 4) | \
            (self.pattern_sprite << 3) | \
            (self.increment_mode << 2) | \
            (self.nametable_y << 1) | \
            (self.nametable_x)

    @value.setter  
    def value(self, long value):
        """Set register value and parse individual flags."""
        value &= 0xFF
        self.nametable_x = value & 0b1
        self.nametable_y = ((value & 0b10) >> 1) & 1
        self.increment_mode = ((value & 0b100) >> 2) & 1
        self.pattern_sprite = ((value & 0b1000) >> 3) & 1
        self.pattern_background = ((value & 0b10000) >> 4) & 1
        self.sprite_size = ((value & 0b100000) >> 5) & 1
        self.slave_mode = ((value & 0b1000000) >> 6) & 1
        self.enable_nmi = ((value & 0b10000000) >> 7) & 1 

cdef class LoopRegister:
    """
    PPU VRAM address register with automatic increment and looping.
    
    15-bit register used for both scrolling and VRAM access.
    Composed of: unused(1) | fine_y(3) | nt_y(1) | nt_x(1) | coarse_y(5) | coarse_x(5)
    """
    def __init__(self) -> None:
        self.reset()

    cdef void reset(self):
        """Reset all VRAM address components."""
        self.coarse_x = 0b00000
        self.coarse_y = 0b00000
        self.nametable_x = 0
        self.nametable_y = 0
        self.fine_y = 0b000
        self.unused = 0

    @property
    def value(self):
        """Get raw 15-bit VRAM address."""
        return (self.unused << 15) | \
            (self.fine_y << 12) | \
            (self.nametable_y << 11) | \
            (self.nametable_x << 10) | \
            (self.coarse_y << 5) | \
            self.coarse_x

    @value.setter
    def value(self, long value):
        """Set VRAM address and parse individual components."""
        value &= 0xFFFF
        self.coarse_x = value & 0b11111
        self.coarse_y = (value >> 5) & 0b11111
        self.nametable_x = (value >> 10) & 0b1
        self.nametable_y = (value >> 11) & 0b1
        self.fine_y = (value >> 12) & 0b111
        self.unused = (value >> 15) & 0b1

cdef class BackgroundShiftRegister:
    """
    16-bit shift register for background tile rendering.
    
    Used to shift out background tile pattern data during rendering.
    """
    def __init__(self) -> None:
        self.reset()

    cdef void reset(self):
        """Clear shift register contents."""
        self.low_bits = 0x0000
        self.high_bits = 0x0000