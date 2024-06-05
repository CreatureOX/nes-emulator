from libc.stdint cimport uint8_t, uint16_t
import numpy as np
cimport numpy as np

from ppu cimport PPU2C02


cdef class PPU_DEBUG:
    cdef PPU2C02 ppu

    cpdef uint8_t[:,:,:] palette(self)
    cpdef uint8_t[:,:,:] pattern_table(self, uint8_t, uint8_t)
