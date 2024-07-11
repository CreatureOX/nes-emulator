from libc.stdint cimport int8_t, uint16_t

from nes.bus.bus cimport CPUBus


cdef class CPUDebugger:
    cdef CPUBus bus

    cpdef dict status(self)
    cpdef dict registers(self)
    cpdef str ram(self, uint16_t, uint16_t)
    cpdef dict to_asm(self, uint16_t, uint16_t)
    cpdef uint16_t PC(self)