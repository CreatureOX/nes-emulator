from cartridge cimport Cartridge
from bus cimport CPUBus


cdef class Console:
    cdef public CPUBus bus

    cpdef void reset(self)
    cpdef void clock(self)
    cpdef void frame(self)
    cpdef void run(self)
    