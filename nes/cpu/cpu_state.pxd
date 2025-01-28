from libc.stdint cimport uint8_t, uint16_t
import numpy as np
cimport numpy as np

from nes.cpu.registers cimport Registers
from nes.cpu.cpu cimport CPU6502


cdef class CPUState:
    cdef Registers registers
    cdef np.ndarray ram
    cdef uint8_t fetched
    cdef uint16_t addr_abs
    cdef uint16_t addr_rel
    cdef uint8_t opcode
    cdef uint16_t temp
    cdef uint8_t remaining_cycles

    cdef void load_to(self, CPU6502 cpu)
