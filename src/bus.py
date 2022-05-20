from numpy import uint16, uint8, void

class Bus:
    
    def __init__(self) -> None:
        self.ram = [0x00] * 64 * 1024

    def read(self, addr: uint16, readOnly: bool) -> uint8:
        if 0x0000 <= addr <= 0xFFFF:
            return self.ram[addr]
        return 0x00

    def write(self, addr: uint16, data: uint8) -> void:
        if 0x0000 <= addr <= 0xFFFF:
            self.ram[addr] = data
    