"""
Blargg NES test ROM verifier — screenshot-based headless runner.

Runs ROMs in failed/*.nes for enough frames to let the test complete,
captures a screenshot, and the human reads PASS/FAIL directly from
the screen image (black background, white text).

Test ROM source: https://github.com/christopherpow/nes-test-roms

Usage (from repo root):
    python test/run_test.py              # run all ROMs (each in its own process)
    python test/run_test.py <name>       # single ROM by basename
    python test/run_test.py <name> <N>   # single ROM with N frames

Screenshots → test_artifacts/verify_shots/ (gitignored).
"""
import os
import sys
import time
import glob
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

# ── per-ROM frame counts ─────────────────────────────────────────────────
DEFAULT_FRAMES = 1200  # ~20s at 60 fps, generous for most tests
PER_ROM_FRAMES = {
    "official_only": 5400,  # 16-instruction serial test, ~90s
}
SHOT_DIR = os.path.join(ROOT, "test_artifacts", "verify_shots")


def run_one(rom_path: str, frames: int) -> str:
    """Run *rom_path* for *frames* frames, save screenshot, return path."""
    import numpy as np
    from PIL import Image
    from nes.console import Console

    tag = os.path.basename(rom_path)[:-4]
    console = Console(rom_path)
    console.power_up()

    t0 = time.time()
    for f in range(frames):
        # Use console.run() -> bus.run_frame(): the SAME path the real GUI
        # uses. (console.frame() is a separate legacy path; testing through
        # it previously diverged from what the user actually runs.)
        console.run()
        # Drain APU samples periodically to prevent unbounded list growth.
        if f % 60 == 0:
            console.bus.apu.drain_samples()
    elapsed = time.time() - t0

    # Capture final screen → PNG
    arr = np.array(console.bus.ppu.screen())
    os.makedirs(SHOT_DIR, exist_ok=True)
    out = os.path.join(SHOT_DIR, f"{tag}.png")
    Image.fromarray(arr).save(out)

    status = console.bus.read(0x6000, True)
    print(f"  {tag:28s}  frames={frames:>5d}  {elapsed:5.1f}s  "
          f"$6000=0x{status:02X}  ->  {out}")
    return out


def main(argv: list[str]) -> None:
    rom_dir = os.path.join(ROOT, "failed")
    all_roms = sorted(glob.glob(os.path.join(rom_dir, "*.nes")))
    if not all_roms:
        print(f"No .nes ROMs found under {rom_dir}")
        return

    custom_frames = None
    if len(argv) > 1:
        name = argv[1]
        if name.isdigit():
            custom_frames = int(name)
        else:
            if name.endswith(".nes"):
                name = name[:-4]
            all_roms = [r for r in all_roms if os.path.basename(r)[:-4] == name]
            if not all_roms:
                print(f"No ROM matching '{argv[1]}'")
                return
            if len(argv) > 2:
                custom_frames = int(argv[2])

    # Batch "all" mode: run each ROM in a separate subprocess to prevent
    # global state pollution across ROMs (e.g. Cython module globals).
    if len(all_roms) > 1:
        print(f"=== {len(all_roms)} ROM(s) → screenshots in "
              f"{os.path.relpath(SHOT_DIR, ROOT)}/ ===\n")
        total = 0
        t0 = time.time()
        py = sys.executable
        script = os.path.abspath(__file__)
        for rom in all_roms:
            tag = os.path.basename(rom)[:-4]
            frames = custom_frames or PER_ROM_FRAMES.get(tag, DEFAULT_FRAMES)
            # Run this single ROM in a subprocess
            cmd = [py, script, tag, str(frames)]
            result = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT)
            if result.returncode != 0:
                print(f"  {tag:28s}  ERROR rc={result.returncode}")
                if result.stderr:
                    for line in result.stderr.strip().splitlines()[:3]:
                        print(f"    {line}")
            else:
                print(result.stdout, end="")
            total += 1
        print(f"\nDone. {total} ROM(s) in {time.time() - t0:.0f}s. "
              f"Screenshots in {os.path.relpath(SHOT_DIR, ROOT)}/"
              f"\nRead the PNGs to verify PASS/FAIL.")
        return

    # Single-ROM mode (subprocess entry point or direct run)
    rom = all_roms[0]
    tag = os.path.basename(rom)[:-4]
    frames = custom_frames or PER_ROM_FRAMES.get(tag, DEFAULT_FRAMES)
    run_one(rom, frames)


if __name__ == "__main__":
    main(sys.argv)
