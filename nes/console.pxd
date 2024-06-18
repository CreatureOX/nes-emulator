from libc.stdint cimport uint8_t, uint16_t

from cartridge cimport Cartridge
from bus cimport CPUBus

from ppu_debug cimport PPUDebugger


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
    
    cdef PPUDebugger ppu_debugger

    cpdef void power_up(self)
    cpdef void reset(self)
    cpdef void clock(self)
    cpdef void frame(self)
    cpdef void run(self)
    cpdef void control(self, list)

    cpdef dict cpu_status_info(self)
    cpdef dict cpu_registers_info(self)
    cpdef str cpu_ram(self,uint16_t,uint16_t)
    cpdef dict cpu_code_readable(self,uint16_t,uint16_t)
    cpdef uint16_t cpu_pc(self)

    cpdef uint8_t[:,:,:] ppu_pattern_table(self, uint8_t)
    cpdef uint8_t[:,:,:] ppu_palette(self)
    