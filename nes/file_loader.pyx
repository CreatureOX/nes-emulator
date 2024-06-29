from cart_ines cimport INesCart
from cart_nes2 cimport Nes2Cart


cdef class FileLoader:
    @staticmethod
    def load(filename: str) -> Cartridge:
        cdef bint is_nes2_format

        with open(filename, 'rb') as nes_file:
            is_nes2_format = Cartridge.is_nes2(nes_file.read(16))
        if is_nes2_format:
            return Nes2Cart(filename)
        else:
            return INesCart(filename)
