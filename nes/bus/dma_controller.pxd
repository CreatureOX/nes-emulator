from libc.stdint cimport uint8_t, uint16_t, uint64_t

from nes.bus.bus cimport CPUBus


cdef class DMAController:
    cdef CPUBus bus

    cdef uint8_t dma_page
    cdef uint8_t dma_addr
    cdef uint8_t dma_data
    cdef bint dma_dummy
    cdef bint dma_transfer
    cdef bint dma_write_pending
    cdef bint oam_dmc_running
    cdef bint oam_dmc_need_halt
    cdef bint oam_dmc_need_dummy

    # Latched copy of the APU's request line and its age in CPU cycles.
    cdef bint request_armed
    cdef int armed_cycles
    cdef bint dmc_oam_tail_pending

    cpdef void reset(self)
    cdef void on_cpu_cycle(self)
    cdef bint may_halt_on_read(self, bint operand_fetch)
    cdef bint active(self)
    cdef void start_oam(self, uint8_t page)
    cdef void tick(self, uint64_t cpu_cycle)
    cdef void run_dmc_dma(self, uint16_t cpu_read_addr)
    cdef void halt_cycle(self, uint16_t dummy_addr, bint do_dummy_read)
