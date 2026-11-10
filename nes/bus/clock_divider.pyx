'''
Master-clock divider for the 2A03 / 2C02 timing domains.

The console has one crystal. This module owns the single derived time base
(the PPU dot counter) and publishes the edges at which the CPU runs and
samples its interrupt lines. It holds no chip state: the CPU, PPU, APU and
DMA controller each keep their own phase and react to the edges as signals.

Ref: NESdev wiki "Clock rates"; NES reference guide (2A03 / 2C02 clocks).
'''

NTSC_PPU_DIVIDER = 4
NTSC_CPU_DIVIDER = 12
CPU_TICK_DOT = 1
PHI2_DOT = 2


cdef class ClockDivider:
    '''
    Single time base and edge generator for the console.

    State owned: the PPU dot counter, the CPU cycle count and the phase
    inside the current CPU cycle. Timing model: one advance() is one PPU
    dot; a CPU cycle spans cpu_divider / ppu_divider dots, the CPU is ticked
    on cpu_tick_dot, and its interrupt lines are sampled one dot later on
    phi2_dot. Neighbours read the cached edge flags as plain signals; no CPU,
    PPU or APU state lives here.

    NTSC divides the master clock by 4 for the PPU and by 12 for the CPU,
    giving 3 PPU dots per CPU cycle. PAL and Dendy use different ratios and
    do not have an integer dot count per CPU cycle; ppu_divider and
    cpu_divider are the single place to change for them. Those regions are
    deliberately not enabled: the ROM suite runs NTSC only.

    Ref: NESdev wiki "Clock rates"; NES reference guide (2A03 / 2C02 clocks).
    '''
    def __init__(self, ppu_divider=NTSC_PPU_DIVIDER,
                 cpu_divider=NTSC_CPU_DIVIDER):
        '''
        Bind the two clock ratios and start at power-up phase.

        Only the ratios belong to the divider; the phase offsets inside a
        CPU cycle stay fixed for the NTSC timing domain.
        '''
        self.ppu_divider = <uint32_t>ppu_divider
        self.cpu_divider = <uint32_t>cpu_divider
        self.dots_per_cpu_cycle = self.cpu_divider // self.ppu_divider
        self.cpu_tick_dot = CPU_TICK_DOT
        self.phi2_dot = PHI2_DOT
        self.reset()

    cdef void _update_edges(self):
        '''Recompute the cached edges from the current phase.

        Caching keeps the per-PPU-dot hot loop free of division and modulo:
        the divider advances once per dot and every consumer reads a flag.
        '''
        self.cpu_tick_edge = (self.phase == self.cpu_tick_dot)
        self.phi2_edge = (self.phase == self.phi2_dot)

    cdef void reset(self):
        '''Return the time base to the power-up phase.

        Dot 0 is the first PPU dot; the CPU tick and phi2 edges fall on dots
        1 and 2 of the first CPU cycle. Components that own their own phase
        are reset separately by CPUBus.reset / CPUBus.power_up.
        '''
        self.dot = 0
        self.cpu_cycle = 0
        self.phase = 0
        self._update_edges()

    cdef void advance(self):
        '''Advance one PPU dot and publish the new clock edges.

        cpu_cycle increments only when the phase wraps, matching the prior
        dot // 3 expression. Consumers see cpu_tick_edge and phi2_edge as
        signal lines rather than recomputing the phase themselves.
        '''
        self.dot += 1
        self.phase += 1
        if self.phase == self.dots_per_cpu_cycle:
            self.phase = 0
            self.cpu_cycle += 1
        self._update_edges()
