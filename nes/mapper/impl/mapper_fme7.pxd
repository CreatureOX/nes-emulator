from libc.stdint cimport uint8_t, uint16_t

from nes.mapper.mapper cimport Mapper


cdef class MapperFME7(Mapper):
    """Sunsoft FME-7: command/parameter registers, 1 KiB CHR, cycle IRQ."""
    cdef uint8_t command
    cdef uint8_t[:] reg
    cdef uint8_t mirroring

    cdef uint16_t irq_counter
    cdef bint irq_enabled
    cdef bint irq_counter_enabled
    cdef bint irq_pending
    cdef uint8_t[:] RAM_static

    cdef object sram(self)
