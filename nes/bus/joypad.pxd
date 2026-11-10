from libc.stdint cimport uint8_t


cdef class Joypad:
    cdef public uint8_t buttons
    cdef uint8_t shift

    cpdef void reset(self)
    cdef void strobe(self)
    cdef uint8_t read(self)
