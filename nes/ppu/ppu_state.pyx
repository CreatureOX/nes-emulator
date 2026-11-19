import cython

import numpy as np
cimport numpy as np


@cython.auto_pickle(True)
cdef class PPUState:
    """
    PPU state snapshot for save/load functionality.
    
    Captures the complete state of the PPU including pattern tables,
    nametables, palette data, registers, and rendering state.
    """
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
        # Copy register values into standalone objects. Holding the PPU's
        # register objects by reference makes every snapshot alias the same
        # live objects, so rewind cannot restore distinct points in time.
        self.PPUSTATUS = Status(); self.PPUSTATUS.value = ppu.PPUSTATUS.value
        self.PPUMASK = Mask(); self.PPUMASK.value = ppu.PPUMASK.value
        self.PPUCTRL = Controller(); self.PPUCTRL.value = ppu.PPUCTRL.value
        self.VRAM_addr = LoopRegister(); self.VRAM_addr.value = ppu.VRAM_addr.value
        self.temp_VRAM_addr = LoopRegister(); self.temp_VRAM_addr.value = ppu.temp_VRAM_addr.value
        self.fine_x = ppu.fine_x
        self.address_latch = ppu.address_latch
        self.ppu_data_buffer = ppu.ppu_data_buffer
        self.scanline = ppu.scanline
        self.cycle = ppu.cycle
        self.background_next_tile_id = ppu.background_next_tile_id
        self.background_next_tile_attribute = ppu.background_next_tile_attribute
        self.background_next_tile_lsb = ppu.background_next_tile_lsb
        self.background_next_tile_msb = ppu.background_next_tile_msb
        self.background_pattern_shift_register = BackgroundShiftRegister()
        self.background_pattern_shift_register.low_bits = ppu.background_pattern_shift_register.low_bits
        self.background_pattern_shift_register.high_bits = ppu.background_pattern_shift_register.high_bits
        self.background_attribute_shift_register = BackgroundShiftRegister()
        self.background_attribute_shift_register.low_bits = ppu.background_attribute_shift_register.low_bits
        self.background_attribute_shift_register.high_bits = ppu.background_attribute_shift_register.high_bits
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

        # Timing / interrupt / open-bus state at the sampled dot.
        self.nmi_line = ppu.nmi_line
        self.odd_frame = ppu.odd_frame
        self.odd_skip_pending = ppu.odd_skip_pending
        self.vbl_suppress = ppu.vbl_suppress
        self.overflow_dot = ppu.overflow_dot
        self.open_bus = ppu.open_bus
        self.open_bus_frame = [ppu.open_bus_frame[i] for i in range(8)]
        self.frame_count = ppu.frame_count
        self._page_cross_echo = ppu._page_cross_echo
        self._prev_read_value = ppu._prev_read_value

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

        ppu.nmi_line = self.nmi_line
        ppu.odd_frame = self.odd_frame
        ppu.odd_skip_pending = self.odd_skip_pending
        ppu.vbl_suppress = self.vbl_suppress
        ppu.overflow_dot = self.overflow_dot
        ppu.open_bus = self.open_bus
        for i in range(8):
            ppu.open_bus_frame[i] = self.open_bus_frame[i]
        ppu.frame_count = self.frame_count
        ppu._page_cross_echo = self._page_cross_echo
        ppu._prev_read_value = self._prev_read_value

        ppu._pattern_table = self._pattern_table
        ppu._nametable = self._nametable
        ppu._palette_table = self._palette_table
        ppu._screen = self._screen