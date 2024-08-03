from libc.stdint cimport uint8_t, uint16_t

from nes.cpu.registers cimport Registers

import numpy as np
cimport numpy as np


cdef class CPUState:
    cdef Registers registers
    cdef np.ndarray ram
    cdef uint8_t fetched
    cdef uint16_t addr_abs
    cdef uint16_t addr_rel
    cdef uint8_t opcode
    cdef uint16_t temp
    cdef uint8_t remaining_cycles
