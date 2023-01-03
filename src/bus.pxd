from libc.stdint cimport uint8_t, uint16_t, uint32_t

from cartridge cimport Cartridge
from cpu cimport CPU6502
#from ppu cimport PPU2C02

import cython


cdef class CPUBus:
    cdef uint8_t[2048] ram
    cdef public list controller
    cdef uint8_t[2] controller_state
    cdef uint32_t nSystemClockCounter

    cdef uint8_t dma_page
    cdef uint8_t dma_addr
    cdef uint8_t dma_data

    cdef bint dma_dummy
    cdef bint dma_transfer

    cdef public CPU6502 cpu 
    cdef public object ppu
    cdef Cartridge cartridge

    @cython.locals(success=bint, data=uint8_t)
    cpdef uint8_t read(self, uint16_t, bint)
    @cython.locals(success=bint)
    cpdef void write(self, uint16_t, uint8_t)
    cpdef void reset(self)
    cpdef void clock(self)