from apu_registers cimport APUTriangle, APUPulse, APUNoise, APUDMC


cdef enum:
    # sound synthesis constants
    SAMPLE_RATE = 48000     # 48kHz sample rate
    SAMPLE_SCALE = 65536    # 16 bit samples

    CPU_FREQ_HZ = 1789773   # https://wiki.nesdev.com/w/index.php/Cycle_reference_chart#Clock_rates
    MAX_CPU_CYCLES_PER_LOOP = 24  # if the cpu has done more than this many cycles, complete them in loops

    # counter modes
    FOUR_STEP = 0
    FIVE_STEP = 1

    # Bits in the status register during write
    BIT_ENABLE_DMC = 4
    BIT_ENABLE_NOISE = 3
    BIT_ENABLE_TRIANGLE = 2
    BIT_ENABLE_PULSE2 = 1
    BIT_ENABLE_PULSE1 = 0

    # Bits in the frame counter register
    BIT_MODE = 7
    BIT_IRQ_INHIBIT = 6

    # buffer length of the APU's output buffer; must be a power of 2
    APU_BUFFER_LENGTH = 65536
    CHUNK_SIZE = 10000

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
        short output[APU_BUFFER_LENGTH]   # final output from the mixer; power of two sized to make ring buffer easier to implement
        short buffer[CHUNK_SIZE]

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

