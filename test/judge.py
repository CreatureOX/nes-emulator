"""
Reliable blargg result judge — reads PPU nametable text via the $2007 port
and prints a PASS/FAIL/#N verdict for each ROM, so we don't depend on
screenshot OCR.

IMPORTANT: runs through console.run() (== bus.run_frame() == the SAME path
the GUI uses). The old read_screen_text.py used console.frame() (legacy
path) which diverged in timing and gave false PASSED results.

Blargg renders text with a font whose tile index equals the ASCII code, so
the nametable bytes ARE the screen text. We try two decodings (raw and +0x20)
and pick whichever yields recognizable result keywords.

Runs the ROMs in parallel across processes -- serially the full sweep takes
~10 minutes, which is far too slow to sit through after every rebuild.

Usage (from repo root):
    python test/judge.py            # judge all ROMs
    python test/judge.py <name>     # single ROM
    python test/judge.py <name> <N> # single ROM, N frames
    python test/judge.py all <N>    # all ROMs, N frames
"""
import os
import sys
import glob
import multiprocessing as mp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

FRAMES = 1200
PER_ROM = {"official_only": 5400}


def decode(rows_bytes):
    """Decode a list of 960 nametable bytes into two candidate text views."""
    raw = "".join(chr(b) if 0x20 <= b < 0x7F else " " for b in rows_bytes)
    off = "".join(chr(b + 0x20) if 0 <= b + 0x20 < 0x7F else " " for b in rows_bytes)
    return raw, off


def read_nametable(bus):
    """Read nametable 0 ($2000..$23BF) via the $2007 port, returning 960 bytes.

    Disables rendering first so $2007 uses the +1 increment path, and primes
    the PPU data buffer so the first returned byte isn't stale.
    """
    bus.write(0x2001, 0x00)          # disable rendering -> +1 increment
    bus.read(0x2002, False)          # reset $2005/$2006 address latch
    bus.write(0x2006, 0x20)          # VRAM addr high = $20
    bus.write(0x2006, 0x00)          # VRAM addr low  = $00  -> $2000
    bus.read(0x2007, False)          # prime buffer (returns stale, loads $2000)
    return [bus.read(0x2007, False) for _ in range(960)]


def judge_one(args):
    """Run one ROM and return (tag, verdict, detail, status).

    Takes a single tuple so it can be handed straight to Pool.imap_unordered.
    """
    tag, frames = args
    os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
    sys.path.insert(0, ROOT)
    try:
        from nes.console import Console
        rom = os.path.join(ROOT, "failed", f"{tag}.nes")
        console = Console(rom)
        console.power_up()
        for f in range(frames):
            console.run()
            if f % 60 == 0:
                console.bus.apu.drain_samples()

        nt = read_nametable(console.bus)
        raw, off = decode(nt)
        # Merge both decodings into lines and look for result keywords.
        verdict = "RUNNING/blank"
        detail = ""
        blob = raw + "\n" + off
        low = blob.lower()
        if "pass" in low and "fail" not in low:
            verdict = "PASS"
        elif "fail" in low:
            verdict = "FAIL"
            # try to extract the failure number
            import re
            m = re.search(r"fail(?:ed)?[^0-9]*#?\s*(\d+)", low)
            if m:
                detail = f" #N={m.group(1)}"
            else:
                # capture a snippet around 'fail'
                idx = low.find("fail")
                snippet = blob[max(0, idx - 20): idx + 30].replace("\n", " ")
                detail = f" ({snippet.strip()})"
        status = console.bus.read(0x6000, True)
        return (tag, verdict, detail, f"0x{status:02X}")
    except Exception as e:
        return (tag, "ERROR", f" {e!r}", "--")


def main(argv):
    rom_dir = os.path.join(ROOT, "failed")
    roms = sorted(glob.glob(os.path.join(rom_dir, "*.nes")))
    names = [os.path.basename(r)[:-4] for r in roms]

    custom = None
    if len(argv) > 1 and argv[1] != "all":
        names = [argv[1]]
        custom = int(argv[2]) if len(argv) > 2 else None
    elif len(argv) > 2:
        custom = int(argv[2])

    jobs = [(tag, custom or PER_ROM.get(tag, FRAMES)) for tag in names]
    print(f"=== judge {len(jobs)} ROM(s) ===\n", flush=True)

    if len(jobs) == 1:
        results = [judge_one(jobs[0])]
    else:
        # The heavy ROMs dominate the wall clock, so start them first.
        jobs.sort(key=lambda j: -j[1])
        workers = min(len(jobs), mp.cpu_count())
        with mp.Pool(workers) as pool:
            results = []
            for r in pool.imap_unordered(judge_one, jobs):
                print(f"  {r[0]:28s}  {r[1]}{r[2]:14s}  $6000={r[3]}", flush=True)
                results.append(r)
        results.sort(key=lambda r: r[0])
        n_pass = sum(1 for r in results if r[1] == "PASS")
        print(f"\n=== {n_pass} PASS / {len(results) - n_pass} not-pass ===")
        return

    for r in results:
        print(f"  {r[0]:28s}  {r[1]}{r[2]:14s}  $6000={r[3]}")
    print("\n=== done ===")


if __name__ == "__main__":
    mp.freeze_support()
    main(sys.argv)
