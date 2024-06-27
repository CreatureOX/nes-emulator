from libc.stdint cimport uint8_t, uint16_t, uint32_t

from mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class Mapper:
    cdef str mapper_no

    cdef uint8_t PRG_banks
    cdef uint8_t CHR_banks

    cdef CPUReadMapping mapReadByCPU(self, uint16_t addr)
    cdef CPUWriteMapping mapWriteByCPU(self, uint16_t, uint8_t)
    cdef PPUReadMapping mapReadByPPU(self, uint16_t)
    cdef PPUWriteMapping mapWriteByPPU(self, uint16_t)

    cdef void reset(self)

    cdef uint8_t mirror(self)

    cdef bint IRQ_state(self)
    cdef void IRQ_clear(self)
    
    cdef void scanline(self)
