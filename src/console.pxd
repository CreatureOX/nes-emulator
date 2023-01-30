from libc.stdint cimport uint8_t

from cartridge cimport Cartridge
from bus cimport CPUBus


cdef uint8_t K_x
cdef uint8_t K_z
cdef uint8_t K_a
cdef uint8_t K_s
cdef uint8_t K_UP
cdef uint8_t K_DOWN
cdef uint8_t K_LEFT
cdef uint8_t K_RIGHT

cdef class Console:
    cdef public CPUBus bus

    cpdef void reset(self)
    cpdef void clock(self)
    cpdef void frame(self)
    cpdef void run(self)
    cpdef void control(self, list)
    