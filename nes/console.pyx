from libc.stdint cimport uint8_t, int8_t

import pyaudio
import pygame

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
        self.cpu_debugger = CPUDebugger(self.bus)
        self.ppu_debugger = PPUDebugger(self.bus.ppu)

    cpdef void power_up(self):
        self.bus.power_up()

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
        self.bus.run_frame()

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
