from libc.stdint cimport uint8_t, uint16_t
import numpy as np
cimport numpy as np


cdef class PPUDebugger:
    """
    Debug utilities for PPU visualization.
    
    Provides methods to extract pattern tables and palette data for debugging
    and visualization of NES graphics.
    """
    def __init__(self, PPU2C02 ppu):
        self.ppu = ppu
        self._pattern_table = [np.zeros((128,128,3)).astype(np.uint8),np.zeros((128,128,3)).astype(np.uint8)]

    cpdef uint8_t[:,:,:] palette(self):
        """Get the palette data as a 4x16x3 RGB array."""
        _palette = np.zeros((4, 16, 3)).astype(np.uint8)
        for x in range(4):
            for y in range(16):
                _palette[x][y][:] = self.ppu.palette_panel[x * 16 + y]
        return _palette

    cpdef uint8_t[:,:,:] pattern_table(self, uint8_t i, uint8_t palette):
        """
        Render a pattern table (128x128 pixels) using specified palette.
        
        Args:
            i: Pattern table index (0 or 1)
            palette: Palette number to use for rendering
        """
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