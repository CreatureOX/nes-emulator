from libc.stdint cimport uint8_t, int16_t

from nes.ppu.registers cimport Controller, Mask, Status, LoopRegister, BackgroundShiftRegister
from nes.ppu.ppu cimport PPU2C02

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
    cdef int16_t cycle
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

    # Timing / interrupt / open-bus state. The snapshot is sampled at an
    # arbitrary PPU dot (right after run_frame), and these drive NMI delivery,
    # odd-frame dot skip and $2002/$2007 open-bus reads. Leaving them at their
    # "now" values after a rewind desynchronises rendering and NMI.
    cdef bint nmi_line
    cdef bint odd_frame
    cdef bint odd_skip_pending
    cdef bint vbl_suppress
    cdef int overflow_dot
    cdef uint8_t open_bus
    cdef list open_bus_frame
    cdef long long frame_count
    cdef bint _page_cross_echo
    cdef uint8_t _prev_read_value

    cdef void load_to(self, PPU2C02 ppu)