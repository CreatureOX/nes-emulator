cdef class CPUDebugger:
    def __init__(self, bus: CPUBus) -> None:
        self.bus = bus

    cpdef dict status(self):
        return {
            "N": self.bus.cpu.registers.status.status_mask["N"] > 0,
            "V": self.bus.cpu.registers.status.status_mask["V"] > 0,
            "U": self.bus.cpu.registers.status.status_mask["U"] > 0,
            "B": self.bus.cpu.registers.status.status_mask["B"] > 0,
            "D": self.bus.cpu.registers.status.status_mask["D"] > 0,
            "I": self.bus.cpu.registers.status.status_mask["I"] > 0,
            "Z": self.bus.cpu.registers.status.status_mask["Z"] > 0,
        }

    cpdef dict registers(self):
        return {
            "PC":  self.bus.cpu.registers.PC,
             "A":  self.bus.cpu.registers.A,
             "X":  self.bus.cpu.registers.X,
             "Y":  self.bus.cpu.registers.Y,
            "SP":  self.bus.cpu.registers.SP,
        }

    cpdef str ram(self, uint16_t start_addr, uint16_t end_addr):
        hex_code = ""
        for addr in range(start_addr, end_addr, 16):
            code_group = ["{hex:02X}".format(hex = self.bus.read(_addr, True)) for _addr in range(addr, min(addr + 16, end_addr))]
            hex_code += "${addr:04X}: {codes}\n".format(addr = addr, codes = " ".join(code_group))
        return hex_code

    cpdef dict to_asm(self, uint16_t start_addr, uint16_t end_addr):
        asm = {}

        addr: int = start_addr
        while addr < end_addr:
            opcode = self.bus.read(addr, True)
            opaddr = addr
            addr += 1
            op = self.bus.cpu.lookup[opcode]
            if op.addrmode.__name__ == "IMP":
                value = "    "
            if op.addrmode.__name__ == "IMM":
                value = "#${value:02X}".format(value = self.bus.read(addr, True))
                addr += 1
            elif op.addrmode.__name__ == "ZP0":
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X}".format(value = lo) 
            elif op.addrmode.__name__ == "ZPX":
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},X".format(value = lo) 
            elif op.addrmode.__name__ == "ZPY":
                lo = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},Y".format(value = lo)
            elif op.addrmode.__name__ == "IZX":
                lo = self.bus.read(addr, True)
                addr += 1
                value = "(${value:02X},X)".format(value = lo)
            elif op.addrmode.__name__ == "IZY":
                lo = self.bus.read(addr, True)
                addr += 1  
                value = "(${value:02X},Y)".format(value = lo)  
            elif op.addrmode.__name__ == "ABS":
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X}".format(value = hi << 8 | lo)
            elif op.addrmode.__name__ == "ABX":
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},X".format(value = hi << 8 | lo)
            elif op.addrmode.__name__ == "ABY":
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "${value:02X},Y".format(value = hi << 8 | lo)
            elif op.addrmode.__name__ == "IND":
                lo = self.bus.read(addr, True)
                addr += 1
                hi = self.bus.read(addr, True)
                addr += 1
                value = "(${value:02X})".format(value = hi << 8 | lo)
            elif op.addrmode.__name__ == "REL":
                inst = self.bus.read(addr, True)
                addr += 1
                offset = addr + <int8_t> inst
                value = "${value:02X} [${offset:04X}]".format(value = inst, offset = offset)

            asm[opaddr] = "${addr:04X}: {name} {value:11s} ({addrmode})".format(
                addr = opaddr,
                name = op.name,
                value = value,
                addrmode = op.addrmode.__name__)
        return asm 

    cpdef uint16_t PC(self):
        return self.bus.cpu.registers.PC
