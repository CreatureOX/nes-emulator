from libc.stdint cimport uint8_t, uint16_t, int16_t

from nes.ppu.registers cimport Controller, Mask, Status, LoopRegister, BackgroundShiftRegister

import numpy as np
cimport numpy as np


cdef class PPUState:
    cdef np.ndarray _pattern_table
    cdef np.ndarray _nametable
    cdef np.ndarray _palette_table
    cdef list _screen
    cdef Status PPUSTATUS
    cdef Mask PPUMASK
    cdef Controller PPUCTRL
    cdef LoopRegister VRAM_addr
    cdef LoopRegister temp_VRAM_addr
    cdef uint8_t fine_x
    cdef uint8_t address_latch
    cdef uint8_t ppu_data_buffer
    cdef int16_t scanline
    cdef uint8_t cycle
    cdef uint8_t background_next_tile_id
    cdef uint8_t background_next_tile_attribute
    cdef uint8_t background_next_tile_lsb, background_next_tile_msb
    cdef BackgroundShiftRegister background_pattern_shift_register
    cdef BackgroundShiftRegister background_attribute_shift_register
    cdef list sprite_pattern_shift_registers
    cdef list OAM
    cdef uint8_t OAMADDR
    cdef list secondary_OAM
    cdef uint8_t sprite_count
    cdef bint eval_sprite0
    cdef bint render_sprite0
    cdef bint foreground_priority
    cdef bint nmi
    cdef bint frame_complete
