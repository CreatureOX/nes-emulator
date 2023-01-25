from cartridge import Cartridge
from bus import CPUBus


class Console:
    bus: CPUBus

    def __init__(self, filename: str) -> None:
        cart = Cartridge(filename)
        self.bus = CPUBus(cart)

    def reset(self) -> None:
        self.bus.reset()

    def clock(self) -> None:
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        while True:
            self.bus.clock()
            if not self.bus.cpu.complete():
                break

    def frame(self) -> None:
        while True:
            self.bus.clock()
            if self.bus.ppu.frame_complete:
                break
        while True:
            self.bus.clock()
            if self.bus.cpu.complete():
                break
        self.bus.ppu.frame_complete = False

    def run(self):
        while True:
            self.bus.clock()
            if self.bus.ppu.frame_complete:
                break
        self.bus.ppu.frame_complete = False                
