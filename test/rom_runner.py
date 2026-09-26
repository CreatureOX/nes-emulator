"""
Drive a single test ROM to completion and read its verdict off the screen.

The verdict is read from the PPU nametable via the $2007 port rather than by
OCR-ing a screenshot: blargg renders text with a font whose tile index equals
the ASCII code, so the nametable bytes ARE the screen text. Two decodings are
tried (raw and +0x20) and whichever yields recognizable result keywords wins.

IMPORTANT: everything runs through console.run() (== bus.run_frame() == the
SAME path the GUI uses). console.frame() is a separate legacy path that
diverges in timing and gives false PASSED results -- never judge through it.

This module owns the ONE implementation of "run a ROM for N frames". The
regression runner (test/regression_runner.py) goes through it, so the
reset-injection policy and the periodic APU drain cannot drift apart between
callers.

One blargg-shell behaviour is handled while a ROM is running:

* Some suites (apu_reset, cpu_reset) halt with "Press RESET" on screen and
  wait for the reset button forever -- they can never print a result on their
  own. When that prompt appears we wait RESET_WAIT_FRAMES and then call
  console.reset(), so the next phase of the test actually runs. Some ROMs
  legitimately need more than one reset (apu_reset/4017_written has three
  phases: power -> first reset -> second reset), so up to MAX_INJECTED_RESETS
  are served.
  NOTE: the shell also raises $6000=$81 to ask for a reset, but those ROMs
  carry no WRAM so the write never lands on this emulator -- screen text is
  the only signal that works here.

This module is a LIBRARY -- it exposes no CLI. The single CLI entry point:
    python test/regression_runner.py ...   # the suite
"""
import os
import sys
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

# Frame-budget defaults. These are the ONLY place the numbers are spelled
# out: test/suite.py imports them to build its own [settings] defaults, so
# changing them here changes every entry point at once.
FRAMES = 1200
DETECTOR = "blargg"
DEFAULT_SETTINGS = {"frames": FRAMES, "detector": DETECTOR}

# A few ROMs need far longer than the default budget to print anything.
# Measured: official_only is a 16-instruction serial test needing ~90s.
PER_ROM_FRAMES = {"official_only": 5400}

# How often (in frames) the nametable is inspected while a ROM is running, to
# look for the "Press RESET" prompt.
POLL_EVERY = 10
# Guard against a ROM that asks for reset in a loop.
MAX_INJECTED_RESETS = 3
RESET_PROMPT = "press reset"
# The shell contract (source/common/run_at_reset.s) is: print the prompt,
# delay_msec 1000 twice (~120 frames at 60 Hz), *then* hide the console and
# let the caller finish preparing -- cpu_reset/ram_after_reset fills its RAM
# pattern only after that, measured at frame ~140 with the prompt up at ~10.
# We read VRAM directly, so console_hide is invisible to us (it only clears
# PPUMASK, not the nametable) and the prompt text never appears to go away.
# Hence a single constant wait, generously above the shell's own 120 frames,
# before *every* reset -- no escalation needed.
RESET_WAIT_FRAMES = 180


def decode(rows_bytes):
    """Decode a list of 960 nametable bytes into two candidate text views."""
    raw = "".join(chr(b) if 0x20 <= b < 0x7F else " " for b in rows_bytes)
    off = "".join(chr(b + 0x20) if 0 <= b + 0x20 < 0x7F else " " for b in rows_bytes)
    return raw, off


def read_nametable(bus):
    """Read nametable 0 ($2000..$23BF) via the $2007 port, returning 960 bytes.

    Disables rendering first so $2007 uses the +1 increment path, and primes
    the PPU data buffer so the first returned byte isn't stale.

    DESTRUCTIVE: it clears PPUMASK and moves the VRAM address, and PPU state
    is private cdef that cannot be snapshotted from Python. Only call this
    once the ROM has finished running.
    """
    bus.write(0x2001, 0x00)          # disable rendering -> +1 increment
    bus.read(0x2002, False)          # reset $2005/$2006 address latch
    bus.write(0x2006, 0x20)          # VRAM addr high = $20
    bus.write(0x2006, 0x00)          # VRAM addr low  = $00  -> $2000
    bus.read(0x2007, False)          # prime buffer (returns stale, loads $2000)
    return [bus.read(0x2007, False) for _ in range(960)]


def resolve_rom(entry):
    """Return an existing ROM path for an entry, or None.

    ROMs live in the nes-test-roms submodule (`git submodule update --init`).
    There is intentionally no local fallback: a missing submodule should show
    up as MISSING rather than silently testing a stale copy.
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
    """Drive *console* for up to *frames* frames. Returns resets injected.

    This is the single implementation of the run loop. Every caller goes
    through it so the periodic APU drain and the reset-injection policy stay
    identical everywhere.

    poll=False is the clean path: no screen inspection at all, so the PPU is
    left untouched (read_nametable is destructive -- see its docstring).

    poll=True inspects the screen every POLL_EVERY frames, which perturbs the
    PPU but is the only way to serve a ROM that is waiting on the reset
    button.
    """
    resets = 0
    prompt_since = None
    for f in range(frames):
        console.run()
        if f % 60 == 0:
            console.bus.apu.drain_samples()
        if not poll:
            continue
        if f % POLL_EVERY != 0:
            continue
        raw, off = decode(read_nametable(console.bus))
        blob = (raw + "\n" + off).lower()
        if RESET_PROMPT not in blob:
            continue
        if resets >= MAX_INJECTED_RESETS:
            continue
        if prompt_since is None:
            prompt_since = f
        # Sit on the prompt for the shell's full prepare window, then press.
        # Consecutive resets are therefore spaced >= RESET_WAIT_FRAMES apart.
        if f - prompt_since >= RESET_WAIT_FRAMES:
            console.reset()
            resets += 1
            prompt_since = None
    return resets


def verdict_from_screen(console, detector):
    """Read the final screen and classify it. Returns (verdict, detail)."""
    raw, off = decode(read_nametable(console.bus))
    verdict, detail = "RUNNING/blank", ""
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
    return verdict, detail


def run_one(entry):
    """Run a single ROM entry and return a result dict.

    entry keys: id, path, frames (optional), detector (optional).
    Returns {id, verdict, detail, status, path}.
    """
    os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
    frames = int(entry.get("frames") or FRAMES)
    detector = entry.get("detector") or DEFAULT_SETTINGS["detector"]
    rom = resolve_rom(entry)
    if rom is None:
        return {"id": entry["id"], "verdict": "MISSING",
                "detail": " ROM not found", "status": "--", "path": None}
    try:
        console = open_console(rom)
        run_frames(console, frames, poll=False)
        verdict, detail = verdict_from_screen(console, detector)

        # A ROM that produced nothing may be blocked on "Press RESET". Re-run
        # it with screen polling on: that perturbs the PPU, but pass 1 already
        # established that the clean path yields no result anyway.
        if verdict == "RUNNING/blank" and detector == "blargg":
            console = open_console(rom)
            # The configured budget is often the ~60 frames a well-behaved ROM
            # needs; a ROM waiting for reset also needs the prepare window
            # before each of its resets, so give this pass room to breathe.
            budget = max(frames,
                         RESET_WAIT_FRAMES * (MAX_INJECTED_RESETS + 1))
            resets = run_frames(console, budget, poll=True)
            verdict, detail = verdict_from_screen(console, detector)
            if resets:
                detail += f" [reset x{resets}]"
        status = console.bus.read(0x6000, True)
        return {"id": entry["id"], "verdict": verdict, "detail": detail,
                "status": f"0x{status:02X}", "path": rom}
    except Exception as e:
        return {"id": entry["id"], "verdict": "ERROR", "detail": f" {e!r}",
                "status": "--", "path": rom}


def normalize(entry, settings=None):
    """Fill in default frames/detector so run_one has everything it needs.

    *settings* comes from the [settings] table of regression.toml (see
    suite.load_settings) and takes effect here; a per-entry value wins over
    it, and PER_ROM_FRAMES wins over both.
    """
    s = settings or DEFAULT_SETTINGS
    e = dict(entry)
    e["frames"] = int(
        entry.get("frames")
        or PER_ROM_FRAMES.get(os.path.basename(entry.get("id", "")))
        or s.get("frames", FRAMES))
    e["detector"] = entry.get("detector") or s.get("detector", "blargg")
    return e
