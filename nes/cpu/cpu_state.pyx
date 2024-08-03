from libc.stdint cimport uint8_t
from libc.string cimport memcpy

from nes.cpu.cpu cimport CPU6502

import numpy as np
cimport numpy as np


cdef class CPUState:
    def __init__(self, CPU6502 cpu) -> None:
        self.registers = cpu.registers
        self.ram = np.array(cpu.ram, dtype=np.uint8)
        self.fetched = cpu.fetched
        self.addr_abs = cpu.addr_abs
        self.addr_rel = cpu.addr_rel
        self.opcode = cpu.opcode
        self.temp = cpu.temp
        self.remaining_cycles = cpu.remaining_cycles
