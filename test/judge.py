"""
Reliable blargg result judge -- reads the PPU nametable text via the $2007
port and prints a PASS/FAIL/#N verdict for each ROM, so we don't depend on
screenshot OCR.

IMPORTANT: runs through console.run() (== bus.run_frame() == the SAME path
the GUI uses). The old read_screen_text.py used console.frame() (legacy
path) which diverged in timing and gave false PASSED results.

Blargg renders text with a font whose tile index equals the ASCII code, so
the nametable bytes ARE the screen text. We try two decodings (raw and +0x20)
and pick whichever yields recognizable result keywords.

ROMs are described by test/regression.toml (id -> path/frames/detector).
The `path` is canonical inside the nes-test-roms submodule; if that file is
absent we fall back to a local failed/<basename>.nes copy so the suite still
runs before the submodule is initialised.

Usage (from repo root):
    python test/judge.py            # judge every active ROM in regression.toml
    python test/judge.py <id>       # single ROM (looked up in regression.toml)
    python test/judge.py <id> <N>   # single ROM, N frames
    python test/judge.py all <N>    # every active ROM, N frames
"""
import os
import sys
import re
import multiprocessing as mp

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - python < 3.11
    tomllib = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

FRAMES = 1200
SETTINGS = {"frames": FRAMES, "detector": "blargg"}


def _default_settings():
    return {"frames": FRAMES, "detector": "blargg"}


def load_regression():
    """Load test/regression.toml.

    Returns (settings dict, list of test entries). Missing file or missing
    tomllib degrades gracefully to an empty suite so the legacy
    `failed/<id>.nes` path still works.
    """
    if tomllib is None:
        return _default_settings(), []
    path = os.path.join(ROOT, "test", "regression.toml")
    if not os.path.exists(path):
        return _default_settings(), []
    with open(path, "rb") as f:
        cfg = tomllib.load(f)
    settings = dict(_default_settings(), **cfg.get("settings", {}))
    return settings, cfg.get("tests", [])


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


def resolve_rom(entry):
    """Return an existing ROM path for an entry, or None.

    Prefers the configured `path` (canonical = inside the nes-test-roms
    submodule); falls back to a local `failed/<basename>.nes` copy so the
    suite still runs before the submodule is initialised.
    """
    rel = entry.get("path", "")
    if rel:
        cand = os.path.join(ROOT, rel)
        if os.path.exists(cand):
            return cand
    base = os.path.basename(entry.get("path", entry["id"] + ".nes"))
    fb = os.path.join(ROOT, "failed", base)
    if os.path.exists(fb):
        return fb
    return None


def run_one(entry):
    """Run a single ROM entry and return a result dict.

    entry keys: id, path, frames (optional), detector (optional).
    Returns {id, verdict, detail, status, path}.
    """
    os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
    frames = int(entry.get("frames") or SETTINGS.get("frames", FRAMES))
    detector = entry.get("detector") or SETTINGS.get("detector", "blargg")
    rom = resolve_rom(entry)
    if rom is None:
        return {"id": entry["id"], "verdict": "MISSING",
                "detail": " ROM not found", "status": "--", "path": None}
    try:
        from nes.console import Console
        console = Console(rom)
        console.power_up()
        for f in range(frames):
            console.run()
            if f % 60 == 0:
                console.bus.apu.drain_samples()

        nt = read_nametable(console.bus)
        raw, off = decode(nt)
        verdict = "RUNNING/blank"
        detail = ""
        if detector == "blargg":
            blob = raw + "\n" + off
            low = blob.lower()
            if "pass" in low and "fail" not in low:
                verdict = "PASS"
            elif "fail" in low:
                verdict = "FAIL"
                m = re.search(r"fail(?:ed)?[^0-9]*#?\s*(\d+)", low)
                if m:
                    detail = f" #N={m.group(1)}"
                else:
                    idx = low.find("fail")
                    snippet = blob[max(0, idx - 20): idx + 30].replace("\n", " ")
                    detail = f" ({snippet.strip()})"
        status = console.bus.read(0x6000, True)
        return {"id": entry["id"], "verdict": verdict, "detail": detail,
                "status": f"0x{status:02X}", "path": rom}
    except Exception as e:
        return {"id": entry["id"], "verdict": "ERROR", "detail": f" {e!r}",
                "status": "--", "path": rom}


def normalize(entry):
    """Fill in default frames/detector so run_one has everything it needs."""
    e = dict(entry)
    e["frames"] = int(entry.get("frames") or SETTINGS.get("frames", FRAMES))
    e["detector"] = entry.get("detector") or SETTINGS.get("detector", "blargg")
    return e


def judge_one(args):
    """Pool-compatible wrapper: args = (entry_dict,)."""
    entry, = args
    return run_one(entry)


def _find_entry(tests, tag):
    for t in tests:
        if t.get("id") == tag:
            return t
    return None


def main(argv):
    global SETTINGS
    SETTINGS, tests = load_regression()
    active = [t for t in tests if t.get("expected") != "skip"]

    custom = None
    single = None
    if len(argv) > 1 and argv[1] != "all":
        single = argv[1]
        entry = _find_entry(tests, single)
        if entry is None:
            # legacy: build a synthetic entry from failed/<tag>.nes
            entry = {"id": single, "path": os.path.join("failed", f"{single}.nes"),
                     "expected": "skip"}
        jobs = [normalize(entry)]
        if len(argv) > 2:
            custom = int(argv[2])
            jobs[0]["frames"] = custom
    else:
        if len(argv) > 1 and argv[1] == "all" and len(argv) > 2:
            custom = int(argv[2])
        jobs = [normalize(t) for t in active]
        if custom is not None:
            for j in jobs:
                j["frames"] = custom

    if not jobs:
        print("No active ROMs configured in test/regression.toml.")
        return

    print(f"=== judge {len(jobs)} ROM(s) ===\n", flush=True)

    if len(jobs) == 1:
        results = [run_one(jobs[0])]
    else:
        jobs.sort(key=lambda j: -j["frames"])
        workers = min(len(jobs), mp.cpu_count())
        with mp.Pool(workers) as pool:
            results = []
            for r in pool.imap_unordered(judge_one, [(j,) for j in jobs]):
                print(f"  {r['id']:28s}  {r['verdict']}{r['detail']:14s}  $6000={r['status']}", flush=True)
                results.append(r)
        results.sort(key=lambda r: r["id"])
        n_pass = sum(1 for r in results if r["verdict"] == "PASS")
        print(f"\n=== {n_pass} PASS / {len(results) - n_pass} not-pass ===")
        return

    for r in results:
        print(f"  {r['id']:28s}  {r['verdict']}{r['detail']:14s}  $6000={r['status']}")
    print("\n=== done ===")


if __name__ == "__main__":
    mp.freeze_support()
    main(sys.argv)
