from libc.stdint cimport uint8_t, uint16_t, uint32_t

from nes.mapper.mapper cimport Mapper


cdef class Header:
    cdef bytes trainer

cdef class CartridgeCPUPort:
    cdef Cartridge cart
    cdef (bint, uint8_t) read(self, uint16_t)
    cdef bint write(self, uint16_t, uint8_t)

cdef class CartridgePPUPort:
    cdef Cartridge cart
    cdef (bint, uint8_t) read(self, uint16_t, uint8_t)
    cdef bint write(self, uint16_t, uint8_t)

cdef class Cartridge:
    cdef uint32_t PRG_ROM_bytes
    cdef uint32_t PRG_RAM_bytes
    cdef uint32_t CHR_ROM_bytes
    cdef uint32_t CHR_RAM_bytes

    cdef uint8_t[:] PRG_ROM_data
    cdef uint8_t[:] PRG_RAM_data
    cdef uint8_t[:] CHR_ROM_data
    cdef uint8_t[:] CHR_RAM_data
    cdef uint8_t[:] wram          # WRAM window $6000-$7FFF (blargg result RAM)

    cdef Mapper mapper
    cdef CartridgeCPUPort cpu
    cdef CartridgePPUPort ppu
    cdef uint8_t mirror_mode

    cdef void reset(self)
    cdef uint16_t mapper_no(self)
