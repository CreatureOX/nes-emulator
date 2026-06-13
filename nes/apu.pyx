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
    """
    Audio Processing Unit (APU) emulation for the 2A03 chip.
    
    Implements two pulse channels with sweep, envelope, and length counters.
    Uses a NES-like filter chain for authentic audio output.
    """
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
        """
        Initialize the APU.
        
        Args:
            sample_rate: Audio sample rate in Hz (default: 44100)
            cpu_rate: CPU clock rate in Hz (default: 1789772.5 for NTSC NES)
        """
        self.sample_rate = sample_rate
        self.cpu_rate = cpu_rate
        self.cycles_per_sample = self.cpu_rate / self.sample_rate
        self.cycles_per_length = self.cpu_rate / 240.0
        self.sample_accum = 0.0
        self.length_accum = 0.0
        self.last_output = 0.0
        self._samples = []
        cdef double two_pi = 6.283185307179586
        self.hp1_coef = (two_pi * 90.0) / (self.sample_rate + (two_pi * 90.0))
        self.hp2_coef = (two_pi * 440.0) / (self.sample_rate + (two_pi * 440.0))
        self.lp_coef = (two_pi * 14000.0) / (self.sample_rate + (two_pi * 14000.0))
        self.reset()

    cpdef void reset(self):
        """Reset all pulse channel state and filters."""
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
        """Initialize APU state at power-up."""
        self.reset()

    cpdef int readByCPU(self, int addr):
        """
        Read from APU registers (0x4015 status register).
        
        Returns channel enable status bits.
        """
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
        """
        Write to APU registers ($4000-$4015).
        
        Register layout:
        - $4000/$4004: Channel duty, loop envelope, constant volume, envelope period
        - $4001/$4005: Sweep enabled, period, negate, shift count
        - $4002/$4006: Timer low 8 bits
        - $4003/$4007: Timer high 3 bits and length counter load
        - $4015: Channel enable flags
        """
        cdef int channel = 0 if addr < 0x4004 else 1
        cdef int index = addr & 0x0003
        cdef int length_index

        if index == 0:
            # Pulse channel control ($4000 or $4004)
            # Bits 7-6: Duty cycle (0-3)
            # Bit 5: Length counter halt (loop flag)
            # Bit 4: Constant volume flag
            # Bits 3-0: Envelope period
            self.pulse_duty[channel] = (data >> 6) & 0x03
            self.pulse_loop[channel] = 1 if (data & 0x20) else 0
            self.pulse_constant[channel] = 1 if (data & 0x10) else 0
            self.pulse_env_period[channel] = data & 0x0F
            self.pulse_volume[channel] = data & 0x0F
            self.pulse_env_start[channel] = 1
        elif index == 1:
            # Sweep register ($4001 or $4005)
            # Bit 7: Sweep enabled
            # Bits 6-4: Sweep period
            # Bit 3: Sweep negate (0=positive, 1=negative)
            # Bits 2-0: Sweep shift count
            self.pulse_sweep_enabled[channel] = 1 if (data & 0x80) else 0
            self.pulse_sweep_period[channel] = (data >> 4) & 0x07
            self.pulse_sweep_negate[channel] = 1 if (data & 0x08) else 0
            self.pulse_sweep_shift[channel] = data & 0x07
            self.pulse_sweep_reload[channel] = 1  # Flag to reload sweep divider
        elif index == 2:
            # Timer low ($4002 or $4006) - lower 8 bits of period
            self.pulse_period[channel] = (self.pulse_period[channel] & 0x0700) | data
        elif index == 3:
            # Timer high ($4003 or $4007) - upper 3 bits and length/reset
            self.pulse_period[channel] = (self.pulse_period[channel] & 0x00FF) | ((data & 0x07) << 8)
            # Load length counter from lookup table
            length_index = (data >> 3) & 0x1F
            self.pulse_length[channel] = LENGTH_TABLE[length_index] if length_index < 32 else 0
            self.pulse_timer[channel] = self.pulse_period[channel] + 1
            self.pulse_step[channel] = 0
            self.pulse_enabled[channel] = 1  # Enable channel
            self.pulse_env_start[channel] = 1  # Start envelope

        if addr == 0x4015:
            # Channel enable register
            # Bits 0-1 enable pulse channels 0 and 1
            # Writing 0 to a channel clears its length counter
            self.pulse_enabled[0] = 1 if (data & 0x01) else 0
            self.pulse_enabled[1] = 1 if (data & 0x02) else 0
            if not self.pulse_enabled[0]:
                self.pulse_length[0] = 0
            if not self.pulse_enabled[1]:
                self.pulse_length[1] = 0

    cpdef void clock(self, int cycles):
        """
        Clock the APU for a number of cycles.
        
        Updates pulse timers, envelope generators, length counters,
        sweep units, and generates audio samples.
        """
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
                    # Decrement length counter (unless loop flag is set)
                    if self.pulse_length[channel] > 0 and not self.pulse_loop[channel]:
                        self.pulse_length[channel] -= 1
                        if self.pulse_length[channel] == 0:
                            self.pulse_enabled[channel] = 0

                    # Envelope generator
                    if self.pulse_env_start[channel]:
                        # Start flag: reset decay counter
                        self.pulse_env_start[channel] = 0
                        self.pulse_env_decay[channel] = 15
                        self.pulse_env_divider[channel] = self.pulse_env_period[channel] + 1
                    else:
                        # Clock envelope divider
                        self.pulse_env_divider[channel] -= 1
                        if self.pulse_env_divider[channel] <= 0:
                            self.pulse_env_divider[channel] = self.pulse_env_period[channel] + 1
                            if self.pulse_env_decay[channel] > 0:
                                self.pulse_env_decay[channel] -= 1
                            elif self.pulse_loop[channel]:
                                # Loop: wrap decay counter to 15
                                self.pulse_env_decay[channel] = 15

                    # Sweep unit
                    if self.pulse_sweep_reload[channel]:
                        if self.pulse_sweep_enabled[channel]:
                            self.pulse_sweep_divider[channel] = self.pulse_sweep_period[channel] + 1
                        self.pulse_sweep_reload[channel] = 0
                    else:
                        self.pulse_sweep_divider[channel] -= 1
                        if self.pulse_sweep_divider[channel] <= 0:
                            self.pulse_sweep_divider[channel] = self.pulse_sweep_period[channel] + 1
                            if self.pulse_sweep_enabled[channel] and self.pulse_sweep_shift[channel] != 0:
                                # Calculate sweep target period
                                target = self.pulse_period[channel] >> self.pulse_sweep_shift[channel]
                                if self.pulse_sweep_negate[channel]:
                                    # Negative sweep (decreasing pitch)
                                    if channel == 0:
                                        target = self.pulse_period[channel] - target - 1
                                    else:
                                        target = self.pulse_period[channel] - target
                                else:
                                    # Positive sweep (increasing pitch)
                                    target = self.pulse_period[channel] + target
                                # Disable channel if target exceeds range
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
                if total > 0:
                    value = 95.88 / (8128.0 / total + 100.0)
                else:
                    value = 0.0
                if value > 1.0:
                    value = 1.0
                self._samples.append(<int>(value * 32767.0))

    cpdef np.ndarray drain_samples(self):
        """
        Retrieve and clear all accumulated audio samples.
        
        Returns:
            NumPy array of int16 audio samples
        """
        if len(self._samples) == 0:
            return np.zeros(0, dtype=np.int16)

        cdef np.ndarray[np.int16_t, ndim=1] buffer = np.array(self._samples, dtype=np.int16)
        self._samples = []
        if buffer.size > 0:
            mean_val = int(np.mean(buffer))
            if mean_val != 0:
                buffer = (buffer.astype(np.int32) - mean_val).astype(np.int16)
        return buffer