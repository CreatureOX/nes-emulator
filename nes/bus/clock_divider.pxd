from libc.stdint cimport uint32_t, uint64_t


cdef class ClockDivider:
    cdef public uint64_t dot
    cdef public uint64_t cpu_cycle
    cdef public bint on_cpu_cycle
    cdef public bint on_phi2
    cdef readonly uint32_t ppu_divider
    cdef readonly uint32_t cpu_divider
    cdef uint32_t dots_per_cpu_cycle
    cdef uint32_t cpu_tick_dot
    cdef uint32_t phi2_dot
    cdef uint32_t phase

    cdef void _update_edges(self)
    cdef void reset(self)
    cdef void advance(self)
