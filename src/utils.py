from numpy import uint16, uint8


def set_bit(v: uint8, index: int, bit: uint8) -> uint8:
    mask = uint8(1 << index)
    v &= ~mask
    return v | mask if bit == 1 else v

def get_bit(v: uint8, index: int) -> uint8:
    mask = uint8(1 << index)
    return (v & mask) >> index

def set_bit(v: uint16, index: int, bit: uint16) -> uint16:
    mask = uint16(1 << index)
    v &= ~mask
    return v | mask if bit == 1 else v

def get_bit(v: uint16, index: int) -> uint16:
    mask = uint16(1 << index)
    return (v & mask) >> index
