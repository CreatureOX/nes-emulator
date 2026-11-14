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
    cdef uint16_t last_ppu_addr
    cdef uint8_t match_count
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
    cdef bint pcm_channel_enable

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr)
    cdef CPUWriteMapping map_cpu_write(self, uint16_t addr, uint8_t data)
    cdef PPUReadMapping map_ppu_read(self, uint16_t addr)
    cdef PPUWriteMapping map_ppu_write(self, uint16_t addr)
    cdef void reset(self)
    cdef bint irq_line(self)
    cdef int8_t nametable_source(self, uint16_t addr)
    cdef uint8_t nametable_read(self, uint16_t addr)
    cdef void nametable_write(self, uint16_t addr, uint8_t data)
    cdef void ppu_fetch_kind(self, uint8_t kind)
    cdef int background_attribute(self, uint16_t nt_addr)
    cdef int expansion_audio_sample(self)
    cdef bint _in_split(self)
    cdef bint _in_split_for_col(self, int ht)

    cdef uint32_t _prg_addr(self, uint16_t addr)
    cdef uint32_t _chr_addr(self, uint16_t addr)
    cdef void _detect_scanline(self, uint16_t addr)
    cdef void _on_scanline(self)
    cdef void _leave_frame(self)
