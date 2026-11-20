'''
Master-clock divider for the 2A03 / 2C02 timing domains.

The console has one crystal. This module owns the single derived time base
(the PPU dot counter) and publishes the edges at which the CPU runs and
samples its interrupt lines. It holds no chip state: the CPU, PPU, APU and
DMA controller each keep their own phase and react to the edges as signals.

Each region is expressed as a repeating dot grid. NTSC uses 3 dots per CPU
cycle; PAL needs 3.2, published as a 16-dot grid carrying 5 CPU cycles.
The grid is expanded into a bit mask of tick dots and phi2 dots so the hot
loop needs no division or float accumulation.

Ref: NESdev wiki "Clock rates", "NTSC video"; NES reference guide
(2A03 / 2C02 clocks).
'''

from libc.stdint cimport uint32_t

NTSC_PPU_DIVIDER = 4
NTSC_CPU_DIVIDER = 12

# Dot grid length and edge masks. Bit i of a mask means "phase i publishes
# this edge". NTSC: 3 dots/cycle, CPU tick at dot 1, phi2 at dot 2.
NTSC_CYCLE_DOTS = 3
NTSC_TICK_MASK = 0b010
NTSC_PHI2_MASK = 0b100

# PAL: 16 master-tick units / 5 CPU cycles = 3.2 dots/cycle. Five CPU ticks
# fall on dots 1,4,7,10,13 and their phi2 samples one dot later at 2,5,8,11,14
# (gaps 3,3,3,3,4). Dendy keeps 3 dots/cycle like NTSC but with a /5 PPU
# divider; only its PPU frame geometry differs, so it reuses the NTSC masks.
PAL_CYCLE_DOTS = 16
PAL_TICK_MASK = (1 << 1) | (1 << 4) | (1 << 7) | (1 << 10) | (1 << 13)
PAL_PHI2_MASK = (1 << 2) | (1 << 5) | (1 << 8) | (1 << 11) | (1 << 14)


cdef class ClockDivider:
    '''
    Single time base and edge generator for the console.

    State owned: the PPU dot counter, the CPU cycle count and the phase
    inside the current dot grid. Timing model: one advance() is one PPU
    dot; the grid masks decide which chips see an edge. Neighbours read the
    cached edge flags as plain signals; no CPU, PPU or APU state lives here.

    The cycle grid, tick mask and phi2 mask are configuration, not state.
    state.pyx snapshots only dot/cycle/phase/edges and restores them in
    place, so switching regions between snapshots is safe as long as the
    console rebuilds the divider for the new region.

    Ref: NESdev wiki "Clock rates"; NES reference guide (2A03 / 2C02 clocks).
    '''
    def __init__(self, uint32_t ppu_divider=NTSC_PPU_DIVIDER,
                 uint32_t cpu_divider=NTSC_CPU_DIVIDER,
                 uint32_t cycle_dots=NTSC_CYCLE_DOTS,
                 uint32_t tick_mask=NTSC_TICK_MASK,
                 uint32_t phi2_mask=NTSC_PHI2_MASK):
        '''
        Bind the clock ratios and edge grid, then start at power-up phase.

        The masks are stored as integers so _update_edges() is two shifts
        per dot. Callers that need PAL or Dendy pass the region's grid via
        nes.region.RegionSpec.divider_args().
        '''
        self.ppu_divider = ppu_divider
        self.cpu_divider = cpu_divider
        self.cycle_dots = cycle_dots
        self.tick_mask = tick_mask
        self.phi2_mask = phi2_mask
        self.reset()

    cdef void _update_edges(self):
        '''Recompute the cached edges from the current grid phase.

        Caching keeps the per-PPU-dot hot loop free of division and modulo:
        the divider advances once per dot and every consumer reads a flag.
        '''
        self.cpu_tick_edge = ((self.tick_mask >> self.phase) & 1) != 0
        self.phi2_edge = ((self.phi2_mask >> self.phase) & 1) != 0

    cdef void reset(self):
        '''Return the time base to the power-up phase.

        Dot 0 is the first PPU dot; the CPU tick and phi2 edges fall on dots
        1 and 2 of the first cycle grid. Components that own their own phase
        are reset separately by CPUBus.reset / CPUBus.power_up.
        '''
        self.dot = 0
        self.cpu_cycle = 0
        self.phase = 0
        self._update_edges()

    cdef void advance(self):
        '''Advance one PPU dot and publish the new clock edges.

        cpu_cycle increments on each phi2 sample, which is one per CPU
        cycle in every region's grid. For NTSC this reproduces the old
        wrap-at-dot-3 value on every dot, not just on tick dots; the DMA
        controller reads cpu_cycle parity directly inside its transfer
        loop. Consumers see cpu_tick_edge and phi2_edge as signal lines
        rather than recomputing the phase themselves. The grid wraps at
        cycle_dots, which is 3 for NTSC/Dendy and 16 for PAL.
        '''
        self.dot += 1
        if self.phi2_edge:
            self.cpu_cycle += 1
        self.phase += 1
        if self.phase == self.cycle_dots:
            self.phase = 0
        self._update_edges()
