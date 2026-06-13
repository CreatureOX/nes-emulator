"""
Sprite constants and utilities for PPU.

Sprite OAM format (4 bytes per sprite):
- Y: Y position
- ID: Tile ID
- ATTRIBUTES: Color palette and flip bits
- X: X position
"""
Y = 0
ID = 1
ATTRIBUTES = 2
X = 3

cdef uint8_t flipbyte(uint8_t b):
    """Reverse bit order in a byte."""
    b = (b & 0xF0) >> 4 | (b & 0x0F) << 4
    b = (b & 0xCC) >> 2 | (b & 0x33) << 2
    b = (b & 0xAA) >> 1 | (b & 0x55) << 1
    return b
    
cdef uint8_t attribute(uint8_t attributes, SpriteAttribute which_attribute):
    """Extract a specific attribute from sprite attributes byte."""
    return attributes & which_attribute