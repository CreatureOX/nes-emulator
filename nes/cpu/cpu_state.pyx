import numpy as np
cimport numpy as np


cdef class CPUState:
    """
    CPU state snapshot for save/load functionality.
    
    Captures the complete state of the 6502 CPU including registers,
    RAM contents, and internal execution state.
    """
    def __init__(self, CPU6502 cpu) -> None:
        self.registers = cpu.registers
        self.ram = np.array(cpu.ram, dtype=np.uint8)
        self.fetched = cpu.fetched
        self.addr_abs = cpu.addr_abs
        self.addr_rel = cpu.addr_rel
        self.opcode = cpu.opcode
        self.temp = cpu.temp
        self.remaining_cycles = cpu.remaining_cycles

    cdef void load_to(self, CPU6502 cpu):
        """Restore CPU state from this snapshot."""
        cpu.registers = self.registers
        cpu.ram = self.ram
        cpu.fetched = self.fetched
        cpu.addr_abs = self.addr_abs
        cpu.addr_rel = self.addr_rel
        cpu.opcode = self.opcode
        cpu.temp = self.temp
        cpu.remaining_cycles = self.remaining_cycles