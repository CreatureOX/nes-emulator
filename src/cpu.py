from typing import List, Dict
from numpy import uint16, uint8, int8

from bus import CPUBus


C = 1 << 0 # Carry Bit
Z = 1 << 1 # Zero
I = 1 << 2 # Disable Interrupts
D = 1 << 3 # Decimal Mode
B = 1 << 4 # Break
U = 1 << 5 # Unused
V = 1 << 6 # Overflow
N = 1 << 7 # Negative

class Op:
    name: str
    operate: callable
    addrmode: callable
    cycles: int 

    def __init__(self, name: str, operate: callable, addrmode: callable, cycles: int) -> None:
        self.name = name
        self.operate = operate
        self.addrmode = addrmode
        self.cycles = cycles

class CPU6502:
    a: uint8 # Accumlator Register
    x: uint8 # X Register
    y: uint8 # Y Register
    stkp: uint8 # Stack Pointer
    pc: uint16 # Program Counter
    status: uint8 # Status Register

    def set_a(self, a: uint8):
        self.a = a & 0xFF

    def set_x(self, x: uint8):
        self.x = x & 0xFF

    def set_y(self, y: uint8):
        self.y = y & 0xFF

    def set_stkp(self, stkp: uint8):
        self.stkp = stkp & 0xFF

    def set_pc(self, pc: uint16):
        self.pc = pc & 0xFFFF

    def set_status(self, status: uint8):
        self.status = status & 0xFF

    def getFlag(self, f: uint8) -> uint8:
        return 1 if (self.status & f) > 0 else 0

    def setFlag(self, f: uint8, v: bool) -> None: 
        if v:
            self.set_status(self.status | f)
        else:
            self.set_status(self.status & ~f)

    ram: List[uint8]
    bus: CPUBus
     
    def read(self, addr: uint16) -> uint8:
        addr &= 0xFFFF
        return self.bus.read(addr, False)

    def write(self, addr: uint16, data: uint8) -> None:
        addr, data = addr & 0xFFFF, data & 0xFF
        self.bus.write(addr, data)

    fetched: uint8
    addr_abs: uint16
    addr_rel: uint16

    def set_fetched(self, fetched: uint8):
        self.fetched = fetched & 0xFF

    def set_addr_abs(self, addr_abs: uint16):
        self.addr_abs = addr_abs & 0xFFFF

    def set_addr_rel(self, addr_rel: uint16):
        self.addr_rel = addr_rel & 0xFFFF

    def IMP(self) -> uint8:
        '''
        Address Mode: Implied
        '''
        self.set_fetched(self.a)
        return 0

    def IMM(self) -> uint8:
        '''
        Address Mode: Immediate
        '''
        self.set_addr_abs(self.pc)
        self.set_pc(self.pc + 1)
        return 0

    def ZP0(self) -> uint8:
        '''
        Address Mode: Zero Page
        '''
        self.set_addr_abs(self.read(self.pc)) 
        self.set_pc(self.pc + 1)
        self.set_addr_abs(self.addr_abs & 0x00FF)
        return 0

    def ZPX(self) -> uint8:
        '''
        Address Mode: Zero Page with X Offset
        '''
        self.set_addr_abs(self.read(self.pc) + self.x)
        self.set_pc(self.pc + 1)
        self.set_addr_abs(self.addr_abs & 0x00FF)
        return 0
    
    def ZPY(self) -> uint8:
        '''
        Address Mode: Zero Page with Y Offset
        '''
        self.set_addr_abs(self.read(self.pc) + self.y)
        self.set_pc(self.pc + 1)
        self.set_addr_abs(self.addr_abs & 0x00FF)
        return 0
    
    def REL(self) -> uint8:
        '''
        Address Mode: Relative 
        '''
        self.set_addr_rel(self.read(self.pc))
        self.set_pc(self.pc + 1)
        if (self.addr_rel & 0x80):
            self.set_addr_rel(self.addr_rel | 0xFF00)
        return 0

    def ABS(self) -> uint8:
        '''
        Address Mode: Absolute 
        '''
        lo = self.read(self.pc)
        self.set_pc(self.pc + 1)
        hi = self.read(self.pc)
        self.set_pc(self.pc + 1)
        
        self.set_addr_abs((hi << 8) | lo)
        return 0

    def ABX(self) -> uint8:
        '''
        Address Mode: Absolute with X Offset
        '''
        lo = self.read(self.pc)
        self.set_pc(self.pc + 1)
        hi = self.read(self.pc)
        self.set_pc(self.pc + 1)
        
        self.set_addr_abs((hi << 8) | lo)
        self.set_addr_abs(self.addr_abs + self.x)
        
        return 1 if (self.addr_abs & 0xFF00) != (hi << 8) else 0

    def ABY(self) -> uint8:
        '''
        Address Mode: Absolute with Y Offset
        '''
        lo = self.read(self.pc)
        self.set_pc(self.pc + 1)
        hi = self.read(self.pc)
        self.set_pc(self.pc + 1)
        
        self.set_addr_abs((hi << 8) | lo)
        self.set_addr_abs(self.addr_abs + self.y)

        return 1 if (self.addr_abs & 0xFF00) != (hi << 8) else 0

    def IND(self) -> uint8:
        '''
        Address Mode: Indirect
        '''
        ptr_lo = self.read(self.pc)
        self.set_pc(self.pc + 1)
        ptr_hi = self.read(self.pc)
        self.set_pc(self.pc + 1)
        
        ptr = (ptr_hi << 8) | ptr_lo
        
        if ptr_lo == 0x00FF:
            self.set_addr_abs((self.read(ptr & 0xFF00) << 8) | (self.read(ptr + 0)))
        else:
            self.set_addr_abs((self.read(ptr + 1) << 8) | (self.read(ptr + 0)))
        return 0

    def IZX(self) -> uint8:
        '''
        Address Mode: Indirect X
        '''
        t = self.read(self.pc)
        self.set_pc(self.pc + 1)

        lo = self.read((t + self.x) & 0x00FF)
        hi = self.read((t + self.x + 1) & 0x00FF)
        
        self.set_addr_abs((hi << 8) | lo)
        return 0

    def IZY(self) -> uint8:
        '''
        Address Mode: Indirect Y
        '''
        t = self.read(self.pc)
        self.set_pc(self.pc + 1)
        
        lo = (self.read(t & 0x00FF))
        hi = (self.read((t + 1) & 0x00FF))

        self.set_addr_abs((hi << 8) | lo)
        self.set_addr_abs(self.addr_abs + self.y)

        return 1 if (self.addr_abs & 0xFF00) != (hi << 8) else 0

    opcode: uint8
    temp: uint16
    remaining_cycles: uint8

    def set_temp(self, temp: uint16):
        self.temp = temp & 0xFFFF

    def fetch(self) -> uint8:
        '''
        fetch opcode
        '''
        if self.lookup[self.opcode].addrmode != self.IMP:
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
        self.set_temp(self.a + self.fetched + self.getFlag(C))

        self.setFlag(C, self.temp > 255)
        self.setFlag(Z, (self.temp & 0x00FF) == 0)
        self.setFlag(V, (~(self.a ^ self.fetched) & (self.a ^ self.temp)) & 0x0080)
        self.setFlag(N, self.temp & 0x80)
        
        self.set_a(self.temp & 0x00FF)
        return 1

    def SBC(self) -> uint8:
        '''
        Instruction: Subtraction with Borrow In
        Function:    A = A - M - (1 - C)
        Flags Out:   C, V, N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        value = self.fetched ^ 0x00FF
        self.set_temp(self.a + value + self.getFlag(C))

        self.setFlag(C, self.temp & 0xFF00)
        self.setFlag(Z, (self.temp & 0x00FF) == 0)
        self.setFlag(V, (self.temp ^ self.a) & (self.temp ^ value) & 0x0080)
        self.setFlag(N, self.temp & 0x0080)

        self.set_a(self.temp & 0x00FF)
        return 1

    def AND(self) -> uint8:
        '''
        Instruction: Bitwise Logic AND
        Function:    A = A & M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.set_a(self.a & self.fetched)
        
        self.setFlag(Z, self.a == 0x00)
        self.setFlag(N, self.a & 0x80)
        
        return 1

    def ASL(self) -> uint8:
        '''
        Instruction: Arithmetic Shift Left
        Function:    A = C <- (A << 1) <- 0
        Flags Out:   N, Z, C
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.fetched << 1)
        
        self.setFlag(C, (self.temp & 0xFF00) > 0)
        self.setFlag(Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(N, self.temp & 0x80)
        
        if (self.lookup[self.opcode].addrmode == self.IMP):
            self.set_a(self.temp & 0x00FF)
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    def BCC(self) -> uint8:
        '''
        Instruction: Branch if Carry Clear
        Function:    if(C == 0) pc = address 
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(C) == 0):
            self.remaining_cycles += 1
            self.set_addr_abs(self.pc + self.addr_rel)
            
            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.set_pc(self.addr_abs)
        return 0

    def BCS(self) -> uint8:
        '''
        Instruction: Branch if Carry Set
        Function:    if(C == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(C) == 1):
            self.remaining_cycles += 1
            self.set_addr_abs(self.pc + self.addr_rel)
            
            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.set_pc(self.addr_abs)
        return 0

    def BEQ(self) -> uint8:
        '''
        Instruction: Branch if Equal
        Function:    if(Z == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(Z) == 1):
            self.remaining_cycles += 1
            self.set_addr_abs(self.pc + self.addr_rel)
            
            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.set_pc(self.addr_abs)
        return 0

    def BIT(self) -> uint8:
        ''' 
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.a & self.fetched)

        self.setFlag(Z, self.temp & 0x00FF == 0x00)
        self.setFlag(N, self.fetched & (1 << 7))
        self.setFlag(V, self.fetched & (1 << 6))

        return 0

    def BMI(self) -> uint8:
        '''
        Instruction: Branch if Negative
        Function:    if(N == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(N) == 1):
            self.remaining_cycles += 1
            self.set_addr_abs(self.pc + self.addr_rel)
            
            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1
            self.set_pc(self.addr_abs)
        return 0

    def BNE(self) -> uint8:
        '''
        Instruction: Branch if Not Equal
        Function:    if(Z == 0) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(Z) == 0):
            self.remaining_cycles += 1
            self.set_addr_abs(self.pc + self.addr_rel)

            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.set_pc(self.addr_abs)
        return 0

    def BPL(self) -> uint8:
        '''
        Instruction: Branch if Positive
        Function:    if(N == 0) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(N) == 0):
            self.remaining_cycles += 1
            self.set_addr_abs(self.pc + self.addr_rel)

            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.set_pc(self.addr_abs)
    
        return 0

    def BRK(self) -> uint8:
        '''
        Instruction: Break
        Function:    Program Sourced Interrupt
        Return:      Require additional 0 clock cycle
        '''
        self.set_pc(self.pc + 1)
    
        self.setFlag(I, 1)
        self.write(0x0100 + self.stkp, (self.pc >> 8) & 0x00FF)
        self.set_stkp(self.stkp - 1)
        self.write(0x0100 + self.stkp, self.pc & 0x00FF)
        self.set_stkp(self.stkp - 1)

        self.setFlag(B, 1)
        self.write(0x0100 + self.stkp, self.status)
        self.set_stkp(self.stkp - 1)
        self.setFlag(B, 0)
        
        self.set_pc(self.read(0xFFFE) | self.read(0xFFFF) << 8)
        return 0

    def BVC(self) -> uint8:
        '''
        Instruction: Branch if Overflow Clear
        Function:    if(V == 0) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(V) == 0):
            self.remaining_cycles += 1
            self.set_addr_abs(self.pc + self.addr_rel)

            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.set_pc(self.addr_abs)
        return 0

    def BVS(self) -> uint8:
        '''
        Instruction: Branch if Overflow Set
        Function:    if(V == 1) pc = address
        Return:      Require additional 0 clock cycle
        '''
        if (self.getFlag(V) == 1):
            self.remaining_cycles += 1
            self.set_addr_abs(self.pc + self.addr_rel)

            if ((self.addr_abs & 0xFF00) != (self.pc & 0xFF00)):
                self.remaining_cycles += 1

            self.set_pc(self.addr_abs)
        return 0

    def CLC(self) -> uint8:
        '''
        Instruction: Clear Carry Flag
        Function:    C = 0
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(C, False)
        return 0

    def CLD(self) -> uint8:
        '''
        Instruction: Clear Decimal Flag
        Function:    D = 0
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(D, False)
        return 0

    def CLI(self) -> uint8:
        '''
        Instruction: Disable Interrupts / Clear Interrupt Flag
        Function:    I = 0
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(I, False)
        return 0

    def CLV(self) -> uint8:
        '''
        Instruction: Clear Overflow Flag
        Function:    V = 0
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(V, False)
        return 0

    def CMP(self) -> uint8:
        '''
        Instruction: Compare Accumulator
        Function:    C <- A >= M      Z <- (A - M) == 0
        Flags Out:   N, C, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.set_temp(self.a - self.fetched)
        self.setFlag(C, self.a >= self.fetched)
        self.setFlag(Z, self.temp & 0x00FF == 0x0000)
        self.setFlag(N, self.temp & 0x0080)
        return 1

    def CPX(self) -> uint8:
        '''
        Instruction: Compare X Register
        Function:    C <- X >= M      Z <- (X - M) == 0
        Flags Out:   N, C, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.x - self.fetched)
        self.setFlag(C, self.x >= self.fetched)
        self.setFlag(Z, self.temp & 0x00FF == 0x0000)
        self.setFlag(N, self.temp & 0x0080)
        return 0

    def CPY(self) -> uint8:
        '''
        Instruction: Compare Y Register
        Function:    C <- Y >= M      Z <- (Y - M) == 0
        Flags Out:   N, C, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.y - self.fetched)
        self.setFlag(C, self.y >= self.fetched)
        self.setFlag(Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(N, self.temp & 0x0080)
        return 0

    def DEC(self) -> uint8:
        '''
        Instruction: Decrement Value at Memory Location
        Function:    M = M - 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.fetched - 1)
        self.write(self.addr_abs, self.temp & 0x00FF)
        self.setFlag(Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(N, self.temp & 0x0080)
        return 0

    def DEX(self) -> uint8:
        '''
        Instruction: Decrement X Register
        Function:    X = X - 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.set_x(self.x - 1)
        self.setFlag(Z, self.x == 0x00)
        self.setFlag(N, self.x & 0x80)
        return 0

    def DEY(self) -> uint8:
        '''
        Instruction: Decrement Y Register
        Function:    Y = Y - 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.set_y(self.y - 1)
        self.setFlag(Z, self.y == 0x00)
        self.setFlag(N, self.y & 0x80)
        return 0

    def EOR(self) -> uint8:
        '''
        Instruction: Bitwise Logic XOR
        Function:    A = A xor M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.set_a(self.a ^ self.fetched)   
        self.setFlag(Z, self.a == 0x00)
        self.setFlag(N, self.a & 0x80)
        return 1

    def INC(self) -> uint8:
        '''
        Instruction: Increment Value at Memory Location
        Function:    M = M + 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.fetched + 1)
        self.write(self.addr_abs, self.temp & 0x00FF)
        self.setFlag(Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(N, self.temp & 0x0080)
        return 0

    def INX(self) -> uint8:
        '''
        Instruction: Increment X Register
        Function:    X = X + 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.set_x(self.x + 1)
        self.setFlag(Z, self.x == 0x00)
        self.setFlag(N, self.x & 0x80)
        return 0

    def INY(self) -> uint8:
        '''
        Instruction: Increment Y Register
        Function:    Y = Y + 1
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.set_y(self.y + 1)
        self.setFlag(Z, self.y == 0x00)
        self.setFlag(N, self.y & 0x80)
        return 0

    def JMP(self) -> uint8:
        '''
        Instruction: Jump To Location
        Function:    pc = address
        Return:      Require additional 0 clock cycle
        '''
        self.set_pc(self.addr_abs)
        return 0

    def JSR(self) -> uint8:
        '''
        Instruction: Jump To Sub-Routine
        Function:    Push current pc to stack, pc = address
        Return:      Require additional 0 clock cycle
        '''
        self.set_pc(self.pc - 1)

        self.write(0x0100 + self.stkp, (self.pc >> 8) & 0x00FF)
        self.set_stkp(self.stkp - 1)
        self.write(0x0100 + self.stkp, self.pc & 0x00FF)
        self.set_stkp(self.stkp - 1)

        self.set_pc(self.addr_abs)
        return 0

    def LDA(self) -> uint8:
        '''
        Instruction: Load The Accumulator
        Function:    A = M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.set_a(self.fetched)
        self.setFlag(Z, self.a == 0x00)
        self.setFlag(N, self.a & 0x80)
        return 1

    def LDX(self) -> uint8:
        '''
        Instruction: Load The X Register
        Function:    X = M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.set_x(self.fetched)
        self.setFlag(Z, self.x == 0x00)
        self.setFlag(N, self.x & 0x80)
        return 1

    def LDY(self) -> uint8:
        '''
        Instruction: Load The Y Register
        Function:    Y = M
        Flags Out:   N, Z
        Return:      Require additional 1 clock cycle
        '''
        self.fetch()
        self.set_y(self.fetched)
        self.setFlag(Z, self.y == 0x00)
        self.setFlag(N, self.y & 0x80)
        return 1

    def LSR(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.setFlag(C, self.fetched & 0x0001)
        self.set_temp(self.fetched >> 1)   
        self.setFlag(Z, (self.temp & 0x00FF) == 0x0000)
        self.setFlag(N, self.temp & 0x0080)
        if (self.lookup[self.opcode].addrmode == self.IMP):
            self.set_a(self.temp & 0x00FF)
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
        self.set_a(self.a | self.fetched)
        self.setFlag(Z, self.a == 0x00)
        self.setFlag(N, self.a & 0x80)
        return 1

    def PHA(self) -> uint8:
        '''
        Instruction: Push Accumulator to Stack
        Function:    A -> stack
        Return:      Require additional 0 clock cycle
        '''
        self.write(0x0100 + self.stkp, self.a)
        self.set_stkp(self.stkp - 1)
        return 0

    def PHP(self) -> uint8:
        '''
        Instruction: Push Status Register to Stack
        Function:    status -> stack
        Return:      Require additional 0 clock cycle
        '''
        self.write(0x0100 + self.stkp, self.status | B | U)
        self.setFlag(B, 0)
        self.setFlag(U, 0)
        self.set_stkp(self.stkp - 1)
        return 0

    def PLA(self) -> uint8:
        '''
        Instruction: Pop Accumulator off Stack
        Function:    A <- stack
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.set_stkp(self.stkp + 1)
        self.set_a(self.read(0x0100 + self.stkp))
        self.setFlag(Z, self.a == 0x00)
        self.setFlag(N, self.a & 0x80)
        return 0

    def PLP(self) -> uint8:
        '''
        Instruction: Pop Status Register off Stack
        Function:    Status <- stack
        Return:      Require additional 0 clock cycle
        '''
        self.set_stkp(self.stkp + 1)
        self.set_status(self.read(0x0100 + self.stkp))
        self.setFlag(U, 1)
        return 0

    def ROL(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp((self.fetched << 1) | self.getFlag(C))
        self.setFlag(C, self.temp & 0xFF00)
        self.setFlag(Z, self.temp & 0x00FF == 0x0000)
        self.setFlag(N, self.temp & 0x0080)
        if (self.lookup[self.opcode].addrmode == self.IMP):
            self.set_a(self.temp & 0x00FF)
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    def ROR(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.fetch()
        self.set_temp(self.getFlag(C) << 7 | (self.fetched >> 1))
        self.setFlag(C, self.fetched & 0x01)
        self.setFlag(Z, self.temp & 0x00FF == 0x00)
        self.setFlag(N, self.temp & 0x0080)
        if (self.lookup[self.opcode].addrmode == self.IMP):
            self.set_a(self.temp & 0x00FF)
        else:
            self.write(self.addr_abs, self.temp & 0x00FF)
        return 0

    def RTI(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.set_stkp(self.stkp + 1)
        self.set_status(self.read(0x0100 + self.stkp))
        self.set_status(self.status & ~B)
        self.set_status(self.status & ~U)

        self.set_stkp(self.stkp + 1)
        self.set_pc(self.read(0x0100 + self.stkp))
        self.set_stkp(self.stkp + 1)
        self.set_pc(self.pc | (self.read(0x0100 + self.stkp) << 8))
        return 0

    def RTS(self) -> uint8:
        '''
        Return:      Require additional 0 clock cycle
        '''
        self.set_stkp(self.stkp + 1)
        self.set_pc(self.read(0x0100 + self.stkp))
        self.set_stkp(self.stkp + 1)
        self.set_pc(self.pc | (self.read(0x0100 + self.stkp) << 8))
    
        self.set_pc(self.pc + 1)
        return 0

    def SEC(self) -> uint8:
        '''
        Instruction: Set Carry Flag
        Function:    C = 1 
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(C, True)
        return 0

    def SED(self) -> uint8:
        '''
        Instruction: Set Decimal Flag
        Function:    D = 1
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(D, True)
        return 0

    def SEI(self) -> uint8:
        '''
        Instruction: Set Interrupt Flag / Enable Interrupts
        Function:    I = 1
        Return:      Require additional 0 clock cycle
        '''
        self.setFlag(I, True)
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
        self.set_x(self.a)
        self.setFlag(Z, self.x == 0x00)
        self.setFlag(N, self.x & 0x80)
        return 0

    def TAY(self) -> uint8:
        '''
        Instruction: Transfer Accumulator to Y Register
        Function:    Y = A
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.set_y(self.a)
        self.setFlag(Z, self.y == 0x00)
        self.setFlag(N, self.y & 0x80)
        return 0

    def TSX(self) -> uint8:
        '''
        Instruction: Transfer Stack Pointer to X Register
        Function:    X = stack pointer
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.set_x(self.stkp)
        self.setFlag(Z, self.x == 0x00)
        self.setFlag(N, self.x & 0x80)
        return 0

    def TXA(self) -> uint8:
        '''
        Instruction: Transfer X Register to Accumulator
        Function:    A = X
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.set_a(self.x)
        self.setFlag(Z, self.a == 0x00)
        self.setFlag(N, self.a & 0x80)
        return 0

    def TXS(self) -> uint8:
        '''
        Instruction: Transfer X Register to Stack Pointer
        Function:    stack pointer = X
        Return:      Require additional 0 clock cycle
        '''
        self.set_stkp(self.x)
        return 0

    def TYA(self) -> uint8:
        '''
        Instruction: Transfer Y Register to Accumulator
        Function:    A = Y
        Flags Out:   N, Z
        Return:      Require additional 0 clock cycle
        '''
        self.set_a(self.y)
        self.setFlag(Z, self.a == 0x00)
        self.setFlag(N, self.a & 0x80)
        return 0

    def XXX(self) -> uint8:
        '''
        Instruction: captures illegal opcodes
        Return:      Require additional 0 clock cycle
        '''
        return 0

    def __init__(self, bus: CPUBus) -> None:
        self.a = 0x00
        self.x = 0x00
        self.y = 0x00
        self.stkp = 0x00
        self.pc = 0x0000
        self.status = 0x00

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
    
    def reset(self) -> None:
        '''
        Reset Interrupt
        '''
        self.addr_abs = 0xFFFC
        lo = self.read(self.addr_abs + 0)
        hi = self.read(self.addr_abs + 1)
        
        self.set_pc(hi << 8 | lo)

        self.a = 0x00
        self.x = 0x00
        self.y = 0x00
        self.stkp = 0xFD
        self.status = 0x00 | U
        
        self.addr_rel = 0x0000
        self.addr_abs = 0x0000
        self.fetched = 0x00
        
        self.remaining_cycles = 8

    def irq(self) -> None:
        '''
        Interrupt Request
        '''
        if (self.getFlag(I) == 0):
            self.write(0x0100 + self.stkp, (self.pc >> 8) & 0x00FF)
            self.set_stkp(self.stkp - 1)
            self.write(0x0100 + self.stkp, self.pc & 0x00FF)
            self.set_stkp(self.stkp - 1)
            
            self.setFlag(B, 0)
            self.setFlag(U, 1)
            self.setFlag(I, 1)
            self.write(0x0100 + self.stkp, self.status)
            self.set_stkp(self.stkp - 1)

            self.addr_abs = 0xFFFE
            lo = self.read(self.addr_abs + 0)
            hi = self.read(self.addr_abs + 1)
            self.set_pc(hi << 8 | lo)

            self.remaining_cycles = 7
    
    def nmi(self) -> None:
        '''
        Non-Maskable Interrupt Request
        '''
        self.write(0x0100 + self.stkp, (self.pc >> 8) & 0x00FF)
        self.set_stkp(self.stkp - 1)
        self.write(0x0100 + self.stkp, self.pc & 0x00FF)
        self.set_stkp(self.stkp - 1)

        self.setFlag(B, 0)
        self.setFlag(U, 1)
        self.setFlag(I, 1)
        self.write(0x0100 + self.stkp, self.status)
        self.set_stkp(self.stkp - 1)

        self.addr_abs = 0xFFFA
        lo = self.read(self.addr_abs + 0)
        hi = self.read(self.addr_abs + 1)
        self.set_pc(hi << 8 | lo)

        self.remaining_cycles = 8

    clock_count: int

    def clock(self) -> None:
        '''
        Perform one clock cycle
        '''
        if self.remaining_cycles == 0:
            self.opcode = self.read(self.pc)
            self.setFlag(U, True)
            self.set_pc(self.pc + 1)
            op = self.lookup[self.opcode]
            self.remaining_cycles = op.cycles
            additional_cycle1: uint8 = op.addrmode()
            additional_cycle2: uint8 = op.operate()
            self.remaining_cycles += (additional_cycle1 & additional_cycle2)
            self.setFlag(U, True)
            # if debug:
            #     print(op)
            #     print("A: {A} X:{X} Y:{Y} STKP:{STKP} PC: {PC} STATUS:{STATUS}".format(A=hex(self.a), X=hex(self.x), Y=hex(self.y), STKP=hex(self.stkp), PC=hex(self.pc), STATUS=hex(self.status)))
            #     print("fetched: {fetched} addr_rel: {addr_rel} addr_abs: {addr_abs}".format(fetched=hex(self.fetched), addr_rel=hex(self.addr_rel), addr_abs=hex(self.addr_abs)))
            #     print("temp: {temp}\n".format(temp=hex(self.temp)))

        self.clock_count += 1
        self.remaining_cycles -= 1

    def complete(self) -> bool:
        return self.remaining_cycles == 0
    
    def disassemble(self, start: uint16, end: uint16) -> None:
        for addr in range(start, end, 16):
            print("${addr:#04X}: {codes}".format(\
                addr=addr,\
                codes=" ".join(["{hex:02X}".format(hex=self.read(addr)) for addr in range(addr, min(addr+16, end))])\
            ))
        print()
        addr = start
        while addr < end:
            opcode = self.bus.read(addr, True)
            opaddr = addr
            addr += 1
            op = self.lookup[opcode]
            if op.addrmode == self.IMP:
                value = "    "
            if op.addrmode == self.IMM:
                value = "#${value:02X}".format(value=self.bus.read(addr, True))
                addr += 1
            elif op.addrmode == self.ZP0:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X}".format(value=lo) 
            elif op.addrmode == self.ZPX:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},X".format(value=lo) 
            elif op.addrmode == self.ZPY:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},Y".format(value=lo)
            elif op.addrmode == self.IZX:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "(${value:02X},X)".format(value=lo)
            elif op.addrmode == self.IZY:
                lo = self.bus.read(addr, True)
                addr += 1  
                value = "(${value:02X},Y)".format(value=lo)  
            elif op.addrmode == self.ABS:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X}".format(value=hi<<8|lo)
            elif op.addrmode == self.ABX:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},X".format(value=hi<<8|lo)
            elif op.addrmode == self.ABY:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},Y".format(value=hi<<8|lo)
            elif op.addrmode == self.IND:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "(${value:02X})".format(value=hi<<8|lo)
            elif op.addrmode == self.REL:
                inst = self.bus.read(addr, True)
                addr += 1
                offset = addr + int8(inst)
                value = "${value:02X} [${offset:04X}]".format(value=inst,offset=offset)
            print("${addr:04X}: {name} {value:11s} ({addrmode})".format(addr=opaddr,name=op.name,value=value,addrmode=op.addrmode))

    def toHex(self, start: uint16, end: uint16) -> str:
        hex_code = ""
        for addr in range(start, end, 16):
            hex_code += "${addr:04X}: {codes}\n".format(\
                addr=addr,\
                codes=" ".join(["{hex:02X}".format(hex=self.read(addr)) for addr in range(addr, min(addr+16, end))])\
            )
        return hex_code

    def toReadable(self, start: uint16, end: uint16) -> Dict[uint16, str]:
        asm = {}

        addr: int = start
        while addr < end:
            opcode = self.bus.read(addr, True)
            opaddr = addr
            addr += 1
            op = self.lookup[opcode]
            if op.addrmode == self.IMP:
                value = "    "
            if op.addrmode == self.IMM:
                value = "#${value:02X}".format(value=self.bus.read(addr, True))
                addr += 1
            elif op.addrmode == self.ZP0:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X}".format(value=lo) 
            elif op.addrmode ==self.ZPX:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},X".format(value=lo) 
            elif op.addrmode == self.ZPY:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},Y".format(value=lo)
            elif op.addrmode == self.IZX:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "(${value:02X},X)".format(value=lo)
            elif op.addrmode == self.IZY:
                lo = self.bus.read(addr, True)
                addr += 1  
                value = "(${value:02X},Y)".format(value=lo)  
            elif op.addrmode == self.ABS:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X}".format(value=hi<<8|lo)
            elif op.addrmode == self.ABX:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},X".format(value=hi<<8|lo)
            elif op.addrmode == self.ABY:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},Y".format(value=hi<<8|lo)
            elif op.addrmode == self.IND:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "(${value:02X})".format(value=hi<<8|lo)
            elif op.addrmode == self.REL:
                inst = self.bus.read(addr, True)
                addr += 1
                offset = addr + int8(inst)
                value = "${value:02X} [${offset:04X}]".format(value=inst,offset=offset)
            asm[opaddr] = "${addr:04X}: {name} {value:11s} ({addrmode})".format(addr=opaddr,name=op.name,value=value,addrmode=op.addrmode.__name__)
        return asm
