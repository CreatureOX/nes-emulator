from libc.stdint cimport uint8_t

from nes.mapper.mapper cimport Mapper


cdef class MapperMMC2(Mapper):
    """MMC2 keeps five bank latches, two CHR page latches and a mirror bit."""
    cdef uint8_t prg_bank
    cdef uint8_t chr_bank_fd_lo
    cdef uint8_t chr_bank_fe_lo
    cdef uint8_t chr_bank_fd_hi
    cdef uint8_t chr_bank_fe_hi
    cdef uint8_t latch_lo
    cdef uint8_t latch_hi
    # 0xFF means no pending update; 0/1 select the $FD/$FE bank.
    cdef uint8_t pending_lo
    cdef uint8_t pending_hi
    cdef uint8_t mirroring
