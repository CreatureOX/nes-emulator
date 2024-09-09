from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.cart.cart cimport Cartridge
from nes.cpu.cpu cimport CPU6502
from nes.ppu.ppu cimport PPU2C02
from nes.apu.apu cimport APU2A03


cdef class CPUBus:
    cdef uint8_t[2048] ram
    cdef public uint8_t[2] controller
    cdef uint8_t[2] controller_state
    cdef uint32_t system_clock_counter

    cdef uint8_t dma_page
    cdef uint8_t dma_addr
    cdef uint8_t dma_data

    cdef bint dma_dummy
    cdef bint dma_transfer

    cdef public CPU6502 cpu 
    cdef public PPU2C02 ppu
    cdef public APU2A03 apu
    cdef Cartridge cartridge

    cpdef uint8_t read(self, uint16_t addr, bint read_only)
    cpdef void write(self, uint16_t addr, uint8_t data)
    cpdef void reset(self)
    cpdef void power_up(self)
    cpdef void clock(self) except * 
    cpdef void run_frame(self)
