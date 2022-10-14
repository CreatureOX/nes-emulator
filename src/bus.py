from typing import List
from numpy import uint16, uint8, void
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

    def __init__(self, cartridge: Cartridge) -> None:
        from cpu import CPU6502
        from ppu import PPU2C02

        self.cpu = CPU6502(self)
        self.ppu = PPU2C02(self)
        self.cartridge = cartridge
        self.cartridge.connectBus(self)
        self.ppu.connectCartridge(self.cartridge)

    def read(self, addr: uint16, readOnly: bool) -> uint8:
        success, data = self.cartridge.readByCPU(addr)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            data = self.cpu.ram[addr & 0x07FF]
        elif 0x2000 <= addr <= 0x3FFF:
            data = self.ppu.readByCPU(addr & 0x0007, readOnly)
        return data

    def write(self, addr: uint16, data: uint8) -> void:
        success = self.cartridge.writeByCPU(addr, data)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            self.cpu.ram[addr & 0x07FF] = data
        elif 0x2000 <= addr <= 0x3FFF:
            self.ppu.writeByCPU(addr & 0x0007, data)

if __name__ == '__main__':
    cart = Cartridge("./Super Mario Bros (E).nes")
    bus = CPUBus(cart)
    bus.cpu.disassemble(start=0x8000, end=0x800F)
    bus.ppu.clock(debug=True)

