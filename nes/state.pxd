from nes.cpu.cpu_state cimport CPUState
from nes.ppu.ppu_state cimport PPUState
from nes.cart.cart_state cimport CartridgeState
from nes.bus.bus cimport CPUBus


cdef class State:
    cdef CPUState cpu_state
    cdef PPUState ppu_state
    cdef CartridgeState cartridge_state

    cdef void load_to(self, CPUBus bus)
