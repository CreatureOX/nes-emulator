from libc.stdint cimport uint8_t, uint16_t

from bus cimport CPUBus


cdef class StatusRegister:
    def __init__(self):
        self.value = 0
        self.status_mask = {
            "C": 1 << 0, # Carry Bit
            "Z": 1 << 1, # Zero
            "I": 1 << 2, # Disable Interrupts
            "D": 1 << 3, # Decimal Mode
            "B": 1 << 4, # Break
            "U": 1 << 5, # Unused
            "V": 1 << 6, # Overflow
            "N": 1 << 7 # Negative
        }

    cdef void _set_status(self, uint8_t mask, bint value):
        if value:
            self.value |= mask
        else:
            self.value &= ~mask

    cdef bint _get_status(self, uint8_t mask):
        return self.value & mask > 0

    @property
    def C(self):
        return self._get_status(self.status_mask["C"])

    @property
    def Z(self):
        return self._get_status(self.status_mask["Z"])

    @property
    def I(self):
        return self._get_status(self.status_mask["I"])

    @property
    def D(self):
        return self._get_status(self.status_mask["D"])

    @property
    def B(self):
        return self._get_status(self.status_mask["B"])

    @property
    def U(self):
        return self._get_status(self.status_mask["U"])

    @property
    def V(self):
        return self._get_status(self.status_mask["V"])

    @property
    def N(self):
        return self._get_status(self.status_mask["N"])

    @C.setter
    def C(self, bint value):
        self._set_status(self.status_mask["C"], value)

    @Z.setter
    def Z(self, bint value):
        self._set_status(self.status_mask["Z"], value)

    @I.setter
    def I(self, bint value):
        self._set_status(self.status_mask["I"], value)

    @D.setter
    def D(self, bint value):
        self._set_status(self.status_mask["D"], value)

    @B.setter
    def B(self, bint value):
        self._set_status(self.status_mask["B"], value)

    @U.setter
    def U(self, bint value):
        self._set_status(self.status_mask["U"], value)

    @V.setter
    def V(self, bint value):
        self._set_status(self.status_mask["V"], value)

    @N.setter
    def N(self, bint value):
        self._set_status(self.status_mask["N"], value)

cdef class Registers:
    def __init__(self):
        self.program_counter = 0x0000    
        self.stack_pointer = 0x00
        self.accumulator = 0x00
        self.index_X = 0x00                
        self.index_Y = 0x00
        self.status = StatusRegister()

    @property
    def PC(self):
        return self.program_counter

    @property
    def SP(self):
        return self.stack_pointer

    @property
    def A(self):
        return self.accumulator

    @property
    def X(self):
        return self.index_X

    @property
    def Y(self):
        return self.index_Y

    @property
    def P(self):
        return self.status.value

    @PC.setter
    def PC(self, long program_counter):
        self.program_counter = <uint16_t> program_counter & 0xFFFF

    @SP.setter
    def SP(self, long stack_pointer):
        self.stack_pointer = <uint8_t> stack_pointer & 0xFF

    @A.setter
    def A(self, long accumulator):
        self.accumulator = accumulator & 0xFF

    @X.setter
    def X(self, long index_X):
        self.index_X = <uint8_t> index_X & 0xFF

    @Y.setter
    def Y(self, long index_Y):
        self.index_Y = <uint8_t> index_Y & 0xFF

    @P.setter
    def P(self, long status_value):
        self.status.value = <uint8_t> status_value & 0xFF

cdef class Op:
    def __init__(self, str name, object operate, object addrmode, int cycles):
        self.name = name
        self.operate = operate
        self.addrmode = addrmode
        self.cycles = cycles

cdef class CPU6502:    
    cdef uint8_t read(self, uint16_t addr):
        addr &= 0xFFFF
        return self.bus.read(addr, False)

    cdef void write(self, uint16_t addr, uint8_t data):                      
        addr, data = addr & 0xFFFF, data & 0xFF
        self.bus.write(addr, data)

    cdef void set_fetched(self, uint8_t fetched):
        self.fetched = fetched & 0xFF

    cdef void set_addr_abs(self, long addr_abs):
        self.addr_abs = <uint16_t> addr_abs & 0xFFFF

    cdef void set_addr_rel(self, long addr_rel):
        self.addr_rel = <uint16_t> addr_rel & 0xFFFF

    cdef void push(self, uint8_t data):
        '''
        push 1 byte (8 bits) to the stack
        '''
        self.write(0x0100 + self.registers.SP, data)
        self.registers.SP -= 1

    cdef uint8_t pull(self):
        '''
        pop 1 byte (8 bits) from the stack
        '''
        self.registers.SP += 1
        return self.read(0x0100 + self.registers.SP)

    cdef void push_2_bytes(self, uint16_t data):
        '''
        push 2 bytes (16 bits) to the stack
        '''
        cdef uint8_t hi = <uint8_t> (data >> 8)
        cdef uint8_t lo = <uint8_t> (data & 0xFF)
        self.push(hi)
        self.push(lo)

    cdef uint16_t pull_2_bytes(self):
        '''
        pop 2 bytes (16 bits) from the stack
        '''
        cdef uint16_t lo = <uint16_t> self.pull()
        cdef uint16_t hi = <uint16_t> self.pull()
        return hi << 8 | lo

    cpdef uint8_t IMP(self):
        '''
        Address Mode: Implied
        '''
        self.set_fetched(self.registers.A)
        return 0

    cpdef uint8_t IMM(self):
        '''
        Address Mode: Immediate
        '''
        self.set_addr_abs(self.registers.PC)
        self.registers.PC += 1
        return 0

    cpdef uint8_t ZP0(self):
        '''
        Address Mode: Zero Page
        '''
        self.set_addr_abs(self.read(self.registers.PC) & 0x00FF)
        self.registers.PC += 1
        return 0

    cpdef uint8_t ZPX(self):
        '''
        Address Mode: Zero Page with X Offset
        '''
        self.set_addr_abs((self.read(self.registers.PC) + self.registers.X) & 0x00FF)
        self.registers.PC += 1
        return 0

    cpdef uint8_t ZPY(self):
        '''
        Address Mode: Zero Page with Y Offset
        '''
        self.set_addr_abs((self.read(self.registers.PC) + self.registers.Y) & 0x00FF)
        self.registers.PC += 1
        return 0

    cpdef uint8_t REL(self):
        '''
        Address Mode: Relative 
        '''
        self.set_addr_rel(self.read(self.registers.PC))
        self.registers.PC += 1
        if (self.addr_rel & 0x80):
            self.set_addr_rel(self.addr_rel | 0xFF00)
        return 0

    cpdef uint8_t ABS(self):
        '''
        Address Mode: Absolute 
        '''
        cdef uint8_t lo = self.read(self.registers.PC)
        self.registers.PC += 1
        cdef uint8_t hi = self.read(self.registers.PC)
        self.registers.PC += 1
        
        self.set_addr_abs((hi << 8) | lo)
        return 0

    cpdef uint8_t ABX(self):
        '''
        Address Mode: Absolute with X Offset
        '''
        cdef uint8_t lo = self.read(self.registers.PC)
        self.registers.PC += 1
        cdef uint8_t hi = self.read(self.registers.PC)
        self.registers.PC += 1
        
        self.set_addr_abs(<uint16_t>(hi << 8 | lo) + self.registers.X)
                
        return 1 if (self.addr_abs & 0xFF00) != (hi << 8) else 0

    cpdef uint8_t ABY(self):
        '''
        Address Mode: Absolute with Y Offset
        '''
        cdef uint8_t lo = self.read(self.registers.PC)
        self.registers.PC += 1
        cdef uint8_t hi = self.read(self.registers.PC)
        self.registers.PC += 1
        
        self.set_addr_abs(<uint16_t>(hi << 8 | lo) + self.registers.Y)
        
        return 1 if (self.addr_abs & 0xFF00) != (hi << 8) else 0

    cpdef uint8_t IND(self):
        '''
        Address Mode: Indirect
        '''
        cdef uint8_t ptr_lo = self.read(self.registers.PC)
        self.registers.PC += 1
        cdef uint8_t ptr_hi = self.read(self.registers.PC)
        self.registers.PC += 1
        
        cdef uint16_t ptr = (ptr_hi << 8) | ptr_lo
        
        if ptr_lo == 0x00FF:
            self.set_addr_abs((self.read(ptr & 0xFF00) << 8) | (self.read(ptr + 0)))
        else:
            self.set_addr_abs((self.read(ptr + 1) << 8) | (self.read(ptr + 0)))
        return 0

    cpdef uint8_t IZX(self):
        '''
        Address Mode: Indirect X / Indexed Indirect
        '''
        cdef uint8_t t = self.read(self.registers.PC)
        self.registers.PC += 1

        cdef uint8_t lo = self.read((t + self.registers.X) & 0x00FF)
        cdef uint8_t hi = self.read((t + self.registers.X + 1) & 0x00FF)     
        self.set_addr_abs((hi << 8) | lo)

        return 0

    cpdef uint8_t IZY(self):
        '''
        Address Mode: Indirect Y / Indirect Indexed
        '''
        cdef uint8_t t = self.read(self.registers.PC)
        self.registers.PC += 1
        
        cdef uint8_t lo = self.read(t & 0x00FF)
        cdef uint8_t hi = self.read((t + 1) & 0x00FF)
        
        self.set_addr_abs((hi << 8) | lo)
        self.set_addr_abs(self.addr_abs + self.registers.Y)

        return 1 if (self.addr_abs & 0xFF00) != (hi << 8) else 0

    cdef void set_temp(self, uint16_t temp):
        self.temp = temp & 0xFFFF

    cdef uint8_t fetch(self):
        '''
        fetch opcode
        '''
        if self.lookup[self.opcode].addrmode != self.IMP:
            self.fetched = self.read(self.addr_abs)
        return self.fetched

    cpdef uint8_t ADC(self):
        '''
        Instruction: Add with Carry In
        Function:    A = A + M + C
        Flags Out:   C, V, N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.set_temp(<uint16_t>self.registers.A + <uint16_t>self.fetched + <uint16_t>self.registers.status.C)

        self.registers.status.C = self.temp > 255
        self.registers.status.Z = self.temp & 0x00FF == 0
        self.registers.status.V = (~(self.registers.A ^ self.fetched) & (self.registers.A ^ self.temp)) & 0x0080 > 0
        self.registers.status.N = self.temp & 0x80 > 0
        
        self.registers.A = self.temp & 0x00FF
        return 1

    cpdef uint8_t SBC(self):
        '''
        Instruction: Subtraction with Borrow In
        Function:    A = A - M - (1 - C)
        Flags Out:   C, V, N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        cdef uint16_t value = self.fetched ^ 0x00FF
        self.set_temp(<uint16_t>self.registers.A + value + <uint16_t>self.registers.status.C)

        self.registers.status.C = self.temp & 0xFF00 > 0
        self.registers.status.Z = self.temp & 0x00FF == 0
        self.registers.status.V = (self.temp ^ <uint16_t>self.registers.A) & (self.temp ^ value) & 0x0080 > 0
        self.registers.status.N = self.temp & 0x0080 > 0

        self.registers.A = self.temp & 0x00FF
        return 1

    cpdef uint8_t AND(self):
        '''
        Instruction: Bitwise Logic AND
        Function:    A = A & M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.registers.A &= self.fetched
        
        self.registers.status.Z = self.registers.A == 0x00
        self.registers.status.N = self.registers.A & 0x80 > 0
        
        return 1

    cpdef uint8_t ASL(self):
        '''
        Instruction: Arithmetic Shift Left
        Function:    A = C <- (A << 1) <- 0
        Flags Out:   N, Z, C
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(<uint16_t>self.fetched << 1)
        
        self.registers.status.C = self.temp & 0xFF00 > 0
        self.registers.status.Z = self.temp & 0x00FF == 0x0000
        self.registers.status.N = self.temp & 0x80 > 0
        
        if (self.lookup[self.opcode].addrmode == self.IMP):
            self.registers.A = self.temp & 0x00FF
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    cpdef uint8_t BCC(self):
        '''
        Instruction: Branch if Carry Clear
        Function:    if(C == 0) pc = address 
        Return:      Require additional 0 clock cycle
        '''
        if (self.registers.status.C == 0):
            self.remaining_cycles += 1
            self.set_addr_abs(self.registers.PC + self.addr_rel)
            
            if ((self.addr_abs & 0xFF00) != (self.registers.PC & 0xFF00)):
                self.remaining_cycles += 1

            self.registers.PC = self.addr_abs
        return 0

    cpdef uint8_t BCS(self):
        '''
        Instruction: Branch if Carry Set
        Function:    if(C == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.registers.status.C == 1):
            self.remaining_cycles += 1
            self.set_addr_abs(self.registers.PC + self.addr_rel)
            
            if ((self.addr_abs & 0xFF00) != (self.registers.PC & 0xFF00)):
                self.remaining_cycles += 1

            self.registers.PC = self.addr_abs
        return 0

    cpdef uint8_t BEQ(self):
        '''
        Instruction: Branch if Equal
        Function:    if(Z == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.registers.status.Z == 1):
            self.remaining_cycles += 1
            self.set_addr_abs(self.registers.PC + self.addr_rel)
            
            if ((self.addr_abs & 0xFF00) != (self.registers.PC & 0xFF00)):
                self.remaining_cycles += 1

            self.registers.PC = self.addr_abs
        return 0

    cpdef uint8_t BIT(self):
        ''' 
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.registers.A & self.fetched)

        self.registers.status.Z = self.temp & 0x00FF == 0x00
        self.registers.status.N = self.fetched & (1 << 7) > 0
        self.registers.status.V = self.fetched & (1 << 6) > 0

        return 0

    cpdef uint8_t BMI(self):
        '''
        Instruction: Branch if Negative
        Function:    if(N == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.registers.status.N == 1):
            self.remaining_cycles += 1
            self.set_addr_abs(self.registers.PC + self.addr_rel)
            
            if ((self.addr_abs & 0xFF00) != (self.registers.PC & 0xFF00)):
                self.remaining_cycles += 1
            self.registers.PC = self.addr_abs
        return 0

    cpdef uint8_t BNE(self):
        '''
        Instruction: Branch if Not Equal
        Function:    if(Z == 0) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.registers.status.Z == 0):
            self.remaining_cycles += 1
            self.set_addr_abs(self.registers.PC + self.addr_rel)

            if ((self.addr_abs & 0xFF00) != (self.registers.PC & 0xFF00)):
                self.remaining_cycles += 1

            self.registers.PC = self.addr_abs
        return 0

    cpdef uint8_t BPL(self):
        '''
        Instruction: Branch if Positive
        Function:    if(N == 0) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.registers.status.N == 0):
            self.remaining_cycles += 1
            self.set_addr_abs(self.registers.PC + self.addr_rel)

            if ((self.addr_abs & 0xFF00) != (self.registers.PC & 0xFF00)):
                self.remaining_cycles += 1

            self.registers.PC = self.addr_abs
    
        return 0

    cpdef uint8_t BRK(self):
        '''
        Instruction: Break
        Function:    Program Sourced Interrupt
        Return:      Require additional 0 clock cycle
        '''
        self.registers.PC += 1
    
        self.registers.status.I = True
        self.push_2_bytes(self.registers.PC)

        self.registers.status.B = True
        self.push(self.registers.status.value)
        self.registers.status.B = False
        
        self.registers.PC = self.read(0xFFFE) | self.read(0xFFFF) << 8
        return 0

    cpdef uint8_t BVC(self):
        '''
        Instruction: Branch if Overflow Clear
        Function:    if(V == 0) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.registers.status.V == 0):
            self.remaining_cycles += 1
            self.set_addr_abs(self.registers.PC + self.addr_rel)

            if ((self.addr_abs & 0xFF00) != (self.registers.PC & 0xFF00)):
                self.remaining_cycles += 1

            self.registers.PC = self.addr_abs
        return 0

    cpdef uint8_t BVS(self):
        '''
        Instruction: Branch if Overflow Set
        Function:    if(V == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.registers.status.V == 1):
            self.remaining_cycles += 1
            self.set_addr_abs(self.registers.PC + self.addr_rel)

            if ((self.addr_abs & 0xFF00) != (self.registers.PC & 0xFF00)):
                self.remaining_cycles += 1

            self.registers.PC = self.addr_abs
        return 0

    cpdef uint8_t CLC(self):
        '''
        Instruction: Clear Carry Flag
        Function:    C = 0
        Return:      Require additional 0 clock cycle
        '''
        self.registers.status.C = False
        return 0

    cpdef uint8_t CLD(self):
        '''
        Instruction: Clear Decimal Flag
        Function:    D = 0
        Return:      Require additional 0 clock cycle
        '''
        self.registers.status.D = False
        return 0

    cpdef uint8_t CLI(self):
        '''
        Instruction: Disable Interrupts / Clear Interrupt Flag
        Function:    I = 0
        Return:      Require additional 0 clock cycle
        '''
        self.registers.status.I = False
        return 0

    cpdef uint8_t CLV(self):
        '''
        Instruction: Clear Overflow Flag
        Function:    V = 0
        Return:      Require additional 0 clock cycle
        '''
        self.registers.status.V = False
        return 0

    cpdef uint8_t CMP(self):
        '''
        Instruction: Compare Accumulator
        Function:    C <- A >= M      Z <- (A - M) == 0
        Flags Out:   N, C, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.set_temp(<uint16_t>self.registers.A - <uint16_t>self.fetched)
        self.registers.status.C = self.registers.A >= self.fetched
        self.registers.status.Z = self.temp & 0x00FF == 0x0000
        self.registers.status.N = self.temp & 0x0080 > 0
        return 1

    cpdef uint8_t CPX(self):
        '''
        Instruction: Compare X Register
        Function:    C <- X >= M      Z <- (X - M) == 0
        Flags Out:   N, C, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(<uint16_t>self.registers.X - <uint16_t>self.fetched)
        self.registers.status.C = self.registers.X >= self.fetched
        self.registers.status.Z = self.temp & 0x00FF == 0x0000
        self.registers.status.N = self.temp & 0x0080 > 0
        return 0

    cpdef uint8_t CPY(self):
        '''
        Instruction: Compare Y Register
        Function:    C <- Y >= M      Z <- (Y - M) == 0
        Flags Out:   N, C, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(<uint16_t>self.registers.Y - <uint16_t>self.fetched)
        self.registers.status.C = self.registers.Y >= self.fetched
        self.registers.status.Z = self.temp & 0x00FF == 0x0000
        self.registers.status.N = self.temp & 0x0080 > 0
        return 0

    cpdef uint8_t DEC(self):
        '''
        Instruction: Decrement Value at Memory Location
        Function:    M = M - 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.fetched - 1)
        self.write(self.addr_abs, self.temp & 0x00FF)
        self.registers.status.Z = self.temp & 0x00FF == 0x0000
        self.registers.status.N = self.temp & 0x0080 > 0
        return 0

    cpdef uint8_t DEX(self):
        '''
        Instruction: Decrement X Register
        Function:    X = X - 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.X -= 1
        self.registers.status.Z = self.registers.X == 0x00
        self.registers.status.N = self.registers.X & 0x80 > 0
        return 0

    cpdef uint8_t DEY(self):
        '''
        Instruction: Decrement Y Register
        Function:    Y = Y - 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.Y -= 1
        self.registers.status.Z = self.registers.Y == 0x00
        self.registers.status.N = self.registers.Y & 0x80 > 0
        return 0

    cpdef uint8_t EOR(self):
        '''
        Instruction: Bitwise Logic XOR
        Function:    A = A xor M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.registers.A ^= self.fetched
        self.registers.status.Z = self.registers.A == 0x00
        self.registers.status.N = self.registers.A & 0x80 > 0
        return 1

    cpdef uint8_t INC(self):
        '''
        Instruction: Increment Value at Memory Location
        Function:    M = M + 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.fetched + 1)
        self.write(self.addr_abs, self.temp & 0x00FF)
        self.registers.status.Z = self.temp & 0x00FF == 0x0000
        self.registers.status.N = self.temp & 0x0080 > 0
        return 0

    cpdef uint8_t INX(self):
        '''
        Instruction: Increment X Register
        Function:    X = X + 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.X += 1
        self.registers.status.Z = self.registers.X == 0x00
        self.registers.status.N = self.registers.X & 0x80 > 0
        return 0

    cpdef uint8_t INY(self):
        '''
        Instruction: Increment Y Register
        Function:    Y = Y + 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.Y += 1
        self.registers.status.Z = self.registers.Y == 0x00
        self.registers.status.N = self.registers.Y & 0x80 > 0
        return 0

    cpdef uint8_t JMP(self):
        '''
        Instruction: Jump To Location
        Function:    pc = address
        Return:      Require additional 0 clock cycle
        '''
        self.registers.PC = self.addr_abs
        return 0

    cpdef uint8_t JSR(self):
        '''
        Instruction: Jump To Sub-Routine
        Function:    Push current pc to stack, pc = address
        Return:      Require additional 0 clock cycle
        '''
        self.registers.PC -= 1
        self.push_2_bytes(self.registers.PC)
        self.registers.PC = self.addr_abs
        return 0

    cpdef uint8_t LDA(self):
        '''
        Instruction: Load The Accumulator
        Function:    A = M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.registers.A = self.fetched
        self.registers.status.Z = self.registers.A == 0x00
        self.registers.status.N = self.registers.A & 0x80 > 0
        return 1

    cpdef uint8_t LDX(self):
        '''
        Instruction: Load The X Register
        Function:    X = M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.registers.X = self.fetched
        self.registers.status.Z = self.registers.X == 0x00
        self.registers.status.N = self.registers.X & 0x80 > 0
        return 1

    cpdef uint8_t LDY(self):
        '''
        Instruction: Load The Y Register
        Function:    Y = M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.registers.Y = self.fetched
        self.registers.status.Z = self.registers.Y == 0x00
        self.registers.status.N = self.registers.Y & 0x80 > 0
        return 1

    cpdef uint8_t LSR(self):
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.registers.status.C = self.fetched & 0x0001 > 0
        self.set_temp(self.fetched >> 1)   
        self.registers.status.Z = self.temp & 0x00FF == 0x0000
        self.registers.status.N = self.temp & 0x0080 > 0
        if (self.lookup[self.opcode].addrmode == self.IMP):
            self.registers.A = self.temp & 0x00FF
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    cpdef uint8_t NOP(self):
        '''
        Instruction: Do nothing
        Return:      Require additional 0 or 1 clock cycle
        '''
        return 1 if self.opcode == 0x1C \
            or self.opcode == 0x3C \
            or self.opcode == 0x5C \
            or self.opcode == 0x7C \
            or self.opcode == 0xDC \
            or self.opcode == 0xFC \
            else 0

    cpdef uint8_t ORA(self):
        '''
        Instruction: Bitwise Logic OR
        Function:    A = A | M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.registers.A |= self.fetched
        self.registers.status.Z = self.registers.A == 0x00
        self.registers.status.N = self.registers.A & 0x80 > 0
        return 1

    cpdef uint8_t PHA(self):
        '''
        Instruction: Push Accumulator to Stack
        Function:    A -> stack
        Return:      Require additional 0 clock cycle
        '''
        self.push(self.registers.A)
        return 0

    cpdef uint8_t PHP(self):
        '''
        Instruction: Push Status Register to Stack
        Function:    status -> stack
        Return:      Require additional 0 clock cycle
        '''
        self.push(self.registers.status.value | self.registers.status.status_mask["B"] | self.registers.status.status_mask["U"])
        self.registers.status.B = False
        self.registers.status.U = False
        return 0

    cpdef uint8_t PLA(self):
        '''
        Instruction: Pop Accumulator off Stack
        Function:    A <- stack
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.A = self.pull()
        self.registers.status.Z = self.registers.A == 0x00
        self.registers.status.N = self.registers.A & 0x80 > 0
        return 0

    cpdef uint8_t PLP(self):
        '''
        Instruction: Pop Status Register off Stack
        Function:    Status <- stack
        Return:      Require additional 0 clock cycle
        '''
        self.registers.status.value = self.pull()
        self.registers.status.U = True
        return 0

    cpdef uint8_t ROL(self):
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(<uint16_t> (self.fetched << 1) | self.registers.status.C)
        self.registers.status.C = self.temp & 0xFF00 > 0
        self.registers.status.Z = self.temp & 0x00FF == 0x0000
        self.registers.status.N = self.temp & 0x0080 > 0
        if (self.lookup[self.opcode].addrmode == self.IMP):
            self.registers.A = self.temp & 0x00FF
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    cpdef uint8_t ROR(self):
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(<uint16_t> (self.registers.status.C << 7) | (self.fetched >> 1))
        self.registers.status.C = self.fetched & 0x01 > 0
        self.registers.status.Z = self.temp & 0x00FF == 0x00
        self.registers.status.N = self.temp & 0x0080 > 0
        if (self.lookup[self.opcode].addrmode == self.IMP):
            self.registers.A = self.temp & 0x00FF
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    cpdef uint8_t RTI(self):
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.registers.status.value = self.pull()
        self.registers.status.value &= ~self.registers.status.status_mask["B"]
        self.registers.status.value &= ~self.registers.status.status_mask["U"]

        self.registers.PC = self.pull_2_bytes()
        return 0

    cpdef uint8_t RTS(self):
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.registers.PC = self.pull_2_bytes()
    
        self.registers.PC += 1
        return 0

    cpdef uint8_t SEC(self):
        '''
        Instruction: Set Carry Flag
        Function:    C = 1 
        Return:      Require additional 0 clock cycle
        '''
        self.registers.status.C = True
        return 0

    cpdef uint8_t SED(self):
        '''
        Instruction: Set Decimal Flag
        Function:    D = 1
        Return:      Require additional 0 clock cycle
        '''
        self.registers.status.D = True
        return 0

    cpdef uint8_t SEI(self):
        '''
        Instruction: Set Interrupt Flag / Enable Interrupts
        Function:    I = 1
        Return:      Require additional 0 clock cycle
        '''
        self.registers.status.I = True
        return 0

    cpdef uint8_t STA(self):
        '''
        Instruction: Store Accumulator at Address
        Function:    M = A
        Return:      Require additional 0 clock cycle
        '''
        self.write(self.addr_abs, self.registers.A)
        return 0

    cpdef uint8_t STX(self):
        '''
        Instruction: Store X Register at Address
        Function:    M = X
        Return:      Require additional 0 clock cycle
        '''
        self.write(self.addr_abs, self.registers.X)
        return 0

    cpdef uint8_t STY(self):
        '''
        Instruction: Store Y Register at Address
        Function:    M = Y
        Return:      Require additional 0 clock cycle
        '''
        self.write(self.addr_abs, self.registers.Y)
        return 0

    cpdef uint8_t TAX(self):
        '''
        Instruction: Transfer Accumulator to X Register
        Function:    X = A
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.X = self.registers.A
        self.registers.status.Z = self.registers.X == 0x00
        self.registers.status.N = self.registers.X & 0x80 > 0
        return 0

    cpdef uint8_t TAY(self):
        '''
        Instruction: Transfer Accumulator to Y Register
        Function:    Y = A
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.Y = self.registers.A
        self.registers.status.Z = self.registers.Y == 0x00
        self.registers.status.N = self.registers.Y & 0x80 > 0
        return 0

    cpdef uint8_t TSX(self):
        '''
        Instruction: Transfer Stack Pointer to X Register
        Function:    X = stack pointer
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.X = self.registers.SP
        self.registers.status.Z = self.registers.X == 0x00
        self.registers.status.N = self.registers.X & 0x80 > 0
        return 0

    cpdef uint8_t TXA(self):
        '''
        Instruction: Transfer X Register to Accumulator
        Function:    A = X
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.A = self.registers.X
        self.registers.status.Z = self.registers.A == 0x00
        self.registers.status.N = self.registers.A & 0x80 > 0
        return 0

    cpdef uint8_t TXS(self):
        '''
        Instruction: Transfer X Register to Stack Pointer
        Function:    stack pointer = X
        Return:      Require additional 0 clock cycle
        '''
        self.registers.SP = self.registers.X
        return 0

    cpdef uint8_t TYA(self):
        '''
        Instruction: Transfer Y Register to Accumulator
        Function:    A = Y
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.registers.A = self.registers.Y
        self.registers.status.Z = self.registers.A == 0x00
        self.registers.status.N = self.registers.A & 0x80 > 0
        return 0

    cpdef uint8_t XXX(self):
        '''
        Instruction: captures illegal opcodes
        Return:      Require additional 0 clock cycle
        '''
        return 0

    def __init__(self, CPUBus bus):
        self.registers = Registers()        
        self.registers.status.value = 0x34
        self.registers.SP = 0xFD
        
        self.ram = [0x00] * 2 * 1024

        self.bus = bus

        self.fetched = 0x00
        self.addr_abs = 0x0000
        self.addr_rel = 0x0000

        self.opcode = 0x00
        self.temp = 0x0000
        self.remaining_cycles = 0x00

        self.clock_count = 0

        self.lookup = [
            Op( "BRK", self.BRK, self.IMM, 7 ),Op( "ORA", self.ORA, self.IZX, 6 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "???", self.NOP, self.IMP, 3 ),Op( "ORA", self.ORA, self.ZP0, 3 ),Op( "ASL", self.ASL, self.ZP0, 5 ),Op( "???", self.XXX, self.IMP, 5 ),Op( "PHP", self.PHP, self.IMP, 3 ),Op( "ORA", self.ORA, self.IMM, 2 ),Op( "ASL", self.ASL, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "ORA", self.ORA, self.ABS, 4 ),Op( "ASL", self.ASL, self.ABS, 6 ),Op( "???", self.XXX, self.IMP, 6 ),
            Op( "BPL", self.BPL, self.REL, 2 ),Op( "ORA", self.ORA, self.IZY, 5 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "ORA", self.ORA, self.ZPX, 4 ),Op( "ASL", self.ASL, self.ZPX, 6 ),Op( "???", self.XXX, self.IMP, 6 ),Op( "CLC", self.CLC, self.IMP, 2 ),Op( "ORA", self.ORA, self.ABY, 4 ),Op( "???", self.NOP, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 7 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "ORA", self.ORA, self.ABX, 4 ),Op( "ASL", self.ASL, self.ABX, 7 ),Op( "???", self.XXX, self.IMP, 7 ),
            Op( "JSR", self.JSR, self.ABS, 6 ),Op( "AND", self.AND, self.IZX, 6 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "BIT", self.BIT, self.ZP0, 3 ),Op( "AND", self.AND, self.ZP0, 3 ),Op( "ROL", self.ROL, self.ZP0, 5 ),Op( "???", self.XXX, self.IMP, 5 ),Op( "PLP", self.PLP, self.IMP, 4 ),Op( "AND", self.AND, self.IMM, 2 ),Op( "ROL", self.ROL, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "BIT", self.BIT, self.ABS, 4 ),Op( "AND", self.AND, self.ABS, 4 ),Op( "ROL", self.ROL, self.ABS, 6 ),Op( "???", self.XXX, self.IMP, 6 ),
            Op( "BMI", self.BMI, self.REL, 2 ),Op( "AND", self.AND, self.IZY, 5 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "AND", self.AND, self.ZPX, 4 ),Op( "ROL", self.ROL, self.ZPX, 6 ),Op( "???", self.XXX, self.IMP, 6 ),Op( "SEC", self.SEC, self.IMP, 2 ),Op( "AND", self.AND, self.ABY, 4 ),Op( "???", self.NOP, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 7 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "AND", self.AND, self.ABX, 4 ),Op( "ROL", self.ROL, self.ABX, 7 ),Op( "???", self.XXX, self.IMP, 7 ),
            Op( "RTI", self.RTI, self.IMP, 6 ),Op( "EOR", self.EOR, self.IZX, 6 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "???", self.NOP, self.IMP, 3 ),Op( "EOR", self.EOR, self.ZP0, 3 ),Op( "LSR", self.LSR, self.ZP0, 5 ),Op( "???", self.XXX, self.IMP, 5 ),Op( "PHA", self.PHA, self.IMP, 3 ),Op( "EOR", self.EOR, self.IMM, 2 ),Op( "LSR", self.LSR, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "JMP", self.JMP, self.ABS, 3 ),Op( "EOR", self.EOR, self.ABS, 4 ),Op( "LSR", self.LSR, self.ABS, 6 ),Op( "???", self.XXX, self.IMP, 6 ),
            Op( "BVC", self.BVC, self.REL, 2 ),Op( "EOR", self.EOR, self.IZY, 5 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "EOR", self.EOR, self.ZPX, 4 ),Op( "LSR", self.LSR, self.ZPX, 6 ),Op( "???", self.XXX, self.IMP, 6 ),Op( "CLI", self.CLI, self.IMP, 2 ),Op( "EOR", self.EOR, self.ABY, 4 ),Op( "???", self.NOP, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 7 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "EOR", self.EOR, self.ABX, 4 ),Op( "LSR", self.LSR, self.ABX, 7 ),Op( "???", self.XXX, self.IMP, 7 ),
            Op( "RTS", self.RTS, self.IMP, 6 ),Op( "ADC", self.ADC, self.IZX, 6 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "???", self.NOP, self.IMP, 3 ),Op( "ADC", self.ADC, self.ZP0, 3 ),Op( "ROR", self.ROR, self.ZP0, 5 ),Op( "???", self.XXX, self.IMP, 5 ),Op( "PLA", self.PLA, self.IMP, 4 ),Op( "ADC", self.ADC, self.IMM, 2 ),Op( "ROR", self.ROR, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "JMP", self.JMP, self.IND, 5 ),Op( "ADC", self.ADC, self.ABS, 4 ),Op( "ROR", self.ROR, self.ABS, 6 ),Op( "???", self.XXX, self.IMP, 6 ),
            Op( "BVS", self.BVS, self.REL, 2 ),Op( "ADC", self.ADC, self.IZY, 5 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "ADC", self.ADC, self.ZPX, 4 ),Op( "ROR", self.ROR, self.ZPX, 6 ),Op( "???", self.XXX, self.IMP, 6 ),Op( "SEI", self.SEI, self.IMP, 2 ),Op( "ADC", self.ADC, self.ABY, 4 ),Op( "???", self.NOP, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 7 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "ADC", self.ADC, self.ABX, 4 ),Op( "ROR", self.ROR, self.ABX, 7 ),Op( "???", self.XXX, self.IMP, 7 ),
            Op( "???", self.NOP, self.IMP, 2 ),Op( "STA", self.STA, self.IZX, 6 ),Op( "???", self.NOP, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 6 ),Op( "STY", self.STY, self.ZP0, 3 ),Op( "STA", self.STA, self.ZP0, 3 ),Op( "STX", self.STX, self.ZP0, 3 ),Op( "???", self.XXX, self.IMP, 3 ),Op( "DEY", self.DEY, self.IMP, 2 ),Op( "???", self.NOP, self.IMP, 2 ),Op( "TXA", self.TXA, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "STY", self.STY, self.ABS, 4 ),Op( "STA", self.STA, self.ABS, 4 ),Op( "STX", self.STX, self.ABS, 4 ),Op( "???", self.XXX, self.IMP, 4 ),
            Op( "BCC", self.BCC, self.REL, 2 ),Op( "STA", self.STA, self.IZY, 6 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 6 ),Op( "STY", self.STY, self.ZPX, 4 ),Op( "STA", self.STA, self.ZPX, 4 ),Op( "STX", self.STX, self.ZPY, 4 ),Op( "???", self.XXX, self.IMP, 4 ),Op( "TYA", self.TYA, self.IMP, 2 ),Op( "STA", self.STA, self.ABY, 5 ),Op( "TXS", self.TXS, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 5 ),Op( "???", self.NOP, self.IMP, 5 ),Op( "STA", self.STA, self.ABX, 5 ),Op( "???", self.XXX, self.IMP, 5 ),Op( "???", self.XXX, self.IMP, 5 ),
            Op( "LDY", self.LDY, self.IMM, 2 ),Op( "LDA", self.LDA, self.IZX, 6 ),Op( "LDX", self.LDX, self.IMM, 2 ),Op( "???", self.XXX, self.IMP, 6 ),Op( "LDY", self.LDY, self.ZP0, 3 ),Op( "LDA", self.LDA, self.ZP0, 3 ),Op( "LDX", self.LDX, self.ZP0, 3 ),Op( "???", self.XXX, self.IMP, 3 ),Op( "TAY", self.TAY, self.IMP, 2 ),Op( "LDA", self.LDA, self.IMM, 2 ),Op( "TAX", self.TAX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "LDY", self.LDY, self.ABS, 4 ),Op( "LDA", self.LDA, self.ABS, 4 ),Op( "LDX", self.LDX, self.ABS, 4 ),Op( "???", self.XXX, self.IMP, 4 ),
            Op( "BCS", self.BCS, self.REL, 2 ),Op( "LDA", self.LDA, self.IZY, 5 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 5 ),Op( "LDY", self.LDY, self.ZPX, 4 ),Op( "LDA", self.LDA, self.ZPX, 4 ),Op( "LDX", self.LDX, self.ZPY, 4 ),Op( "???", self.XXX, self.IMP, 4 ),Op( "CLV", self.CLV, self.IMP, 2 ),Op( "LDA", self.LDA, self.ABY, 4 ),Op( "TSX", self.TSX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 4 ),Op( "LDY", self.LDY, self.ABX, 4 ),Op( "LDA", self.LDA, self.ABX, 4 ),Op( "LDX", self.LDX, self.ABY, 4 ),Op( "???", self.XXX, self.IMP, 4 ),
            Op( "CPY", self.CPY, self.IMM, 2 ),Op( "CMP", self.CMP, self.IZX, 6 ),Op( "???", self.NOP, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "CPY", self.CPY, self.ZP0, 3 ),Op( "CMP", self.CMP, self.ZP0, 3 ),Op( "DEC", self.DEC, self.ZP0, 5 ),Op( "???", self.XXX, self.IMP, 5 ),Op( "INY", self.INY, self.IMP, 2 ),Op( "CMP", self.CMP, self.IMM, 2 ),Op( "DEX", self.DEX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "CPY", self.CPY, self.ABS, 4 ),Op( "CMP", self.CMP, self.ABS, 4 ),Op( "DEC", self.DEC, self.ABS, 6 ),Op( "???", self.XXX, self.IMP, 6 ),
            Op( "BNE", self.BNE, self.REL, 2 ),Op( "CMP", self.CMP, self.IZY, 5 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "CMP", self.CMP, self.ZPX, 4 ),Op( "DEC", self.DEC, self.ZPX, 6 ),Op( "???", self.XXX, self.IMP, 6 ),Op( "CLD", self.CLD, self.IMP, 2 ),Op( "CMP", self.CMP, self.ABY, 4 ),Op( "NOP", self.NOP, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 7 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "CMP", self.CMP, self.ABX, 4 ),Op( "DEC", self.DEC, self.ABX, 7 ),Op( "???", self.XXX, self.IMP, 7 ),
            Op( "CPX", self.CPX, self.IMM, 2 ),Op( "SBC", self.SBC, self.IZX, 6 ),Op( "???", self.NOP, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "CPX", self.CPX, self.ZP0, 3 ),Op( "SBC", self.SBC, self.ZP0, 3 ),Op( "INC", self.INC, self.ZP0, 5 ),Op( "???", self.XXX, self.IMP, 5 ),Op( "INX", self.INX, self.IMP, 2 ),Op( "SBC", self.SBC, self.IMM, 2 ),Op( "NOP", self.NOP, self.IMP, 2 ),Op( "???", self.SBC, self.IMP, 2 ),Op( "CPX", self.CPX, self.ABS, 4 ),Op( "SBC", self.SBC, self.ABS, 4 ),Op( "INC", self.INC, self.ABS, 6 ),Op( "???", self.XXX, self.IMP, 6 ),
            Op( "BEQ", self.BEQ, self.REL, 2 ),Op( "SBC", self.SBC, self.IZY, 5 ),Op( "???", self.XXX, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 8 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "SBC", self.SBC, self.ZPX, 4 ),Op( "INC", self.INC, self.ZPX, 6 ),Op( "???", self.XXX, self.IMP, 6 ),Op( "SED", self.SED, self.IMP, 2 ),Op( "SBC", self.SBC, self.ABY, 4 ),Op( "NOP", self.NOP, self.IMP, 2 ),Op( "???", self.XXX, self.IMP, 7 ),Op( "???", self.NOP, self.IMP, 4 ),Op( "SBC", self.SBC, self.ABX, 4 ),Op( "INC", self.INC, self.ABX, 7 ),Op( "???", self.XXX, self.IMP, 7 ),
        ]

    cdef void power_up(self):
        '''
        Power Up
        '''
        self.reset()
        self.registers.SP = 0xFD
        
    cdef void reset(self):
        '''
        Reset Interrupt
        '''
        self.addr_abs = 0xFFFC
        cdef uint8_t lo = self.read(self.addr_abs + 0)
        cdef uint8_t hi = self.read(self.addr_abs + 1)
        self.registers.PC = hi << 8 | lo

        self.registers.SP -= 3
        self.registers.status.I = True
        
        self.remaining_cycles = 8    

    cdef void irq(self):
        '''
        Interrupt Request
        '''
        cdef uint8_t lo, hi 

        if (self.registers.status.I == 0):
            self.push_2_bytes(self.registers.PC)
            
            self.registers.status.B = False
            self.registers.status.U = True
            self.registers.status.I = True
            self.push(self.registers.status.value)

            self.addr_abs = 0xFFFE
            lo = self.read(self.addr_abs + 0)
            hi = self.read(self.addr_abs + 1)
            self.registers.PC = hi << 8 | lo

            self.remaining_cycles = 7

    cdef void nmi(self):
        '''
        Non-Maskable Interrupt Request
        '''
        cdef uint8_t lo, hi 

        self.push_2_bytes(self.registers.PC)

        self.registers.status.B = False
        self.registers.status.U = True
        self.registers.status.I = True
        self.push(self.registers.status.value)

        self.addr_abs = 0xFFFA
        lo = self.read(self.addr_abs + 0)
        hi = self.read(self.addr_abs + 1)
        self.registers.PC = hi << 8 | lo

        self.remaining_cycles = 8
        
    cdef uint8_t clock(self):
        '''
        Perform one clock cycle
        '''
        cdef Op op 
        cdef uint8_t op_cycles = 0
        cdef uint8_t additional_cycle1 = 0
        cdef uint8_t additional_cycle2 = 0

        if self.remaining_cycles == 0:
            self.opcode = self.read(self.registers.PC)
            self.registers.status.U = True
            self.registers.PC = self.registers.PC + 1
            op = self.lookup[self.opcode]
            self.remaining_cycles = op.cycles
            op_cycles = op.cycles
            additional_cycle1 = op.addrmode()
            additional_cycle2 = op.operate()
            self.remaining_cycles += (additional_cycle1 & additional_cycle2)
            self.registers.status.U = True
        self.clock_count += 1
        self.remaining_cycles -= 1
        return op_cycles + additional_cycle1 + additional_cycle2

    cpdef bint complete(self):
        return self.remaining_cycles == 0
