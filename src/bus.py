from typing import List
from numpy import uint16, uint8, uint32, void
from cartridge import Cartridge

class Bus:
    def __init__(self) -> None:
        self.ram = [0x00] * 64 * 1024

    def read(self, addr: uint16, readOnly: bool) -> uint8:
        if 0x0000 <= addr <= 0xFFFF:
            return self.ram[addr]
        return 0x00

    def write(self, addr: uint16, data: uint8) -> void:
        if 0x0000 <= addr <= 0xFFFF:
            self.ram[addr] = data

class CPUBus:
    ram: List[uint8] = [0x00] * 2 * 1024
    nSystemClockCounter: uint32 = 0

    def __init__(self, cartridge: Cartridge) -> None:
        from cpu import CPU6502
        from ppu import PPU2C02

        self.cpu = CPU6502(self)
        self.ppu = PPU2C02(self)
        self.cartridge = cartridge
        self.cartridge.connectBus(self)
        self.ppu.connectCartridge(self.cartridge)

    def read(self, addr: uint16, readOnly: bool) -> uint8:
        addr = uint16(addr)
        success, data = self.cartridge.readByCPU(addr)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            data = self.cpu.ram[addr & 0x07FF]
        elif 0x2000 <= addr <= 0x3FFF:
            data = self.ppu.readByCPU(addr & uint16(0x0007), readOnly)
        return uint8(data)

    def write(self, addr: uint16, data: uint8) -> void:
        addr, data = uint16(addr), uint8(data)
        success = self.cartridge.writeByCPU(addr, data)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            self.cpu.ram[addr & 0x07FF] = data
        elif 0x2000 <= addr <= 0x3FFF:
            self.ppu.writeByCPU(addr & uint16(0x0007), data)

    def reset(self) -> None:
        self.cpu.reset()
        self.nSystemClockCounter = 0

    def clock(self) -> None:
        self.ppu.clock()
        if self.nSystemClockCounter % 3 == 0:
            self.cpu.clock()
        self.nSystemClockCounter += 1

if __name__ == '__main__':
    cart = Cartridge("./nestest.nes")
    bus = CPUBus(cart)
    bus.reset()

    def test():
        while True:
            bus.clock()
            if bus.ppu.frame_complete:
                break
        while True:
            bus.clock()
            if bus.cpu.complete():
                break
        bus.ppu.frame_complete = False

    for _ in range(6):
        test()
    #bus.cpu.disassemble(start=0xC000, end=0xC020)

