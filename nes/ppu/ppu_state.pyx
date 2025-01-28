import cython

import numpy as np
cimport numpy as np


@cython.auto_pickle(True)
cdef class PPUState:
    def __init__(self, PPU2C02 ppu):
        self._pattern_table = np.array(ppu._pattern_table, dtype = np.uint8).reshape((2, 64 * 64))
        self._nametable = np.array(ppu._nametable, dtype = np.uint8)
        self._palette_table = np.array(ppu._palette_table, dtype = np.uint8)
        self._screen = [
            [
                [ppu._screen[i][j][k] for k in range(3)]
                for j in range(256)
            ]
            for i in range(240)
        ]
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
        self.sprite_pattern_shift_registers = [
            [ppu.sprite_pattern_shift_registers[i][j] for j in range(2)]
            for i in range(8)
        ]
        self.OAM = [
            [ppu.OAM[i][j] for j in range(4)]
            for i in range(64)
        ]
        self.OAMADDR = ppu.OAMADDR
        self.secondary_OAM = [
            [ppu.secondary_OAM[i][j] for j in range(4)]
            for i in range(8)
        ] 
        self.sprite_count = ppu.sprite_count
        self.eval_sprite0 = ppu.eval_sprite0
        self.render_sprite0 = ppu.render_sprite0
        self.foreground_priority = ppu.foreground_priority
        self.nmi = ppu.nmi
        self.frame_complete = ppu.frame_complete

    cdef void load_to(self, PPU2C02 ppu):
        ppu.PPUCTRL.value = self.PPUCTRL.value & 0xFF
        ppu.PPUMASK.value = self.PPUMASK.value & 0xFF
        ppu.PPUSTATUS.value = self.PPUSTATUS.value & 0xFF
        ppu.OAMADDR = self.OAMADDR & 0xFF
        ppu.VRAM_addr.value = self.VRAM_addr.value & 0xFFFF
        ppu.temp_VRAM_addr.value = self.temp_VRAM_addr.value & 0xFFFF
        ppu.fine_x = self.fine_x & 0xFF
        ppu.address_latch = self.address_latch & 0xFF
        ppu.ppu_data_buffer = self.ppu_data_buffer & 0xFF
        ppu.scanline = self.scanline
        ppu.cycle = self.cycle
        ppu.background_next_tile_id = self.background_next_tile_id & 0xFF
        ppu.background_next_tile_attribute = self.background_next_tile_attribute & 0xFF
        ppu.background_next_tile_lsb = self.background_next_tile_lsb & 0xFF
        ppu.background_next_tile_msb = self.background_next_tile_msb & 0xFF
        ppu.background_pattern_shift_register.low_bits = self.background_pattern_shift_register.low_bits & 0xFFFF
        ppu.background_pattern_shift_register.high_bits = self.background_pattern_shift_register.high_bits & 0xFFFF
        ppu.background_attribute_shift_register.low_bits = self.background_attribute_shift_register.low_bits & 0xFFFF
        ppu.background_attribute_shift_register.high_bits = self.background_attribute_shift_register.high_bits & 0xFFFF
        ppu.sprite_pattern_shift_registers = self.sprite_pattern_shift_registers
        ppu.OAM = self.OAM
        ppu.secondary_OAM = self.secondary_OAM
        ppu.sprite_count = self.sprite_count
        ppu.eval_sprite0 = self.eval_sprite0
        ppu.render_sprite0 = self.render_sprite0
        ppu.foreground_priority = self.foreground_priority
        ppu.nmi = self.nmi
        ppu.frame_complete = self.frame_complete
        ppu._pattern_table = self._pattern_table
        ppu._nametable = self._nametable
        ppu._palette_table = self._palette_table
        ppu._screen = self._screen