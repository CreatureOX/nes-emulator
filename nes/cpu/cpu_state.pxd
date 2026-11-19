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

    # Instruction-pipeline and interrupt state. A snapshot is sampled right
    # after bus.run_frame() (PPU frame boundary), which need not coincide with
    # an instruction boundary, so it can land mid-instruction or mid-interrupt
    # sequence. Restoring only the visible registers leaves the pipeline in
    # the "now" state and corrupts execution after a rewind.
    cdef bint pending_execute
    cdef uint16_t last_opcode_addr
    cdef bint operand_fetch

    # /NMI and /IRQ line levels, edge detector and pending latch.
    cdef bint nmi_line
    cdef bint nmi_prev_phi2_level
    cdef bint nmi_pending
    cdef bint irq_line

    # Interrupt poll margins and the dot timestamps they compare against.
    # These share the PPU-dot time base with bus.divider.dot, which the bus
    # snapshot restores, so they must be restored together.
    cdef long long nmi_latch_dot
    cdef long long irq_latch_dot
    cdef long long last_clock_dot

    # In-flight interrupt sequence state (incl. NMI hijack of IRQ/BRK).
    cdef bint in_interrupt
    cdef bint irq_i_latched
    cdef bint irq_defer_i
    cdef bint branch_ignore_irq
    cdef uint8_t branch_dummy_reads
    cdef uint16_t branch_dummy_addr
    cdef bint int_seq_deferred
    cdef long long int_seq_start_dot
    cdef long long int_seq_start_margin
    cdef long long last_fetch_dot
    cdef long long last_fetch_margin

    cdef int clock_count

    cdef void load_to(self, CPU6502 cpu)