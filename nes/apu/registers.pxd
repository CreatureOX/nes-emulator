cdef class APUEnvelope:
    cdef:
        bint start_flag, loop_flag
        unsigned int decay_level, divider, volume

    cdef void update(self)
    cdef void restart(self)

cdef class APUUnit:
    cdef:
        bint enable, ctr_halt
        int length_ctr
        short[48000] output

    cdef void update_length_ctr(self)
    cdef void set_enable(self, bint value)
    cdef void set_length_ctr(self, int value)

cdef class APUTriangle(APUUnit):
    cdef:
        bint linear_reload_flag
        int linear_reload_value, period, linear_ctr
        double phase

    cdef void write_register(self, int address, unsigned char value)
    cdef void quarter_frame(self)
    cdef void half_frame(self)
    cdef int generate_sample(self)

cdef class APUPulse(APUUnit):
    cdef:
        bint constant_volume, is_unit_1
        int period, adjusted_period, duty
        double phase
        APUEnvelope env
        bint sweep_enable, sweep_negate, sweep_reload
        int sweep_period, sweep_shift, sweep_divider

        int[4][8] duty_waveform # duty cycle sequences

    cdef void write_register(self, int address, unsigned char value)
    cdef void sweep_update(self)
    cdef void quarter_frame(self)
    cdef void half_frame(self)
    cdef int generate_sample(self)

cdef class APUNoise(APUUnit):
    cdef:
        bint constant_volume, mode
        int period, feedback, timer
        #double shift_ctr
        APUEnvelope env

        unsigned int[16] timer_table # noise timer periods

    cdef void write_register(self, int address, unsigned char value)
    cdef void update_cycles(self, int cycles)
    cdef void quarter_frame(self)
    cdef void half_frame(self)
    cdef int generate_sample(self)

cdef class APUDMC(APUUnit):
    """
    The DMC unit is pretty different to the other APU units
    """
    cdef:
        bint irq_enable, loop_flag, silence, interrupt_flag
        unsigned int sample_address, sample_length, address, bytes_remaining
        unsigned int rate, timer
        int output_level, bits_remaining
        unsigned char sample

        unsigned int[16] rate_table # sample consumption rates for the dmc

    cdef void write_register(self, int address, unsigned char value)
    cdef void update_cycles(self, int cycles)
    cdef void read_advance(self)
    cdef int generate_sample(self)
