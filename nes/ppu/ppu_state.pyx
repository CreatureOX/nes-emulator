from nes.ppu.ppu cimport PPU2C02
import cython

import numpy as np
cimport numpy as np


cdef class PPUState:
    def __init__(self, PPU2C02 ppu):
        self._pattern_table = np.array(ppu._pattern_table, dtype = np.uint8)
        self._nametable = np.array(ppu._nametable, dtype = np.uint8)
        self._palette_table = np.array(ppu._palette_table, dtype = np.uint8)
        self._screen = ppu._screen
        self.PPUSTATUS = ppu.PPUSTATUS
        self.PPUMASK = ppu.PPUMASK
        self.PPUCTRL = ppu.PPUCTRL
        self.VRAM_addr = ppu.VRAM_addr
        self.temp_VRAM_addr = ppu.temp_VRAM_addr
        self.fine_x = ppu.fine_x
        self.address_latch = ppu.address_latch
        self.ppu_data_buffer = ppu.ppu_data_buffer
        self.scanline = ppu.scanline
        self.cycle = ppu.cycle
        self.background_next_tile_id = ppu.background_next_tile_id
        self.background_next_tile_attribute = ppu.background_next_tile_attribute
        self.background_next_tile_lsb = ppu.background_next_tile_lsb
        self.background_next_tile_msb = ppu.background_next_tile_msb
        self.background_pattern_shift_register = ppu.background_pattern_shift_register
        self.background_attribute_shift_register = ppu.background_attribute_shift_register
        self.sprite_pattern_shift_registers = ppu.sprite_pattern_shift_registers
        self.OAM = ppu.OAM
        self.OAMADDR = ppu.OAMADDR
        self.secondary_OAM = ppu.secondary_OAM
        self.sprite_count = ppu.sprite_count
        self.eval_sprite0 = ppu.eval_sprite0
        self.render_sprite0 = ppu.render_sprite0
        self.foreground_priority = ppu.foreground_priority
        self.nmi = ppu.nmi
        self.frame_complete = ppu.frame_complete
