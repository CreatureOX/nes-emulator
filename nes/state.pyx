import cython


@cython.auto_pickle(True)
cdef class State:
    """
    Serializable state container for save/load functionality.
    
    Bundles CPU, PPU, and cartridge state into a single object
    that can be pickled for persistence.
    """
    def __init__(self, CPUBus bus) -> None:
        self.cpu_state = CPUState(bus.cpu)
        self.ppu_state = PPUState(bus.ppu)
        self.cartridge_state = CartridgeState(bus.cartridge)

    cdef void load_to(self, CPUBus bus):
        """Restore saved state to the console components."""
        self.cpu_state.load_to(bus.cpu)
        self.ppu_state.load_to(bus.ppu)
        self.cartridge_state.load_to(bus.cartridge)