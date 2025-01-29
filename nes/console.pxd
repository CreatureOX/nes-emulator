from libc.stdint cimport uint8_t

from nes.bus.bus cimport CPUBus

from nes.cpu.cpu_debug cimport CPUDebugger
from nes.ppu.ppu_debug cimport PPUDebugger
from nes.cart.cart_debug cimport CartridgeDebugger


cdef uint8_t K_x
cdef uint8_t K_z
cdef uint8_t K_a
cdef uint8_t K_s
cdef uint8_t K_UP
cdef uint8_t K_DOWN
cdef uint8_t K_LEFT
cdef uint8_t K_RIGHT

cdef class Console:
    cdef public CPUBus bus
    
    cdef public CPUDebugger cpu_debugger
    cdef public PPUDebugger ppu_debugger
    cdef public CartridgeDebugger cartridge_debugger

    cpdef void power_up(self)
    cpdef void reset(self)
    cpdef void clock(self)
    cpdef void frame(self)
    cpdef void run(self)
    cpdef void control(self, list)

    cpdef void save_state(self, str)
    cpdef void load_state(self, str)
