# cython: language_level=3
import numpy as np
cimport numpy as np
from libc.stdint cimport uint8_t, uint16_t

cdef int LENGTH_TABLE[32]
LENGTH_TABLE = [
    10, 254, 20, 2, 40, 4, 80, 6,
    160, 8, 60, 10, 14, 12, 26, 14,
    12, 16, 24, 18, 48, 20, 96, 22,
    192, 24, 72, 26, 16, 28, 32, 30
]

# DMC rate table: CPU cycles per bit (NTSC). Index = $4010 bits 3-0.
cdef int DMC_RATE_TABLE[16]
DMC_RATE_TABLE = [428, 380, 340, 320, 286, 254, 226, 214,
                  190, 160, 142, 128, 106, 84, 72, 54]

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

    cdef int pulse_duty[2]
    cdef int pulse_volume[2]
    cdef int pulse_constant[2]
    cdef int pulse_env_period[2]
    cdef int pulse_env_divider[2]
    cdef int pulse_env_decay[2]
    cdef int pulse_env_start[2]
    cdef int pulse_timer[2]
    cdef int pulse_period[2]
    cdef int pulse_step[2]
    cdef int pulse_sweep_enabled[2]
    cdef int pulse_sweep_period[2]
    cdef int pulse_sweep_negate[2]
    cdef int pulse_sweep_shift[2]
    cdef int pulse_sweep_divider[2]
    cdef int pulse_sweep_reload[2]
    cdef int pulse_sweep_mute[2]

    # Length counters exist for all four main channels -- pulse 1, pulse 2,
    # triangle, noise -- even though only the pulse channels are synthesised.
    # $4015 reports them and the frame counter clocks them, so they have to be
    # modelled independently of whether the channel makes any sound.
    cdef int channel_enabled[4]
    cdef int length_counter[4]
    cdef int length_halt[4]

    # Frame counter ("frame sequencer"), driven from $4017.
    cdef int frame_mode          # 0 = 4-step, 1 = 5-step
    cdef int frame_irq_inhibit
    cdef int frame_irq_flag
    cdef int frame_cycle
    cdef int frame_reset_delay
    cdef int cycle_parity

    # DMC channel (delta PCM). The channel reads samples from CPU memory via
    # DMA, so it needs a back-reference to the bus to fetch bytes.
    #
    # State machine mirrors Mesen2's DeltaModulationChannel (Core/NES/APU/
    # DeltaModulationChannel.cpp) field-for-field; names in (_parens) below.
    cdef int dmc_irq_enable        # _irqEnabled
    cdef int dmc_loop              # _loopFlag
    cdef int dmc_rate              # $4010 bits 3-0 index into DMC_RATE_TABLE
    cdef int dmc_addr              # _currentAddr  -- current sample fetch address
    cdef int dmc_addr_load         # _sampleAddr   -- 0xC000 + (val<<6)
    cdef int dmc_len               # _bytesRemaining
    cdef int dmc_len_load          # _sampleLength -- (val<<4)|1
    cdef int dmc_buffer            # _readBuffer   -- -1 when empty
    cdef int dmc_shift             # _shiftRegister (8 bits)
    cdef int dmc_bits              # _bitsRemaining
    cdef int dmc_timer             # _timer        -- countdown; fires (reloads) when < 0
    cdef int dmc_period            # _period       -- DMC_RATE_TABLE[rate] - 1 (Mesen2 stores table-1)
    cdef int dmc_silence           # _silenceFlag  -- 1 while the output unit is silent
    cdef int dmc_transfer_delay    # _transferStartDelay -- cycles until the first DMA after enable (2/3)
    cdef int dmc_disable_delay     # _disableDelay -- cycles until the channel stops after $4015 bit4=0 (2/3)
    cdef int dmc_irq_flag          # DMC interrupt flag (bit 7 of $4015 read)
    cdef int dmc_output            # delta counter, 0-125
    cdef public object bus_ref

    cdef double last_output
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
        self.sample_accum = 0.0
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
        # Power-up state of $4017 is $00: 4-step mode with the frame IRQ
        # enabled. Nothing consumes the flag yet -- it is only visible through
        # $4015 -- but it has to behave correctly for the length tests.
        self.frame_mode = 0
        self.frame_irq_inhibit = 0
        self.frame_irq_flag = 0
        self.frame_cycle = 0
        self.frame_reset_delay = 0
        self.cycle_parity = 0

        self.dmc_irq_enable = 0
        self.dmc_loop = 0
        self.dmc_rate = 0
        # Mesen2 Reset(): _timer.SetTimer(_timer.GetPeriod()) -- the bit timer
        # starts at the FULL period so the first delta bit takes a full
        # rate-period of CPU cycles. _period itself is table[0]-1 (Mesen2
        # stores the lookup value minus one because ApuTimer does not decrement
        # on SetPeriod). The DMC fires one bit every DMC_RATE_TABLE[rate]
        # cycles, matching real hardware and blargg's timing windows.
        self.dmc_period = DMC_RATE_TABLE[0] - 1
        self.dmc_timer = self.dmc_period
        self.dmc_addr = 0xC000
        self.dmc_addr_load = 0xC000
        self.dmc_len = 0
        self.dmc_len_load = 1
        self.dmc_buffer = -1
        self.dmc_shift = 0
        self.dmc_bits = 8
        self.dmc_silence = 1
        self.dmc_transfer_delay = 0
        self.dmc_disable_delay = 0
        self.dmc_irq_flag = 0
        self.dmc_output = 0
        # bus_ref is structural wiring installed exactly once by Bus.__init__
        # (self.apu.bus_ref = self) and MUST NOT be cleared here: bus.reset()
        # and bus.power_up() both call this method again while the same Bus
        # object is alive, and wiping bus_ref would leave the DMC channel unable
        # to request its sample-byte DMA (the "if self.bus_ref is not None"
        # guards would then skip the request push permanently).

        for i in range(4):
            self.channel_enabled[i] = 0
            self.length_counter[i] = 0
            self.length_halt[i] = 0

        for i in range(2):
            self.pulse_duty[i] = 0
            self.pulse_volume[i] = 0
            self.pulse_constant[i] = 1
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
            self.pulse_sweep_mute[i] = 0
            self.pulse_timer[i] = 0
            self.pulse_period[i] = 0
            self.pulse_step[i] = 0

    cpdef void power_up(self):
        """Initialize APU state at power-up."""
        self.reset()

    cpdef int readByCPU(self, int addr):
        """
        Read from APU registers (0x4015 status register).
        
        Returns channel enable status bits.
        """
        cdef int status
        cdef int channel
        if addr == 0x4015:
            status = 0
            # Bits 0-3 report "length counter is non-zero" for pulse 1, pulse 2,
            # triangle and noise. Note this tracks the length counter, not the
            # $4015 enable bit -- disabling a channel zeroes its length, so the
            # bit falls on its own.
            for channel in range(4):
                if self.length_counter[channel] > 0:
                    status |= (1 << channel)
            # Bit 4: DMC active. Hardware defines this as bytes-remaining > 0,
            # so it clears the instant the LAST byte is fetched into the 1-byte
            # buffer -- even though that byte's 8 bits may still be shifting
            # out. This is what makes blargg's 7-dmc_basics #19 ("one-byte
            # buffer filled immediately") and 8-dmc_rates both pass.
            if self.dmc_len > 0:
                status |= 0x10
            # Bit 7: DMC interrupt flag.
            if self.dmc_irq_flag:
                status |= 0x80
            # Bit 6: frame interrupt flag (read acknowledges it, but NOT the
            # DMC flag). NOTE: blargg's apu_test (3-irq_flag / 4-jitter) and
            # dummy_reads_apu both expect the frame interrupt here at bit 6,
            # so this placement is intentional and must not be moved to bit 5.
            if self.frame_irq_flag:
                status |= 0x40
            self.frame_irq_flag = 0
            return status
        return 0

    cpdef void writeByCPU(self, int addr, int data):
        """
        Write to an APU register.

        Register map:
        - $4000-$4003 / $4004-$4007: pulse 1 / pulse 2
        - $4008-$400B: triangle  (only the length counter is modelled)
        - $400C-$400F: noise     (only the length counter is modelled)
        - $4015: channel enable
        - $4017: frame counter
        """
        cdef int channel
        cdef int index

        # Only $4000-$4007 belong to the two pulse channels. Decoding the
        # channel/index for every address made unrelated registers alias onto
        # pulse 2: a write to $4017 (frame counter) landed on index 3 and so
        # reloaded pulse 2's period, reloaded its length counter and switched
        # the channel on; $4015 aliased onto the sweep register; and the
        # triangle/noise/DMC registers at $4008-$4013 all fell through here
        # too.
        if 0x4000 <= addr <= 0x4007:
            channel = 0 if addr < 0x4004 else 1
            index = addr & 0x0003

            if index == 0:
                # Pulse control ($4000 / $4004)
                # Bits 7-6: duty cycle
                # Bit 5:    length counter halt, doubles as the envelope loop
                # Bit 4:    constant volume
                # Bits 3-0: envelope period / volume
                self.pulse_duty[channel] = (data >> 6) & 0x03
                self.length_halt[channel] = 1 if (data & 0x20) else 0
                self.pulse_constant[channel] = 1 if (data & 0x10) else 0
                self.pulse_env_period[channel] = data & 0x0F
                self.pulse_volume[channel] = data & 0x0F
                self.pulse_env_start[channel] = 1
            elif index == 1:
                # Sweep ($4001 / $4005)
                self.pulse_sweep_enabled[channel] = 1 if (data & 0x80) else 0
                self.pulse_sweep_period[channel] = (data >> 4) & 0x07
                self.pulse_sweep_negate[channel] = 1 if (data & 0x08) else 0
                self.pulse_sweep_shift[channel] = data & 0x07
                self.pulse_sweep_reload[channel] = 1
            elif index == 2:
                # Timer low ($4002 / $4006)
                self.pulse_period[channel] = (self.pulse_period[channel] & 0x0700) | data
            else:
                # Timer high + length load ($4003 / $4007)
                self.pulse_period[channel] = (self.pulse_period[channel] & 0x00FF) | ((data & 0x07) << 8)
                self._load_length(channel, data)
                self.pulse_timer[channel] = self.pulse_period[channel] + 1
                self.pulse_step[channel] = 0
                self.pulse_env_start[channel] = 1
                self.pulse_sweep_mute[channel] = 0
        elif addr == 0x4008:
            # Triangle linear counter control; bit 7 also halts its length.
            self.length_halt[2] = 1 if (data & 0x80) else 0
        elif addr == 0x400B:
            self._load_length(2, data)
        elif addr == 0x400C:
            # Noise envelope register; bit 5 halts its length.
            self.length_halt[3] = 1 if (data & 0x20) else 0
        elif addr == 0x400F:
            self._load_length(3, data)
        elif addr == 0x4010:
            # DMC control: bit7 = IRQ enable, bit6 = loop, bits 3-0 = rate.
            # Mesen2 WriteRam(0x4010): _timer.SetPeriod(table[rate]-1). The
            # ApuTimer then fires one bit every (period+1) cycles =
            # DMC_RATE_TABLE[rate] cycles; the in-flight countdown is NOT
            # reloaded here, so a rate change takes effect on the next bit
            # boundary (one partial old-period bit, then the new period) --
            # exactly what blargg 8-dmc_rates expects. Reloading the timer
            # immediately (as older revisions did) stretched the sample and
            # failed the +/-45 cycle window.
            new_rate = data & 0x0F
            self.dmc_rate = new_rate
            self.dmc_period = DMC_RATE_TABLE[new_rate] - 1
            self.dmc_irq_enable = 1 if (data & 0x80) else 0
            self.dmc_loop = 1 if (data & 0x40) else 0
            # Clearing the IRQ-enable bit also clears the DMC interrupt flag.
            if not self.dmc_irq_enable:
                self.dmc_irq_flag = 0
        elif addr == 0x4011:
            # Direct load of the delta counter (7 bits).
            self.dmc_output = data & 0x7F
        elif addr == 0x4012:
            # Sample address = $C000 + (value << 6).
            self.dmc_addr_load = 0xC000 + ((data & 0xFF) << 6)
        elif addr == 0x4013:
            # Sample length = (value * 16) + 1 bytes.
            self.dmc_len_load = (data & 0xFF) * 16 + 1
        elif addr == 0x4015:
            # Channel enable. Clearing a bit zeroes that length counter, and
            # while the bit stays clear the counter cannot be reloaded.
            for channel in range(4):
                if data & (1 << channel):
                    self.channel_enabled[channel] = 1
                else:
                    self.channel_enabled[channel] = 0
                    self.length_counter[channel] = 0
            # Writing $4015 clears the DMC interrupt flag (bit 7) only. The
            # frame-interrupt flag (bit 6) is NOT cleared by a write -- only by
            # reading $4015. blargg 04-dummy_reads_apu clears it through the
            # page-cross *dummy read* that lands on $4015 (a read), not a write,
            # so this matches real hardware and keeps apu_test's red line intact.
            self.dmc_irq_flag = 0
            if data & 0x10:
                self.arm_dmc_sample()
            else:
                # Stop: Mesen2 SetEnabled(false) arms a 1-APU-cycle delay
                # (_disableDelay = 2 on an even cycle, 3 on an odd one) after
                # which ProcessClock zeroes _bytesRemaining and cancels any DMA
                # that has not yet started. A DMA that actually begins during
                # the delay still halts the CPU for one cycle (real hardware),
                # so we only cancel the request flag here and let _clock_dmc's
                # ProcessClock clear the rest when the delay elapses.
                if self.dmc_disable_delay == 0:
                    self.dmc_disable_delay = 2 if self.cycle_parity == 0 else 3
        elif addr == 0x4017:
            self._write_frame_counter(data)

    cdef void _load_length(self, int channel, int data):
        """
        Load a length counter from the lookup table (bits 7-3 of the write).

        Hardware ignores the load outright while the channel is disabled via
        $4015 -- it is not queued for when the channel comes back.
        """
        if not self.channel_enabled[channel]:
            return
        self.length_counter[channel] = LENGTH_TABLE[(data >> 3) & 0x1F]

    cdef void _write_frame_counter(self, int data):
        """
        Handle a $4017 write.

        Bit 7 selects the sequence: 0 = 4-step (with frame IRQ), 1 = 5-step.
        Bit 6 inhibits (and immediately acknowledges) the frame IRQ.

        Selecting the 5-step sequence immediately emits one quarter- and one
        half-frame clock; selecting the 4-step sequence does not.

        The divider is clocked at the APU rate (every second CPU cycle), so a
        write landing on an APU cycle restarts it 3 CPU cycles later while one
        landing between APU cycles takes 4. That single-cycle difference is the
        "APU clock jitter" measured by apu_test's 4-jitter.
        """
        self.frame_mode = 1 if (data & 0x80) else 0
        self.frame_irq_inhibit = 1 if (data & 0x40) else 0
        if self.frame_irq_inhibit:
            self.frame_irq_flag = 0
        if self.frame_mode:
            self._quarter_frame()
            self._half_frame()
        self.frame_reset_delay = 3 if self.cycle_parity else 4

    cdef inline bint _pulse_active(self, int channel):
        """A pulse channel runs while it is enabled and its length is non-zero."""
        return self.channel_enabled[channel] and self.length_counter[channel] > 0

    cdef void _clock_frame_counter(self):
        """
        Advance the frame counter by one CPU cycle.

        Step boundaries are the NTSC ones, counted in CPU cycles from the last
        divider reset. Mode 0 runs four steps over 29830 cycles and raises the
        frame IRQ across the last three; mode 1 runs five steps over 37282 and
        never raises it.
        """
        if self.frame_reset_delay > 0:
            # A $4017 write restarts the divider 3-4 cycles later.
            self.frame_reset_delay -= 1
            if self.frame_reset_delay == 0:
                self.frame_cycle = 0
            return

        self.frame_cycle += 1

        if self.frame_mode == 0:
            if self.frame_cycle == 7457:
                self._quarter_frame()
            elif self.frame_cycle == 14913:
                self._quarter_frame()
                self._half_frame()
            elif self.frame_cycle == 22371:
                self._quarter_frame()
            elif self.frame_cycle == 29828:
                if not self.frame_irq_inhibit:
                    self.frame_irq_flag = 1
            elif self.frame_cycle == 29829:
                self._quarter_frame()
                self._half_frame()
                if not self.frame_irq_inhibit:
                    self.frame_irq_flag = 1
            elif self.frame_cycle >= 29830:
                if not self.frame_irq_inhibit:
                    self.frame_irq_flag = 1
                self.frame_cycle = 0
        else:
            if self.frame_cycle == 7457:
                self._quarter_frame()
            elif self.frame_cycle == 14913:
                self._quarter_frame()
                self._half_frame()
            elif self.frame_cycle == 22371:
                self._quarter_frame()
            elif self.frame_cycle == 37281:
                self._quarter_frame()
                self._half_frame()
            elif self.frame_cycle >= 37282:
                self.frame_cycle = 0

    cdef void _quarter_frame(self):
        """Quarter-frame clock (~240 Hz): envelope generators."""
        cdef int channel
        for channel in range(2):
            if self.pulse_env_start[channel]:
                # Start flag: reload the decay counter and divider.
                self.pulse_env_start[channel] = 0
                self.pulse_env_decay[channel] = 15
                self.pulse_env_divider[channel] = self.pulse_env_period[channel] + 1
            else:
                self.pulse_env_divider[channel] -= 1
                if self.pulse_env_divider[channel] <= 0:
                    self.pulse_env_divider[channel] = self.pulse_env_period[channel] + 1
                    if self.pulse_env_decay[channel] > 0:
                        self.pulse_env_decay[channel] -= 1
                    elif self.length_halt[channel]:
                        # The halt bit doubles as the envelope loop flag.
                        self.pulse_env_decay[channel] = 15

    cdef void _half_frame(self):
        """Half-frame clock (~120 Hz): length counters and sweep units."""
        cdef int channel
        cdef int target

        for channel in range(4):
            if self.length_counter[channel] > 0 and not self.length_halt[channel]:
                self.length_counter[channel] -= 1

        for channel in range(2):
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
                            # Pulse 1 negates with an extra -1; pulse 2 does not.
                            if channel == 0:
                                target = self.pulse_period[channel] - target - 1
                            else:
                                target = self.pulse_period[channel] - target
                        else:
                            target = self.pulse_period[channel] + target
                        # Out of range mutes the channel but must not touch the
                        # length counter -- $4015 keeps reporting it.
                        if target > 0x7FF:
                            self.pulse_sweep_mute[channel] = 1
                        else:
                            self.pulse_period[channel] = target

    cdef void _clock_dmc(self):
        """Advance the DMC channel by one CPU cycle.

        Faithful port of Mesen2's DeltaModulationChannel (ProcessClock + Run)
        and ApuTimer::Run, called once per APU/CPU cycle.

        Two phases run each cycle:
          * ProcessClock (the _disableDelay / _transferStartDelay countdowns).
            When _transferStartDelay elapses it fires StartDmcTransfer() -- the
            first sample-byte DMA after an enable is requested. When
            _disableDelay elapses it zeroes _bytesRemaining and cancels any
            not-yet-started DMA (the real "stop" path).
          * Run (the bit timer). Mesen2 clocks the DMC timer from
            NesApu::Run(), which fires on every APU register access and at
            least once per frame-counter period, and which clocks the DMC
            channel unconditionally once it runs. The timer therefore NEVER
            freezes: while the channel is idle it keeps counting and firing,
            with _silenceFlag blocking the delta output -- a free-running
            hardware counter, not a gated one. The timer fires once every
            DMC_RATE_TABLE[rate] CPU cycles; on each fire it outputs one
            LSB-first delta bit, then at the 8-bit boundary it loads the next
            byte out of the 1-byte buffer and -- crucially -- requests the
            FOLLOWING byte immediately (the 1-byte lookahead that keeps the
            buffer primed). That lookahead is what makes each DMC DMA land on
            the same phase of the CPU's instruction stream every byte, which
            is exactly what blargg's dmc_dma_during_read4 needs to observe its
            extra $2007 reads.

        An earlier model froze the timer once _bytesRemaining reached 0 (a
        local reading of Mesen2's _needToRun gate). That was wrong: _needToRun
        only decides whether NesApu::Run() is forced on every cycle, and Run()
        clocks the DMC timer whenever it does fire, so the phase keeps
        advancing through idle periods. Freezing left every post-idle restart
        on a stale phase -- shifted by the idle gap modulo the rate period --
        which pushed the byte-boundary DMA off the CPU read that blargg's
        dma_2007_read measures.

        Ref: Mesen2 Core/NES/APU/DeltaModulationChannel.cpp (Run, ProcessClock,
        NeedToRun), Core/NES/APU/NesApu.cpp (Run, Exec, NeedToRun),
        Core/NES/APU/ApuTimer.h (Run).
        """
        # ---- ProcessClock: delay countdowns (Mesen2 DeltaModulationChannel::ProcessClock) ----
        if self.dmc_disable_delay > 0:
            self.dmc_disable_delay -= 1
            if self.dmc_disable_delay == 0:
                # Stop: drop the sample and cancel any pending DMA that has not
                # yet started fetching. A DMA already in flight still completes
                # (real hardware halts the CPU for one cycle even on a cancelled
                # transfer), so we only clear the request flag here.
                self.dmc_len = 0
                if self.bus_ref is not None:
                    self.bus_ref.dmc_dma_request = False
        if self.dmc_transfer_delay > 0:
            self.dmc_transfer_delay -= 1
            if self.dmc_transfer_delay == 0:
                self.start_dmc_transfer()
        # ---- Run: bit timer + byte-boundary lookahead (Mesen2 Run) ----
        # ApuTimer fires when the cycles elapsed exceed the timer; with _timer
        # initialised to _period = table[rate]-1 this is exactly one bit every
        # DMC_RATE_TABLE[rate] CPU cycles. There is deliberately no idle gate
        # here -- see the docstring on the free-running timer.
        self.dmc_timer -= 1
        if self.dmc_timer < 0:
            self.dmc_timer = self.dmc_period
            # Output one delta bit (only when the output unit is not silent).
            if not self.dmc_silence:
                if self.dmc_shift & 1:
                    self.dmc_output += 2
                    if self.dmc_output > 125:
                        self.dmc_output = 125
                else:
                    self.dmc_output -= 2
                    if self.dmc_output < 0:
                        self.dmc_output = 0
                self.dmc_shift >>= 1
            # Byte boundary: advance the bit count every fire, silent or not.
            self.dmc_bits -= 1
            if self.dmc_bits == 0:
                self.dmc_bits = 8
                if self.dmc_buffer < 0:
                    # Buffer still empty: the output unit goes silent and waits
                    # for the in-flight fetch (no bit is output).
                    self.dmc_silence = 1
                else:
                    # Reload the output unit from the 1-byte buffer and, in the
                    # SAME cycle, request the NEXT byte. This 1-byte lookahead
                    # is the heart of the phase-correct model.
                    self.dmc_silence = 0
                    self.dmc_shift = self.dmc_buffer
                    self.dmc_buffer = -1
                    if self.dmc_transfer_delay == 0:
                        self.start_dmc_transfer()

    cpdef uint16_t dmc_read_addr(self):
        """Address the pending sample-byte fetch reads from (for the bus DMA)."""
        return <uint16_t>self.dmc_addr

    cpdef void dmc_deliver(self, uint8_t byte):
        """Receive a sample byte fetched through the CPU bus DMA.

        Port of Mesen2's SetDmcReadBuffer: the byte fills the 1-byte buffer
        ONLY -- the output unit is never touched here. Reader bookkeeping
        (address increment with $8000 wrap, byte decrement, loop reload, and
        end-of-sample DMC IRQ) is performed. The bus clears dmc_dma_request
        when it starts the transfer; we also clear it here so a stale request
        can never wedge the channel.
        """
        if self.bus_ref is not None:
            self.bus_ref.dmc_dma_request = False
        if self.dmc_len > 0:
            self.dmc_buffer = byte & 0xFF
            self.dmc_addr = (self.dmc_addr + 1) & 0xFFFF
            if self.dmc_addr == 0:
                self.dmc_addr = 0x8000
            self.dmc_len -= 1
            if self.dmc_len == 0:
                if self.dmc_loop:
                    self.init_dmc_sample()
                elif self.dmc_irq_enable:
                    self.dmc_irq_flag = 1

    cdef void init_dmc_sample(self):
        """Mesen2 InitSample(): reload the reader (address + remaining bytes).

        The output unit (shift register, bit count, buffer, rate timer) is
        deliberately left running so an in-flight byte finishes first. This is
        what makes blargg 7-dmc_basics #19 and #3 behave correctly.
        """
        self.dmc_addr = self.dmc_addr_load
        self.dmc_len = self.dmc_len_load

    cdef void start_dmc_transfer(self):
        """Mesen2 StartDmcTransfer(): request a sample-byte DMA.

        Only fires when the 1-byte buffer is empty and bytes remain. Pushes the
        request onto the bus; the bus performs the 3-4 cycle CPU stall on the
        next CPU read and delivers the byte via dmc_deliver().
        """
        if self.dmc_buffer < 0 and self.dmc_len > 0 and self.bus_ref is not None:
            self.bus_ref.dmc_dma_request = True

    cdef void arm_dmc_sample(self):
        """Mesen2 SetEnabled(true): (re)start the sample reader.

        A restart only takes effect while the channel is idle
        (_bytesRemaining == 0). An already-playing sample is left untouched so
        its buffered bits finish first. Only the reader is reloaded
        (InitSample); the output unit -- including the bit timer -- keeps
        running, so the restart lands on whatever phase the free-running timer
        happens to be at. This split is what blargg 7-dmc_basics #19 ("a
        one-byte buffer that's filled immediately if empty") checks, and it is
        why 08.irq_timing and 7-dmc_basics #3 (restart timing) behave.

        transferStartDelay: 2 cycles on an even CPU cycle, 3 on an odd one
        (Mesen2 SetEnabled). The countdown runs in _clock_dmc's ProcessClock;
        when it hits 0 the first sample-byte DMA is requested.
        """
        if self.dmc_len == 0:
            if self.bus_ref is not None:
                self.bus_ref.dmc_dma_request = False
            self.init_dmc_sample()
            self.dmc_transfer_delay = 2 if self.cycle_parity == 1 else 3

    cpdef bint irq_level(self):
        """
        Current level of the APU's interrupt outputs to the CPU.

        Bit 6 of $4015 (frame interrupt) and bit 7 (DMC interrupt) are both
        level-triggered /IRQ sources. The flag bits stay set until $4015 is
        read (frame) or the enable is cleared (DMC), so OR-ing them in here is
        exactly what the bus must drive onto the CPU's /IRQ line. Previously
        these were never wired up, so the APU could set its flag yet the CPU
        never took the interrupt (blargg 08.irq_timing reported "Never
        occurred", and cpu_interrupts_v2's frame-IRQ subtests failed).
        """
        return self.frame_irq_flag != 0 or self.dmc_irq_flag != 0

    cpdef void clock(self, int cycles):
        """
        Clock the APU for a number of cycles.
        
        Updates pulse timers, envelope generators, length counters,
        sweep units, and generates audio samples.
        """
        cdef int cycle, channel, volume
        cdef double value, filtered
        for cycle in range(cycles):
            self.cycle_parity ^= 1
            self._clock_frame_counter()
            self._clock_dmc()

            for channel in range(2):
                if self._pulse_active(channel):
                    self.pulse_timer[channel] -= 1
                    if self.pulse_timer[channel] < 0:
                        self.pulse_timer[channel] = self.pulse_period[channel] + 1
                        self.pulse_step[channel] = (self.pulse_step[channel] + 1) & 0x07

            self.sample_accum += 1.0
            if self.sample_accum >= self.cycles_per_sample:
                self.sample_accum -= self.cycles_per_sample
                total = 0
                for channel in range(2):
                    if self._pulse_active(channel) and not self.pulse_sweep_mute[channel] and self.pulse_period[channel] >= 8 and self.pulse_period[channel] <= 0x7FF:
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
