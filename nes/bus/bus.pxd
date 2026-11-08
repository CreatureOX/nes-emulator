from libc.stdint cimport uint8_t, uint16_t

from nes.bus.clock_divider cimport ClockDivider
from nes.bus.dma_controller cimport DmaController
from nes.bus.joypad cimport Joypad
from nes.cart.cart cimport Cartridge
from nes.cpu.cpu cimport CPU6502
from nes.ppu.ppu cimport PPU2C02
# from nes.apu.apu cimport APU2A03


cdef class CPUBus:
    cdef uint8_t[2048] ram
    # Controller ports are first-class devices; the bus holds no button or
    # shift-register state of its own.
    cdef public Joypad joy1
    cdef public Joypad joy2
    # The single time base. No chip owns a system-wide counter; the divider
    # publishes PPU-dot, CPU-cycle and phi2 edges as signals instead.
    cdef public ClockDivider divider

    # APU-driven DMC request signal line. DmaController latches it on each
    # CPU-cycle edge; the bus routes it but never interprets it.
    cdef public bint dmc_dma_request

    # CPU data-bus open bus: the last value driven onto the bus. Reads of
    # undriven space ($4000-$4014 write-only APU, $4018-$40FF unmapped,
    # unmapped PRG) return it; every real read/write refreshes it. See read().
    cdef uint8_t open_bus

    cdef public DmaController dma
    cdef public CPU6502 cpu
    cdef public PPU2C02 ppu
    cdef public object apu
    cdef Cartridge cartridge

    cdef void propagate_lines(self, long long dot)

    cpdef uint8_t read(self, uint16_t, bint)
    cpdef void write(self, uint16_t, uint8_t)
    cpdef void reset(self)
    cpdef void power_up(self)
    cpdef void clock(self)
    cpdef void run_frame(self)
