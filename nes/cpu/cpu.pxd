from libc.stdint cimport uint8_t, uint16_t

from nes.bus.bus cimport CPUBus
from nes.cpu.registers cimport Registers, StatusMask
    
cdef class CPU6502:
    cdef Registers registers
    cdef uint8_t[:] ram
    
    cdef CPUBus bus

    cdef uint8_t read(self, uint16_t)
    cdef void write(self, uint16_t, uint8_t)

    cdef uint8_t fetched
    cdef uint16_t addr_abs
    cdef uint16_t addr_rel

    cdef void set_fetched(self, uint8_t)
    cdef void set_addr_abs(self, long)
    cdef void set_addr_rel(self, long)

    cdef void push(self, uint8_t)
    cdef uint8_t pull(self)
    cdef void push_2_bytes(self, uint16_t)
    cdef uint16_t pull_2_bytes(self)

    cpdef uint8_t IMP(self)
    cpdef uint8_t IMM(self)
    cpdef uint8_t ZP0(self)
    cpdef uint8_t ZPX(self)
    cpdef uint8_t ZPY(self)
    cpdef uint8_t REL(self)
    cpdef uint8_t ABS(self)
    cpdef uint8_t ABX(self)
    cpdef uint8_t ABY(self)
    cpdef uint8_t IND(self)
    cpdef uint8_t IZX(self)
    cpdef uint8_t IZY(self)

    cdef uint8_t opcode
    cdef uint16_t temp
    cdef uint8_t remaining_cycles

    cdef void set_temp(self, uint16_t)
    cdef uint8_t fetch(self)

    cpdef uint8_t ADC(self)
    cpdef uint8_t SBC(self)
    cpdef uint8_t AND(self)
    cpdef uint8_t ASL(self)
    cpdef uint8_t BCC(self)
    cpdef uint8_t BCS(self)
    cpdef uint8_t BEQ(self)
    cpdef uint8_t BIT(self)
    cpdef uint8_t BMI(self)
    cpdef uint8_t BNE(self)
    cpdef uint8_t BPL(self)
    cpdef uint8_t BRK(self)
    cpdef uint8_t BVC(self)
    cpdef uint8_t BVS(self)
    cpdef uint8_t CLC(self)
    cpdef uint8_t CLD(self)
    cpdef uint8_t CLI(self)
    cpdef uint8_t CLV(self)
    cpdef uint8_t CMP(self)
    cpdef uint8_t CPX(self)
    cpdef uint8_t CPY(self)
    cpdef uint8_t DEC(self)
    cpdef uint8_t DEX(self)
    cpdef uint8_t DEY(self)
    cpdef uint8_t EOR(self)
    cpdef uint8_t INC(self)
    cpdef uint8_t INX(self)
    cpdef uint8_t INY(self)
    cpdef uint8_t JMP(self)
    cpdef uint8_t JSR(self)
    cpdef uint8_t LDA(self)
    cpdef uint8_t LDX(self)
    cpdef uint8_t LDY(self)
    cpdef uint8_t LSR(self)
    cpdef uint8_t NOP(self)
    cpdef uint8_t ORA(self)
    cpdef uint8_t PHA(self)
    cpdef uint8_t PHP(self)
    cpdef uint8_t PLA(self)
    cpdef uint8_t PLP(self)
    cpdef uint8_t ROL(self)
    cpdef uint8_t ROR(self)
    cpdef uint8_t RTI(self)
    cpdef uint8_t RTS(self)
    cpdef uint8_t SEC(self)
    cpdef uint8_t SED(self)
    cpdef uint8_t SEI(self)
    cpdef uint8_t STA(self)
    cpdef uint8_t STX(self)
    cpdef uint8_t STY(self)
    cpdef uint8_t TAX(self)
    cpdef uint8_t TAY(self)
    cpdef uint8_t TSX(self)
    cpdef uint8_t TXA(self)
    cpdef uint8_t TXS(self)
    cpdef uint8_t TYA(self)
    cpdef uint8_t XXX(self)
    
    cdef list lookup
    
    cdef void power_up(self)
    cdef void reset(self)
    cdef void irq(self)
    cdef void nmi(self)

    # A1: /NMI signal line (level driven by PPU, edge detected by CPU)
    cdef bint nmi_line
    # /NMI line level as of the last phi2 sample; the edge detector compares
    # the current phi2 sample against this to detect a low->high transition.
    cdef bint nmi_prev_phi2_level
    cdef bint nmi_pending
    cdef void set_nmi_line(self, bint level)

    # A1: /IRQ signal line (level driven by mapper/APU, sampled by CPU at
    # instruction boundaries and masked by the I flag; no edge latch)
    cdef bint irq_line
    cdef void set_irq_line(self, bint level)

    # HARDWARE QUIRK method: page-cross dummy read (see doc/13-quirk-method-extraction.md)
    cdef bint emulate_page_cross_dummy_read(self, uint16_t base, uint16_t addr)

    # A2: instruction execution is deferred to the LAST cycle of the
    # instruction's cycle budget, so that bus accesses (PPU registers in
    # particular) land at the right dot instead of up to N-1 CPU cycles early.
    cdef bint pending_execute

    # S2: bus dot (nSystemClockCounter) at the moment the /NMI edge latched or
    # the /IRQ line went high. A 6502 samples its interrupt inputs at phi2 of
    # the SECOND-TO-LAST cycle of the instruction in progress (the last cycle
    # is reserved for the instruction's final bus operation and cannot be
    # preempted). Each CPU cycle spans three PPU dots; phi2 is the middle dot,
    # one dot after the cycle's tick dot. So with the boundary at bus dot D
    # the sample lands at D-5, and an edge that arrives after it (latch dot
    # >= D-4) is deferred to the NEXT instruction's end. The CPU services a
    # pending interrupt at its boundary iff latch_dot <= D-5.
    cdef long long nmi_latch_dot
    cdef long long irq_latch_dot
    # True while the 7/8-cycle interrupt sequence itself is running. Hardware
    # does not poll during that sequence, which guarantees at least one handler
    # instruction executes before another interrupt can be taken.
    cdef bint in_interrupt

    cdef int clock_count
    
    cdef uint8_t clock(self) except *
    cpdef bint complete(self)