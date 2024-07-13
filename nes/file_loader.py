from nes.cart.cart import Cartridge
from nes.cart.impl.cart_ines import INesCart
from nes.cart.impl.cart_nes2 import Nes2Cart


class FileLoader:
    @staticmethod
    def load(filename: str) -> Cartridge:
        with open(filename, 'rb') as nes_file:
            nes_version = Cartridge.nes_version(nes_file.read(16))
        if nes_version == 2:
            return Nes2Cart(filename)
        if nes_version == 1:
            return INesCart(filename)
        return None
