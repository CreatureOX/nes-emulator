Y = 0
ID = 1
ATTRIBUTES = 2
X = 3

cdef uint8_t attribute(uint8_t attributes, SpriteAttribute which_attribute):
    return attributes & which_attribute
