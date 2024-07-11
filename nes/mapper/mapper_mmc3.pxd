from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapper cimport Mapper


cdef class MapperMMC3(Mapper):
    cdef uint8_t target_register
    cdef bint PRG_bank_mode
    cdef bint CHR_inversion
    cdef uint8_t mirrormode

    cdef uint32_t[8] register
    cdef uint32_t[8] CHR_bank
    cdef uint32_t[4] PRG_bank

    cdef bint IRQ_active
    cdef bint IRQ_enable
    cdef bint IRQ_update
    cdef uint16_t IRQ_counter
    cdef uint16_t IRQ_reload

    cdef uint8_t[:] RAM_static
