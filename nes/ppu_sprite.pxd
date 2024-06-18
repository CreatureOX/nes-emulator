from libc.stdint cimport uint8_t


cdef int Y, ID, ATTRIBUTES, X

cdef uint8_t flipbyte(uint8_t b)

ctypedef enum SpriteAttribute:
    BIT_PALETTE = 0b11
    BIT_PRIORITY = 1<<5
    BIT_HORIZONTAL_FLIP = 1<<6
    BIT_VERTICAL_FLIP = 1<<7

cdef uint8_t attribute(uint8_t, SpriteAttribute)
