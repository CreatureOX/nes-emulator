try:
    import pyaudio
    has_audio = False
except ImportError:
    has_audio = True

#### The APU ###########################################################################################################

cdef class APU2A03:
    """
    NES APU

    Sources:
        [1] https://wiki.nesdev.com/w/index.php/APU#Registers
        [2] https://wiki.nesdev.com/w/index.php/APU_Frame_Counter
        [3] https://wiki.nesdev.com/w/index.php/APU_Length_Counter

        [10] DMC interrupt flag reset: http://www.slack.net/~ant/nes-emu/apu_ref.txt
    """
    def __init__(self, master_volume=0.5):
        # self.interrupt_listener = interrupt_listener

        # Power-up and reset have the effect of writing $00 to apu status (0x4015), silencing all channels [1]
        self.frame_segment = 0
        self.cycles = 0
        self._reset_timer_in = -1
        self.samples_per_cycle = SAMPLE_RATE * 1. / CPU_FREQ_HZ
        self.samples_required = 0
        self.rate=SAMPLE_RATE
        self.irq_inhibit = True

        # the frame_interrupt_flag is connected to the CPU's IRQ line, so changes to this flag should be accompanied by
        # a change to the interrupt_listener's state
        self.frame_interrupt_flag = False

        # sound output buffer (this is a ring buffer, so these variables track the current start and end position)
        self._buffer_start = 0
        self._buffer_end = 1600  # give it some bonus sound to start with

        self.master_volume = master_volume
        self.mode = FOUR_STEP

        # sound production units
        self.triangle = APUTriangle()
        self.pulse1 = APUPulse(is_unit_1=True)
        self.pulse2 = APUPulse(is_unit_1=False)
        self.noise = APUNoise()
        self.dmc = APUDMC()

        for i in range(APU_BUFFER_LENGTH):
            self.output[i] = 0

    cpdef short[:] get_sound(self, int samples):
        """
        Generate samples of audio using the current audio settings.  The number of samples generated
        should be small (probably at most about 1/4 frame - 200 samples at 48kHz - to allow all effects to be
        reproduced, however, somewhat longer windows can probably be used; there are 800 samples in a frame at 48kHz).
        The absolute maximum that will be returned is 1s of audio.
        """
        cdef int i
        samples = min(samples, CHUNK_SIZE, self._buffer_end - self._buffer_start)
        for i in range(samples):
            self.buffer[i] = self.output[(self._buffer_start + i) & (APU_BUFFER_LENGTH - 1)]
        self._buffer_start += samples
        cdef short[:] data = <short[:samples]>self.buffer
        return data

    cdef void generate_sample(self):
        tri = self.triangle.generate_sample()
        p1 = self.pulse1.generate_sample()
        p2 = self.pulse2.generate_sample()
        noise = self.noise.generate_sample()
        dmc = self.dmc.generate_sample()

        v = self.mix(tri, p1, p2, noise, dmc)

        self.output[self._buffer_end & (APU_BUFFER_LENGTH - 1)] = v
        self._buffer_end += 1

    cpdef int buffer_remaining(self):
        return self._buffer_end - self._buffer_start

    cpdef void set_volume(self, float volume):
        self.master_volume = volume

    cpdef void set_rate(self, int rate):
        self.rate = rate
        self.samples_per_cycle = self.rate * 1. / CPU_FREQ_HZ

    cpdef int get_rate(self):
        return self.rate

    ######## interfacing with pyaudio #####################
    # keep all pyaudio code in this section

    def pyaudio_callback(self, in_data, frame_count, time_info, status):
        if self.buffer_remaining() > 0:
            data = self.get_sound(frame_count)
            return (data, pyaudio.paContinue)
        else:
            return (None, pyaudio.paAbort)

    ########################################################

    cdef int clock(self, int cpu_cycles):
        """
        Updates the APU by the given number of cpu cycles.  This updates the frame counter if
        necessary (every quarter or fifth video frame).  Timings from [2].
        """
        cdef int new_segment, cpu_cycles_per_loop, cycles
        cdef bint quarter_frame = False, force_ticks = False

        while cpu_cycles > 0:
            cycles = cpu_cycles if cpu_cycles < MAX_CPU_CYCLES_PER_LOOP else MAX_CPU_CYCLES_PER_LOOP
            self.cycles += cycles
            cpu_cycles -= MAX_CPU_CYCLES_PER_LOOP

            self.dmc.update_cycles(cycles)
            self.noise.update_cycles(cycles)

            self.samples_required += cycles * self.samples_per_cycle
            while self.samples_required > 1:
                self.generate_sample()
                self.samples_required -= 1

            if self._reset_timer_in >= 0:
                self._reset_timer_in -= cycles
                if self._reset_timer_in < 0:
                    self.cycles = 0
                    if self.mode == FIVE_STEP:
                        force_ticks = True
                    else: # four step mode
                        # If mode is FOUR_STEP, do *not* generate frame ticks
                        self.frame_segment = 0

            if self.cycles < 7457:
                new_segment = 0
            elif self.cycles < 14913:
                new_segment = 1
            elif self.cycles < 22371:
                new_segment = 2
            elif self.cycles <= 29829:   # this should be <, but logic is easier this way
                new_segment = 3
            else:
                if self.mode == FOUR_STEP:
                    new_segment = 0
                    self.cycles -= 29830
                    if not self.irq_inhibit:
                        # self.interrupt_listener.raise_irq()
                        self.frame_interrupt_flag = True
                else:  # five-step counter
                    if self.cycles <= 37281:
                        new_segment = 5
                    else:
                        new_segment = 0
                        self.cycles -= 37282

            if self.frame_segment != new_segment or force_ticks:
                if self.mode == FOUR_STEP or new_segment != 3:
                    # the quarter frame tick happens on the 0, 1, 2, 4 ticks in FIVE_STEP mode
                    # source: (https://wiki.nesdev.com/w/index.php/APU) section on Frame Counter
                    self.quarter_frame_tick()
                quarter_frame = True
                if new_segment == 0 or new_segment == 2 or force_ticks:
                    self.half_frame_tick()

            self.frame_segment = new_segment
        return quarter_frame

    cdef void quarter_frame_tick(self):
        """
        This is a tick that happens four times every (video) frame.  It updates the envelopes and the
        linear counter of the triange generator [2].
        """
        self.triangle.quarter_frame()
        self.pulse1.quarter_frame()
        self.pulse2.quarter_frame()
        self.noise.quarter_frame()

    cdef void half_frame_tick(self):
        """
        This is a tick that happens twice every (video) frame.  It updates the length counters and the
        sweep units [2].
        """
        self.triangle.half_frame()
        self.pulse1.half_frame()
        self.pulse2.half_frame()
        self.noise.half_frame()

    cdef unsigned char readByCPU(self, int address):
        """
        Read an APU register.  Actually the only one you can read is STATUS (0x4015).
        """
        cdef unsigned char value
        cdef bint dmc_active = False

        dmc_active = self.dmc.bytes_remaining > 0

        if address == 0x4015:
            value = (  (self.dmc.interrupt_flag << 7)
                     + (self.frame_interrupt_flag << 6)
                     + (dmc_active << 4)
                     + ((self.noise.length_ctr > 0) << 3)
                     + ((self.triangle.length_ctr > 0) << 2)
                     + ((self.pulse2.length_ctr > 0) << 1)
                     + (self.pulse1.length_ctr > 0)
                    )
            self.frame_interrupt_flag = False
            # "When $4015 is written to, the channels' length counter enable flags are set,
            # the DMC is possibly started or stopped, and the DMC's IRQ occurred flag is cleared." [10]
            self.dmc.interrupt_flag = False
            # self.interrupt_listener.reset_irq()
            return value

    cdef void writeByCPU(self, int address, unsigned char value):
        """
        Write to one of the APU registers.
        """
        cdef APUPulse pulse

        if address == 0x4015:
            self._set_status(value)
        elif address == 0x4017:
            self.mode = (value >> BIT_MODE) & 1
            self.irq_inhibit = (value >> BIT_IRQ_INHIBIT) & 1
            if self.irq_inhibit:
                self.frame_interrupt_flag = False
                # self.interrupt_listener.reset_irq()
            # side effects:  reset timer (in 3-4 cpu cycles' time, if mode set generate quarter and half frame signals)
            self._reset_timer_in = 3 + self.cycles % 2
        elif 0x4000 <= address <= 0x4007:
            # a pulse register
            # there are two pulse registers set by 0x4000-0x4003 and 0x4004-0x4007; select the correct one to update
            pulse = self.pulse1 if address < 0x4004 else self.pulse2
            pulse.write_register(address, value)
        elif 0x4008 <= address <= 0x400B:
            # a triangle register
            self.triangle.write_register(address, value)
        elif 0x400C <= address <= 0x400F:
            self.noise.write_register(address, value)
        elif 0x4010 <= address <= 0x4013:
            self.dmc.write_register(address, value)

    cdef void _set_status(self, unsigned char value):
        """
        Sets up the status register from a write to the status register 0x4015
        """
        self.triangle.set_enable((value >> BIT_ENABLE_TRIANGLE) & 1)
        self.pulse1.set_enable((value >> BIT_ENABLE_PULSE1) & 1) 
        self.pulse2.set_enable((value >> BIT_ENABLE_PULSE2) & 1)
        self.noise.set_enable((value >> BIT_ENABLE_NOISE) & 1)
        self.dmc.set_enable((value >> BIT_ENABLE_DMC) & 1)

    cdef int mix(self, int triangle, int pulse1, int pulse2, int noise, int dmc):
        """
        Mix the channels into signed 16-bit audio samples
        """
        cdef double pulse_out, tnd_out, sum_pulse, sum_tnd

        sum_pulse = pulse1 + pulse2
        sum_tnd = (triangle / 8227.) + (noise / 12241.) + (dmc / 22638.)
        pulse_out = 95.88 / ((8128. / sum_pulse) + 100.) if sum_pulse != 0 else 0
        tnd_out = 159.79 / (1. / sum_tnd + 100.) if sum_tnd != 0 else 0
        return int( ((pulse_out + tnd_out) ) * self.master_volume * SAMPLE_SCALE)
