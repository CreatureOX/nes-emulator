"""Audio golden regression: deterministic stimuli, sample-by-sample hashes.

The 165-ROM gate judges screens only; it cannot see audio. This harness drives
the APU directly with a synthetic mapper-0 cartridge (no ROM file, no game
code), so each stimulus depends only on the APU register writes and CPU-cycle
count. Results are compared as SHA-256 digests of the full int16 sample stream
-- a single changed sample fails the case.

Usage:
    python tests/audio_golden.py            # compare against baseline
    python tests/audio_golden.py --record   # re-record baseline (review diff!)

Baseline lives in tests/audio_golden_baseline.json. Re-recording is an explicit
act: the operator must diff the JSON and confirm each change is intended.
"""
import os
import sys
import json
import hashlib
import argparse
import tempfile
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")

from nes.console import Console  # noqa: E402

BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "audio_golden_baseline.json")
MMC5_ROM = os.path.join(ROOT, "nes-test-roms", "mmc5test", "mmc5test.nes")

# Minimal iNES: mapper 0, 1x16KB PRG, 1x8KB CHR, horizontal mirror. No game
# code runs -- the console is powered up then the APU is driven by hand.
INES = (b"NES\x1a" + bytes([1, 1, 0x01, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0]))
CYCLES = 120000  # ~2.7 s of samples per stimulus

# Each stimulus: APU register writes applied after power_up, then CYCLES cycles.
# $4015 enables pulse channels; $4017 selects the 4-step frame counter.
ENABLE = [(0x4015, 0x03), (0x4017, 0x00)]
STIMULI = {
    "silence": [],
    "pulse1_duty12_const": [(0x4000, 0x1F), (0x4002, 0x95), (0x4003, 0x30)],
    "pulse1_duty25_const": [(0x4000, 0x7F), (0x4002, 0x95), (0x4003, 0x30)],
    "pulse1_duty50_const": [(0x4000, 0xBF), (0x4002, 0x95), (0x4003, 0x30)],
    "pulse1_duty75_const": [(0x4000, 0xFF), (0x4002, 0x95), (0x4003, 0x30)],
    "pulse2_duty50_const": [(0x4004, 0xBF), (0x4006, 0x40), (0x4007, 0x08)],
    "pulse1_env_decay": [(0x4000, 0xA8), (0x4002, 0x95), (0x4003, 0xF8)],
    "both_pulses": [(0x4000, 0xBF), (0x4002, 0x95), (0x4003, 0x30),
                    (0x4004, 0x3F), (0x4006, 0x40), (0x4007, 0x08)],
    "frame_irq_mode": [(0x4000, 0x1F), (0x4002, 0x95), (0x4003, 0x30),
                       (0x4017, 0x80)],
}


# MMC5 expansion audio, driven on the real mmc5test ROM (the mapper must be
# fully initialized). Writes go through the bus because $5000-$5015 are
# mapper registers. 2A03 is silenced so these isolate MMC5 output.
MMC5_STIMULI = {
    "mmc5_pulse_duty50": [(0x5015, 0x01), (0x5000, 0xBF),
                          (0x5002, 0x95), (0x5003, 0x30)],
    "mmc5_pulse_both": [(0x5015, 0x03),
                        (0x5000, 0xBF), (0x5002, 0x95), (0x5003, 0x30),
                        (0x5004, 0x7F), (0x5006, 0x40), (0x5007, 0xF8)],
    "mmc5_pcm_alt": [("pcm_alt", None)],  # alternating DAC, see runner
}


def _run_stimulus(rom_path, writes):
    console = Console(rom_path)
    console.power_up()
    apu = console.bus.apu
    apu.drain_samples()  # discard any power-up residue
    for addr, value in ENABLE + list(writes):
        apu.write(addr, value)
    for _ in range(CYCLES):
        apu.clock(1)
    samples = apu.drain_samples()
    return np.ascontiguousarray(samples, dtype=np.int16)


def _run_mmc5_stimulus(writes):
    console = Console(MMC5_ROM)
    console.power_up()
    bus, apu = console.bus, console.bus.apu
    apu.drain_samples()
    bus.write(0x4015, 0x00)  # silence 2A03; isolate expansion audio
    for item in writes:
        if isinstance(item[0], str):  # alternating PCM DAC
            for cycle in range(CYCLES):
                bus.write(0x5011, 0xFF if (cycle // 300) % 2 else 0x01)
                apu.clock(1)
            samples = apu.drain_samples()
            return np.ascontiguousarray(samples, dtype=np.int16)
        bus.write(*item)
    for _ in range(CYCLES):
        apu.clock(1)
    samples = apu.drain_samples()
    return np.ascontiguousarray(samples, dtype=np.int16)


def _digest(samples):
    return hashlib.sha256(samples.tobytes()).hexdigest()


def _summarize(samples):
    return {
        "count": int(samples.size),
        "hash": _digest(samples),
        "min": int(samples.min()) if samples.size else 0,
        "max": int(samples.max()) if samples.size else 0,
        "sum": int(samples.sum()) if samples.size else 0,
    }


def collect():
    """Run every stimulus (2A03 on synthetic ROM, MMC5 on the test ROM)."""
    result = {}
    fd, path = tempfile.mkstemp(suffix=".nes")
    os.write(fd, INES + bytes(16 * 1024) + bytes(8 * 1024))
    os.close(fd)
    try:
        for name, writes in STIMULI.items():
            result[name] = _summarize(_run_stimulus(path, writes))
    finally:
        os.remove(path)
    if os.path.exists(MMC5_ROM):
        for name, writes in MMC5_STIMULI.items():
            result[name] = _summarize(_run_mmc5_stimulus(writes))
    else:
        print("Note: mmc5test ROM absent, skipping MMC5 stimuli.",
              file=sys.stderr)
    return result


def record():
    """Record a fresh baseline. Review the diff before committing."""
    result = collect()
    with open(BASELINE, "w", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("Recorded", len(result), "stimuli ->", BASELINE)
    for name in sorted(result):
        print(" ", name, result[name]["hash"][:16])


def compare():
    """Compare current output against the recorded baseline, sample-exact."""
    if not os.path.exists(BASELINE):
        print("No baseline; run with --record first.", file=sys.stderr)
        return 1
    with open(BASELINE, encoding="utf-8") as handle:
        expected = json.load(handle)

    result = collect()
    names = sorted(set(expected) & set(result))
    failed = []
    for name in names:
        got, want = result[name], expected[name]
        if got["hash"] != want["hash"] or got["count"] != want["count"]:
            failed.append(name)
            print("FAIL", name,
                  "hash", got["hash"][:16], "!=", want["hash"][:16],
                  "count", got["count"], "!=", want["count"])
        else:
            print("PASS", name, got["hash"][:16], "samples", got["count"])
    for name in sorted(set(expected) - set(result)):
        failed.append(name)
        print("FAIL", name, "stimulus did not run (missing ROM?)")
    print("\n{} passed, {} failed".format(len(names) - len(failed), len(failed)))
    return 1 if failed else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--record", action="store_true",
                        help="re-record baseline (review the JSON diff!)")
    args = parser.parse_args()
    sys.exit(record() if args.record else compare())
