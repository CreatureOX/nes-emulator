from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class MapperMMC4(Mapper):
    """MMC4 shares MMC2's CHR latches but uses 16 KiB PRG banks."""
    cdef uint8_t prg_bank
    cdef uint8_t chr_bank_fd_lo
    cdef uint8_t chr_bank_fe_lo
    cdef uint8_t chr_bank_fd_hi
    cdef uint8_t chr_bank_fe_hi
    cdef uint8_t latch_lo
    cdef uint8_t latch_hi
    cdef uint8_t pending_lo
    cdef uint8_t pending_hi
    cdef uint8_t mirroring
    cdef uint8_t[:] RAM_static

    cdef object sram(self)
