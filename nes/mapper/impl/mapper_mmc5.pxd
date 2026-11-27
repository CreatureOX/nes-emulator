from libc.stdint cimport uint8_t, int8_t, uint16_t, uint32_t

from nes.mapper.mapper cimport Mapper
from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping
from nes.mapper.mapping cimport PPUReadMapping, PPUWriteMapping


cdef class MapperMMC5(Mapper):
    cdef uint8_t prg_mode
    cdef uint8_t chr_mode
    cdef uint8_t protect1
    cdef uint8_t protect2
    cdef uint8_t exram_mode
    cdef uint8_t nt_mapping
    cdef uint8_t fill_tile
    cdef uint8_t fill_attr
    cdef uint8_t prg_bank[5]
    cdef uint8_t chr_bank_a[8]
    cdef uint8_t chr_bank_b[4]
    cdef uint8_t chr_upper
    cdef uint8_t split_mode
    cdef uint8_t split_scroll
    cdef uint8_t split_bank
    cdef uint8_t irq_target
    cdef bint irq_enable
    cdef bint irq_pending
    cdef bint in_frame
    cdef uint8_t irq_counter
    cdef uint8_t mul_a
    cdef uint8_t mul_b
    cdef uint8_t exram[1024]
    cdef bint last_chr_set
    cdef bint started
    cdef uint8_t fetch_kind
    cdef uint8_t sprite_8x16
    cdef bint substitutions
    cdef uint8_t pcm_data
    cdef uint8_t pcm_control
    cdef bint pcm_irq_pending

    # MMC5 dual pulse ($5000-$5007), status $5015. Unlike the 2A03 the MMC5
    # has no sweep unit; envelope and length both clock at ~240 Hz and share
    # the halt bit. The length table differs from the APU at index $1C.
    cdef int pulse_period[2]
    cdef int pulse_timer[2]
    cdef int pulse_step[2]
    cdef int pulse_duty[2]
    cdef int pulse_volume[2]
    cdef bint pulse_constant[2]
    cdef bint pulse_halt[2]
    cdef bint pulse_enabled[2]
    cdef bint pulse_env_start[2]
    cdef int pulse_env_decay[2]
    cdef int pulse_env_divider[2]
    cdef int pulse_length[2]
    cdef long long pulse_audio_cycle

    # 32 KiB switchable PRG RAM. $5113 owns the $6000 window; $5114-$5116
    # bit 7 clears route their $8000+ window here instead of PRG ROM.
    cdef uint8_t[:] prg_ram

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr)
    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data)
    cdef PPUReadMapping map_ppu_read(self, uint16_t addr)
    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr)
    cdef void reset(self)
    cdef void scanline(self)
    cdef bint irq_line(self)
    cdef int8_t nametable_source(self, uint16_t addr)
    cdef uint8_t nametable_read(self, uint16_t addr)
    cdef void nametable_write(self, uint16_t addr, uint8_t data)
    cdef void ppu_fetch_kind(self, uint8_t kind)
    cdef int background_attribute(self, uint16_t nt_addr)
    cdef int expansion_audio_sample(self)
    cdef int expansion_pulse_sample(self)
    cdef void audio_clock(self, int cycles)
    cdef void _clock_pulse_frame(self)
    cdef bint _in_split(self)
    cdef bint _in_split_for_col(self, int ht)

    cdef uint32_t _prg_addr(self, uint16_t addr)
    cdef bint _prg_ram_offset(self, uint16_t addr, uint32_t* offset)
    cdef uint32_t _chr_addr(self, uint16_t addr)
    cdef void _on_scanline(self)
    cdef void _leave_frame(self)
