from libc.stdint cimport uint8_t, uint16_t
import numpy as np
cimport numpy as np

from ppu cimport PPU2C02


cdef class PPU_DEBUG:
    def __init__(self, PPU2C02 ppu):
        self.ppu = ppu

    cpdef uint8_t[:,:,:] palette(self):
        _palette = np.zeros((4, 16, 3)).astype(np.uint8)
        for x in range(4):
            for y in range(16):
                _palette[x][y][:] = self.ppu.palettePanel[x * 16 + y]
        return _palette
