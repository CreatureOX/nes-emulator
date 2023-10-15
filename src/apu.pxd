from libc.stdint cimport uint8_t, uint16_t, uint32_t

cdef enum:
    SAMPLE_RATE = 48000 
    SAMPLE_SCALE = 65536    
    CPU_FREQ_HZ = 1789773
    MAX_CPU_CYCLES_PER_LOOP = 24

    FOUR_STEP = 0
    FIVE_STEP = 1

    APU_BUFFER_LENGTH = 65536
    CHUNK_SIZE = 10000

cdef class Divider:
    cdef uint16_t period
    cdef uint16_t counter

    cdef void setPeriod(self,uint16_t)
    cdef uint16_t getPeriod(self)
    cdef void reload(self)
    cdef uint16_t getCounter(self)
    cdef bint clock(self)

cdef class Timer:
    cdef Divider divider
    cdef uint16_t minPeriod

    cdef void reset(self)
    cdef void setPeriod(self,uint16_t)
    cdef uint16_t getPeriod(self)
    cdef void setPeriodLow8(self,uint16_t)
    cdef void setPeriodHigh3(self,uint16_t)
    cdef void setMinPeriod(self,uint16_t)
    cdef bint clock(self)

cdef class LengthCounter:
    cdef uint16_t[32] length_table
    cdef bint enabled
    cdef bint halt
    cdef uint16_t counter

    cdef void setEnabled(self,bint)
    cdef void setHalt(self,bint)
    cdef void loadCounterFromLengthTable(self,uint8_t)
    cdef void clock(self)
    cdef uint16_t getValue(self)
    cdef bint isSilenceChannel(self)

cdef class EnvelopeGenerator:
    cdef bint start
    cdef bint loop
    cdef Divider divider
    cdef uint16_t counter
    cdef bint constantVolumeMode
    cdef uint16_t constantVolume

    cdef void restart(self)
    cdef void setLoop(self,bint)
    cdef void setConstantVolumeMode(self,bint)
    cdef void setConstantVolume(self,uint16_t)
    cdef uint16_t getVolume(self)
    cdef void clock(self)

cdef class SweepUnit:
    cdef uint16_t subtractExtra
    cdef bint enabled
    cdef bint negate
    cdef bint reload
    cdef bint silenceChannel
    cdef uint8_t shiftCount
    cdef Divider divider
    cdef uint16_t targetPeriod
    cdef uint16_t adjusted_period

    cdef void setSubtractExtra(self)
    cdef void setEnabled(self,bint)
    cdef void setNegate(self,bint)
    cdef void setPeriod(self,uint16_t,Timer)
    cdef void setShiftCount(self,uint8_t)
    cdef void restart(self)
    cdef void clock(self,Timer)
    # cdef bint isSilenceChannel(self)
    # cdef void computeTargetPeriod(self,Timer)
    # cdef void adjustTimerPeriod(self,Timer)

cdef class PulseWaveGenerator:
    cdef uint16_t[4][8] sequences
    cdef uint8_t duty
    cdef uint8_t step

    cdef void restart(self)
    cdef void setDuty(self,uint8_t)
    cdef void clock(self)
    cdef uint16_t getValue(self)

cdef class PulseChannel:
    cdef uint8_t channelNo
    cdef EnvelopeGenerator envelopeGenerator
    cdef SweepUnit sweepUnit
    cdef Timer timer
    cdef LengthCounter lengthCounter
    cdef PulseWaveGenerator pulseWaveGenerator
    cdef short output[SAMPLE_RATE]

    cdef void clockQuarterFrameChips(self)
    cdef void clockHalfFrameChips(self)
    cdef int generate_sample(self)
    cdef void writeByCPU(self,uint16_t,uint8_t)

cdef class LinearCounter:
    cdef bint reload
    cdef bint control
    cdef Divider divider

    cdef void restart(self)
    cdef void setControlAndPeriod(self,bint,uint16_t)
    cdef void clock(self)
    cdef uint16_t getValue(self)
    cdef bint isSilenceChannel(self)

cdef class TriangleWaveGenerator:
    cdef uint16_t[32] sequences
    cdef uint8_t step

    cdef void clock(self)
    cdef uint16_t getValue(self)

cdef class TriangleChannel:
    cdef Timer timer
    cdef LengthCounter lengthCounter
    cdef LinearCounter linearCounter
    cdef TriangleWaveGenerator triangleWaveGenerator
    cdef short output[SAMPLE_RATE]

    cdef void clockQuarterFrameChips(self)
    cdef void clockHalfFrameChips(self)
    cdef int generate_sample(self)
    cdef void writeByCPU(self,uint16_t,uint8_t)

cdef class LinearFeedbackShiftRegister:
    cdef uint16_t register
    cdef bint mode

    cdef void clock(self)
    # cdef bint isSilenceChannel(self)

cdef class NoiseChannel:
    cdef uint16_t[16] ntscPeriods
    cdef Timer timer
    cdef LengthCounter lengthCounter
    cdef EnvelopeGenerator envelopeGenerator
    cdef LinearFeedbackShiftRegister LFSR
    cdef short output[SAMPLE_RATE]

    cdef void clockQuarterFrameChips(self)
    cdef void clockHalfFrameChips(self)
    cdef void update_cycles(self, int cycles)
    cdef int generate_sample(self)
    cdef void writeByCPU(self,uint16_t,uint8_t)
    cdef void setNoiseTimerPeriod(self,uint16_t)
    
cdef class APU2A03:
    cdef PulseChannel pulse0
    cdef PulseChannel pulse1
    cdef TriangleChannel triangle
    cdef NoiseChannel noise
    # cdef FrameCounter frameCounter

    cdef double master_volume

    cdef int frame_counter

    cdef int cycles,rate  # cycle within the current frame (counted in CPU cycles NOT APU cycles as specified in [2]
    cdef int frame_segment  # which segment of the frame the apu is in
    cdef int _reset_timer_in  # after this number of cycles, reset the timer; ignored if < 0
    cdef double samples_per_cycle  # number of output samples to generate per output cycle (will be <1)
    cdef double samples_required  # number of samples currently required, once this gets over 1, generate a sample
    cdef unsigned long long _buffer_start, _buffer_end  # start and end index of the sample ring buffer
    cdef bint mode

    cdef short output[APU_BUFFER_LENGTH]
    cdef short buffer[CHUNK_SIZE]

    cdef void reset(self)
    cdef void writeByCPU(self,uint16_t,uint8_t)
    cdef uint8_t readByCPU(self,uint16_t)
    cdef void frameCounterClockQuarter(self)
    cdef void frameCounterClockHalf(self)
    cdef int run_cycles(self, int cpu_cycles)
    cdef void generate_sample(self)
    cdef int mix(self, int tri, int p1, int p2, int noise, int dmc)
    cpdef short[:] get_sound(self, int samples)
    cpdef int buffer_remaining(self)
    