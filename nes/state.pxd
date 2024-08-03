from nes.cpu.cpu_state cimport CPUState
from nes.ppu.ppu_state cimport PPUState


cdef class State:
    cdef CPUState cpu_state
    cdef PPUState ppu_state
