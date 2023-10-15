from numpy import uint8, uint16, uint32
from typing import List


class Divider:
    period: uint16
    counter: uint16

    def __init__(self) -> None:
        self.period = self.counter = 0

    def setPeriod(self, period: uint16) -> None:
        self.period = period

    def getPeriod(self) -> uint16:
        return self.period

    def reload(self) -> None:
        self.counter = self.period

    def getCounter(self) -> uint16:
        return self.counter

    def clock(self) -> bool:
        if self.counter > 0:
            self.counter -= 1
            return False
        else:
            self.reload()
            return True

class Timer:
    divider: Divider
    minPeriod: uint16

    def __init__(self) -> None:
        self.minPeriod = 0
        self.divider = Divider()

    def reset(self) -> None:
        self.divider.reload()

    def setPeriod(self, period: uint16) -> None:
        self.divider.setPeriod(period)

    def getPeriod(self) -> uint16:
        return self.divider.getPeriod()

    def setPeriodLow8(self, value: uint16) -> None:
        period = self.divider.getPeriod()
        period = (period & 0b111_0000_0000) | value
        self.divider.setPeriod(period)

    def setPeriodHigh3(self, value: uint16) -> None:
        period = self.divider.getPeriod()
        period = (period & 0b1111_1111) | (value << 8)
        self.divider.setPeriod(period)

        self.divider.reload()

    def setMinPeriod(self, minPeriod: uint16) -> None:
        self.minPeriod = minPeriod

    def clock(self) -> bool:
        if self.divider.getPeriod() < self.minPeriod:
            return False
        return self.divider.clock()

class LengthCounter:
    length_table: List[uint8] = [
        10,254, 20,  2, 40,  4, 80,  6, 160,  8, 60, 10, 14, 12, 26, 14,
        12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30
    ]

    enabled: bool
    halt: bool
    counter: uint16

    def __init__(self) -> None:
        self.enabled = False
        self.halt = False
        self.counter = 0

    def setEnabled(self, enabled: bool) -> None:
        self.enabled = enabled
        if not self.enabled:
            self.counter = 0

    def setHalt(self, halt: bool) -> None:
        self.halt = halt

    def loadCounterFromLengthTable(self, i: uint8) -> None:
        if not self.enabled:
            return
        self.counter = self.length_table[i]

    def clock(self) -> None:
        if self.halt or self.counter == 0:
            return
        self.counter -= 1

    def getValue(self) -> uint16:
        return self.counter

    def isSilenceChannel(self) -> bool:
        return self.counter == 0

class EnvelopeGenerator:
    start: bool
    loop: bool
    divider: Divider
    counter: uint16
    constantVolumeMode: bool
    constantVolume: uint16

    def __init__(self) -> None:
        self.start = True
        self.loop = False
        self.divider = Divider()
        self.counter = 0
        self.constantVolumeMode = False
        self.constantVolume = 0

    def restart(self) -> None:
        self.start = True

    def setLoop(self, loop: bool) -> None:
        self.loop = loop

    def setConstantVolumeMode(self, mode: bool) -> None:
        self.constantVolumeMode = mode

    def setConstantVolume(self, value: uint16) -> None:
        self.constantVolume = value
        self.divider.setPeriod(self.constantVolume)

    def getVolume(self) -> uint16:
        return self.constantVolume if self.constantVolumeMode else self.counter

    def clock(self) -> None:
        if self.start:
            self.start = False
            self.counter = 15
            self.divider.reload()
        else:
            if self.divider.clock():
                if self.counter > 0:
                    self.counter -= 1
                elif self.loop:
                    self.counter = 15

class SweepUnit:
    subtractExtra: uint16
    enabled: bool
    negate: bool
    reload: bool
    silenceChannel: bool
    shiftCount: uint8
    divider: Divider
    targetPeriod: uint16

    def __init__(self) -> None:
        self.subtractExtra = 0
        self.enabled = False
        self.negate = False
        self.reload = False
        self.silenceChannel = False
        self.shiftCount = 0
        self.divider = Divider()
        self.targetPeriod = 0

    def setSubtractExtra(self) -> None:
        self.subtractExtra = 1

    def setEnabled(self, enabled: bool) -> None:
        self.enabled = enabled

    def setNegate(self, negate: bool) -> None:
        self.negate = negate

    def setPeriod(self, period: uint16, timer: Timer) -> None:
        self.divider.setPeriod(period)
        self.computeTargetPeriod(timer)

    def setShiftCount(self, shiftCount: uint8) -> None:
        self.shiftCount = shiftCount

    def restart(self) -> None:
        self.reload = True

    def clock(self, timer: Timer) -> None:
        self.computeTargetPeriod(timer)

        if self.reload:
            if self.enabled and self.divider.clock():
                self.adjustTimerPeriod(timer)
            self.divider.reload()
            self.reload = False
        else:
            if self.divider.getCounter() > 0:
                self.divider.clock()
            elif self.enabled and self.divider.clock():
                self.adjustTimerPeriod(timer)

    def isSilenceChannel(self) -> bool:
        return self.silenceChannel

    def computeTargetPeriod(self, timer: Timer) -> None:
        currPeriod: uint16 = timer.getPeriod()
        shiftedPeriod: uint16 = currPeriod >> self.shiftCount

        if self.negate:
            self.targetPeriod = currPeriod - (shiftedPeriod - self.subtractExtra)
        else:
            self.targetPeriod = currPeriod + shiftedPeriod
        self.silenceChannel = (currPeriod < 8 or (self.targetPeriod > 0x7FF))

    def adjustTimerPeriod(self, timer: Timer) -> None:
        if self.enabled and self.shiftCount > 0 and not self.silenceChannel:
            timer.setPeriod(self.targetPeriod)

class PulseWaveGenerator:
    sequences: List[List[uint16]] = [
        # 12.5%
        [0, 1, 0, 0, 0, 0, 0, 0],
        # 25%
        [0, 1, 1, 0, 0, 0, 0, 0],
        # 50%
        [0, 1, 1, 1, 1, 0, 0, 0],
        # 25% negated
        [1, 0, 0, 1, 1, 1, 1, 1]
    ]

    duty: uint8
    step: uint8

    def __init__(self) -> None:
        self.duty = 0
        self.step = 0

    def restart(self) -> None:
        self.step = 0

    def setDuty(self, duty: uint8) -> None:
        self.duty = duty

    def clock(self) -> None:
        self.step = (self.step + 1) % 8

    def getValue(self) -> uint16:
        return self.sequences[self.duty][self.step]

class PulseChannel:
    envelopeGenerator: EnvelopeGenerator
    sweepUnit: SweepUnit
    timer: Timer
    lengthCounter: LengthCounter
    pulseWaveGenerator: PulseWaveGenerator

    def __init__(self, channelNo: uint8) -> None:
        self.envelopeGenerator = EnvelopeGenerator()
        self.sweepUnit = SweepUnit()
        self.timer = Timer()
        self.lengthCounter = LengthCounter()
        self.pulseWaveGenerator = PulseWaveGenerator()

        if channelNo == 0:
            self.sweepUnit.setSubtractExtra()

    def clockQuarterFrameChips(self) -> None:
        self.envelopeGenerator.clock()

    def clockHalfFrameChips(self) -> None:
        self.lengthCounter.clock()
        self.sweepUnit.clock(self.timer)

    def clockTimer(self) -> None:
        if self.timer.clock():
            self.pulseWaveGenerator.clock()

    def writeByCPU(self, addr: uint16, data: uint8) -> None:
        addr -= 4 if self.sweepUnit.subtractExtra == 1 else 0

        if addr == 0x4000:
            self.pulseWaveGenerator.setDuty((data & 0b11000000) >> 6)
            self.lengthCounter.setHalt(((data & 0b100000) >> 5) != 0)
            self.envelopeGenerator.setLoop(((data & 0b100000) >> 5) != 0)
            self.envelopeGenerator.setConstantVolumeMode(((data & 0b10000) >> 4) != 0)
            self.envelopeGenerator.setConstantVolume(data & 0b1111)
        elif addr == 0x4001:
            self.sweepUnit.setEnabled(((data & 0b10000000) >> 7) != 0)
            self.sweepUnit.setPeriod((data & 0b01110000) >> 4, self.timer)
            self.sweepUnit.setNegate(((data & 0b1000) >> 3) != 0)
            self.sweepUnit.setShiftCount(data & 0b111)

            self.sweepUnit.restart()
        elif addr == 0x4002:
            self.timer.setPeriodLow8(data)
        elif addr == 0x4003:
            self.timer.setPeriodHigh3(data & 0b111)
            self.lengthCounter.loadCounterFromLengthTable((data & 0b11111000) >> 3)

            self.envelopeGenerator.restart()
            self.pulseWaveGenerator.restart()

    def getValue(self) -> uint16:
        if self.sweepUnit.isSilenceChannel():
            return 0
        if self.lengthCounter.isSilenceChannel():
            return 0
        return self.envelopeGenerator.getVolume() * self.pulseWaveGenerator.getValue()

class LinearCounter:
    reload: bool
    control: bool
    divider: Divider

    def __init__(self) -> None:
        self.reload = True
        self.control = True
        self.divider = Divider()

    def restart(self) -> None:
        self.reload = True

    def setControlAndPeriod(self, control: bool, period: uint16) -> None:
        self.control = control
        self.divider.setPeriod(period)

    def clock(self) -> None:
        if self.reload:
            self.divider.reload()
        elif self.divider.getCounter() > 0:
            self.divider.clock()
        if not self.control:
            self.reload = False

    def getValue(self) -> uint16:
        return self.divider.getCounter()
    
    def isSilenceChannel(self) -> bool:
        return self.getValue() == 0

class TriangleWaveGenerator:
    sequences: List[uint16] = [
        15, 14, 13, 12, 11, 10, 9, 8, 7, 6,  5,  4,  3,  2,  1,  0,
         0,  1,  2,  3,  4,  5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
    ]

    step: uint8

    def __init__(self) -> None:
        self.step = 0

    def clock(self) -> None:
        self.step = (self.step + 1) % 32

    def getValue(self) -> uint16:
        return self.sequences[self.step]

class TriangleChannel:
    timer: Timer
    lengthCounter: LengthCounter
    linearCounter: LinearCounter
    triangleWaveGenerator: TriangleWaveGenerator    


    def __init__(self) -> None:
        self.timer = Timer()
        self.timer.setMinPeriod(2)
        self.lengthCounter = LengthCounter()
        self.linearCounter = LinearCounter()
        self.triangleWaveGenerator = TriangleWaveGenerator()

    def clockQuarterFrameChips(self) -> None:
        self.linearCounter.clock()

    def clockHalfFrameChips(self) -> None:
        self.lengthCounter.clock()

    def clockTimer(self) -> None:
        if self.timer.clock():
            if self.linearCounter.getValue() > 0 and self.lengthCounter > 0:
                self.triangleWaveGenerator.clock()

    def writeByCPU(self, addr: uint16, data: uint8) -> None:
        if addr == 0x4008:
            self.lengthCounter.setHalt(((data & 0b10000000) >> 7) != 0)
            self.linearCounter.setControlAndPeriod(((data & 0b10000000) >> 7) != 0, data & 0b1111111)
        elif addr == 0x400A:
            self.timer.setPeriodLow8(data)
        elif addr == 0x400B:
            self.timer.setPeriodHigh3(data & 0b111)
            
            self.linearCounter.restart()
            self.lengthCounter.loadCounterFromLengthTable(data >> 3)

    def getValue(self) -> uint16:
        return self.triangleWaveGenerator.getValue()

class LinearFeedbackShiftRegister:
    register: uint16
    mode: bool

    def __init__(self) -> None:
        self.register = 1
        self.mode = False

    def clock(self) -> None:
        bit0: uint16 = self.register & 0b1

        bitNShift: uint16 = 6 if self.mode else 1
        bitN: uint16 = (self.register & (1 << bitNShift)) >> bitNShift

        feedback: uint16 = bit0 ^ bitN

        self.register = (self.register >> 1) | (feedback << 14)

    def isSilenceChannel(self) -> bool:
        return (self.register & 0b1) != 0

class NoiseChannel:
    ntscPeriods: List[uint16] = [
        4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068
    ]

    timer: Timer
    lengthCounter: LengthCounter
    envelopeGenerator: EnvelopeGenerator
    LFSR: LinearFeedbackShiftRegister

    def __init__(self) -> None:
        self.timer = Timer()
        self.lengthCounter = LengthCounter()
        self.envelopeGenerator = EnvelopeGenerator()
        self.LFSR = LinearFeedbackShiftRegister()

        self.envelopeGenerator.setLoop(True)

    def clockQuarterFrameChips(self) -> None:
        self.envelopeGenerator.clock()

    def clockHalfFrameChips(self) -> None:
        self.lengthCounter.clock()

    def clockTimer(self) -> None:
        if self.timer.clock():
            self.LFSR.clock()

    def getValue(self) -> uint16:
        if self.LFSR.isSilenceChannel() or self.lengthCounter.isSilenceChannel():
            return 0
        return self.envelopeGenerator.getVolume()
    
    def writeByCPU(self, addr: uint16, data: uint8) -> None:
        if addr == 0x400C:
            self.lengthCounter.setHalt(((data & 0b100000) >> 5) != 0)
            self.envelopeGenerator.setConstantVolumeMode(((data & 0b10000) >> 4) != 0)
            self.envelopeGenerator.setConstantVolume(data & 0b1111)
        elif addr == 0x400E:
            self.LFSR.mode = (data & 0b10000000) >> 7
            self.setNoiseTimerPeriod(data & 0b1111)
        elif addr == 0x400F:
            self.lengthCounter.loadCounterFromLengthTable(data >> 3)
            self.envelopeGenerator.restart()

    def setNoiseTimerPeriod(self, i: uint16):
        periodReloadValue: uint16 = (self.ntscPeriods[i] / 2) - 1
        self.timer.setPeriod(periodReloadValue)

class FrameCounter:
    cpuCycles: uint16
    steps: uint16
    inbibitInterrupt: bool

    def __init__(self) -> None:
        self.cpuCycles = 0
        self.steps = 4
        self.inbibitInterrupt = True

    def setMode(self, mode: uint8) -> None:
        if mode == 0:
            self.steps = 4
        else:
            self.steps = 5
        self.cpuCycles = 0

    def allowInterrupt(self) -> None:
        self.inbibitInterrupt = False

    def writeByCPU(self, address: uint16, data: uint8) -> None:
        if address != 0x4017:
            return
        self.setMode((data & 0b10000000) >> 7)
        if data & 0b1000000 != 0:
            self.allowInterrupt()

    def toCPUCycles(self, apuCycles: uint16) -> uint16:
        return 2 * apuCycles

class APU2A03:
    pulse0: PulseChannel
    pulse1: PulseChannel
    triangle: TriangleChannel
    noise: NoiseChannel
    frameCounter: FrameCounter

    evenFrame: bool
    elapsedCPUCycles: float
    sampleSum: float
    sampleNum: float

    def __init__(self) -> None:
        self.pulse0 = PulseChannel(channelNo=0)
        self.pulse1 = PulseChannel(channelNo=1)
        self.triangle = TriangleChannel()
        self.noise = NoiseChannel()
        self.frameCounter = FrameCounter()
        
        self.evenFrame = True
        self.elapsedCPUCycles = 0.0
        self.sampleSum = 0.0
        self.sampleNum = 0.0

        self.sampleRate = 44100

    def reset(self) -> None:
        self.evenFrame = True
        self.elapsedCPUCycles = 0
        self.sampleSum = 0
        self.sampleNum = 0
        self.writeByCPU(0x4017, 0)
        self.writeByCPU(0x4015, 0)
        for addr in range(0x4000, 0x400F + 1):
            self.writeByCPU(addr, 0)

    def writeByCPU(self, addr: uint16, data: uint8):
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
            self.frameCounter.writeByCPU(addr, data)
            if self.frameCounter.steps == 5:
                self.frameCounterClockQuarter()
                self.frameCounterClockHalf()

    def readByCPU(self, addr: uint16) -> uint8:
        data: uint8 = 0

        if addr == 0x4015:
            data |= 1 if self.pulse0.lengthCounter.getValue() > 0 else 0
            data |= (1 if self.pulse1.lengthCounter.getValue() > 0 else 0) << 1
            data |= (1 if self.triangle.lengthCounter.getValue() > 0 else 0) << 2
            data |= (1 if self.noise.lengthCounter.getValue() > 0 else 0) << 3

        return data

    def frameCounterClockQuarter(self):
        self.pulse0.clockQuarterFrameChips()
        self.pulse1.clockQuarterFrameChips()
        self.triangle.clockQuarterFrameChips()
        self.noise.clockQuarterFrameChips()

    def frameCounterClockHalf(self):
        self.pulse0.clockHalfFrameChips()
        self.pulse1.clockHalfFrameChips()
        self.triangle.clockHalfFrameChips()
        self.noise.clockHalfFrameChips()

    def frameCounterClock(self):
        resetCycles: bool = False

        if self.frameCounter.cpuCycles == self.frameCounter.toCPUCycles(3728.5):
            self.frameCounterClockQuarter()
        elif self.frameCounter.cpuCycles == self.frameCounter.toCPUCycles(7456.5):
            self.frameCounterClockQuarter()
            self.frameCounterClockHalf()
        elif self.frameCounter.cpuCycles == self.frameCounter.toCPUCycles(11185.5):
            self.frameCounterClockQuarter()
        elif self.frameCounter.cpuCycles == self.frameCounter.toCPUCycles(14914):
            pass
        elif self.frameCounter.cpuCycles == self.frameCounter.toCPUCycles(14914.5):
            if self.frameCounter.steps == 4:
                self.frameCounterClockQuarter()
                self.frameCounterClockHalf()     
        elif self.frameCounter.cpuCycles == self.frameCounter.toCPUCycles(14915):
            if self.frameCounter.steps == 4:
                resetCycles = True
        elif self.frameCounter.cpuCycles == self.frameCounter.toCPUCycles(18640.5):
            if self.frameCounter.steps == 5:
                self.frameCounterClockQuarter()
                self.frameCounterClockHalf()
        elif self.frameCounter.cpuCycles == self.frameCounter.toCPUCycles(18641):
            if self.frameCounter.steps == 5:
                resetCycles = True

        self.frameCounter.cpuCycles = 0 if resetCycles else self.frameCounter.cpuCycles + 1

    def clock(self, cpuCycles: uint32) -> float:
        avgNumScreenPPUCycles: float = 89342 - 0.5
        cpuCyclesPerSec: float = (avgNumScreenPPUCycles / 3) * 60.0
        cpuCyclesPerSample: float = cpuCyclesPerSec / self.sampleRate
        
        for i in range(cpuCycles):
            self.frameCounterClock()

            self.triangle.clockTimer()
            if self.evenFrame:
                self.pulse0.clockTimer()
                self.pulse1.clockTimer()
                self.noise.clockTimer()

            self.evenFrame = not self.evenFrame

            # self.sampleSum += self.mix()
            # self.sampleNum += 1
            self.elapsedCPUCycles += 1
            if self.elapsedCPUCycles >= cpuCyclesPerSample:
                self.elapsedCPUCycles -= cpuCyclesPerSample
                # sample: float = self.sampleSum / self.sampleNum
                # self.sampleSum = 0
                # self.sampleNum = 0
                sample: float = self.mix()
        return sample

    def mix(self) -> float:
        pulse1: uint16 = self.pulse0.getValue()
        pulse2: uint16 = self.pulse1.getValue()
        triangle: uint16 = self.triangle.getValue()
        noise: uint16 = self.noise.getValue()
        dmc: uint16 = 0

        pulseOut: float = 0.00752 * (pulse1 + pulse2)
        tndOut: float = 0.00851 * triangle + 0.00494 * noise + 0.00335 * dmc
        return (pulseOut + tndOut)