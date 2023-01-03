from libc.stdint cimport uint8_t, uint16_t

from bus cimport CPUBus


cdef class Op:
    cdef public str name
    cdef public object operate
    cdef public object addrmode
    cdef public int cycles

cdef class CPU6502:
    cdef public uint8_t a 
    cdef public uint8_t x
    cdef public uint8_t y
    cdef public uint8_t stkp
    cdef public uint16_t pc
    cdef public uint8_t status

    cdef void set_a(self, uint8_t)
    cdef void set_x(self, uint8_t)
    cdef void set_y(self, uint8_t)
    cdef void set_stkp(self, uint8_t)
    cdef void set_pc(self, uint16_t)
    cdef void set_status(self, uint8_t)
    cdef uint8_t getFlag(self, FLAGS)
    cdef void setFlag(self, FLAGS, bint)

    cdef uint8_t[2048] ram
    cdef CPUBus bus

    cdef uint8_t read(self, uint16_t)
    cdef void write(self, uint16_t, uint8_t)

    cdef uint8_t fetched
    cdef uint16_t addr_abs
    cdef uint16_t addr_rel

    cdef void set_fetched(self, uint8_t)
    cdef void set_addr_abs(self, uint16_t)
    cdef void set_addr_rel(self, uint16_t)

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
    
    cpdef void reset(self)
    cpdef void irq(self)
    cpdef void nmi(self)

    cdef int clock_count

    cpdef void clock(self)
    cpdef bint complete(self)