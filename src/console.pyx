from libc.stdint cimport uint8_t, int8_t

from cpu cimport C, Z, I, D, B, U, V, N


K_x = 0
K_z = 1
K_a = 2
K_s = 3
K_UP = 4
K_DOWN = 5
K_LEFT = 6
K_RIGHT = 7

cdef class Console:
    def __init__(self, filename: str) -> None:
        cart = Cartridge(filename)
        self.bus = CPUBus(cart)

    cpdef void reset(self):
        self.bus.reset()

    cpdef void clock(self):
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        while True:
            self.bus.clock()
            if not self.bus.cpu.complete():
                break

    cpdef void frame(self):
        while True:
            self.bus.clock()
            if self.bus.ppu.frame_complete:
                break
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        self.bus.ppu.frame_complete = False

    cpdef void run(self):
        while True:
            self.bus.clock()
            if self.bus.ppu.frame_complete:
                break
        self.bus.ppu.frame_complete = False 

    cpdef void control(self, list pressed):
        self.bus.controller[0] = 0x00
        if pressed[K_x]:
            self.bus.controller[0] |= 0x80
        elif pressed[K_z]:
            self.bus.controller[0] |= 0x40
        elif pressed[K_a]:
            self.bus.controller[0] |= 0x20
        elif pressed[K_s]:
            self.bus.controller[0] |= 0x10
        elif pressed[K_UP]:
            self.bus.controller[0] |= 0x08
        elif pressed[K_DOWN]:
            self.bus.controller[0] |= 0x04
        elif pressed[K_LEFT]:
            self.bus.controller[0] |= 0x02
        elif pressed[K_RIGHT]:
            self.bus.controller[0] |= 0x01

    cpdef dict cpu_status_info(self):
        return {
            "N": True if self.bus.cpu.status & N > 0 else False,
            "V": True if self.bus.cpu.status & V > 0 else False,
            "U": True if self.bus.cpu.status & U > 0 else False,
            "B": True if self.bus.cpu.status & B > 0 else False,
            "D": True if self.bus.cpu.status & D > 0 else False,
            "I": True if self.bus.cpu.status & I > 0 else False,
            "Z": True if self.bus.cpu.status & Z > 0 else False,
        }

    cpdef dict cpu_registers_info(self):
        return {
            "PC": self.bus.cpu.pc,
            "A": self.bus.cpu.a,
            "X": self.bus.cpu.x,
            "Y": self.bus.cpu.y,
            "SP": self.bus.cpu.stkp,
        }

    cpdef str cpu_ram(self, uint16_t start_addr, uint16_t end_addr):
        hex_code = ""
        for addr in range(start_addr, end_addr, 16):
            hex_code += "${addr:04X}: {codes}\n".format(\
                addr=addr,\
                codes=" ".join(["{hex:02X}".format(hex=self.bus.cpu.read(_addr)) for _addr in range(addr, min(addr+16, end_addr))])\
            )
        return hex_code

    cpdef dict cpu_code_readable(self, uint16_t start_addr, uint16_t end_addr):
        asm = {}

        addr: int = start_addr
        while addr < end_addr:
            opcode = self.bus.read(addr, True)
            opaddr = addr
            addr += 1
            op = self.bus.cpu.lookup[opcode]
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
                offset = addr + <int8_t>inst
                value = "${value:02X} [${offset:04X}]".format(value=inst,offset=offset)
            asm[opaddr] = "${addr:04X}: {name} {value:11s} ({addrmode})".format(addr=opaddr,name=op.name,value=value,addrmode=op.addrmode.__name__)
        return asm 

    cpdef uint16_t cpu_pc(self):
        return self.bus.cpu.pc   

    cpdef uint8_t[:,:,:] ppu_pattern_table(self, uint8_t i):
        return self.bus.ppu.getPatternTable(i,0)
        
    cpdef uint8_t[:,:,:] ppu_palette(self):
        return self.bus.ppu.getPalette()

        