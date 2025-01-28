from libc.stdint cimport uint32_t
import numpy as np
cimport numpy as np

from nes.cart.cart cimport Cartridge


cdef class CartridgeState:
    cdef uint32_t PRG_ROM_bytes
    cdef uint32_t PRG_RAM_bytes
    cdef uint32_t CHR_ROM_bytes
    cdef uint32_t CHR_RAM_bytes

    cdef np.ndarray PRG_ROM_data
    cdef np.ndarray PRG_RAM_data
    cdef np.ndarray CHR_ROM_data
    cdef np.ndarray CHR_RAM_data

    cdef void load_to(self, Cartridge cartridge)
