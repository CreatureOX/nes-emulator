from libc.stdint cimport uint8_t, uint16_t, int16_t

from nes.ppu.registers cimport Controller, Mask, Status, LoopRegister, BackgroundShiftRegister


cdef class PPUState:
    cdef uint8_t[2][4096] _pattern_table
    cdef uint8_t[2][1024] _nametable
    cdef uint8_t[32] _palette_table
    cdef list palette_panel
    cdef uint8_t[240][256][3] _screen
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
    cdef uint8_t[8][2] sprite_pattern_shift_registers
    cdef uint8_t[64][4] OAM
    cdef uint8_t OAMADDR
    cdef uint8_t[8][4] secondary_OAM
    cdef uint8_t sprite_count
    cdef bint eval_sprite0
    cdef bint render_sprite0
    cdef bint foreground_priority
    cdef bint nmi
    cdef bint frame_complete
