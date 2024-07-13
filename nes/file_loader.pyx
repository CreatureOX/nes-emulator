from nes.cart.impl.cart_ines cimport INesCart
from nes.cart.impl.cart_nes2 cimport Nes2Cart


cdef class FileLoader:
    @staticmethod
    def load(filename: str) -> Cartridge:
        cdef int nes_version

        with open(filename, 'rb') as nes_file:
            nes_version = Cartridge.nes_version(nes_file.read(16))
        if nes_version == 2:
            return Nes2Cart(filename)
        if nes_version == 1:
            return INesCart(filename)
        return None
