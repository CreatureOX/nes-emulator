cdef enum:
    # sound synthesis constants
    SAMPLE_RATE = 48000     # 48kHz sample rate
    CPU_FREQ_HZ = 1789773   # https://wiki.nesdev.com/w/index.php/Cycle_reference_chart#Clock_rates

cdef class APUEnvelope:
    """
    Volume envelope unit used in pulse and noise APU units
    Reference:
        [6] envelope:  https://wiki.nesdev.com/w/index.php/APU_Envelope
    """
    def __init__(self):
        self.start_flag = False
        self.loop_flag = False
        self.decay_level = 0
        self.divider = 0
        self.volume = 0

    cdef void restart(self):
        self.start_flag = False
        self.decay_level = 15
        self.divider = self.volume

    cdef void update(self):
        if not self.start_flag:   # if start flag is clear
            # clock divider
            if self.divider == 0:
                # When divider is clocked while at 0, it is loaded with volume and clocks the decay level counter [6]
                self.divider = self.volume
                # clock decay counter:
                #   if the counter is non-zero, it is decremented, otherwise if the loop flag is set, the decay level
                #   counter is loaded with 15. [6]
                if self.decay_level > 0:
                    self.decay_level -=1
                elif self.loop_flag:
                    self.decay_level = 15
            else:
                # clock divider (is this right?)
                self.divider -= 1
        else:
            self.restart()

#### Length Table and other constant arrays ############################################################################

cdef int[32] LENGTH_TABLE = [ 10, 254, 20,  2, 40,  4, 80,  6, 160,  8, 60, 10, 14, 12, 26, 14,
                              12,  16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30 ]
                              
cdef class APUUnit:
    """
    Base class for the APU's sound generation units providing some basic common functionality
    """

    def __init__(self):
        self.enable = False
        self.length_ctr = 0
        self.ctr_halt = False
        for i in range(SAMPLE_RATE):
            self.output[i] = 0

    cdef void update_length_ctr(self):
        if not self.ctr_halt:
            self.length_ctr = (self.length_ctr - 1) if self.length_ctr > 0 else 0

    cdef void set_enable(self, bint value):
        self.enable = value
        if not self.enable:
            self.length_ctr = 0

    cdef void set_length_ctr(self, int value):
        if self.enable:
            self.length_ctr = LENGTH_TABLE[value & 0b11111]

#### Sound generation units ############################################################################################

cdef class APUTriangle(APUUnit):
    """
    APU unit for generating triangle waveform
    Reference:
        [4] triangle:  https://wiki.nesdev.com/w/index.php/APU_Triangle
    """
    def __init__(self):
        super().__init__()
        self.period = 0
        self.phase = 0

        self.linear_reload_flag = False
        self.linear_reload_value = 0
        self.linear_ctr = 0

    cdef void write_register(self, int address, unsigned char value):
        """
        Set properties of the triangle waveform generator from a write to its registers.
        """
        if address == 0x4008:
            self.ctr_halt = (value >> 7) & 1
            # don't set the counter directly, just set the reload value for now
            self.linear_reload_value = value & 0b01111111
        elif address == 0x400A:
            self.period = (self.period & 0xFF00) + value
        elif address == 0x400B:
            self.period = (self.period & 0xFF) + ((value & 0b00000111) << 8)
            self.set_length_ctr(value >> 3)
            self.linear_reload_flag = True

    cdef void quarter_frame(self):

        # Update triangle linear counter.  This is a bit complicated and occurs as follows [4]:
        # if counter reload flag is set:
        #     linear counter <-- counter reload value
        # elif linear counter > 0:
        #     decrement linear counter
        # if control flag clear:
        #     counter reload flag cleared
        if self.linear_reload_flag:
            self.linear_ctr = self.linear_reload_value
        elif self.linear_ctr > 0:
             self.linear_ctr -= 1

        if not self.ctr_halt:  # this is also the control flag
            self.linear_reload_flag = False

    cdef void half_frame(self):
        self.update_length_ctr()

    cdef int generate_sample(self):
        """
        Generate a single sample of the triangle wave and advance the phase appropriately
        """
        cdef double freq_hz
        cdef int v

        # frequency of the triangle wave is given by timer as follows [4]:
        freq_hz = CPU_FREQ_HZ * 1. / (32. * (self.period + 1))

        # how much phase we step with each cycle is given by
        #   phase_per_samp = cycles per sample = (freq_hz / samples per second)
        # unit of phase here is CYCLES not radians (i.e. 1 cycle = 2pi radians)
        phase_per_samp = freq_hz / SAMPLE_RATE

        # if the triangle wave is not enabled or its linear or length counter is zero, this is zero.
        # Also added here is an exclusion for ultrasonic frequencies, which is used in MegaMan to silence the triangle
        # this is not entirely accurate, but probably produces nicer sounds.
        if (not self.enable) or self.length_ctr == 0 or self.linear_ctr == 0 or self.period < 2:
            v = 0
        else:
            v = int(31.999999 * abs(0.5 - self.phase))    # int cast rounds down, should never be 16
            self.phase = (self.phase + phase_per_samp) % 1.

        return v


cdef class APUPulse(APUUnit):
    """
    APU pulse unit; there are two of these in the APU
    Reference:
        [5] pulse: https://wiki.nesdev.com/w/index.php/APU_Pulse
        [12] http://nesdev.com/apu_ref.txt
        [13] https://wiki.nesdev.com/w/index.php/APU_Sweep
    """
    # Duty cycles for the pulse generators [5]
    DUTY_CYCLES = [[0, 1, 0, 0,  0, 0, 0, 0],
                   [0, 1, 1, 0,  0, 0, 0, 0],
                   [0, 1, 1, 1,  1, 0, 0, 0],
                   [1, 0, 0, 1,  1, 1, 1, 1]]

    def __init__(self, is_unit_1):
        super().__init__()
        self.constant_volume = False
        self.period = 1
        self.adjusted_period = 1   # period adjusted by the sweep units
        self.duty = 0
        self.phase = 0
        self.env = APUEnvelope()
        self.is_unit_1 = is_unit_1

        self.sweep_enable = False
        self.sweep_negate = False
        self.sweep_reload = False
        self.sweep_period = 1
        self.sweep_shift = 0
        self.sweep_divider = 0

        # copy the pulse duty cycle patterns into an int array
        # todo: is there a way to have shared cython class-level variables or constants?
        for i in range(4):
            for j in range(8):
                self.duty_waveform[i][j] = self.DUTY_CYCLES[i][j]

    cdef void write_register(self, int address, unsigned char value):
        """
        Set properties of the pulse waveform generators from a write to one of their registers; assumes address has been
        mapped to the 0x4000-0x4003 range (i.e. if this is pulse 1, subtract 4)
        """
        address -= 4 if not self.is_unit_1 else 0
        if address == 0x4000:
            self.duty = (value & 0b11000000) >> 6
            self.ctr_halt = self.env.loop_flag = (value >> 5) & 1
            self.constant_volume = (value >> 4) & 1
            self.env.volume = value & 0b00001111
        elif address == 0x4001:
            self.sweep_enable = (value >> 7) & 1
            self.sweep_period = ((value & 0b01110000) >> 4) + 1
            self.sweep_negate = (value >> 3) & 1
            self.sweep_shift = value & 0b00000111
            self.sweep_reload = True
            #print("sweep: {:08b}".format(value))
        elif address == 0x4002:
            # timer low
            self.period = (self.period & 0xFF00) + value
            self.adjusted_period = self.period
        elif address == 0x4003:
            self.period = (self.period & 0xFF) + ((value & 0b00000111) << 8)
            self.adjusted_period = self.period
            self.set_length_ctr(value >> 3)
            # side effect: the sequencer is restarted at the first value of the sequence and envelope is restarted [5]
            self.phase = 0
            # side effect: restart envelope and set the envelope start flag
            self.env.restart()
            self.env.start_flag = True

    cdef void quarter_frame(self):
        self.env.update()

    cdef void half_frame(self):
        self.sweep_update()
        self.update_length_ctr()

    cdef void sweep_update(self):
        """
        Adjust the period based on the sweep unit.  Part of the functionality here is based on the following paragraph
        from [12]:
            "When the channel's period is less than 8 or the result of the shifter is
             greater than $7FF, the channel's DAC receives 0 and the sweep unit doesn't
             change the channel's period. Otherwise, if the sweep unit is enabled and the
             shift count is greater than 0, when the divider outputs a clock, the channel's
             period in the third and fourth registers are updated with the result of the
             shifter."
        This seems to disagree a little with [13] in that the description in [13] permits zero as a shift
        value (and even uses it as an example), whereas the above text excludes it.  This makes a difference in the
        game Ghengis Khan, which if 0 is permitted as a shift has background music which sounds wrong (and differs from
        FCEUX) in the main game screens.

        In the system here, adjusted_period is used to determine whether or not the period has been changed outside of
        the permitted range, silencing the channel (without adjusting period outside that range).  Don't know if this is
        correct, but it seems to be what is implied in [12].

        Finally, should the change amount be based on the non-adjusted period or the adjusted period?  I.e. should the
        period be irrevocably altered by the sweep unit, or is the original period retained somewhere and used to
        calculate the shift each time?  In a recurring multiple shift, this changes the frequency change rate from
        exponential to linear.  No clear idea of what is correct.
        """
        cdef int change_amount
        if self.sweep_reload:
            # If [the divider's counter is zero or] the reload flag is true, the counter is set to P and the reload flag
            # is cleared. [7]
            self.sweep_divider = self.sweep_period
            self.sweep_reload = False
            return

        if self.sweep_divider > 0:
            # Otherwise, the counter is decremented. [7]
            self.sweep_divider -= 1
        else: # self.sweep_divider == 0:
            # If the divider's counter is zero [...], the counter is set to P and the reload flag is cleared. [7]
            self.sweep_divider = self.sweep_period
            self.sweep_reload = False

            if self.sweep_enable and self.sweep_shift > 0:
                # in this case, trigger a period adjustment
                change_amount = self.period >> self.sweep_shift
                if self.sweep_negate:
                    change_amount = -change_amount
                    if not self.is_unit_1:
                        change_amount -= 1

                # check if the adjusted period would go outside range; if so, don't update main period, but channel
                # will be silenced (see description above)
                self.adjusted_period = self.period + change_amount
                if 8 < self.adjusted_period <= 0x7FF:
                    self.period += change_amount

    cdef int generate_sample(self):
        """
        Generate one output sample from the pulse unit.
        """
        cdef double freq_hz
        cdef int v, volume, change_amount

        freq_hz = CPU_FREQ_HZ * 1. / (16. * (self.period + 1))

        # how much phase we step with each cycle is given by
        #   phase_per_samp = cycles per sample = (freq_hz / samples per second)
        # unit of phase here is CYCLES not radians (i.e. 1 cycle = 2pi radians)
        phase_per_samp = freq_hz / SAMPLE_RATE

        # there are several conditions under which the channel is muted.  [7] and others.
        if ( not self.enable
             or self.length_ctr == 0
             or self.adjusted_period < 8
             or self.adjusted_period > 0x7FF
            ):
            v = 0
        else:
            volume = self.env.volume if self.constant_volume else self.env.decay_level
            v = volume * self.duty_waveform[self.duty][int(7.999999 * self.phase)]
            self.phase = (self.phase + phase_per_samp) % 1.
        return v


cdef class APUNoise(APUUnit):
    """
    APU pulse unit; there are two of these in the APU
    Reference:
        [8] noise: https://wiki.nesdev.com/w/index.php/APU_Noise

    """
    TIMER_TABLE = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068]

    def __init__(self):
        super().__init__()
        self.constant_volume = False
        self.mode = False
        self.period = 4
        self.feedback = 1  # loaded with 1 on power up [8]
        self.timer = 0
        self.env = APUEnvelope()
        for i in range(16):
            self.timer_table[i] = self.TIMER_TABLE[i]

    cdef void write_register(self, int address, unsigned char value):
        """
        Set properties of the noise waveform generators from a write to its registers.
        """
        if address == 0x400C:
            self.ctr_halt = self.env.loop_flag = (value >> 5) & 1
            self.constant_volume = (value >> 4) & 1
            self.env.volume = value & 0b00001111
        elif address == 0x400E:
            self.mode = (value >> 7) & 1
            self.period = self.timer_table[value & 0b00001111]
        elif address == 0x400F:
            self.set_length_ctr(value >> 3)
            # side effect: restart envelope and set the envelope start flag
            self.env.restart()
            self.env.start_flag = True

    cdef void quarter_frame(self):
        self.env.update()

    cdef void half_frame(self):
        self.update_length_ctr()

    cdef void update_cycles(self, int cycles):
        cdef int xor_bit, feedback_bit
        self.timer += cycles

        if self.timer >= 2 * self.period:
            self.timer -= 2 * self.period
            xor_bit = 6 if self.mode else 1
            feedback_bit = ((self.feedback >> 0) & 1) ^ ((self.feedback >> xor_bit) & 1)
            self.feedback >>= 1
            self.feedback |= (feedback_bit << 14)

    cdef int generate_sample(self):
        """
        Generates a noise sample.  Updates a shift register to create pseudo-random samples and applies the
        noise volume envelope.
        """
        # clock the feedback register 0.5 * CPU_FREQ / SAMPLE_RATE / noise_period times per sample
        volume = self.env.volume if self.constant_volume else self.env.decay_level
        if not self.enable or self.length_ctr==0:
            return 0
        return volume * (self.feedback & 1)   # bit here should actually be negated, but doesn't matter


cdef class APUDMC(APUUnit):
    """
    The delta modulation channel (DMC) of the APU.  This allows delta-coded 1-bit samples to be played
    directly from memory.  It operates in a different way to the other channels, so is not based on them.
    References:
        [9] DMC: https://wiki.nesdev.com/w/index.php/APU_DMC
        [10] DMC interrupt flag reset: http://www.slack.net/~ant/nes-emu/apu_ref.txt
        [11] interesting DMC model: http://www.slack.net/~ant/nes-emu/dmc/
    """
    RATE_TABLE = [428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106,  84,  72,  54]

    def __init__(self):
        super().__init__()

        self.enable = False
        self.silence = True
        self.irq_enable = False
        self.loop_flag = False
        self.interrupt_flag = False

        self.rate = 0
        self.output_level = 0
        self.sample_address = 0
        self.address = 0
        self.sample_length = 0
        self.bytes_remaining = 0
        self.sample = 0
        self.timer = 0

        # copy the rate table lookup into the cdef'ed variable for speed
        for i in range(16):
            self.rate_table[i] = self.RATE_TABLE[i]

    cdef void write_register(self, int address, unsigned char value):
        """
        Write a value to one of the dmc's control registers; called from APU write register.  Address must be in the
        0x4010 - 0x4013 range (inclusive); if not the write is ignored
        """
        if address == 0x4010:
            self.irq_enable = (value >> 7) & 1
            if not self.irq_enable:
                self.interrupt_flag = False
            self.loop_flag = (value >> 6) & 1
            self.rate = self.rate_table[value & 0b00001111]
        elif address == 0x4011:
            self.output_level = value & 0b01111111
        elif address == 0x4012:
            self.sample_address = 0xC000 + (value << 6)
            self.address = self.sample_address
        elif address == 0x4013:
            self.sample_length = (value << 4) + 1
            self.bytes_remaining = self.sample_length

    cdef void update_cycles(self, int cpu_cycles):
        """
        Update that occurs on every CPU clock tick, run cpu_cycles times
        """
        cdef int v
        self.timer += cpu_cycles

        if self.timer < 2 * self.rate:
            return

        # now the unit's timer has ticked, so update the unit
        self.timer -= 2 * self.rate

        # update bits_remaining counter
        if self.bits_remaining == 0:
            # cycle end; a new cycle can start
            self.bits_remaining = 8
            self.read_advance()

        # read the bit
        v = self.sample & 1

        if not self.silence:
            if v == 0 and self.output_level >= 2:
                self.output_level -= 2
            elif v == 1 and self.output_level <= 125:
                self.output_level += 2

        # clock the shift register one place to the right
        self.sample >>= 1
        self.bits_remaining -= 1

    cdef void read_advance(self):
        """
        Reads a byte of memory and places it into the sample buffer; advances memory pointer, wrapping if necessary.
        """
        if self.bytes_remaining == 0:
            if self.loop_flag:
                # if looping and have run out of data, go back to the start
                self.bytes_remaining = self.sample_length
                self.address = self.sample_address
            else:
                self.silence = True

        if self.bytes_remaining > 0:
            self.sample = self.memory.read(self.address)
            self.address = (self.address + 1) & 0xFFFF
            self.bytes_remaining -= 1
            self.silence = False
            if self.bytes_remaining == 0 and self.irq_enable:
                # this was the last byte that we just read
                # "the IRQ is generated when the last byte of the sample is read, not when the last sample of the
                # sample plays" [9]
                # self.interrupt_listener.raise_irq()
                self.interrupt_flag = True

            # a DMC memory read should stall the CPU here for a variable number of cycles

    cdef int generate_sample(self):
        """
        Generate the next DMC sample.
        """
        return self.output_level
