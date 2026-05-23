from libc.stdint cimport uint8_t, uint16_t, uint32_t
from nes.cpu.status_register cimport StatusRegister

cdef enum StatusMask:
    C = 1 << 0
    Z = 1 << 1
    I = 1 << 2
    D = 1 << 3
    B = 1 << 4
    U = 1 << 5
    V = 1 << 6
    N = 1 << 7

cdef class Registers:
    cdef public uint16_t PC
    cdef public uint8_t SP
    cdef public uint8_t A
    cdef public uint8_t X
    cdef public uint8_t Y
    cdef public StatusRegister status