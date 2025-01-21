from libc.stdint cimport uint8_t, uint16_t


cdef extern from *: 
    """ 
    struct StatusBitField { 
        unsigned int C: 1;
        unsigned int Z: 1;
        unsigned int I: 1;
        unsigned int D: 1;
        unsigned int B: 1;
        unsigned int U: 1;
        unsigned int V: 1;
        unsigned int N: 1;
    }; 
    """ 
    cdef struct StatusBitField:
        bint C
        bint Z
        bint I
        bint D
        bint B
        bint U
        bint V
        bint N

cdef union StatusUnion:
    StatusBitField bits
    unsigned int value

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
    cdef public uint16_t PC # program_counter    
    cdef public uint8_t SP  # stack_pointer
    cdef public uint8_t A   # accumulator
    cdef public uint8_t X   # index_X
    cdef public uint8_t Y   # index_Y
    cdef public StatusUnion status
