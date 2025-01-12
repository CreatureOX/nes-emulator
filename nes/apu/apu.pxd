from nes.apu.registers cimport APUTriangle, APUPulse, APUNoise, APUDMC


cdef class APU2A03:
    """
    References:
        [1] https://wiki.nesdev.com/w/index.php/APU#Registers
        [2] https://wiki.nesdev.com/w/index.php/APU_Frame_Counter
    """
    cdef:
        #### master volume
        double master_volume

        #### apu state variables
        int cycles,rate  # cycle within the current frame (counted in CPU cycles NOT APU cycles as specified in [2]
        int frame_segment  # which segment of the frame the apu is in
        int _reset_timer_in  # after this number of cycles, reset the timer; ignored if < 0
        double samples_per_cycle  # number of output samples to generate per output cycle (will be <1)
        double samples_required  # number of samples currently required, once this gets over 1, generate a sample
        unsigned long long _buffer_start, _buffer_end  # start and end index of the sample ring buffer

        #### system interrupt listener

        #### buffers for up to 1s of data for each of the waveform generators
        short[65536] output # final output from the mixer; power of two sized to make ring buffer easier to implement
        short[10000] buffer

        #### status register
        bint mode, irq_inhibit, frame_interrupt_flag

        #### Sound units
        APUTriangle triangle
        APUPulse pulse1, pulse2
        APUNoise noise
        APUDMC dmc

        #### Frame counters
        int frame_counter

    ##########################################################################

    # register control functions
    cdef unsigned char readByCPU(self, int address)
    cdef void writeByCPU(self, int address, unsigned char value)
    cdef void _set_status(self, unsigned char value)

    # synchronous update functions
    cdef int clock(self, int cpu_cycles)
    cdef void quarter_frame_tick(self)
    cdef void half_frame_tick(self)

    # mixer
    cdef int mix(self, int tri, int p1, int p2, int noise, int dmc)

    # output
    cdef void generate_sample(self)
    cpdef short[:] get_sound(self, int samples)
    cpdef void set_volume(self, float volume)

    cpdef int buffer_remaining(self)

    cpdef void set_rate(self, int rate)
    cpdef int get_rate(self)

