from typing import List
from numpy import int32, uint16, uint8, void
from src.cartridge import Cartridge

from src.ppu import PPU2C02

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

    ppu: PPU2C02
    cartridge: Cartridge

    def read(self, addr: uint16, readOnly: bool) -> uint8:
        if 0x0000 <= addr <= 0x1FFF:
            return self.ram[addr & 0x07FF]
        if 0x2000 <= addr <= 0x3FFF:
            return self.ppu.readByCPU(addr & 0x0007, readOnly)
        if 0x4020 <= addr <= 0xFFFF:
            success, data = self.cartridge.readByCPU(addr)
            return data if success else 0x00
        return 0x00

    def write(self, addr: uint16, data: uint8) -> void:
        if 0x0000 <= addr <= 0x1FFF:
            self.ram[addr] = data
        if 0x2000 <= addr <= 0x3FFF:
            self.ppu.writeByCPU(addr & 0x0007, data)
        if 0x4020 <= addr <= 0xFFFF:
            success = self.cartridge.writeByCPU(addr)

    systemClockCount: int32 = 0 

    def reset(self) -> void:
        self.systemClockCount = 0
    
    def clock(self) -> void:
        self.systemClockCount += 1
