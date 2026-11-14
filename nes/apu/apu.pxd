from libc.stdint cimport uint8_t, uint16_t

cimport numpy as np

from nes.bus.bus cimport CPUBus
from nes.mapper.mapper cimport Mapper


cdef class APU2A03:
    cdef public int sample_rate
    cdef public double cpu_rate
    cdef double cycles_per_sample
    cdef double sample_accum
    cdef object _samples

    # Pulse 1 / pulse 2: duty, envelope, timer and sweep state.
    cdef int pulse_duty[2]
    cdef int pulse_volume[2]
    cdef int pulse_constant[2]
    cdef int pulse_env_period[2]
    cdef int pulse_env_divider[2]
    cdef int pulse_env_decay[2]
    cdef int pulse_env_start[2]
    cdef int pulse_timer[2]
    cdef int pulse_period[2]
    cdef int pulse_step[2]
    cdef int pulse_sweep_enabled[2]
    cdef int pulse_sweep_period[2]
    cdef int pulse_sweep_negate[2]
    cdef int pulse_sweep_shift[2]
    cdef int pulse_sweep_divider[2]
    cdef int pulse_sweep_reload[2]
    cdef int pulse_sweep_mute[2]

    # Length counters exist for all four main channels even though only the
    # pulse channels are synthesised: $4015 reports them and the frame
    # sequencer clocks them. A write stores a pending reload plus a snapshot
    # of the counter; the frame step applies it one cycle later.
    cdef int channel_enabled[4]
    cdef int length_counter[4]
    cdef int length_halt[4]
    cdef int length_reload_pending[4]
    cdef int length_reload_prev[4]
    cdef int length_new_halt[4]

    # Frame sequencer driven from $4017 (4-step / 5-step mode).
    cdef int frame_mode
    cdef int frame_irq_inhibit
    cdef int frame_irq_flag
    cdef int frame_cycle
    cdef int frame_reset_delay
    cdef int cycle_parity

    # 1 = load (first fetch after $4015), 2 = reload (buffer emptied).
    cdef int dmc_request_kind

    # DMC reader and output unit. The bus services the sample-byte DMA, so the
    # APU holds the bus as a signal line rather than reading CPU memory itself.
    cdef int dmc_irq_enable
    cdef int dmc_loop
    cdef int dmc_rate
    cdef int dmc_addr
    cdef int dmc_addr_load
    cdef int dmc_len
    cdef int dmc_len_load
    cdef int dmc_buffer
    cdef int dmc_shift
    cdef int dmc_bits
    cdef int dmc_timer
    cdef int dmc_period
    cdef int dmc_silence
    cdef int dmc_transfer_delay
    cdef int dmc_disable_delay
    cdef int dmc_irq_flag
    cdef int dmc_output
    cdef CPUBus bus
    cdef Mapper expansion_mapper

    # Audio filter chain state.
    cdef double last_output
    cdef double hp1_last_input
    cdef double hp1_last_output
    cdef double hp2_last_input
    cdef double hp2_last_output
    cdef double lp_last_output
    cdef double hp1_coef
    cdef double hp2_coef
    cdef double lp_coef

    cpdef void reset(self)
    cpdef void power_up(self)
    cpdef uint8_t read(self, int addr)
    cpdef void write(self, int addr, int data)
    cdef void _load_length(self, int channel, int data)
    cdef void _write_frame_counter(self, int data)
    cdef bint _pulse_active(self, int channel)
    cdef void _clock_frame_counter(self)
    cdef void _apply_pending_length(self)
    cdef void _quarter_frame(self)
    cdef void _half_frame(self)
    cdef void _clock_dmc(self)
    cpdef uint16_t dmc_read_addr(self)
    cpdef void dmc_deliver(self, uint8_t byte)
    cdef void init_dmc_sample(self)
    cpdef int dmc_dma_request_kind(self)
    cdef void start_dmc_transfer(self, int kind)
    cdef void arm_dmc_sample(self)
    cpdef bint irq_level(self)
    cpdef void clock(self, int cycles)
    cpdef np.ndarray drain_samples(self)
