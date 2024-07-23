from nes.console cimport Console
import cython


@cython.auto_pickle(True)
cdef class State:
    def __init__(self, Console console) -> None:
        self.cpu_state = CPUState(console.bus.cpu)
        # self.ppu_state = PPUState(console.bus.ppu)
