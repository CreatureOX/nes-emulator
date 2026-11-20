from libc.stdint cimport uint32_t, uint64_t


cdef class ClockDivider:
    cdef public uint64_t dot
    cdef public uint64_t cpu_cycle
    cdef public bint cpu_tick_edge
    cdef public bint phi2_edge
    cdef readonly uint32_t ppu_divider
    cdef readonly uint32_t cpu_divider
    cdef readonly uint32_t cycle_dots
    cdef readonly uint32_t tick_mask
    cdef readonly uint32_t phi2_mask
    cdef uint32_t phase

    cdef void _update_edges(self)
    cdef void reset(self)
    cdef void advance(self)
