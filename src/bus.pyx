from libc.stdint cimport uint8_t, uint16_t, uint32_t

from cartridge cimport Cartridge
from cpu cimport CPU6502
from ppu cimport PPU2C02


cdef class CPUBus:
    def __init__(self, Cartridge cartridge) -> None:
        self.ram = [0x00] * 2 * 1024
        self.controller = [0x00,0x00]
        self.controller_state = [0x00,0x00]
        self.nSystemClockCounter = 0

        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00

        self.dma_dummy = True
        self.dma_transfer = False

        self.cpu = CPU6502(self)
        self.ppu = PPU2C02(self)
        self.cartridge = cartridge
        self.cartridge.connectBus(self)
        self.ppu.connectCartridge(self.cartridge)

    cpdef uint8_t read(self, uint16_t addr, bint readOnly):
        success, data = self.cartridge.readByCPU(addr)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            data = self.cpu.ram[addr & 0x07FF]
        elif 0x2000 <= addr <= 0x3FFF:
            data = self.ppu.readByCPU(addr & 0x0007, readOnly)
        elif addr == 0x4015:
            pass
            # data = self.apu.readByCPU(addr)
        elif 0x4016 <= addr <= 0x4017:       
            data = 1 if (self.controller_state[addr & 0x0001] & 0x80) > 0 else 0
            self.controller_state[addr & 0x0001] <<= 1
        return data

    cpdef void write(self, uint16_t addr, uint8_t data):
        success = self.cartridge.writeByCPU(addr, data)
        if success:
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            self.cpu.ram[addr & 0x07FF] = data
        elif 0x2000 <= addr <= 0x3FFF:
            self.ppu.writeByCPU(addr & 0x0007, data)
        elif 0x4000 <= addr <= 0x4013 or addr == 0x4015 or addr == 0x4017:
            pass
            # self.apu.writeByCPU(addr, data)
        elif addr == 0x4014:
            self.dma_page = data
            self.dma_addr = 0x00
            self.dma_transfer = True
        elif 0x4016 <= addr <= 0x4017:
            self.controller_state[addr & 0x0001] = self.controller[addr & 0x0001]

    cpdef void reset(self):
        self.cartridge.reset()
        self.cpu.reset()
        self.ppu.reset()
        self.nSystemClockCounter = 0
        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00
        self.dma_dummy = True
        self.dma_transfer = False

    cpdef void clock(self) except *:
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
                        self.ppu.pOAM[self.dma_addr & 0xFF] = self.dma_data
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
