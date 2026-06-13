# cython: language_level=3
import numpy as np
cimport numpy as np

cdef int LENGTH_TABLE[32]
LENGTH_TABLE = [
    10, 254, 20, 2, 40, 4, 80, 6,
    160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22,
    192, 24, 72, 26, 16, 28, 32, 30
]

cdef int DUTY_PATTERNS[4][8]
DUTY_PATTERNS = [
    [0, 1, 0, 0, 0, 0, 0, 0],
    [0, 1, 1, 0, 0, 0, 0, 0],
    [0, 1, 1, 1, 1, 0, 0, 0],
    [1, 0, 0, 1, 1, 1, 1, 1],
]

cdef class APU2A03:
    cdef public int sample_rate
    cdef public double cpu_rate
    cdef double cycles_per_sample
    cdef double sample_accum
    cdef object _samples

    cdef int pulse_enabled[2]
    cdef int pulse_duty[2]
    cdef int pulse_volume[2]
    cdef int pulse_constant[2]
    cdef int pulse_loop[2]
    cdef int pulse_env_period[2]
    cdef int pulse_env_divider[2]
    cdef int pulse_env_decay[2]
    cdef int pulse_env_start[2]
    cdef int pulse_timer[2]
    cdef int pulse_period[2]
    cdef int pulse_step[2]
    cdef int pulse_length[2]
    cdef int pulse_sweep_enabled[2]
    cdef int pulse_sweep_period[2]
    cdef int pulse_sweep_negate[2]
    cdef int pulse_sweep_shift[2]
    cdef int pulse_sweep_divider[2]
    cdef int pulse_sweep_reload[2]
    cdef double last_output
    cdef double length_accum
    cdef double cycles_per_length
    cdef double hp1_last_input
    cdef double hp1_last_output
    cdef double hp2_last_input
    cdef double hp2_last_output
    cdef double lp_last_output
    cdef double hp1_coef
    cdef double hp2_coef
    cdef double lp_coef

    def __cinit__(self, int sample_rate=44100, double cpu_rate=1789772.5):
        self.sample_rate = sample_rate
        self.cpu_rate = cpu_rate
        self.cycles_per_sample = self.cpu_rate / self.sample_rate
        self.cycles_per_length = self.cpu_rate / 240.0
        self.sample_accum = 0.0
        self.length_accum = 0.0
        self.last_output = 0.0
        self._samples = []
        # filter coefficients for NES-like output chain
        cdef double two_pi = 6.283185307179586
        self.hp1_coef = (two_pi * 90.0) / (self.sample_rate + (two_pi * 90.0))
        self.hp2_coef = (two_pi * 440.0) / (self.sample_rate + (two_pi * 440.0))
        self.lp_coef = (two_pi * 14000.0) / (self.sample_rate + (two_pi * 14000.0))
        self.reset()

    cpdef void reset(self):
        self.sample_accum = 0.0
        self.last_output = 0.0
        self._samples = []
        self.hp1_last_input = 0.0
        self.hp1_last_output = 0.0
        self.hp2_last_input = 0.0
        self.hp2_last_output = 0.0
        self.lp_last_output = 0.0
        for i in range(2):
            self.pulse_enabled[i] = 0
            self.pulse_duty[i] = 0
            self.pulse_volume[i] = 0
            self.pulse_constant[i] = 1
            self.pulse_loop[i] = 0
            self.pulse_env_period[i] = 0
            self.pulse_env_divider[i] = 0
            self.pulse_env_decay[i] = 0
            self.pulse_env_start[i] = 0
            self.pulse_sweep_enabled[i] = 0
            self.pulse_sweep_period[i] = 0
            self.pulse_sweep_negate[i] = 0
            self.pulse_sweep_shift[i] = 0
            self.pulse_sweep_divider[i] = 0
            self.pulse_sweep_reload[i] = 0
            self.pulse_timer[i] = 0
            self.pulse_period[i] = 0
            self.pulse_step[i] = 0
            self.pulse_sweep_divider[i] = 0
            self.pulse_env_divider[i] = 0
            self.pulse_length[i] = 0

    cpdef void power_up(self):
        self.reset()

    cpdef int readByCPU(self, int addr):
        cdef int status
        if addr == 0x4015:
            status = 0
            if self.pulse_enabled[0] and self.pulse_length[0] > 0:
                status |= 0x01
            if self.pulse_enabled[1] and self.pulse_length[1] > 0:
                status |= 0x02
            return status
        return 0

    cpdef void writeByCPU(self, int addr, int data):
        cdef int channel = 0 if addr < 0x4004 else 1
        cdef int index = addr & 0x0003
        cdef int length_index

        if index == 0:
            self.pulse_duty[channel] = (data >> 6) & 0x03
            self.pulse_loop[channel] = 1 if (data & 0x20) else 0
            self.pulse_constant[channel] = 1 if (data & 0x10) else 0
            self.pulse_env_period[channel] = data & 0x0F
            self.pulse_volume[channel] = data & 0x0F
            self.pulse_env_start[channel] = 1
        elif index == 1:
            self.pulse_sweep_enabled[channel] = 1 if (data & 0x80) else 0
            self.pulse_sweep_period[channel] = (data >> 4) & 0x07
            self.pulse_sweep_negate[channel] = 1 if (data & 0x08) else 0
            self.pulse_sweep_shift[channel] = data & 0x07
            self.pulse_sweep_reload[channel] = 1
        elif index == 2:
            self.pulse_period[channel] = (self.pulse_period[channel] & 0x0700) | data
        elif index == 3:
            self.pulse_period[channel] = (self.pulse_period[channel] & 0x00FF) | ((data & 0x07) << 8)
            length_index = (data >> 3) & 0x1F
            self.pulse_length[channel] = LENGTH_TABLE[length_index] if length_index < 32 else 0
            self.pulse_timer[channel] = self.pulse_period[channel] + 1
            self.pulse_step[channel] = 0
            self.pulse_enabled[channel] = 1
            self.pulse_env_start[channel] = 1

        if addr == 0x4015:
            self.pulse_enabled[0] = 1 if (data & 0x01) else 0
            self.pulse_enabled[1] = 1 if (data & 0x02) else 0
            if not self.pulse_enabled[0]:
                self.pulse_length[0] = 0
            if not self.pulse_enabled[1]:
                self.pulse_length[1] = 0

    cpdef void clock(self, int cycles):
        cdef int cycle, channel, volume
        cdef double value, filtered
        for cycle in range(cycles):
            for channel in range(2):
                if self.pulse_enabled[channel] and self.pulse_length[channel] > 0:
                    self.pulse_timer[channel] -= 1
                    if self.pulse_timer[channel] < 0:
                        self.pulse_timer[channel] = self.pulse_period[channel] + 1
                        self.pulse_step[channel] = (self.pulse_step[channel] + 1) & 0x07

            self.length_accum += 1.0
            if self.length_accum >= self.cycles_per_length:
                self.length_accum -= self.cycles_per_length
                for channel in range(2):
                    if self.pulse_length[channel] > 0 and not self.pulse_loop[channel]:
                        self.pulse_length[channel] -= 1
                        if self.pulse_length[channel] == 0:
                            self.pulse_enabled[channel] = 0

                    if self.pulse_env_start[channel]:
                        self.pulse_env_start[channel] = 0
                        self.pulse_env_decay[channel] = 15
                        self.pulse_env_divider[channel] = self.pulse_env_period[channel] + 1
                    else:
                        self.pulse_env_divider[channel] -= 1
                        if self.pulse_env_divider[channel] <= 0:
                            self.pulse_env_divider[channel] = self.pulse_env_period[channel] + 1
                            if self.pulse_env_decay[channel] > 0:
                                self.pulse_env_decay[channel] -= 1
                            elif self.pulse_loop[channel]:
                                self.pulse_env_decay[channel] = 15

                    if self.pulse_sweep_reload[channel]:
                        if self.pulse_sweep_enabled[channel]:
                            self.pulse_sweep_divider[channel] = self.pulse_sweep_period[channel] + 1
                        self.pulse_sweep_reload[channel] = 0
                    else:
                        self.pulse_sweep_divider[channel] -= 1
                        if self.pulse_sweep_divider[channel] <= 0:
                            self.pulse_sweep_divider[channel] = self.pulse_sweep_period[channel] + 1
                            if self.pulse_sweep_enabled[channel] and self.pulse_sweep_shift[channel] != 0:
                                target = self.pulse_period[channel] >> self.pulse_sweep_shift[channel]
                                if self.pulse_sweep_negate[channel]:
                                    if channel == 0:
                                        target = self.pulse_period[channel] - target - 1
                                    else:
                                        target = self.pulse_period[channel] - target
                                else:
                                    target = self.pulse_period[channel] + target
                                if target > 0x7FF:
                                    self.pulse_enabled[channel] = 0
                                else:
                                    self.pulse_period[channel] = target

            self.sample_accum += 1.0
            if self.sample_accum >= self.cycles_per_sample:
                self.sample_accum -= self.cycles_per_sample
                total = 0
                for channel in range(2):
                    if self.pulse_enabled[channel] and self.pulse_length[channel] > 0 and self.pulse_period[channel] >= 8 and self.pulse_period[channel] <= 0x7FF:
                        if self.pulse_constant[channel]:
                            volume = self.pulse_volume[channel]
                        else:
                            volume = self.pulse_env_decay[channel]
                        if DUTY_PATTERNS[self.pulse_duty[channel]][self.pulse_step[channel]] == 1:
                            total += volume
                # Use NES pulse mixer formula from NESdev APU documentation
                if total > 0:
                    value = 95.88 / (8128.0 / total + 100.0)
                else:
                    value = 0.0
                # use raw APU output without additional filter attenuation for now
                if value > 1.0:
                    value = 1.0
                self._samples.append(<int>(value * 32767.0))

    cpdef np.ndarray drain_samples(self):
        if len(self._samples) == 0:
            return np.zeros(0, dtype=np.int16)

        cdef np.ndarray[np.int16_t, ndim=1] buffer = np.array(self._samples, dtype=np.int16)
        self._samples = []
        if buffer.size > 0:
            mean_val = int(np.mean(buffer))
            if mean_val != 0:
                buffer = (buffer.astype(np.int32) - mean_val).astype(np.int16)
        return buffer
