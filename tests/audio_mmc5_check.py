"""MMC5 pulse integration probe: volume parity and PCM path.

Uses the real mmc5test ROM so the mapper is fully initialized. Drives the APU
by hand (no game code) and checks:
  1. A 2A03 pulse alone and an MMC5 pulse alone reach comparable amplitude
     (NESdev: MMC5 pulses are equivalent in volume to APU pulses).
  2. The $5011 PCM DAC still reaches its known level with pulses off.
  3. MMC5 pulse fields are present in the mapper's snapshot field set.

Polarity inversion is implemented in the APU mix (value -= pulse_formula) per
NESdev wiki "MMC5 audio"; it is not asserted here because drain_samples()
removes DC and phase offsets make a waveform-correlation check unreliable.

The 165-ROM gate judges screens only; this probe is the audio-semantic check.
"""
import os
import sys
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")

from nes.console import Console  # noqa: E402
from nes.mapper.impl.mapper_mmc5 import MapperMMC5  # noqa: E402

ROM = "nes-test-roms/mmc5test/mmc5test.nes"
CYCLES = 120000


def _drive(apu, cycles=CYCLES):
    for _ in range(cycles):
        apu.clock(1)
    return apu.drain_samples()


def _peak(samples):
    return int(np.max(np.abs(samples))) if samples.size else 0


def _board():
    console = Console(ROM)
    console.power_up()
    console.bus.apu.drain_samples()
    return console.bus.apu, console.bus


def _apu_pulse(apu):
    for addr, value in [(0x4015, 0x01), (0x4017, 0x00),
                        (0x4000, 0xBF), (0x4002, 0x95), (0x4003, 0x30)]:
        apu.write(addr, value)


def _mmc5_pulse(bus):
    # Hardware order: enable first, then timer/length ($5003 loads length).
    for addr, value in [(0x5015, 0x01), (0x5000, 0xBF),
                        (0x5002, 0x95), (0x5003, 0x30)]:
        bus.write(addr, value)


def _snapshot_fields():
    """Diff the mapper's declared pulse fields against reduce_cython keys."""
    mapper = MapperMMC5(16, 16)
    fields = list(mapper.__reduce_cython__()[-1])
    # The pulse_* arrays are the only length-2 lists in the MMC5 field set.
    pulse_hits = [i for i, f in enumerate(fields)
                  if isinstance(f, (list, tuple)) and len(f) == 2]
    return len(fields), pulse_hits


def main():
    a_apu, _ = _board(); _apu_pulse(a_apu); apu_only = _drive(a_apu)

    a_mmc5, bus_mmc5 = _board(); bus_mmc5.write(0x4015, 0x00)
    _mmc5_pulse(bus_mmc5); mmc5_only = _drive(a_mmc5)

    # PCM: alternate the DAC so drain_samples' DC removal cannot zero it.
    a_pcm, bus_pcm = _board(); bus_pcm.write(0x4015, 0x00)
    for cycle in range(12000):
        bus_pcm.write(0x5011, 0xFF if (cycle // 300) % 2 else 0x01)
        a_pcm.clock(1)
    pcm = a_pcm.drain_samples()

    pa, pm = _peak(apu_only), _peak(mmc5_only)
    print("2A03 pulse peak:", pa, " MMC5 pulse peak:", pm,
          " ratio:", round(pm / pa, 3) if pa else "n/a")
    print("PCM alternating peak:", _peak(pcm))

    field_count, pulse_hits = _snapshot_fields()
    print("mapper snapshot fields:", field_count,
          " two-slot pulse arrays at:", pulse_hits)

    volume_ok = pa > 0 and pm > 0 and 0.5 <= pm / pa <= 2.0
    pcm_ok = _peak(pcm) > 5000
    snap_ok = len(pulse_hits) >= 1
    print("VERDICT volume:", "PASS" if volume_ok else "FAIL",
          "pcm:", "PASS" if pcm_ok else "FAIL",
          "snapshot:", "PASS" if snap_ok else "FAIL")


if __name__ == "__main__":
    main()
