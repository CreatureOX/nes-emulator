'''Region timing profiles for the three NES video standards.

A region is selected from the cartridge header at load time and injected
into the clock divider, PPU and APU as configuration. The emulation
algorithms stay shared; only geometry and step tables change. PAL needs
3.2 PPU dots per CPU cycle, expressed as a 16-dot grid carrying 5 cycles.
Dendy keeps NTSC's 3-dot grid and APU step sequence but uses PAL's PPU
frame geometry with the NMI at scanline 291.

Ref: NESdev wiki "Clock rates", "NTSC video"; Mesen2 Core/NES
(NesConsole.cpp, NesPpu.cpp, APU/ApuFrameCounter.h).
'''

NTSC = 0
PAL = 1
DENDY = 2

# iNES header values.
_INES_PAL = 1
_INES_DENDY = 3


def region_from_header(header_bytes):
    '''Resolve a region from the 16-byte iNES/NES2 header.

    Dual-compatible headers fall back to NTSC, matching Mesen's Auto
    policy. NES2.0 flags 12 carries the authoritative timing mode when
    bit 2 of flags 7 marks the file as NES2.0.
    '''
    if len(header_bytes) < 16:
        return NTSC
    if (header_bytes[7] & 0x0C) == 0x08:
        timing = header_bytes[12] & 0x03
        if timing == 1:
            return PAL
        if timing == 3:
            return DENDY
        return NTSC
    if (header_bytes[10] & 0x03) == _INES_DENDY:
        return DENDY
    if (header_bytes[10] & 0x03) == 2 or (header_bytes[9] & 0x01) == _INES_PAL:
        return PAL
    return NTSC


class RegionSpec:
    '''Immutable timing and geometry profile for one video standard.'''

    def __init__(self, region):
        if region == PAL:
            self.name = 'PAL'
            self.divider_args = (5, 16, 16,
                                 (1 << 1) | (1 << 4) | (1 << 7) |
                                 (1 << 10) | (1 << 13),
                                 (1 << 2) | (1 << 5) | (1 << 8) |
                                 (1 << 11) | (1 << 14))
            self.cpu_rate = 1662607.0
            self.last_scanline = 311
            self.nmi_scanline = 241
            self.vblank_end = 310
            self.odd_frame_skip = False
            # Mesen2 APU/ApuFrameCounter.h _stepCyclesPal.
            self.frame_steps = (
                (8313, 16627, 24939, 33252, 33253, 33254),
                (8313, 16627, 24939, 33253, 41565, 41566),
            )
            # Mesen2 APU/DeltaModulationChannel.h _dmcPeriodLookupTablePal.
            self.dmc_rates = (398, 354, 316, 298, 276, 236, 210, 198,
                              176, 148, 132, 118, 98, 78, 66, 50)
            # Mesen2 APU/NoiseChannel.h _noisePeriodLookupTablePal.
            self.noise_periods = (4, 8, 14, 30, 60, 88, 118, 148,
                                  188, 236, 354, 472, 708, 944, 1890, 3778)
        elif region == DENDY:
            self.name = 'Dendy'
            self.divider_args = (5, 15, 3, 0b010, 0b100)
            self.cpu_rate = 1773448.0
            self.last_scanline = 311
            self.nmi_scanline = 291
            self.vblank_end = 310
            self.odd_frame_skip = False
            # Dendy's APU runs at NTSC timings (Mesen2 NesApu.cpp
            # GetApuRegion).
            self.frame_steps = RegionSpec(NTSC).frame_steps
            self.dmc_rates = RegionSpec(NTSC).dmc_rates
            self.noise_periods = RegionSpec(NTSC).noise_periods
        else:
            self.name = 'NTSC'
            self.divider_args = (4, 12, 3, 0b010, 0b100)
            self.cpu_rate = 1789772.5
            self.last_scanline = 261
            self.nmi_scanline = 241
            self.vblank_end = 260
            self.odd_frame_skip = True
            # Mesen2 APU/ApuFrameCounter.h _stepCyclesNtsc.
            self.frame_steps = (
                (7457, 14913, 22371, 29828, 29829, 29830),
                (7457, 14913, 22371, 29829, 37281, 37282),
            )
            # Mesen2 APU/DeltaModulationChannel.h _dmcPeriodLookupTableNtsc.
            self.dmc_rates = (428, 380, 340, 320, 286, 254, 226, 214,
                              190, 160, 142, 128, 106, 84, 72, 54)
            # Mesen2 APU/NoiseChannel.h _noisePeriodLookupTableNtsc.
            self.noise_periods = (4, 8, 16, 32, 64, 96, 128, 160,
                                  202, 254, 380, 508, 762, 1016, 2034, 4068)


_SPECS = {NTSC: RegionSpec(NTSC), PAL: RegionSpec(PAL), DENDY: RegionSpec(DENDY)}


def spec_for(region):
    '''Return the cached RegionSpec for a numeric region id.'''
    return _SPECS[region]
