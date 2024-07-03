cdef class CartridgeDebugger:
    def __init__(self, cartridge: Cartridge) -> None:
        self.cartridge = cartridge

    cpdef dict view(self):
        return {
            "PRG ROM": str(self.cartridge.PRG_ROM_bytes // 1024) + "KB",
            "PRG RAM": str(self.cartridge.PRG_RAM_bytes // 1024) + "KB",
            "CHR ROM": str(self.cartridge.CHR_ROM_bytes // 1024) + "KB",
            "CHR RAM": str(self.cartridge.CHR_RAM_bytes // 1024) + "KB",
            "mapper no": self.cartridge.mapper_no(),
        }