from libc.stdint cimport uint8_t, uint16_t

from nes.mapper.mapping cimport CPUReadMapping, CPUWriteMapping, PPUReadMapping, PPUWriteMapping


cdef class Mapper:
    cdef str mapper_no

    cdef uint8_t PRG_banks
    cdef uint8_t CHR_banks

    cdef CPUReadMapping map_cpu_read(self, uint16_t addr)
    cdef CPUWriteMapping map_cpu_write(self, uint16_t, uint8_t)
    cdef PPUReadMapping map_ppu_read(self, uint16_t)
    cdef PPUWriteMapping map_ppu_write(self, uint16_t)

    cdef void reset(self)

    cdef uint8_t mirror(self)

    cdef bint irq_line(self)

    cdef void scanline(self)

    cdef void a12_notify(self, uint16_t addr)
