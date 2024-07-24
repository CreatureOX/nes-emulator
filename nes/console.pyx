from libc.stdint cimport uint8_t, int8_t

from nes.file_loader import FileLoader

import pyaudio
import pygame
import pickle

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
        cart = FileLoader.load(filename)
        self.bus = CPUBus(cart)
        self.cpu_debugger = CPUDebugger(self.bus)
        self.ppu_debugger = PPUDebugger(self.bus.ppu)
        self.cartridge_debugger = CartridgeDebugger(self.bus.cartridge)

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

    cpdef void save_state(self, str archive_path):
        cdef State state

        with open(archive_path, "wb") as file:
            state = State(self)
            data = pickle.dump(state, file)

    cpdef void load_state(self, str archive_path):
        cdef State state

        with open(archive_path, "rb") as file:
            state = pickle.load(file)

            self.__load_cpu_state(state.cpu_state)
            self.__load_ppu_state(state.ppu_state)

    cdef void __load_cpu_state(self, CPUState cpu_state):
        import numpy as np

        self.bus.cpu.registers = cpu_state.registers
        self.bus.cpu.ram = cpu_state.ram
        self.bus.cpu.fetched = cpu_state.fetched
        self.bus.cpu.addr_abs = cpu_state.addr_abs
        self.bus.cpu.addr_rel = cpu_state.addr_rel
        self.bus.cpu.opcode = cpu_state.opcode
        self.bus.cpu.temp = cpu_state.temp
        self.bus.cpu.remaining_cycles = cpu_state.remaining_cycles

    cdef void __load_ppu_state(self, PPUState ppu_state):
        self.bus.ppu.PPUCTRL = ppu_state.PPUCTRL
        self.bus.ppu.PPUMASK = ppu_state.PPUMASK
        self.bus.ppu.PPUSTATUS = ppu_state.PPUSTATUS
        self.bus.ppu.OAMADDR = ppu_state.OAMADDR
        self.bus.ppu.VRAM_addr = ppu_state.VRAM_addr
        self.bus.ppu.temp_VRAM_addr = ppu_state.temp_VRAM_addr
        self.bus.ppu.fine_x = ppu_state.fine_x
        self.bus.ppu.address_latch = ppu_state.address_latch
        self.bus.ppu.ppu_data_buffer = ppu_state.ppu_data_buffer
        self.bus.ppu.scanline = ppu_state.scanline
        self.bus.ppu.cycle = ppu_state.cycle
        self.bus.ppu.background_next_tile_id = ppu_state.background_next_tile_id
        self.bus.ppu.background_next_tile_attribute = ppu_state.background_next_tile_attribute
        self.bus.ppu.background_next_tile_lsb = ppu_state.background_next_tile_lsb
        self.bus.ppu.background_next_tile_msb = ppu_state.background_next_tile_msb
        self.bus.ppu.background_pattern_shift_register = ppu_state.background_pattern_shift_register
        self.bus.ppu.background_attribute_shift_register = ppu_state.background_attribute_shift_register
        # self.bus.ppu.sprite_pattern_shift_registers = ppu_state.sprite_pattern_shift_registers
        # self.bus.ppu.OAM = ppu_state.OAM
        # self.bus.ppu.secondary_OAM = ppu_state.secondary_OAM
        self.bus.ppu.sprite_count = ppu_state.sprite_count
        self.bus.ppu.eval_sprite0 = ppu_state.eval_sprite0
        self.bus.ppu.render_sprite0 = ppu_state.render_sprite0
        self.bus.ppu.foreground_priority = ppu_state.foreground_priority
        self.bus.ppu.nmi = ppu_state.nmi
        self.bus.ppu.frame_complete = ppu_state.frame_complete
        self.bus.ppu._pattern_table = ppu_state._pattern_table
        self.bus.ppu._nametable = ppu_state._nametable
        self.bus.ppu._palette_table = ppu_state._palette_table
        # self.bus.ppu._screen = ppu_state._screen
