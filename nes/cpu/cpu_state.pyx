import numpy as np
cimport numpy as np


cdef class CPUState:
    """
    CPU state snapshot for save/load functionality.
    
    Captures the complete state of the 6502 CPU including registers,
    RAM contents, and internal execution state.
    """
    def __init__(self, CPU6502 cpu) -> None:
        # Copy register values into a standalone object. Holding cpu.registers
        # by reference would make every snapshot alias the same live registers,
        # so rewind could not restore distinct points in time.
        self.registers = Registers()
        self.registers.PC = cpu.registers.PC
        self.registers.SP = cpu.registers.SP
        self.registers.A = cpu.registers.A
        self.registers.X = cpu.registers.X
        self.registers.Y = cpu.registers.Y
        self.registers.P = cpu.registers.P
        self.ram = np.array(cpu.ram, dtype=np.uint8)
        self.fetched = cpu.fetched
        self.addr_abs = cpu.addr_abs
        self.addr_rel = cpu.addr_rel
        self.opcode = cpu.opcode
        self.temp = cpu.temp
        self.remaining_cycles = cpu.remaining_cycles

        # Pipeline / interrupt state sampled at an arbitrary PPU dot, not an
        # instruction boundary. Without these a rewind resumes with a coherent
        # register file but a stale execution pipeline.
        self.pending_execute = cpu.pending_execute
        self.last_opcode_addr = cpu.last_opcode_addr
        self.operand_fetch = cpu.operand_fetch
        self.nmi_line = cpu.nmi_line
        self.nmi_prev_phi2_level = cpu.nmi_prev_phi2_level
        self.nmi_pending = cpu.nmi_pending
        self.irq_line = cpu.irq_line
        self.nmi_latch_dot = cpu.nmi_latch_dot
        self.irq_latch_dot = cpu.irq_latch_dot
        self.last_clock_dot = cpu.last_clock_dot
        self.in_interrupt = cpu.in_interrupt
        self.irq_i_latched = cpu.irq_i_latched
        self.irq_defer_i = cpu.irq_defer_i
        self.branch_ignore_irq = cpu.branch_ignore_irq
        self.branch_dummy_reads = cpu.branch_dummy_reads
        self.branch_dummy_addr = cpu.branch_dummy_addr
        self.int_seq_deferred = cpu.int_seq_deferred
        self.int_seq_start_dot = cpu.int_seq_start_dot
        self.int_seq_start_margin = cpu.int_seq_start_margin
        self.last_fetch_dot = cpu.last_fetch_dot
        self.last_fetch_margin = cpu.last_fetch_margin
        self.clock_count = cpu.clock_count

    cdef void load_to(self, CPU6502 cpu):
        """Restore CPU state from this snapshot."""
        cpu.registers.PC = self.registers.PC
        cpu.registers.SP = self.registers.SP
        cpu.registers.A = self.registers.A
        cpu.registers.X = self.registers.X
        cpu.registers.Y = self.registers.Y
        cpu.registers.P = self.registers.P
        cpu.ram = self.ram
        cpu.fetched = self.fetched
        cpu.addr_abs = self.addr_abs
        cpu.addr_rel = self.addr_rel
        cpu.opcode = self.opcode
        cpu.temp = self.temp
        cpu.remaining_cycles = self.remaining_cycles

        cpu.pending_execute = self.pending_execute
        cpu.last_opcode_addr = self.last_opcode_addr
        cpu.operand_fetch = self.operand_fetch
        cpu.nmi_line = self.nmi_line
        cpu.nmi_prev_phi2_level = self.nmi_prev_phi2_level
        cpu.nmi_pending = self.nmi_pending
        cpu.irq_line = self.irq_line
        cpu.nmi_latch_dot = self.nmi_latch_dot
        cpu.irq_latch_dot = self.irq_latch_dot
        cpu.last_clock_dot = self.last_clock_dot
        cpu.in_interrupt = self.in_interrupt
        cpu.irq_i_latched = self.irq_i_latched
        cpu.irq_defer_i = self.irq_defer_i
        cpu.branch_ignore_irq = self.branch_ignore_irq
        cpu.branch_dummy_reads = self.branch_dummy_reads
        cpu.branch_dummy_addr = self.branch_dummy_addr
        cpu.int_seq_deferred = self.int_seq_deferred
        cpu.int_seq_start_dot = self.int_seq_start_dot
        cpu.int_seq_start_margin = self.int_seq_start_margin
        cpu.last_fetch_dot = self.last_fetch_dot
        cpu.last_fetch_margin = self.last_fetch_margin
        cpu.clock_count = self.clock_count