import cython
import numpy as np
cimport numpy as np


@cython.auto_pickle(True)
cdef class CartridgeState:
    def __init__(self, Cartridge cartridge) -> None:
        self.PRG_ROM_bytes = cartridge.PRG_ROM_bytes
        self.PRG_RAM_bytes = cartridge.PRG_RAM_bytes
        self.CHR_ROM_bytes = cartridge.CHR_ROM_bytes
        self.CHR_RAM_bytes = cartridge.CHR_RAM_bytes
        self.PRG_ROM_data = np.array(cartridge.PRG_ROM_data, dtype = np.uint8)
        if self.PRG_RAM_bytes > 0:
            self.PRG_RAM_data = np.array(cartridge.PRG_RAM_data, dtype = np.uint8)
        else:
            self.PRG_RAM_data = np.zeros(self.PRG_RAM_bytes, dtype = np.uint8)
        if self.CHR_ROM_bytes > 0:
            self.CHR_ROM_data = np.array(cartridge.CHR_ROM_data, dtype = np.uint8)
        else:
            self.CHR_ROM_data = np.zeros(self.CHR_ROM_bytes, dtype = np.uint8)
        if self.CHR_RAM_bytes > 0:
            self.CHR_RAM_data = np.array(cartridge.CHR_RAM_data, dtype = np.uint8)
        else:
            self.CHR_RAM_data = np.zeros(self.CHR_RAM_bytes, dtype = np.uint8)

    cdef void load_to(self, Cartridge cartridge):
        cartridge.PRG_ROM_bytes = self.PRG_ROM_bytes
        cartridge.PRG_RAM_bytes = self.PRG_RAM_bytes
        cartridge.CHR_ROM_bytes = self.CHR_ROM_bytes
        cartridge.CHR_RAM_bytes = self.CHR_RAM_bytes
        cartridge.PRG_ROM_data = self.PRG_ROM_data
        cartridge.PRG_RAM_data = self.PRG_RAM_data
        cartridge.CHR_ROM_data = self.CHR_ROM_data
        cartridge.CHR_RAM_data = self.CHR_RAM_data
    