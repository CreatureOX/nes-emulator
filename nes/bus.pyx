from libc.stdint cimport uint8_t, uint16_t, uint32_t

from cartridge cimport Cartridge
from cpu cimport CPU6502
from ppu cimport PPU2C02
from apu cimport APU2A03

import pyaudio
import pygame


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
        self.apu = APU2A03()
        self.cartridge = cartridge
        self.cartridge.connectBus(self)
        self.ppu.connectCartridge(self.cartridge)

    cpdef uint8_t read(self, uint16_t addr, bint readOnly):
        success, data = self.cartridge.readByCPU(addr)
        if success:
            # $4020–$FFFF: Cartridge space: PRG ROM, PRG RAM, and mapper registers
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            # $0000–$07FF: 2KB internal RAM
            # $0800–$0FFF, $1000–$17FF, $1800–$1FFF are Mirrors of $0000–$07FF
            data = self.cpu.ram[addr & 0x07FF]
        elif 0x2000 <= addr <= 0x3FFF:
            # $2000–$2007: NES PPU registers
            # $2008–$3FFF are Mirrors of $2000–$2007 (repeats every 8 bytes)
            data = self.ppu.readByCPU(addr & 0x0007, readOnly)
        elif addr == 0x4015:
            # $4015: APU Status
            data = self.apu.readByCPU(addr)
        elif 0x4016 <= addr <= 0x4017:
            # $4016:  I/O registers Joystick 1 data
            # $4017:  I/O registers Joystick 2 data       
            data = 1 if (self.controller_state[addr & 0x0001] & 0x80) > 0 else 0
            self.controller_state[addr & 0x0001] <<= 1
        return data

    cpdef void write(self, uint16_t addr, uint8_t data):
        success = self.cartridge.writeByCPU(addr, data)
        if success:
            # $4020–$FFFF: Cartridge space: PRG ROM, PRG RAM, and mapper registers
            pass
        elif 0x0000 <= addr <= 0x1FFF:
            # $0000–$07FF: 2KB internal RAM
            # $0800–$0FFF, $1000–$17FF, $1800–$1FFF are Mirrors of $0000–$07FF
            self.cpu.ram[addr & 0x07FF] = data
        elif 0x2000 <= addr <= 0x3FFF:
            # $2000–$2007: NES PPU registers
            # $2008–$3FFF are Mirrors of $2000–$2007 (repeats every 8 bytes)
            self.ppu.writeByCPU(addr & 0x0007, data)
        elif 0x4000 <= addr <= 0x4013 or addr == 0x4015 or addr == 0x4017:
            # $4000–$4007: Pulse
            # $4008–$400B: Triangle
            # $400C–$400F: Noise
            # $4010–$4013: DMC
            # $4015: Status
            # $4017: Frame Counter
            self.apu.writeByCPU(addr, data)
        elif addr == 0x4014:
            # $4014: Copy 256 bytes from $xx00-$xxFF into OAM via OAMDATA ($2004)
            self.dma_page = data
            self.dma_addr = 0x00
            self.dma_transfer = True
        elif 0x4016 <= addr <= 0x4017:
            # $4016: Joystick strobe
            # $4017: Frame counter control
            self.controller_state[addr & 0x0001] = self.controller[addr & 0x0001]

    cpdef void reset(self):
        self.cartridge.reset()
        self.cpu.reset()
        self.ppu.reset()
        # self.apu.reset()
        self.nSystemClockCounter = 0
        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00
        self.dma_dummy = True
        self.dma_transfer = False

    cpdef void power_up(self):
        self.cartridge.reset()
        self.cpu.power_up()
        self.ppu.reset()
        self.nSystemClockCounter = 0
        self.dma_page = 0x00
        self.dma_addr = 0x00
        self.dma_data = 0x00
        self.dma_dummy = True
        self.dma_transfer = False    

    cpdef void clock(self) except *:
        cdef uint8_t cycles = 0

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
                        self.write(0x2004, self.dma_data)
                        self.dma_addr += 1
                        if self.dma_addr == 0x00:
                            self.dma_transfer = False
                            self.dma_dummy = True
            else:
                cycles = self.cpu.clock()
        if self.ppu.nmi:
            self.ppu.nmi = False
            self.cpu.nmi()

        if self.cartridge.getMapper().IRQ_state():
            self.cartridge.getMapper().IRQ_clear()
            self.cpu.irq()

        self.nSystemClockCounter += 1
        self.apu.clock(cycles)
        # if sample > 0.0:
        #     print(sample)

    cpdef void run_frame(self):
        _clock = pygame.time.Clock()
        audio = pyaudio.PyAudio()
        player = audio.open(format=pyaudio.paInt16,
                        channels=1,
                        rate=48000,
                        output=True,
                        frames_per_buffer=400,
                        stream_callback=self.apu.pyaudio_callback,
                        )
        player.start_stream() 
        for _ in range(262):
            for self.ppu.cycle in range(341):               
                self.clock()
                while self.apu.buffer_remaining() > 2400 and player.is_active():
                    _clock.tick(240)  # wait for about 2ms (~= 96 samples)
