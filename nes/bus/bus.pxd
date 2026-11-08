from libc.stdint cimport uint8_t, uint16_t

from nes.bus.clock_divider cimport ClockDivider
from nes.cart.cart cimport Cartridge
from nes.cpu.cpu cimport CPU6502
from nes.ppu.ppu cimport PPU2C02
# from nes.apu.apu cimport APU2A03


cdef class CPUBus:
    cdef uint8_t[2048] ram
    cdef public uint8_t[2] controller
    cdef uint8_t[2] controller_state
    # The single time base. No chip owns a system-wide counter; the divider
    # publishes PPU-dot, CPU-cycle and phi2 edges as signals instead.
    cdef public ClockDivider divider

    cdef uint8_t dma_page
    cdef uint8_t dma_addr
    cdef uint8_t dma_data

    # CPU data-bus open bus: the last value driven onto the bus. Reads of
    # undriven space ($4000-$4014 write-only APU, $4018-$40FF unmapped,
    # unmapped PRG) return it; every real read/write refreshes it. See read().
    cdef uint8_t open_bus

    cdef bint dma_dummy
    cdef bint dma_transfer
    # Set when an OAM DMA read has happened and the matching $2004 write is
    # still owed. A DMC fetch that steals a get cycle leaves this clear, so
    # the next put cycle becomes an alignment cycle instead of a write --
    # this is what re-aligns OAM DMA after a DMC get (NESdev "DMA", "DMC DMA
    # during OAM DMA"). Replaces a bare get/put parity test because a stolen
    # get shifts the read/write pairing.
    cdef bint dma_write_pending

    # A DMC sample fetch that collided with an in-flight OAM DMA: the two DMA
    # units share one get/put cadence. oam_dmc_running stays set until the
    # fetch is performed, even past the end of the OAM DMA (the "last put"
    # case extends the sequence by 3 cycles). The two need_* flags are the
    # DMC DMA's halt and dummy cycles; OAM DMA cycles absorb them for free,
    # which is why a collision in the middle of the copy costs only 2 cycles.
    cdef bint oam_dmc_running
    cdef bint oam_dmc_need_halt
    cdef bint oam_dmc_need_dummy

    # DMC sample-byte DMA request (pushed by the APU) and its once-per-cycle
    # sample; public so the APU can push/clear the request through bus_ref.
    # dmc_dma_armed_prev holds the armed flag as it stood during the PREVIOUS
    # CPU cycle, so read() can tell a request armed this cycle (which belongs
    # to the instruction's own data access) from an older one (which belongs
    # to a deferred operand fetch) -- see CPUBus.read.
    cdef public bint dmc_dma_request
    cdef public bint dmc_dma_armed
    cdef bint dmc_dma_armed_prev

    # Set at the end of an OAM copy. The DMC sequence overlapping the tail of
    # the copy is still sharing OAM's get/put cadence, so the first standalone
    # DMC DMA afterwards must let the next get choose its fetch cycle instead
    # of assuming the reload's four-cycle length; that DMA clears the flag.
    # Ref: NESdev "DMA" (DMC DMA during OAM DMA); dbhq-uk/6502 NesBus.RunDma.
    cdef bint dmc_oam_tail_pending

    cdef public CPU6502 cpu 
    cdef public PPU2C02 ppu
    cdef public object apu
    cdef Cartridge cartridge

    cdef void _dma_halt_cycle(self, uint16_t, bint)
    cdef void _run_dmc_dma(self, uint16_t)

    cpdef uint8_t read(self, uint16_t, bint)
    cpdef void write(self, uint16_t, uint8_t)
    cpdef void reset(self)
    cpdef void power_up(self)
    cpdef void clock(self)
    cpdef void run_frame(self)