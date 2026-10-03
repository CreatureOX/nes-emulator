"""Drive a test ROM and read its screen -- the pure executor.

blargg draws text in font tiles whose index == ASCII code, so nametable bytes
are the screen text -- decoded via $2007, no OCR. All runs go through
run_frames() (same console.run() path as the GUI), so reset injection and APU
draining never drift. Verdict classification lives in test_judge (the judge);
this module only runs the ROM and returns the raw nametable text for it.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import test_judge  # noqa: E402

# Frame-budget default. The canonical value lives in test_judge.DEFAULT_FRAMES
# (the bottom layer both this executor and the config layer read from); this is
# just the local alias. Detector selection lives in test_judge too -- chosen
# per-ROM by test_judge.detector_for (entry override > DETECTOR_BY_DIR > default),
# NOT via a settings dict, so there is no "detector" key here.
FRAMES = test_judge.DEFAULT_FRAMES
DEFAULT_SETTINGS = {"frames": FRAMES}

# Split-suite ROMs run one addressing mode per part and need far more emulated
# time than a normal suite. Keyed by full id so a same-basename ROM in another
# suite can never inherit this budget. Entries here are only consulted when
# launcher.toml pins no `frames` for that id (see prepare_run's priority).
PER_ROM_FRAMES = {
    "instr_test-v5/all_instrs": 5400,
}

POLL_EVERY = 10            # inspect nametable this often (frames) while polling
MAX_INJECTED_RESETS = 3    # guard against a ROM that loops on reset
RESET_PROMPT = "press reset"
RESET_WAIT_FRAMES = 180    # shell prints the prompt then waits ~120 frames
RESET_SUITES = {"apu_reset", "cpu_reset"}


def decode(rows_bytes):
    """Decode 960 nametable bytes into two text views (raw and +0x20)."""
    raw = "".join(chr(b) if 0x20 <= b < 0x7F else " " for b in rows_bytes)
    off = "".join(chr(b + 0x20) if 0 <= b + 0x20 < 0x7F else " " for b in rows_bytes)
    return raw, off


def read_nametable(bus):
    """Read nametable 0 ($2000) via $2007 -> 960 bytes.

    Disables rendering for the +1 increment and primes the PPU read buffer.
    DESTRUCTIVE: clears PPUMASK and moves VRAM addr; PPU state is private cdef
    and can't be snapshotted, so call only after the ROM finishes.
    """
    bus.write(0x2001, 0x00)          # disable rendering -> +1 increment
    bus.read(0x2002, False)          # reset $2005/$2006 address latch
    bus.write(0x2006, 0x20)          # VRAM addr high = $20
    bus.write(0x2006, 0x00)          # VRAM addr low  = $00  -> $2000
    bus.read(0x2007, False)          # prime buffer (returns stale, loads $2000)
    return [bus.read(0x2007, False) for _ in range(960)]


def resolve_rom(entry):
    """Existing ROM path for *entry*, or None.

    ROMs live in the nes-test-roms submodule. No fallback: a missing submodule
    must surface as MISSING, not test a stale copy.
    """
    rel = entry.get("path", "")
    if rel:
        cand = os.path.join(ROOT, rel)
        if os.path.exists(cand):
            return cand
    return None


def open_console(rom):
    """Load *rom* into a fresh Console and power it up."""
    from nes.console import Console
    console = Console(rom)
    console.power_up()
    return console


def run_frames(console, frames, poll=False):
    """Drive *console* up to *frames* frames; return resets injected.

    The only run loop, so every caller shares the APU drain and reset policy.
    poll=True inspects the screen every POLL_EVERY frames and injects a reset
    when the ROM is waiting on it; poll=False leaves the PPU untouched.
    """
    resets = 0
    prompt_since = None
    for f in range(frames):
        console.run()
        if f % 60 == 0:
            console.bus.apu.drain_samples()
        if not poll or f % POLL_EVERY != 0:
            continue
        raw, off = decode(read_nametable(console.bus))
        if RESET_PROMPT not in (raw + "\n" + off).lower() \
                or resets >= MAX_INJECTED_RESETS:
            continue
        if prompt_since is None:
            prompt_since = f
        # Sit on the prompt for the shell's full prepare window, then press.
        # Consecutive resets are thus spaced >= RESET_WAIT_FRAMES apart.
        if f - prompt_since >= RESET_WAIT_FRAMES:
            console.reset()
            resets += 1
            prompt_since = None
    return resets


def verdict_from_screen(console, detector):
    """Read the final nametable and let the judge classify it.

    Returns (verdict, detail). The classification itself lives in
    test_judge.classify_screen -- this module stays the executor.
    """
    raw, off = decode(read_nametable(console.bus))
    low = (raw + "\n" + off).lower()
    return test_judge.classify_screen(raw, low, detector)


def needs_reset(entry):
    """True for suites that halt on 'Press RESET' (apu_reset, cpu_reset)."""
    return test_judge.top_dir(entry.get("id", "")) in RESET_SUITES


def run_one(entry):
    """Run one ROM entry; return {id, verdict, detail, path}."""
    frames = int(entry.get("frames") or FRAMES)
    detector = test_judge.detector_for(entry)
    rom = resolve_rom(entry)
    if rom is None:
        return {"id": entry["id"], "verdict": "MISSING",
                "detail": " ROM not found", "path": None}
    try:
        console = open_console(rom)
        run_frames(console, frames, poll=False)
        verdict, detail = verdict_from_screen(console, detector)
        # Reset-waiting suites print nothing, so re-run with polling.
        if verdict == "RUNNING/blank" and needs_reset(entry):
            console = open_console(rom)
            budget = max(frames, RESET_WAIT_FRAMES * (MAX_INJECTED_RESETS + 1))
            resets = run_frames(console, budget, poll=True)
            verdict, detail = verdict_from_screen(console, detector)
            if resets:
                detail += f" [reset x{resets}]"
        return {"id": entry["id"], "verdict": verdict, "detail": detail,
                "path": rom}
    except Exception as e:
        # Re-raise programming errors (NameError/AttributeError/TypeError/...)
        # so direct/unittest callers fail loud with a full traceback. The pool
        # worker (launcher._run_one) catches them and folds them into an ERROR
        # verdict that carries the type + message + short traceback, so a
        # harness bug still surfaces in the report (not as a bare "worker
        # crashed") without wedging the sweep. Emulator/runtime faults (ROM
        # crashes, APU errors, IO) also become ERROR here.
        if isinstance(e, (NameError, AttributeError, TypeError,
                          ImportError, SyntaxError, IndentationError,
                          UnboundLocalError)):
            raise
        return {"id": entry["id"], "verdict": "ERROR", "detail": f" {e!r}",
                "path": rom}


def prepare_run(entry, settings=None):
    """Fill in default frames/detector so run_one has everything it needs.

    *settings* comes from launcher.toml's [settings] table. Priority for the
    frame budget, highest first: a per-entry `frames` (launcher.toml pins what
    it was verified at) > PER_ROM_FRAMES (split-suite needs) > settings.
    An optional `retry_frames` key (injected by the orchestrator, launcher)
    is honoured by the pool worker: a ROM that fails at a short budget is
    re-run once at that frame count to rule out a false failure.
    """
    s = settings or DEFAULT_SETTINGS
    e = dict(entry)
    e["frames"] = int(
        entry.get("frames")
        or PER_ROM_FRAMES.get(entry.get("id", ""))
        or s["frames"])
    return e
