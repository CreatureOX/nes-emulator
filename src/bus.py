from typing import List
from numpy import uint16, uint8, uint32

from cartridge import Cartridge


class Bus:
    def __init__(self) -> None:
        self.ram = [0x00] * 64 * 1024

    def read(self, addr: uint16, readOnly: bool) -> uint8:
        if 0x0000 <= addr <= 0xFFFF:
            return self.ram[addr]
        return 0x00

    def write(self, addr: uint16, data: uint8) -> None:
        if 0x0000 <= addr <= 0xFFFF:
            self.ram[addr] = data

class CPUBus:
    ram: List[uint8]
    controller: List[uint8]
    controller_state: List[uint8]
    nSystemClockCounter: uint32

    dma_page: uint8
    dma_addr: uint8
    dma_data: uint8

    dma_dummy: bool
    dma_transfer: bool

    def __init__(self, cartridge: Cartridge) -> None:
        self.ram = [0x00] * 2 * 1024
        self.controller = [0x00] * 2
        self.controller_state = [0x00] * 2
        self.nSystemClockCounter = 0

        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00

        self.dma_dummy = True
        self.dma_transfer = False

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
        elif 0x4016 <= addr <= 0x4017:       
            data = 1 if (self.controller_state[addr & 0x0001] & 0x80) > 0 else 0
            self.controller_state[addr & 0x0001] <<= 1
        return data

    def write(self, addr: uint16, data: uint8) -> None:
        success = self.cartridge.writeByCPU(addr, data)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            self.cpu.ram[addr & 0x07FF] = data
        elif 0x2000 <= addr <= 0x3FFF:
            self.ppu.writeByCPU(addr & 0x0007, data)
        elif addr == 0x4014:
            self.dma_page = data
            self.dma_addr = 0x00
            self.dma_transfer = True
        elif 0x4016 <= addr <= 0x4017:
            self.controller_state[addr & 0x0001] = self.controller[addr & 0x0001]

    def reset(self) -> None:
        self.cartridge.reset()
        self.cpu.reset()
        self.ppu.reset()
        self.nSystemClockCounter = 0
        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00
        self.dma_dummy = True
        self.dma_transfer = False

    def clock(self) -> None:
        self.ppu.clock()
        if self.nSystemClockCounter % 3 == 0:
            if self.dma_transfer:
                if self.dma_dummy:
                    if self.nSystemClockCounter % 2 == 1:
                        self.dma_dummy = False
                else:
                    if self.nSystemClockCounter % 2 == 0:
                        self.dma_data = self.read((self.dma_page << 8) | self.dma_addr, False)
                    else:
                        self.ppu.pOAM[self.dma_addr] = self.dma_data
                        self.dma_addr += 1
                        if self.dma_addr == 0x00:
                            self.dma_transfer = False
                            self.dma_dummy = True
            else:
                self.cpu.clock()
        if self.ppu.nmi:
            self.ppu.nmi = False
            self.cpu.nmi()
        self.nSystemClockCounter += 1
