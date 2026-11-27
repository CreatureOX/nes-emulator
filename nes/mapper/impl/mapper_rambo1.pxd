from libc.stdint cimport uint8_t, uint16_t

from nes.mapper.mapper cimport Mapper


cdef class MapperRambo1(Mapper):
    """Tengen RAMBO-1: MMC3-like banking with 1 KiB CHR mode and dual IRQ."""
    cdef uint8_t bank_select
    cdef uint8_t[:] reg
    cdef uint8_t mirroring

    cdef uint8_t irq_latch
    cdef uint8_t irq_counter
    cdef bint irq_enabled
    cdef bint irq_pending
    cdef bint irq_reload_request
    cdef bint irq_cycle_mode
    cdef uint8_t prescaler
    cdef uint8_t a12_prev

    cdef uint8_t _chr_bank(self, uint16_t addr)
    cdef void _clock_irq(self)
