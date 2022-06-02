from collections import namedtuple
from enum import IntEnum
from numpy import uint16, uint32, uint8, void

from .bus import Bus, CPUBus


class CPU6502:
    a: uint8 = 0x00 # Accumlator Register
    x: uint8 = 0x00 # X Register
    y: uint8 = 0x00 # Y Register
    stkp: uint8 = 0x00 # Stack Pointer
    pc: uint8 = 0x0000 # Program Counter
    status: uint8 = 0x00 # Status Register

    class FLAGS(IntEnum):
        C = (1 << 0), # Carry Bit
        Z = (1 << 1), # Zero
        I = (1 << 2), # Disable Interrupts
        D = (1 << 3), # Decimal Mode
        B = (1 << 4), # Break
        U = (1 << 5), # Unused
        V = (1 << 6), # Overflow
        N = (1 << 7), # Negative

    def getFlag(self, f: FLAGS) -> uint8:
        return 1 if (self.status & f.value) > 0 else 0

    def setFlag(self, f: FLAGS, v: bool) -> void: 
        if v:
            self.status |= int(f.value)
        else:
            self.status &= ~int(f.value)

    bus: CPUBus

    def connectBus(self, bus: CPUBus) -> void:
        self.bus = bus
                
    def read(self, addr: uint16) -> uint8:
        return self.bus.read(addr, False)

    def write(self, addr: uint16, data: uint8) -> void:
        self.bus.write(addr, data)

    fetched: uint8 = 0x00
    addr_abs: uint8 = 0x0000
    addr_rel: uint8 = 0x0000
    
    def IMP(self) -> uint8:
        '''
        Address Mode: Implied
        '''
        self.fetched = self.a
        return 0

    def IMM(self) -> uint8:
        '''
        Address Mode: Immediate
        '''
        self.addr_abs = self.pc
        self.pc += 1
        return 0

    def ZP0(self) -> uint8:
        '''
        Address Mode: Zero Page
        '''
        self.addr_abs = self.read(self.pc) 
        self.pc += 1
        self.addr_abs &= 0x00FF
        return 0

    def ZPX(self) -> uint8:
        '''
        Address Mode: Zero Page with X Offset
        '''
        self.addr_abs = (self.read(self.pc) + self.x)
        self.pc += 1
        self.addr_abs &= 0x00FF
        return 0
    
    def ZPY(self) -> uint8:
        '''
        Address Mode: Zero Page with Y Offset
        '''
        self.addr_abs = (self.read(self.pc) + self.y)
        self.pc += 1
        self.addr_abs &= 0x00FF
        return 0
    
    def REL(self) -> uint8:
        '''
        Address Mode: Relative 
        '''
        self.addr_rel = self.read(self.pc)
        self.pc += 1
        if (self.addr_rel & 0x80):
            self.addr_rel |= 0xFF00
        return 0

    def ABS(self) -> uint8:
        '''
        Address Mode: Absolute 
        '''
        lo: uint16 = self.read(self.pc)
        self.pc += 1
        hi: uint16 = self.read(self.pc)
        self.pc += 1
        
        self.addr_abs = (hi << 8) | lo
        return 0

    def ABX(self) -> uint8:
        '''
        Address Mode: Absolute with X Offset
        '''
        lo: uint16 = self.read(self.pc)
        self.pc += 1
        hi: uint16 = self.read(self.pc)
        self.pc += 1
        
        self.addr_abs = (hi << 8) | lo
        self.addr_abs += self.x
        
        return 1 if (self.addr_abs & 0xFF00) != (hi << 8) else 0

    def ABY(self) -> uint8:
        '''
        Address Mode: Absolute with Y Offset
        '''
        lo: uint16 = self.read(self.pc)
        self.pc += 1
        hi: uint16 = self.read(self.pc)
        self.pc += 1
        
        self.addr_abs = (hi << 8) | lo
        self.addr_abs += self.y

        return 1 if (self.addr_abs & 0xFF00) != (hi << 8) else 0

    def IND(self) -> uint8:
        '''
        Address Mode: Indirect
        '''
        ptr_lo: uint16 = self.read(self.pc)
        self.pc += 1
        ptr_hi: uint16 = self.read(self.pc)
        self.pc += 1
        
        ptr: uint16 = (ptr_hi << 8) | ptr_lo
        
        if (ptr_lo == 0x00FF):
            self.addr_abs = (self.read(ptr & 0xFF00) << 8) | self.read(ptr + 0)
        else:
            self.addr_abs = (self.read(ptr + 1) << 8) | self.read(ptr + 0)
        return 0

    def IZX(self) -> uint8:
        '''
        Address Mode: Indirect X
        '''
        t: uint16 = self.read(self.pc)
        self.pc += 1
        x: uint16 = self.x

        lo: uint16 = self.read((uint16)(t + x) & 0x00FF)
        hi: uint16 = self.read((uint16)(t + x + 1) & 0x00FF)
        
        self.addr_abs = (hi << 8) | lo
        return 0

    def IZY(self) -> uint8:
        '''
        Address Mode: Indirect Y
        '''
        t: uint16 = self.read(self.pc)
        self.pc += 1
        
        lo: uint16 = self.read(t & 0x00FF)
        hi: uint16 = self.read((t + 1) & 0x00FF)

        self.addr_abs = (hi << 8) | lo
        self.addr_abs += self.y

        return 1 if (self.addr_abs & 0xFF00) != (hi << 8) else 0

    opcode: uint8 = 0x00
    temp: uint16 = 0x0000
    remaining_cycles: uint8 = 0x00

    def fetch(self) -> uint8:
        '''
        fetch opcode
        '''
        if self.lookup[self.opcode].addrmode != "IMP":
            self.fetched = self.read(self.addr_abs)
        return self.fetched
            
    def ADC(self) -> uint8:
        '''
        Instruction: Add with Carry In
        Function:    A = A + M + C
        Flags Out:   C, V, N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        temp = self.a + self.fetched + self.getFlag(self.FLAGS.C)

        self.setFlag(self.FLAGS.C, self.temp > 255)
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0)
        self.setFlag(self.FLAGS.V, (~(self.a ^ self.fetched) & (self.a ^ self.temp)) & 0x0080)
        self.setFlag(self.FLAGS.N, temp & 0x80)
        
        self.a = temp & 0x00FF
        return 1

    def SBC(self) -> uint8:
        '''
        Instruction: Subtraction with Borrow In
        Function:    A = A - M - (1 - C)
        Flags Out:   C, V, N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        value: uint16 = self.fetched ^ 0x00FF
        self.temp = self.a + value + self.getFlag(self.FLAGS.C)

        self.setFlag(self.FLAGS.C, self.temp & 0xFF00)
        self.setFlag(self.FLAGS.Z, ((self.temp & 0x00FF) == 0))
        self.setFlag(self.FLAGS.V, (self.temp ^ self.a) & (self.temp ^ self.value) & 0x0080)
        self.setFlag(self.FLAGS.N, self.temp & 0x0080)

        self.a = self.temp & 0x00FF
        return 1

    def AND(self) -> uint8:
        '''
        Instruction: Bitwise Logic AND
        Function:    A = A & M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.a = self.a & self.fetched
        
        self.setFlag(self.FLAGS.Z, self.a == 0x00)
        self.setFlag(self.FLAGS.N, self.a & 0x80)
        
        return 1

    def ASL(self) -> uint8:
        '''
        Instruction: Arithmetic Shift Left
        Function:    A = C <- (A << 1) <- 0
        Flags Out:   N, Z, C
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.temp = self.fetched << 1
        
        self.setFlag(self.FLAGS.C, (self.temp & 0xFF00) > 0)
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x00)
        self.setFlag(self.FLAGS.N, self.temp & 0x80)
        
        if (self.lookup[self.opcode].addrmode == "IMP"):
            self.a = self.temp & 0x00FF
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    def BCC(self) -> uint8:
        '''
        Instruction: Branch if Carry Clear
        Function:    if(C == 0) pc = address 
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(self.FLAGS.C) == 0):
            self.remaining_cycles += 1
            self.addr_abs = self.pc + self.addr_rel
            
            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1
            self.pc = self.addr_abs
        return 0

    def BCS(self) -> uint8:
        '''
        Instruction: Branch if Carry Set
        Function:    if(C == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(self.FLAGS.C) == 1):
            self.remaining_cycles += 1
            self.addr_abs = self.pc + self.addr_rel
            
            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1
                
            self.pc = self.addr_abs
        return 0

    def BEQ(self) -> uint8:
        '''
        Instruction: Branch if Equal
        Function:    if(Z == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(self.FLAGS.Z) == 1):
            self.remaining_cycles += 1
            self.addr_abs = self.pc + self.addr_rel
            
            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.pc = self.addr_abs
        return 0

    def BIT(self) -> uint8:
        ''' 
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.temp = self.a & self.fetched

        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x00)
        self.setFlag(self.FLAGS.N, self.fetched & (1 << 7))
        self.setFlag(self.V, self.fetched & (1 << 6))

        return 0

    def BMI(self) -> uint8:
        '''
        Instruction: Branch if Negative
        Function:    if(N == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(self.FLAGS.N) == 1):
            self.remaining_cycles += 1
            self.addr_abs = self.pc + self.addr_rel
            
            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1
            self.pc = self.addr_abs
        return 0

    def BNE(self) -> uint8:
        '''
        Instruction: Branch if Not Equal
        Function:    if(Z == 0) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(self.FLAGS.Z) == 0):
            self.remaining_cycles += 1
            self.addr_abs = self.pc + self.addr_rel

            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.pc = self.addr_abs
        return 0

    def BPL(self) -> uint8:
        '''
        Instruction: Branch if Positive
        Function:    if(N == 0) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(self.FLAGS.N) == 0):
            self.remaining_cycles += 1
            self.addr_abs = self.pc + self.addr_rel

            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.pc = self.addr_abs
    
        return 0

    def BRK(self) -> uint8:
        '''
        Instruction: Break
        Function:    Program Sourced Interrupt
        Return:      Require additional 0 clock cycle
        '''
        self.pc += 1
    
        self.setFlag(self.FLAGS.I, 1)
        self.write(0x0100 + self.stkp, (self.pc >> 8) & 0x00FF)
        self.stkp -= 1
        self.write(0x0100 + self.stkp, self.pc & 0x00FF)
        self.stkp -= 1

        self.setFlag(self.FLAGS.B, 1)
        self.write(0x0100 + self.stkp, self.status)
        self.stkp -= 1
        self.setFlag(self.FLAGS.B, 0)
        
        self.pc = self.read(0xFFFE) | (self.read(0xFFFF) << 8)
        return 0

    def BVC(self) -> uint8:
        '''
        Instruction: Branch if Overflow Clear
        Function:    if(V == 0) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(self.V) == 0):
            self.remaining_cycles += 1
            self.addr_abs = self.pc + self.addr_rel

            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.pc = self.addr_abs
        return 0

    def BVS(self) -> uint8:
        '''
        Instruction: Branch if Overflow Set
        Function:    if(V == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(self.V) == 1):
            self.remaining_cycles += 1
            self.addr_abs = self.pc + self.addr_rel

            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.pc = self.addr_abs
        return 0

    def CLC(self) -> uint8:
        '''
        Instruction: Clear Carry Flag
        Function:    C = 0
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(self.FLAGS.C, False)
        return 0

    def CLD(self) -> uint8:
        '''
        Instruction: Clear Decimal Flag
        Function:    D = 0
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(self.FLAGS.D, False)
        return 0

    def CLI(self) -> uint8:
        '''
        Instruction: Disable Interrupts / Clear Interrupt Flag
        Function:    I = 0
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(self.FLAGS.I, False)
        return 0

    def CLV(self) -> uint8:
        '''
        Instruction: Clear Overflow Flag
        Function:    V = 0
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(self.V, False)
        return 0

    def CMP(self) -> uint8:
        '''
        Instruction: Compare Accumulator
        Function:    C <- A >= M      Z <- (A - M) == 0
        Flags Out:   N, C, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.temp = self.a - self.fetched
        self.setFlag(self.FLAGS.C, self.a >= self.fetched)
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(self.FLAGS.N, self.temp & 0x0080)
        return 1

    def CPX(self) -> uint8:
        '''
        Instruction: Compare X Register
        Function:    C <- X >= M      Z <- (X - M) == 0
        Flags Out:   N, C, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.temp = self.x - self.fetched
        self.setFlag(self.FLAGS.C, self.x >= self.fetched)
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(self.FLAGS.N, self.temp & 0x0080)
        return 0

    def CPY(self) -> uint8:
        '''
        Instruction: Compare Y Register
        Function:    C <- Y >= M      Z <- (Y - M) == 0
        Flags Out:   N, C, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.temp = self.y - self.fetched
        self.setFlag(self.FLAGS.C, self.y >= self.fetched)
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(self.FLAGS.N, self.temp & 0x0080)
        return 0

    def DEC(self) -> uint8:
        '''
        Instruction: Decrement Value at Memory Location
        Function:    M = M - 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.temp = self.fetched - 1
        self.write(self.addr_abs, self.temp & 0x00FF)
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(self.FLAGS.N, self.temp & 0x0080)
        return 0

    def DEX(self) -> uint8:
        '''
        Instruction: Decrement X Register
        Function:    X = X - 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.x -= 1
        self.setFlag(self.FLAGS.Z, self.x == 0x00)
        self.setFlag(self.FLAGS.N, self.x & 0x80)
        return 0

    def DEY(self) -> uint8:
        '''
        Instruction: Decrement Y Register
        Function:    Y = Y - 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.y -= 1
        self.setFlag(self.FLAGS.Z, self.y == 0x00)
        self.setFlag(self.FLAGS.N, self.y & 0x80)
        return 0

    def EOR(self) -> uint8:
        '''
        Instruction: Bitwise Logic XOR
        Function:    A = A xor M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.a = self.a ^ self.fetched   
        self.setFlag(self.FLAGS.Z, self.a == 0x00)
        self.setFlag(self.FLAGS.N, self.a & 0x80)
        return 1

    def INC(self) -> uint8:
        '''
        Instruction: Increment Value at Memory Location
        Function:    M = M + 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.temp = self.fetched + 1
        self.write(self.addr_abs, self.temp & 0x00FF)
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(self.FLAGS.N, self.temp & 0x0080)
        return 0

    def INX(self) -> uint8:
        '''
        Instruction: Increment X Register
        Function:    X = X + 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.x += 1
        self.setFlag(self.FLAGS.Z, self.x == 0x00)
        self.setFlag(self.FLAGS.N, self.x & 0x80)
        return 0

    def INY(self) -> uint8:
        '''
        Instruction: Increment Y Register
        Function:    Y = Y + 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.y += 1
        self.setFlag(self.FLAGS.Z, self.y == 0x00)
        self.setFlag(self.FLAGS.N, self.y & 0x80)
        return 0

    def JMP(self) -> uint8:
        '''
        Instruction: Jump To Location
        Function:    pc = address
        Return:      Require additional 0 clock cycle
        '''
        self.pc = self.addr_abs
        return 0

    def JSR(self) -> uint8:
        '''
        Instruction: Jump To Sub-Routine
        Function:    Push current pc to stack, pc = address
        Return:      Require additional 0 clock cycle
        '''
        self.pc -= 1

        self.write(0x0100 + self.stkp, (self.pc >> 8) & 0x00FF)
        self.stkp -= 1
        self.write(0x0100 + self.stkp, self.pc & 0x00FF)
        self.stkp -= 1

        self.pc = self.addr_abs
        return 0

    def LDA(self) -> uint8:
        '''
        Instruction: Load The Accumulator
        Function:    A = M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.a = self.fetched
        self.setFlag(self.FLAGS.Z, self.a == 0x00)
        self.setFlag(self.FLAGS.N, self.a & 0x80)
        return 1

    def LDX(self) -> uint8:
        '''
        Instruction: Load The X Register
        Function:    X = M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.x = self.fetched
        self.setFlag(self.FLAGS.Z, self.x == 0x00)
        self.setFlag(self.FLAGS.N, self.x & 0x80)
        return 1

    def LDY(self) -> uint8:
        '''
        Instruction: Load The Y Register
        Function:    Y = M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.y = self.fetched
        self.setFlag(self.FLAGS.Z, self.y == 0x00)
        self.setFlag(self.FLAGS.N, self.y & 0x80)
        return 1

    def LSR(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.setFlag(self.FLAGS.C, self.fetched & 0x0001)
        self.temp = self.fetched >> 1   
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(self.FLAGS.N, self.temp & 0x0080)
        if (self.lookup[self.opcode].addrmode == self.FLAGS.IMP()):
            self.a = self.temp & 0x00FF
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    def NOP(self) -> uint8:
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

    def ORA(self) -> uint8:
        '''
        Instruction: Bitwise Logic OR
        Function:    A = A | M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.a = self.a | self.fetched
        self.setFlag(self.FLAGS.Z, self.a == 0x00)
        self.setFlag(self.FLAGS.N, self.a & 0x80)
        return 1

    def PHA(self) -> uint8:
        '''
        Instruction: Push Accumulator to Stack
        Function:    A -> stack
        Return:      Require additional 0 clock cycle
        '''
        self.write(0x0100 + self.stkp, self.a)
        self.stkp -= 1
        return 0

    def PHP(self) -> uint8:
        '''
        Instruction: Push Status Register to Stack
        Function:    status -> stack
        Return:      Require additional 0 clock cycle
        '''
        self.write(0x0100 + self.stkp, self.status | self.FLAGS.B | self.FLAGS.U)
        self.setFlag(self.FLAGS.B, 0)
        self.setFlag(self.FLAGS.U, 0)
        self.stkp -= 1
        return 0

    def PLA(self) -> uint8:
        '''
        Instruction: Pop Accumulator off Stack
        Function:    A <- stack
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.stkp += 1
        self.a = self.read(0x0100 + self.stkp)
        self.setFlag(self.FLAGS.Z, self.a == 0x00)
        self.setFlag(self.FLAGS.N, self.a & 0x80)
        return 0

    def PLP(self) -> uint8:
        '''
        Instruction: Pop Status Register off Stack
        Function:    Status <- stack
        Return:      Require additional 0 clock cycle
        '''
        self.stkp += 1
        self.status = self.read(0x0100 + self.stkp)
        self.setFlag(self.FLAGS.U, 1)
        return 0

    def ROL(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.temp = (self.fetched << 1) | self.getFlag(self.FLAGS.C)
        self.setFlag(self.FLAGS.C, self.temp & 0xFF00)
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(self.FLAGS.N, self.temp & 0x0080)
        if (self.lookup[self.opcode].addrmode == "IMP"):
            self.a = self.temp & 0x00FF
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    def ROR(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.temp = (self.getFlag(self.FLAGS.C) << 7) | (self.fetched >> 1)
        self.setFlag(self.FLAGS.C, self.fetched & 0x01)
        self.setFlag(self.FLAGS.Z, (self.temp & 0x00FF) == 0x00)
        self.setFlag(self.FLAGS.N, self.temp & 0x0080)
        if (self.lookup[self.opcode].addrmode == "IMP"):
            a = self.temp & 0x00FF
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    def RTI(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.stkp += 1
        self.status = self.read(0x0100 + self.stkp)
        self.status &= ~self.FLAGS.B
        self.status &= ~self.FLAGS.U

        self.stkp += 1
        self.pc = self.read(0x0100 + self.stkp)
        self.stkp += 1
        pc |= self.read(0x0100 + self.stkp) << 8
        return 0

    def RTS(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.stkp += 1
        self.pc = self.read(0x0100 + self.stkp)
        self.stkp += 1
        self.pc |= self.read(0x0100 + self.stkp) << 8
    
        self.pc += 1
        return 0

    def SEC(self) -> uint8:
        '''
        Instruction: Set Carry Flag
        Function:    C = 1 
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(self.FLAGS.C, True)
        return 0

    def SED(self) -> uint8:
        '''
        Instruction: Set Decimal Flag
        Function:    D = 1
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(self.FLAGS.D, True)
        return 0

    def SEI(self) -> uint8:
        '''
        Instruction: Set Interrupt Flag / Enable Interrupts
        Function:    I = 1
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(self.FLAGS.I, True)
        return 0

    def STA(self) -> uint8:
        '''
        Instruction: Store Accumulator at Address
        Function:    M = A
        Return:      Require additional 0 clock cycle
        '''
        self.write(self.addr_abs, self.a)
        return 0

    def STX(self) -> uint8:
        '''
        Instruction: Store X Register at Address
        Function:    M = X
        Return:      Require additional 0 clock cycle
        '''
        self.write(self.addr_abs, self.x)
        return 0

    def STY(self) -> uint8:
        '''
        Instruction: Store Y Register at Address
        Function:    M = Y
        Return:      Require additional 0 clock cycle
        '''
        self.write(self.addr_abs, self.y)
        return 0

    def TAX(self) -> uint8:
        '''
        Instruction: Transfer Accumulator to X Register
        Function:    X = A
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.x = self.a
        self.setFlag(self.FLAGS.Z, self.x == 0x00)
        self.setFlag(self.FLAGS.N, self.x & 0x80)
        return 0

    def TAY(self) -> uint8:
        '''
        Instruction: Transfer Accumulator to Y Register
        Function:    Y = A
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.y = self.a
        self.setFlag(self.FLAGS.Z, self.y == 0x00)
        self.setFlag(self.FLAGS.N, self.y & 0x80)
        return 0

    def TSX(self) -> uint8:
        '''
        Instruction: Transfer Stack Pointer to X Register
        Function:    X = stack pointer
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.x = self.stkp
        self.setFlag(self.FLAGS.Z, self.x == 0x00)
        self.setFlag(self.FLAGS.N, self.x & 0x80)
        return 0

    def TXA(self) -> uint8:
        '''
        Instruction: Transfer X Register to Accumulator
        Function:    A = X
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.a = self.x
        self.setFlag(self.FLAGS.Z, self.a == 0x00)
        self.setFlag(self.FLAGS.N, self.a & 0x80)
        return 0

    def TXS(self) -> uint8:
        '''
        Instruction: Transfer X Register to Stack Pointer
        Function:    stack pointer = X
        Return:      Require additional 0 clock cycle
        '''
        self.stkp = self.x
        return 0

    def TYA(self) -> uint8:
        '''
        Instruction: Transfer Y Register to Accumulator
        Function:    A = Y
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.a = self.y
        self.setFlag(self.FLAGS.Z, self.a == 0x00)
        self.setFlag(self.FLAGS.N, self.a & 0x80)
        return 0

    def XXX(self) -> uint8:
        '''
        Instruction: captures illegal opcodes
        Return:      Require additional 0 clock cycle
        '''
        return 0

    def __init__(self) -> None:
        self.address_modes = {
            "IMP": getattr(self, "IMP"), "IMM": getattr(self, "IMM"),
            "ZP0": getattr(self, "ZP0"), "ZPX": getattr(self, "ZPX"),
            "ZPY": getattr(self, "ZPY"), "REL": getattr(self, "REL"),
            "ABS": getattr(self, "ABS"), "ABX": getattr(self, "ABX"),
            "ABY": getattr(self, "ABY"), "IND": getattr(self, "IND"),
            "IZX": getattr(self, "IZX"), "IZY": getattr(self, "IZY"),
        }

        self.operates = {
            "ADC": getattr(self, "ADC"), "AND": getattr(self, "AND"), "ASL": getattr(self, "ASL"), "BCC": getattr(self, "BCC"),
            "BCS": getattr(self, "BCS"), "BEQ": getattr(self, "BEQ"), "BIT": getattr(self, "BIT"), "BMI": getattr(self, "BMI"),
            "BNE": getattr(self, "BNE"), "BPL": getattr(self, "BPL"), "BRK": getattr(self, "BRK"), "BVC": getattr(self, "BVC"),
            "BVS": getattr(self, "BVS"), "CLC": getattr(self, "CLC"), "CLD": getattr(self, "CLD"), "CLI": getattr(self, "CLI"),
            "CLV": getattr(self, "CLV"), "CMP": getattr(self, "CMP"), "CPX": getattr(self, "CPX"), "CPY": getattr(self, "CPY"),
            "DEC": getattr(self, "DEC"), "DEX": getattr(self, "DEX"), "DEY": getattr(self, "DEY"), "EOR": getattr(self, "EOR"),
            "INC": getattr(self, "INC"), "INX": getattr(self, "INX"), "INY": getattr(self, "INY"), "JMP": getattr(self, "JMP"),
            "JSR": getattr(self, "JSR"), "LDA": getattr(self, "LDA"), "LDX": getattr(self, "LDX"), "LDY": getattr(self, "LDY"),
            "LSR": getattr(self, "LSR"), "NOP": getattr(self, "NOP"), "ORA": getattr(self, "ORA"), "PHA": getattr(self, "PHA"),
            "PHP": getattr(self, "PHP"), "PLA": getattr(self, "PLA"), "PLP": getattr(self, "PLP"), "ROL": getattr(self, "ROL"),
            "ROR": getattr(self, "ROR"), "RTI": getattr(self, "RTI"), "RTS": getattr(self, "RTS"), "SBC": getattr(self, "SBC"),
            "SEC": getattr(self, "SEC"), "SED": getattr(self, "SED"), "SEI": getattr(self, "SEI"), "STA": getattr(self, "STA"),
            "STX": getattr(self, "STX"), "STY": getattr(self, "STY"), "TAX": getattr(self, "TAX"), "TAY": getattr(self, "TAY"),
            "TSX": getattr(self, "TSX"), "TXA": getattr(self, "TXA"), "TXS": getattr(self, "TXS"), "TYA": getattr(self, "TYA"),

            "XXX": getattr(self, "XXX"),
        }
        
        Op = namedtuple('Op', ['name', 'operate', 'addrmode', 'cycles'])
        self.lookup = [
            Op( "BRK", "BRK", "IMM", 7 ),Op( "ORA", "ORA", "IZX", 6 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "???", "NOP", "IMP", 3 ),Op( "ORA", "ORA", "ZP0", 3 ),Op( "ASL", "ASL", "ZP0", 5 ),Op( "???", "XXX", "IMP", 5 ),Op( "PHP", "PHP", "IMP", 3 ),Op( "ORA", "ORA", "IMM", 2 ),Op( "ASL", "ASL", "IMP", 2 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "NOP", "IMP", 4 ),Op( "ORA", "ORA", "ABS", 4 ),Op( "ASL", "ASL", "ABS", 6 ),Op( "???", "XXX", "IMP", 6 ),
            Op( "BPL", "BPL", "REL", 2 ),Op( "ORA", "ORA", "IZY", 5 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "???", "NOP", "IMP", 4 ),Op( "ORA", "ORA", "ZPX", 4 ),Op( "ASL", "ASL", "ZPX", 6 ),Op( "???", "XXX", "IMP", 6 ),Op( "CLC", "CLC", "IMP", 2 ),Op( "ORA", "ORA", "ABY", 4 ),Op( "???", "NOP", "IMP", 2 ),Op( "???", "XXX", "IMP", 7 ),Op( "???", "NOP", "IMP", 4 ),Op( "ORA", "ORA", "ABX", 4 ),Op( "ASL", "ASL", "ABX", 7 ),Op( "???", "XXX", "IMP", 7 ),
            Op( "JSR", "JSR", "ABS", 6 ),Op( "AND", "AND", "IZX", 6 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "BIT", "BIT", "ZP0", 3 ),Op( "AND", "AND", "ZP0", 3 ),Op( "ROL", "ROL", "ZP0", 5 ),Op( "???", "XXX", "IMP", 5 ),Op( "PLP", "PLP", "IMP", 4 ),Op( "AND", "AND", "IMM", 2 ),Op( "ROL", "ROL", "IMP", 2 ),Op( "???", "XXX", "IMP", 2 ),Op( "BIT", "BIT", "ABS", 4 ),Op( "AND", "AND", "ABS", 4 ),Op( "ROL", "ROL", "ABS", 6 ),Op( "???", "XXX", "IMP", 6 ),
            Op( "BMI", "BMI", "REL", 2 ),Op( "AND", "AND", "IZY", 5 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "???", "NOP", "IMP", 4 ),Op( "AND", "AND", "ZPX", 4 ),Op( "ROL", "ROL", "ZPX", 6 ),Op( "???", "XXX", "IMP", 6 ),Op( "SEC", "SEC", "IMP", 2 ),Op( "AND", "AND", "ABY", 4 ),Op( "???", "NOP", "IMP", 2 ),Op( "???", "XXX", "IMP", 7 ),Op( "???", "NOP", "IMP", 4 ),Op( "AND", "AND", "ABX", 4 ),Op( "ROL", "ROL", "ABX", 7 ),Op( "???", "XXX", "IMP", 7 ),
            Op( "RTI", "RTI", "IMP", 6 ),Op( "EOR", "EOR", "IZX", 6 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "???", "NOP", "IMP", 3 ),Op( "EOR", "EOR", "ZP0", 3 ),Op( "LSR", "LSR", "ZP0", 5 ),Op( "???", "XXX", "IMP", 5 ),Op( "PHA", "PHA", "IMP", 3 ),Op( "EOR", "EOR", "IMM", 2 ),Op( "LSR", "LSR", "IMP", 2 ),Op( "???", "XXX", "IMP", 2 ),Op( "JMP", "JMP", "ABS", 3 ),Op( "EOR", "EOR", "ABS", 4 ),Op( "LSR", "LSR", "ABS", 6 ),Op( "???", "XXX", "IMP", 6 ),
            Op( "BVC", "BVC", "REL", 2 ),Op( "EOR", "EOR", "IZY", 5 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "???", "NOP", "IMP", 4 ),Op( "EOR", "EOR", "ZPX", 4 ),Op( "LSR", "LSR", "ZPX", 6 ),Op( "???", "XXX", "IMP", 6 ),Op( "CLI", "CLI", "IMP", 2 ),Op( "EOR", "EOR", "ABY", 4 ),Op( "???", "NOP", "IMP", 2 ),Op( "???", "XXX", "IMP", 7 ),Op( "???", "NOP", "IMP", 4 ),Op( "EOR", "EOR", "ABX", 4 ),Op( "LSR", "LSR", "ABX", 7 ),Op( "???", "XXX", "IMP", 7 ),
            Op( "RTS", "RTS", "IMP", 6 ),Op( "ADC", "ADC", "IZX", 6 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "???", "NOP", "IMP", 3 ),Op( "ADC", "ADC", "ZP0", 3 ),Op( "ROR", "ROR", "ZP0", 5 ),Op( "???", "XXX", "IMP", 5 ),Op( "PLA", "PLA", "IMP", 4 ),Op( "ADC", "ADC", "IMM", 2 ),Op( "ROR", "ROR", "IMP", 2 ),Op( "???", "XXX", "IMP", 2 ),Op( "JMP", "JMP", "IND", 5 ),Op( "ADC", "ADC", "ABS", 4 ),Op( "ROR", "ROR", "ABS", 6 ),Op( "???", "XXX", "IMP", 6 ),
            Op( "BVS", "BVS", "REL", 2 ),Op( "ADC", "ADC", "IZY", 5 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "???", "NOP", "IMP", 4 ),Op( "ADC", "ADC", "ZPX", 4 ),Op( "ROR", "ROR", "ZPX", 6 ),Op( "???", "XXX", "IMP", 6 ),Op( "SEI", "SEI", "IMP", 2 ),Op( "ADC", "ADC", "ABY", 4 ),Op( "???", "NOP", "IMP", 2 ),Op( "???", "XXX", "IMP", 7 ),Op( "???", "NOP", "IMP", 4 ),Op( "ADC", "ADC", "ABX", 4 ),Op( "ROR", "ROR", "ABX", 7 ),Op( "???", "XXX", "IMP", 7 ),
            Op( "???", "NOP", "IMP", 2 ),Op( "STA", "STA", "IZX", 6 ),Op( "???", "NOP", "IMP", 2 ),Op( "???", "XXX", "IMP", 6 ),Op( "STY", "STY", "ZP0", 3 ),Op( "STA", "STA", "ZP0", 3 ),Op( "STX", "STX", "ZP0", 3 ),Op( "???", "XXX", "IMP", 3 ),Op( "DEY", "DEY", "IMP", 2 ),Op( "???", "NOP", "IMP", 2 ),Op( "TXA", "TXA", "IMP", 2 ),Op( "???", "XXX", "IMP", 2 ),Op( "STY", "STY", "ABS", 4 ),Op( "STA", "STA", "ABS", 4 ),Op( "STX", "STX", "ABS", 4 ),Op( "???", "XXX", "IMP", 4 ),
            Op( "BCC", "BCC", "REL", 2 ),Op( "STA", "STA", "IZY", 6 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 6 ),Op( "STY", "STY", "ZPX", 4 ),Op( "STA", "STA", "ZPX", 4 ),Op( "STX", "STX", "ZPY", 4 ),Op( "???", "XXX", "IMP", 4 ),Op( "TYA", "TYA", "IMP", 2 ),Op( "STA", "STA", "ABY", 5 ),Op( "TXS", "TXS", "IMP", 2 ),Op( "???", "XXX", "IMP", 5 ),Op( "???", "NOP", "IMP", 5 ),Op( "STA", "STA", "ABX", 5 ),Op( "???", "XXX", "IMP", 5 ),Op( "???", "XXX", "IMP", 5 ),
            Op( "LDY", "LDY", "IMM", 2 ),Op( "LDA", "LDA", "IZX", 6 ),Op( "LDX", "LDX", "IMM", 2 ),Op( "???", "XXX", "IMP", 6 ),Op( "LDY", "LDY", "ZP0", 3 ),Op( "LDA", "LDA", "ZP0", 3 ),Op( "LDX", "LDX", "ZP0", 3 ),Op( "???", "XXX", "IMP", 3 ),Op( "TAY", "TAY", "IMP", 2 ),Op( "LDA", "LDA", "IMM", 2 ),Op( "TAX", "TAX", "IMP", 2 ),Op( "???", "XXX", "IMP", 2 ),Op( "LDY", "LDY", "ABS", 4 ),Op( "LDA", "LDA", "ABS", 4 ),Op( "LDX", "LDX", "ABS", 4 ),Op( "???", "XXX", "IMP", 4 ),
            Op( "BCS", "BCS", "REL", 2 ),Op( "LDA", "LDA", "IZY", 5 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 5 ),Op( "LDY", "LDY", "ZPX", 4 ),Op( "LDA", "LDA", "ZPX", 4 ),Op( "LDX", "LDX", "ZPY", 4 ),Op( "???", "XXX", "IMP", 4 ),Op( "CLV", "CLV", "IMP", 2 ),Op( "LDA", "LDA", "ABY", 4 ),Op( "TSX", "TSX", "IMP", 2 ),Op( "???", "XXX", "IMP", 4 ),Op( "LDY", "LDY", "ABX", 4 ),Op( "LDA", "LDA", "ABX", 4 ),Op( "LDX", "LDX", "ABY", 4 ),Op( "???", "XXX", "IMP", 4 ),
            Op( "CPY", "CPY", "IMM", 2 ),Op( "CMP", "CMP", "IZX", 6 ),Op( "???", "NOP", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "CPY", "CPY", "ZP0", 3 ),Op( "CMP", "CMP", "ZP0", 3 ),Op( "DEC", "DEC", "ZP0", 5 ),Op( "???", "XXX", "IMP", 5 ),Op( "INY", "INY", "IMP", 2 ),Op( "CMP", "CMP", "IMM", 2 ),Op( "DEX", "DEX", "IMP", 2 ),Op( "???", "XXX", "IMP", 2 ),Op( "CPY", "CPY", "ABS", 4 ),Op( "CMP", "CMP", "ABS", 4 ),Op( "DEC", "DEC", "ABS", 6 ),Op( "???", "XXX", "IMP", 6 ),
            Op( "BNE", "BNE", "REL", 2 ),Op( "CMP", "CMP", "IZY", 5 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "???", "NOP", "IMP", 4 ),Op( "CMP", "CMP", "ZPX", 4 ),Op( "DEC", "DEC", "ZPX", 6 ),Op( "???", "XXX", "IMP", 6 ),Op( "CLD", "CLD", "IMP", 2 ),Op( "CMP", "CMP", "ABY", 4 ),Op( "NOP", "NOP", "IMP", 2 ),Op( "???", "XXX", "IMP", 7 ),Op( "???", "NOP", "IMP", 4 ),Op( "CMP", "CMP", "ABX", 4 ),Op( "DEC", "DEC", "ABX", 7 ),Op( "???", "XXX", "IMP", 7 ),
            Op( "CPX", "CPX", "IMM", 2 ),Op( "SBC", "SBC", "IZX", 6 ),Op( "???", "NOP", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "CPX", "CPX", "ZP0", 3 ),Op( "SBC", "SBC", "ZP0", 3 ),Op( "INC", "INC", "ZP0", 5 ),Op( "???", "XXX", "IMP", 5 ),Op( "INX", "INX", "IMP", 2 ),Op( "SBC", "SBC", "IMM", 2 ),Op( "NOP", "NOP", "IMP", 2 ),Op( "???", "SBC", "IMP", 2 ),Op( "CPX", "CPX", "ABS", 4 ),Op( "SBC", "SBC", "ABS", 4 ),Op( "INC", "INC", "ABS", 6 ),Op( "???", "XXX", "IMP", 6 ),
            Op( "BEQ", "BEQ", "REL", 2 ),Op( "SBC", "SBC", "IZY", 5 ),Op( "???", "XXX", "IMP", 2 ),Op( "???", "XXX", "IMP", 8 ),Op( "???", "NOP", "IMP", 4 ),Op( "SBC", "SBC", "ZPX", 4 ),Op( "INC", "INC", "ZPX", 6 ),Op( "???", "XXX", "IMP", 6 ),Op( "SED", "SED", "IMP", 2 ),Op( "SBC", "SBC", "ABY", 4 ),Op( "NOP", "NOP", "IMP", 2 ),Op( "???", "XXX", "IMP", 7 ),Op( "???", "NOP", "IMP", 4 ),Op( "SBC", "SBC", "ABX", 4 ),Op( "INC", "INC", "ABX", 7 ),Op( "???", "XXX", "IMP", 7 ),
        ]
    
    def reset(self) -> void:
        '''
        Reset Interrupt
        '''
        self.addr_abs = 0xFFFC
        lo: uint16 = self.read(self.addr_abs + 0)
        hi: uint16 = self.read(self.addr_abs + 1)
        
        self.pc = (hi << 8) | lo

        self.a = 0
        self.x = 0
        self.y = 0
        self.stkp = 0xFD
        self.status = 0x00 | self.FLAGS.U
        
        self.addr_rel = 0x0000
        self.addr_abs = 0x0000
        self.fetched = 0x00
        
        self.remaining_cycles = 8

    def irq(self) -> void:
        '''
        Interrupt Request
        '''
        if (self.getFlag(self.FLAGS.I) == 0):
            self.write(0x0100 + self.stkp, (self.pc >> 8) & 0x00FF)
            self.stkp -= 1
            self.write(0x0100 + self.stkp, self.pc & 0x00FF)
            self.stkp -= 1
            
            self.setFlag(self.FLAGS.B, 0);
            self.setFlag(self.FLAGS.U, 1);
            self.setFlag(self.FLAGS.I, 1);
            self.write(0x0100 + self.stkp, self.status)
            self.stkp -= 1

            self.addr_abs = 0xFFFE;
            lo: uint16 = self.read(self.addr_abs + 0)
            hi: uint16 = self.read(self.addr_abs + 1)
            self.pc = (hi << 8) | lo

            self.remaining_cycles = 7
    
    def nmi(self) -> void:
        '''
        Non-Maskable Interrupt Request
        '''
        self.write(0x0100 + self.stkp, (self.pc >> 8) & 0x00FF)
        self.stkp -= 1
        self.write(0x0100 + self.stkp, self.pc & 0x00FF)
        self.stkp -= 1

        self.setFlag(self.FLAGS.B, 0);
        self.setFlag(self.FLAGS.U, 1);
        self.setFlag(self.FLAGS.I, 1);
        self.write(0x0100 + self.stkp, self.status)
        self.stkp -= 1

        self.addr_abs = 0xFFFA
        lo: uint16 = self.read(self.addr_abs + 0)
        hi: uint16 = self.read(self.addr_abs + 1)
        self.pc = (hi << 8) | lo

        self.remaining_cycles = 8

    clock_count: uint32 = 0

    def clock(self, debug: bool = False) -> void:
        '''
        Perform one clock cycle
        '''
        if self.remaining_cycles == 0:
            self.opcode = self.read(self.pc)
            self.setFlag(self.FLAGS.U, True)
            self.pc += 1
            self.remaining_cycles = self.lookup[self.opcode].cycles
            op = self.lookup[self.opcode]
            additional_cycle1: uint8 = self.address_modes[op.addrmode]()
            additional_cycle2: uint8 = self.operates[op.operate]()
            self.remaining_cycles += (additional_cycle1 & additional_cycle2)
            self.setFlag(self.FLAGS.U, True)
            if debug:
                print(op)

        self.clock_count += 1
        self.remaining_cycles -= 1
    
    def disassemble(self, start: uint16, end: uint16) -> void:
        for addr in range(start, end, 16):
            print("${addr:#04X}: {codes}".format(\
                addr=addr,\
                codes=" ".join(["{hex:02X}".format(hex=self.read(addr)) for addr in range(addr, min(addr+16, end))])\
            ))
        print()
        addr = start
        while addr < end:
            opcode = self.read(addr)
            opaddr = addr
            addr += 1
            op = self.lookup[opcode]
            if op.addrmode == "IMP":
                value = "    "
            if op.addrmode == "IMM":
                value = "#${value:02X}".format(value=self.read(addr))
                addr += 1
            elif op.addrmode == "ZP0":
                lo = self.read(addr)
                addr += 1
                value = "${value:02X}".format(value=lo) 
            elif op.addrmode == "ZPX":
                lo = self.read(addr)
                addr += 1
                value = "${value:02X},X".format(value=lo) 
            elif op.addrmode == "ZPY":
                lo = self.read(addr)
                addr += 1
                value = "${value:02X},Y".format(value=lo)
            elif op.addrmode == "IZX":
                lo = self.read(addr)
                addr += 1
                value = "(${value:02X},X)".format(value=lo)
            elif op.addrmode == "IZY":
                lo = self.read(addr)
                addr += 1  
                value = "(${value:02X},Y)".format(value=lo)  
            elif op.addrmode == "ABS":
                lo = self.read(addr)
                addr += 1
                hi = self.read(addr)
                addr += 1
                value = "${value:02X}".format(value=hi<<8|lo)
            elif op.addrmode == "ABX":
                lo = self.read(addr)
                addr += 1
                hi = self.read(addr)
                addr += 1
                value = "${value:02X},X".format(value=hi<<8|lo)
            elif op.addrmode == "ABY":
                lo = self.read(addr)
                addr += 1
                hi = self.read(addr)
                addr += 1
                value = "${value:02X},Y".format(value=hi<<8|lo)
            elif op.addrmode == "IND":
                lo = self.read(addr)
                addr += 1
                hi = self.read(addr)
                addr += 1
                value = "(${value:02X})".format(value=hi<<8|lo)
            elif op.addrmode == "REL":
                value = "${value:02X} [${offset:04X}]".format(value=self.read(addr),offset=addr+1+self.read(addr))
                addr += 1
            print("${addr:04X}: {name} {value:11s} ({addrmode})".format(addr=opaddr,name=op.name,value=value,addrmode=op.addrmode))