from libc.stdint cimport uint8_t


cdef class Header:
    cdef str name
    cdef uint8_t prg_rom_chunks
    cdef uint8_t chr_rom_chunks
    cdef uint8_t mapper1
    cdef uint8_t mapper2
    cdef uint8_t prg_ram_size
    cdef uint8_t tv_system1
    cdef uint8_t tv_system2
    cdef str unused
