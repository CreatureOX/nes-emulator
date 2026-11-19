from nes.cpu.cpu_state cimport CPUState
from nes.ppu.ppu_state cimport PPUState
from nes.cart.cart_state cimport CartridgeState
from nes.bus.bus cimport CPUBus
from nes.apu.apu cimport APU2A03
from nes.bus.clock_divider cimport ClockDivider

cdef object _freeze(object)
cdef object _thaw(object)
cdef object _mapper_snapshot(CPUBus)
cdef void _mapper_restore(CPUBus, object)
cdef object _apu_snapshot(CPUBus)
cdef void _apu_restore(CPUBus, object)
cdef object _bus_snapshot(CPUBus)
cdef void _bus_restore(CPUBus, object)


cdef class State:
    cdef CPUState cpu_state
    cdef PPUState ppu_state
    cdef CartridgeState cartridge_state
    cdef object mapper_snapshot
    cdef object apu_snapshot
    cdef object bus_snapshot

    cdef void load_to(self, CPUBus bus)