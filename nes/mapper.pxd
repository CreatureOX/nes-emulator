from libc.stdint cimport uint8_t, uint16_t, uint32_t


cdef class Mapper:
    cdef str mapper_no

    cdef uint8_t PRG_banks
    cdef uint8_t CHR_banks

    cdef (bint, uint32_t, uint8_t) mapReadByCPU(self, uint16_t)
    cdef (bint, uint32_t) mapWriteByCPU(self, uint16_t, uint8_t)
    cdef (bint, uint32_t) mapReadByPPU(self, uint16_t)
    cdef (bint, uint32_t) mapWriteByPPU(self, uint16_t)

    cdef void reset(self)

    cdef uint8_t mirror(self)

    cdef bint IRQ_state(self)
    cdef void IRQ_clear(self)
    
    cdef void scanline(self)

cdef class MapperNROM(Mapper):
    pass

cdef class MapperMMC1(Mapper):
    cdef uint8_t CHR_bank_select_4_lo
    cdef uint8_t CHR_bank_select_4_hi
    cdef uint8_t CHR_bank_select_8

    cdef uint8_t PRG_bank_select_16_lo
    cdef uint8_t PRG_bank_select_16_hi
    cdef uint8_t PRG_bank_select_32

    cdef uint8_t load_register
    cdef uint8_t load_register_count
    cdef uint8_t control_register

    cdef uint8_t mirrormode

    cdef uint8_t[:] RAM_static

cdef class MapperUxROM(Mapper):
    cdef uint8_t PRG_bank_select_lo
    cdef uint8_t PRG_bank_select_hi

cdef class MapperINES003(Mapper):
    cdef uint8_t CHR_bank_select

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

cdef class MapperGxROM(Mapper):
    cdef uint8_t CHR_bank_select
    cdef uint8_t PRG_bank_select