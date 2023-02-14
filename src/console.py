from numpy import int8

from cartridge import Cartridge
from bus import CPUBus
from cpu import C, Z, I, D, B, U, V, N


K_x = 0
K_z = 1
K_a = 2
K_s = 3
K_UP = 4
K_DOWN = 5
K_LEFT = 6
K_RIGHT = 7

class Console:
    bus: CPUBus

    def __init__(self, filename: str) -> None:
        cart = Cartridge(filename)
        self.bus = CPUBus(cart)

    def reset(self) -> None:
        self.bus.reset()

    def clock(self) -> None:
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        while True:
            self.bus.clock()
            if not self.bus.cpu.complete():
                break

    def frame(self) -> None:
        while True:
            self.bus.clock()
            if self.bus.ppu.frame_complete:
                break
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        self.bus.ppu.frame_complete = False

    def run(self):
        while True:
            self.bus.clock()
            if self.bus.ppu.frame_complete:
                break
        self.bus.ppu.frame_complete = False         

    def control(self, pressed):
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

    def cpu_status_info(self) -> dict:
        return {
            "N": True if self.bus.cpu.status & N > 0 else False,
            "V": True if self.bus.cpu.status & V > 0 else False,
            "U": True if self.bus.cpu.status & U > 0 else False,
            "B": True if self.bus.cpu.status & B > 0 else False,
            "D": True if self.bus.cpu.status & D > 0 else False,
            "I": True if self.bus.cpu.status & I > 0 else False,
            "Z": True if self.bus.cpu.status & Z > 0 else False,
        }

    def cpu_registers_info(self) -> dict:
        return {
            "PC": self.bus.cpu.pc,
            "A": self.bus.cpu.a,
            "X": self.bus.cpu.x,
            "Y": self.bus.cpu.y,
            "SP": self.bus.cpu.stkp,
        }

    def cpu_ram(self, start_addr, end_addr) -> str:
        hex_code = ""
        for addr in range(start_addr, end_addr, 16):
            hex_code += "${addr:04X}: {codes}\n".format(\
                addr=addr,\
                codes=" ".join(["{hex:02X}".format(hex=self.bus.cpu.read(_addr)) for _addr in range(addr, min(addr+16, end_addr))])\
            )
        return hex_code

    def cpu_code_readable(self, start_addr, end_addr) -> dict:
        asm = {}

        addr: int = start_addr
        while addr < end_addr:
            opcode = self.bus.read(addr, True)
            opaddr = addr
            addr += 1
            op = self.bus.cpu.lookup[opcode]
            if op.addrmode == self.bus.cpu.IMP:
                value = "    "
            if op.addrmode == self.bus.cpu.IMM:
                value = "#${value:02X}".format(value=self.bus.read(addr, True))
                addr += 1
            elif op.addrmode == self.bus.cpu.ZP0:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X}".format(value=lo) 
            elif op.addrmode ==self.bus.cpu.ZPX:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},X".format(value=lo) 
            elif op.addrmode == self.bus.cpu.ZPY:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},Y".format(value=lo)
            elif op.addrmode == self.bus.cpu.IZX:
                lo = self.bus.read(addr, True)
                addr += 1
                value = "(${value:02X},X)".format(value=lo)
            elif op.addrmode == self.bus.cpu.IZY:
                lo = self.bus.read(addr, True)
                addr += 1  
                value = "(${value:02X},Y)".format(value=lo)  
            elif op.addrmode == self.bus.cpu.ABS:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X}".format(value=hi<<8|lo)
            elif op.addrmode == self.bus.cpu.ABX:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},X".format(value=hi<<8|lo)
            elif op.addrmode == self.bus.cpu.ABY:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},Y".format(value=hi<<8|lo)
            elif op.addrmode == self.bus.cpu.IND:
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "(${value:02X})".format(value=hi<<8|lo)
            elif op.addrmode == self.bus.cpu.REL:
                inst = self.bus.read(addr, True)
                addr += 1
                offset = addr + int8(inst)
                value = "${value:02X} [${offset:04X}]".format(value=inst,offset=offset)
            asm[opaddr] = "${addr:04X}: {name} {value:11s} ({addrmode})".format(addr=opaddr,name=op.name,value=value,addrmode=op.addrmode.__name__)
        return asm 

    def cpu_pc(self):
        return self.bus.cpu.pc   

    def ppu_pattern_table(self, i):
        return self.bus.ppu.getPatternTable(i,0)
        
    def ppu_palette(self):
        return self.bus.ppu.getPalette()
        