from libc.stdint cimport uint8_t, uint16_t
import numpy as np
cimport numpy as np

from nes.ppu.ppu cimport PPU2C02


cdef class PPUDebugger:
    def __init__(self, PPU2C02 ppu):
        self.ppu = ppu
        self._pattern_table = [np.zeros((128,128,3)).astype(np.uint8),np.zeros((128,128,3)).astype(np.uint8)]

    cpdef uint8_t[:,:,:] palette(self):
        _palette = np.zeros((4, 16, 3)).astype(np.uint8)
        for x in range(4):
            for y in range(16):
                _palette[x][y][:] = self.ppu.palette_panel[x * 16 + y]
        return _palette

    cpdef uint8_t[:,:,:] pattern_table(self, uint8_t i, uint8_t palette):
        cdef uint8_t tileY, tileX
        cdef uint8_t tile_lsb, tile_msb
        cdef uint8_t row, col
        cdef uint8_t pixel
        cdef uint16_t x, y, offset

        for tileY in range(0,16):
            for tileX in range(0,16):
                offset = tileY * 256 + tileX * 16
                for row in range(0,8):
                    tile_lsb = self.ppu.readByPPU(i * 0x1000 + offset + row + 0x0000)
                    tile_msb = self.ppu.readByPPU(i * 0x1000 + offset + row + 0x0008)
                    for col in range(0,8):
                        pixel = (tile_msb & 0x01) << 1 | (tile_lsb & 0x01)
                        tile_lsb, tile_msb = tile_lsb >> 1, tile_msb >> 1
                        y, x = tileY * 8 + row, tileX * 8 + (7 - col)
                        self._pattern_table[i][y, x] = self.ppu.fetch_color(palette, pixel)
        
        return self._pattern_table[i]