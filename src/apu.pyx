from libc.stdint cimport uint8_t, uint16_t, uint32_t
from libc.stdio cimport printf
import pyaudio


cdef class Divider:
    def __init__(self) -> None:
        self.period = self.counter = 0

    cdef void setPeriod(self, uint16_t period):
        self.period = period

    cdef uint16_t getPeriod(self):
        return self.period

    cdef void reload(self):
        self.counter = self.period

    cdef uint16_t getCounter(self):
        return self.counter

    cdef bint clock(self):
        if self.counter > 0:
            self.counter -= 1
            return False
        else:
            self.reload()
            return True

cdef class Timer:
    def __init__(self) -> None:
        self.divider = Divider()

    cdef void reset(self):
        self.divider.reload()

    cdef void setPeriod(self, uint16_t period):
        self.divider.setPeriod(period)

    cdef uint16_t getPeriod(self):
        return self.divider.getPeriod()

    cdef void setPeriodLow8(self, uint16_t value):
        period = self.divider.getPeriod()
        period = (period & 0b111_0000_0000) | value
        self.divider.setPeriod(period)

    cdef void setPeriodHigh3(self, uint16_t value):
        period = self.divider.getPeriod()
        period = (period & 0b1111_1111) | (value << 8)
        self.divider.setPeriod(period)

        self.divider.reload()

    cdef void setMinPeriod(self, uint16_t minPeriod):
        self.minPeriod = minPeriod

    cdef bint clock(self):
        if self.divider.getPeriod() < self.minPeriod:
            return False
        return self.divider.clock()

cdef class LengthCounter:
    def __init__(self) -> None:
        self.length_table = [
            10,254, 20,  2, 40,  4, 80,  6, 160,  8, 60, 10, 14, 12, 26, 14,
            12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30
        ]
        self.enabled = False
        self.halt = False
        self.counter = 0

    cdef void setEnabled(self, bint enabled):
        self.enabled = enabled
        if not self.enabled:
            self.counter = 0

    cdef void setHalt(self, bint halt):
        self.halt = halt

    cdef void loadCounterFromLengthTable(self, uint8_t i):
        if not self.enabled:
            return
        self.counter = self.length_table[i]

    cdef void clock(self):
        if self.halt or self.counter == 0:
            return
        self.counter -= 1

    cdef uint16_t getValue(self):
        return self.counter

    cdef bint isSilenceChannel(self):
        return self.counter == 0

cdef class EnvelopeGenerator:
    def __init__(self) -> None:
        self.start = False
        self.loop = False
        self.divider = Divider()
        self.counter = 0
        self.constantVolumeMode = False
        self.constantVolume = 0

    cdef void restart(self):
        self.start = False
        self.counter = 15
        self.divider.reload()

    cdef void setLoop(self, bint loop):
        self.loop = loop

    cdef void setConstantVolumeMode(self, bint mode):
        self.constantVolumeMode = mode

    cdef void setConstantVolume(self, uint16_t value):
        self.constantVolume = value
        self.divider.setPeriod(self.constantVolume)

    cdef uint16_t getVolume(self):
        return self.constantVolume if self.constantVolumeMode else self.counter

    cdef void clock(self):
        if self.start:
            self.restart()
        else:
            if self.divider.clock():
                if self.counter > 0:
                    self.counter -= 1
                elif self.loop:
                    self.counter = 15

cdef class SweepUnit:
    def __init__(self) -> None:
        self.subtractExtra = 0
        self.enabled = False
        self.negate = False
        self.reload = False
        self.silenceChannel = False
        self.shiftCount = 0
        self.divider = Divider()
        self.targetPeriod = 0
        self.adjusted_period = 1

    cdef void setSubtractExtra(self):
        self.subtractExtra = 1

    cdef void setEnabled(self, bint enabled):
        self.enabled = enabled

    cdef void setNegate(self, bint negate):
        self.negate = negate

    cdef void setPeriod(self, uint16_t period, Timer timer):
        self.divider.setPeriod(period)
        self.computeTargetPeriod(timer)

    cdef void setShiftCount(self, uint8_t shiftCount):
        self.shiftCount = shiftCount

    cdef void restart(self):
        self.reload = True

    cdef void clock(self, Timer timer):
        cdef uint16_t change_amount

        if self.reload:
            # if self.enabled and self.divider.clock():
            #     self.adjustTimerPeriod(timer)
            self.divider.reload()
            self.reload = False
            return 

        if self.divider.getCounter() > 0:
            self.divider.clock()
        else:
            self.divider.reload()
            self.reload = False

            if self.enabled and self.shiftCount > 0:
                change_amount = self.timer.getPeriod() >> self.shiftCount
                if self.negate:
                    change_amount = -change_amount
                    change_amount -= self.subtractExtra
                
                self.adjusted_period = self.timer.getPeriod() + change_amount
                if 8 < self.adjusted_period <= 0x7FF:
                    self.timer.setPeriod(self.timer.getPeriod() + change_amount)

    # cdef bint isSilenceChannel(self):
    #     return self.silenceChannel

    # cdef void computeTargetPeriod(self, Timer timer):
    #     cdef uint16_t currPeriod = timer.getPeriod()
    #     cdef uint16_t shiftedPeriod = currPeriod >> self.shiftCount

    #     if self.negate:
    #         self.targetPeriod = currPeriod - (shiftedPeriod - self.subtractExtra)
    #     else:
    #         self.targetPeriod = currPeriod + shiftedPeriod
    #     self.silenceChannel = (currPeriod < 8 or (self.targetPeriod > 0x7FF))

    # cdef void adjustTimerPeriod(self, Timer timer):
    #     if self.enabled and self.shiftCount > 0 and not self.silenceChannel:
    #         timer.setPeriod(self.targetPeriod)

cdef class PulseWaveGenerator:
    def __init__(self) -> None:
        self.sequences = [
            # 12.5%
            [0, 1, 0, 0, 0, 0, 0, 0],
            # 25%
            [0, 1, 1, 0, 0, 0, 0, 0],
            # 50%
            [0, 1, 1, 1, 1, 0, 0, 0],
            # 25% negated
            [1, 0, 0, 1, 1, 1, 1, 1]
        ]
        self.duty = 0
        self.step = 0

    cdef void restart(self):
        self.step = 0

    cdef void setDuty(self, uint8_t duty):
        self.duty = duty

    cdef void clock(self):
        self.step = (self.step + 1) % 8

    cdef uint16_t getValue(self):
        return self.sequences[self.duty][self.step]

cdef class PulseChannel:
    def __init__(self, uint8_t channelNo) -> None:
        self.channelNo = channelNo
        self.envelopeGenerator = EnvelopeGenerator()
        self.sweepUnit = SweepUnit()
        self.timer = Timer()
        self.lengthCounter = LengthCounter()
        self.pulseWaveGenerator = PulseWaveGenerator()

        if channelNo == 0:
            self.sweepUnit.setSubtractExtra()
        for i in range(SAMPLE_RATE):
            self.output[i] = 0

    cdef void clockQuarterFrameChips(self):
        self.envelopeGenerator.clock()

    cdef void clockHalfFrameChips(self):
        self.sweepUnit.clock(self.timer)
        self.lengthCounter.clock()

    cdef int generate_sample(self):
        cdef double freq_hz = CPU_FREQ_HZ * 1. / (16. * (self.timer.getPeriod() + 1))
        cdef uint16_t v

        phase_per_samp = freq_hz / SAMPLE_RATE

        if self.lengthCounter.enabled and self.lengthCounter.getValue() > 0 and 8 <= self.sweepUnit.adjusted_period <= 0x7FF:
            self.pulseWaveGenerator.clock()
        return <int>self.pulseWaveGenerator.getValue()

    cdef void writeByCPU(self, uint16_t addr, uint8_t data):
        addr -= 4 if not self.channelNo else 0

        if addr == 0x4000:
            self.pulseWaveGenerator.setDuty((data & 0b11000000) >> 6)
            self.lengthCounter.setHalt(((data >> 5) & 1) != 0)
            self.envelopeGenerator.setLoop(((data >> 5) & 1) != 0)
            self.envelopeGenerator.setConstantVolumeMode(((data >> 4) & 1) != 0)
            self.envelopeGenerator.setConstantVolume(data & 0b1111)
        elif addr == 0x4001:
            self.sweepUnit.setEnabled(((data >> 7) & 1) != 0)
            self.sweepUnit.setPeriod((data & 0b01110000) >> 4, self.timer)
            self.sweepUnit.setNegate(((data >> 3) & 1) != 0)
            self.sweepUnit.setShiftCount(data & 0b111)

            self.sweepUnit.restart()
        elif addr == 0x4002:
            self.timer.setPeriodLow8(data)
            self.sweepUnit.adjusted_period = self.timer.getPeriod()
        elif addr == 0x4003:
            self.timer.setPeriodHigh3(data & 0b111)
            self.sweepUnit.adjusted_period = self.timer.getPeriod()
            self.lengthCounter.loadCounterFromLengthTable(data >> 3)

            self.pulseWaveGenerator.restart()
            self.envelopeGenerator.restart()
            self.envelopeGenerator.start = True

    # cdef uint16_t getValue(self):
    #     if self.sweepUnit.isSilenceChannel():
    #         return 0
    #     if self.lengthCounter.isSilenceChannel():
    #         return 0
    #     return self.envelopeGenerator.getVolume() * self.pulseWaveGenerator.getValue()

cdef class LinearCounter:
    def __init__(self) -> None:
        self.reload = True
        self.control = True
        self.divider = Divider()

    cdef void restart(self):
        self.reload = True

    cdef void setControlAndPeriod(self, bint control, uint16_t period):
        self.control = control
        self.divider.setPeriod(period)

    cdef void clock(self):
        if self.reload:
            self.divider.reload()
        elif self.divider.getCounter() > 0:
            self.divider.clock()
        if not self.control:
            self.reload = False

    cdef uint16_t getValue(self):
        return self.divider.getCounter()
    
    cdef bint isSilenceChannel(self):
        return self.getValue() == 0

cdef class TriangleWaveGenerator:
    def __init__(self) -> None:
        self.sequences = [
            15, 14, 13, 12, 11, 10, 9, 8, 7, 6,  5,  4,  3,  2,  1,  0,
             0,  1,  2,  3,  4,  5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
        ]
        self.step = 0

    cdef void clock(self):
        self.step = (self.step + 1) % 32

    cdef uint16_t getValue(self):
        return self.sequences[self.step]

cdef class TriangleChannel:
    def __init__(self) -> None:
        self.timer = Timer()
        # self.timer.setMinPeriod(2)
        self.lengthCounter = LengthCounter()
        self.linearCounter = LinearCounter()
        self.triangleWaveGenerator = TriangleWaveGenerator()

        for i in range(SAMPLE_RATE):
            self.output[i] = 0

    cdef void clockQuarterFrameChips(self):
        self.linearCounter.clock()

    cdef void clockHalfFrameChips(self):
        self.lengthCounter.clock()

    cdef int generate_sample(self):
        cdef double freq_hz = CPU_FREQ_HZ * 1. / (32. * (self.timer.getPeriod() + 1))
        cdef int v
        
        phase_per_samp = freq_hz / SAMPLE_RATE

        if self.lengthCounter.enabled and self.lengthCounter.getValue() > 0 and self.linearCounter.getValue() > 0 and self.timer.getPeriod() >= 2:
            self.triangleWaveGenerator.clock()
        return <int>self.triangleWaveGenerator.getValue()
            
    cdef void writeByCPU(self, uint16_t addr, uint8_t data):
        if addr == 0x4008:
            self.lengthCounter.setHalt(((data >> 7) & 1) != 0)
            self.linearCounter.setControlAndPeriod((data >> 7) != 0, data & 0b1111111)
        elif addr == 0x400A:
            self.timer.setPeriodLow8(data)
        elif addr == 0x400B:
            self.timer.setPeriodHigh3(data & 0b111)
            
            self.lengthCounter.loadCounterFromLengthTable(data >> 3)
            self.linearCounter.restart()

cdef class LinearFeedbackShiftRegister:
    def __init__(self) -> None:
        self.register = 1
        self.mode = False

    cdef void clock(self):
        cdef uint16_t bit0 = self.register & 0b1

        cdef uint16_t bitNShift = 6 if self.mode else 1
        cdef uint16_t bitN = (self.register >> bitNShift) & 1

        cdef uint16_t feedback = bit0 ^ bitN

        self.register = (self.register >> 1) | (feedback << 14)

    # cdef bint isSilenceChannel(self):
    #     return (self.register & 0b1) != 0

cdef class NoiseChannel:
    def __init__(self) -> None:
        self.ntscPeriods = [
            4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068
        ]
        self.timer = Timer()
        self.lengthCounter = LengthCounter()
        self.envelopeGenerator = EnvelopeGenerator()
        self.LFSR = LinearFeedbackShiftRegister()

        self.timer.setMinPeriod(2)
        for i in range(SAMPLE_RATE):
            self.output[i] = 0

    cdef void clockQuarterFrameChips(self):
        self.envelopeGenerator.clock()

    cdef void clockHalfFrameChips(self):
        self.lengthCounter.clock()

    cdef void update_cycles(self, int cycles):
        self.timer.divider.counter += cycles

        if self.timer.divider.counter >= 2 * self.timer.getPeriod():
            self.timer.divider.counter -= 2 * self.timer.getPeriod()
            self.LFSR.clock()

    cdef int generate_sample(self):
        if not self.lengthCounter.enabled or self.lengthCounter.isSilenceChannel():
            return 0
        return self.envelopeGenerator().getVolume() * (self.LFSR.register & 1)

    # cdef uint16_t getValue(self):
    #     if self.LFSR.isSilenceChannel() or self.lengthCounter.isSilenceChannel():
    #         return 0
    #     return self.envelopeGenerator.getVolume()
    
    cdef void writeByCPU(self, uint16_t addr, uint8_t data):
        if addr == 0x400C:
            self.lengthCounter.setHalt(((data >> 5) & 1) != 0)
            self.envelopeGenerator.setLoop(((data >> 5) & 1) != 0)
            self.envelopeGenerator.setConstantVolumeMode(((data >> 4) & 1) != 0)
            self.envelopeGenerator.setConstantVolume(data & 0b1111)
        elif addr == 0x400E:
            self.LFSR.mode = (data >> 7) & 1
            self.setNoiseTimerPeriod(data & 0b1111)
        elif addr == 0x400F:
            self.lengthCounter.loadCounterFromLengthTable(data >> 3)
            self.envelopeGenerator.restart()
            self.envelopeGenerator.start = True

    cdef void setNoiseTimerPeriod(self, uint16_t i):
        cdef uint16_t periodReloadValue = self.ntscPeriods[i]
        self.timer.setPeriod(periodReloadValue)

cdef class APU2A03:
    def __init__(self) -> None:
        self.frame_segment = 0
        self.cycles = 0
        self._reset_timer_in = -1
        self.samples_per_cycle = SAMPLE_RATE * 1. / CPU_FREQ_HZ
        self.samples_required = 0
        self.rate=SAMPLE_RATE

        self._buffer_start = 0
        self._buffer_end = 1600

        self.master_volume = 0.5
        self.mode = FOUR_STEP

        self.pulse0 = PulseChannel(channelNo=0)
        self.pulse1 = PulseChannel(channelNo=1)
        self.triangle = TriangleChannel()
        self.noise = NoiseChannel()
        # self.frameCounter = FrameCounter()

        for i in range(APU_BUFFER_LENGTH):
            self.output[i] = 0

    cdef void reset(self):
        pass

    cdef void writeByCPU(self, uint16_t addr, uint8_t data):
        if addr == 0x4000 or addr == 0x4001 or addr == 0x4002 or addr == 0x4003:
            self.pulse0.writeByCPU(addr, data)
        elif addr == 0x4004 or addr == 0x4005 or addr == 0x4006 or addr == 0x4007:
            self.pulse1.writeByCPU(addr, data)
        elif addr == 0x4008 or addr == 0x400A or addr == 0x400B:
            self.triangle.writeByCPU(addr, data)
        elif addr == 0x400C or addr == 0x400E or addr == 0x400F:
            self.noise.writeByCPU(addr, data)
        elif addr == 0x4015:
            self.pulse0.lengthCounter.setEnabled((data & 0b1) != 0)
            self.pulse1.lengthCounter.setEnabled(((data & 0b10) >> 1) != 0)
            self.triangle.lengthCounter.setEnabled(((data & 0b100) >> 2) != 0)
            self.noise.lengthCounter.setEnabled(((data & 0b1000) >> 3) != 0)
        elif addr == 0x4017:
            self.mode = (data >> 7) & 1
            self._reset_timer_in = 3 + self.cycles % 2
            # self.frameCounter.writeByCPU(addr, data)
            # if self.frameCounter.steps == 5:
            #     self.frameCounterClockQuarter()
            #     self.frameCounterClockHalf()

    cdef uint8_t readByCPU(self, uint16_t addr):
        cdef uint8_t data = 0

        if addr == 0x4015:
            data |= 1 if self.pulse0.lengthCounter.getValue() > 0 else 0
            data |= (1 if self.pulse1.lengthCounter.getValue() > 0 else 0) << 1
            data |= (1 if self.triangle.lengthCounter.getValue() > 0 else 0) << 2
            data |= (1 if self.noise.lengthCounter.getValue() > 0 else 0) << 3

        return data

    cdef void frameCounterClockQuarter(self):
        self.pulse0.clockQuarterFrameChips()
        self.pulse1.clockQuarterFrameChips()
        self.triangle.clockQuarterFrameChips()
        self.noise.clockQuarterFrameChips()

    cdef void frameCounterClockHalf(self):
        self.pulse0.clockHalfFrameChips()
        self.pulse1.clockHalfFrameChips()
        self.triangle.clockHalfFrameChips()
        self.noise.clockHalfFrameChips()

    cdef int run_cycles(self, int cpu_cycles):
        """
        Updates the APU by the given number of cpu cycles.  This updates the frame counter if
        necessary (every quarter or fifth video frame).  Timings from [2].
        """
        cdef int new_segment, cpu_cycles_per_loop, cycles
        cdef bint quarter_frame = False, force_ticks = False

        # printf("%d\n", cpu_cycles)
        while cpu_cycles > 0:
            cycles = cpu_cycles if cpu_cycles < MAX_CPU_CYCLES_PER_LOOP else MAX_CPU_CYCLES_PER_LOOP
            self.cycles += cycles
            cpu_cycles -= MAX_CPU_CYCLES_PER_LOOP

            # self.dmc.update_cycles(cycles)
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
                    # if not self.irq_inhibit:
                    #    self.interrupt_listener.raise_irq()
                    #    self.frame_interrupt_flag = True
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
                    self.frameCounterClockQuarter()
                quarter_frame = True
                if new_segment == 0 or new_segment == 2 or force_ticks:
                    self.frameCounterClockHalf()

            self.frame_segment = new_segment

    cdef void generate_sample(self):
        tri = self.triangle.generate_sample()
        p1 = self.pulse0.generate_sample()
        p2 = self.pulse1.generate_sample()
        noise = self.noise.generate_sample()
        # dmc = self.dmc.generate_sample()

        v = self.mix(tri, p1, p2, noise, 0)

        #if v > 0:
        #    printf("%.4d\n", v)

        self.output[self._buffer_end & (APU_BUFFER_LENGTH - 1)] = v
        self._buffer_end += 1

    cdef int mix(self, int triangle, int pulse1, int pulse2, int noise, int dmc):
        """
        Mix the channels into signed 16-bit audio samples
        """
        cdef double pulse_out, tnd_out, sum_pulse, sum_tnd

        sum_pulse = pulse1 + pulse2
        sum_tnd = (triangle / 8227.) + (noise / 12241.) + (dmc / 22638.)
        pulse_out = 95.88 / ((8128. / sum_pulse) + 100.) if sum_pulse != 0 else 0
        tnd_out = 159.79 / (1. / sum_tnd + 100.) if sum_tnd != 0 else 0
        
        # printf("mix: %.4f\n", (pulse_out + tnd_out) )
        return int( ((pulse_out + tnd_out) ) * self.master_volume * SAMPLE_SCALE)  

    cpdef int buffer_remaining(self):
        return self._buffer_end - self._buffer_start

    cpdef short[:] get_sound(self, int samples):
        cdef int i
        samples = min(samples, CHUNK_SIZE, self._buffer_end - self._buffer_start)
        for i in range(samples):
            self.buffer[i] = self.output[(self._buffer_start + i) & (APU_BUFFER_LENGTH - 1)]
        self._buffer_start += samples
        cdef short[:] data = <short[:samples]>self.buffer
        return data

    def pyaudio_callback(self, in_data, frame_count, time_info, status):
        if self.buffer_remaining() > 0:
            data = self.get_sound(frame_count)
            return (data, pyaudio.paContinue)
        else:
            return (None, pyaudio.paAbort)

