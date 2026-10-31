"""Judge a test result -- both stages -- and never run the emulator.

Stage 1, screen -> verdict:
    classify_screen(raw, low, detector, entry, state) turns decoded nametable
    text into a raw verdict. The DETECTORS registry holds one fn per suite
    type; an unknown detector falls back to RUNNING/blank so a bad config can't
    crash the sweep. *entry* is the run entry (per-ROM configuration) and
    *state* is the runtime snapshot (currently the final CPU PC) -- both are
    passed through to the detectors that need them.

Stage 2, verdict -> pass/fail:
    judge_result(result) is the single place the pass/fail rule lives. It reads
    only `verdict` off the result; the launcher only runs must-pass entries, so
    any non-PASS verdict is a failure and it stays a pure function of result.

A run fails only when a must-pass test (expected="pass") does not PASS.

Zero project imports: this module only judges; rom_runner reads the screen
and calls classify_screen().
"""
import re

DEFAULT_DETECTOR = "blargg"
# Canonical default frame budget, owned here so the config layer (test_picker)
# and the executor (rom_runner) both read it from the single bottom layer
# instead of the executor importing the config layer.
DEFAULT_FRAMES = 1200
# Top-level dir -> detector; anything else falls back to DEFAULT_DETECTOR.
DETECTOR_BY_DIR = {"read_joy3": "joy3"}


def top_dir(rom_id):
    """Top-level (suite) directory of a ROM id: 'apu_reset' for both
    'apu_reset/works_immediately' and a bare 'apu_reset'."""
    return rom_id.split("/", 1)[0]


def detector_for(entry):
    """Which detector judges this entry: per-entry override, else the suite
    directory, else the global default."""
    top = top_dir(entry.get("id", ""))
    return entry.get("detector") or DETECTOR_BY_DIR.get(top) or DEFAULT_DETECTOR


def classify_screen(raw, low, detector, entry=None, state=None):
    """Turn decoded nametable text into a raw verdict. Unknown detector ->
    RUNNING/blank so a misconfigured suite can't wedge the sweep.

    *entry* is the run entry and *state* the runtime snapshot; both are
    passed through to the detectors that need them (the CRC detector reads
    its accepted checksums from the entry, the terminal-PC detector reads the
    final CPU PC from the state).
    """
    fn = DETECTORS.get(detector)
    if fn is None:
        return "RUNNING/blank", ""
    return fn(raw, low, entry, state)


def _blargg_verdict(raw, low, entry=None, state=None):
    # Multi-ROM suite: ends with "All tests complete"; "Errors: N" => fail.
    if "all tests complete" in low:
        if "error" in low:
            code = _first_int(low, r"errors?\s*:?\s*(\d+)")
            return "FAIL", (f" #N={code}" if code is not None else " (Errors)")
        return "PASSED", ""
    # Single-suite: "fail(ed)" => fail, whole-word "passed" => pass.
    # Whole-word only so "password"/"bypass" aren't misread.
    if "fail" in low:
        code = _first_int(low, r"fail(?:ed)?[^0-9]*#?\s*(\d+)")
        if code is not None:
            return "FAIL", f" #N={code}"
        idx = low.find("fail")
        return "FAIL", f" ({low[max(0, idx - 20): idx + 30].strip()})"
    if re.search(r"\bpassed\b", low):
        return "PASSED", ""
    # Bare leading "$NN" (tile 0x24='$'): code 1 => pass, >1 => that sub-test.
    # Start-anchored so prose hex like "$2007" isn't mistaken for a code.
    m = re.match(r"\s*\$\s*(\d{1,2})", raw)
    if m:
        code = int(m.group(1))
        return ("PASSED", "") if code == 1 else ("FAIL", f" #N={code}")
    return "RUNNING/blank", ""


def _joy3_verdict(raw, low, entry=None, state=None):
    # Yerrick controller tests.
    #
    # thorough_test prints "Passed" with no tally.
    #
    # count_errors / count_errors_fast print a TALLY ("Conflicts: N/1000" /
    # "Errors: N/1000"), not a verdict: the source says a conflict is benign
    # ("a conflict doesn't affect the result of read_joy, since it compensates
    # when this occurs"), and the ROM self-fails only through test_failed,
    # which prints "Failed". The tally measures how often a DMC sample-byte
    # DMA stole a controller bit, so its value follows the emulator's
    # bit-loss model -- it is NOT a pass criterion. A self-fail IS a failure;
    # the tally is reported so a change in it stays visible in the report.
    if re.search(r"\bfail(?:ed)?\b", raw.lower()):
        return "FAIL", ""
    m = re.search(r"(?:conflicts?|errors?)\s*:\s*(\d+)\s*/\s*1000", low)
    if m:
        return "PASSED", f" tally={m.group(1)}/1000"
    if re.search(r"\bpassed\b", low):
        return "PASSED", ""
    return "RUNNING/blank", ""


def _crc_verdict(raw, low, entry=None, state=None):
    """CRC-only ROMs: compare the printed checksum against the accepted set.

    blargg's dmc_dma_during_read4 prints the CRC-32 complement of its output
    and stops -- it never writes "Passed"/"Failed", so the blargg detector can
    only ever answer RUNNING/blank, no matter how correct the emulator is.
    The accepted checksums are ROM-specific, and a given test may legitimately
    produce more than one of them (the same output lands differently depending
    on the CPU/PPU phase at reset), so the allowed set is configured per entry
    as `crc = [...]`.

    The checksum is the last 8-hex-digit run on screen: the data lines are
    space-separated 2-digit groups, so only the checksum itself is
    contiguous. The screen is read as one flat stream (the nametable is
    decoded without row separators), so a checksum that straddles a row
    boundary is still contiguous.

    A missing checksum means the ROM never got that far -> RUNNING/blank, not
    FAIL: the emulator may simply need more frames.
    """
    allowed = _allowed_crcs(entry)
    if not allowed:
        return "RUNNING/blank", ""
    found = _last_crc(raw)
    if found is None:
        return "RUNNING/blank", ""
    if found in allowed:
        return "PASSED", ""
    return "FAIL", f" CRC={found} (want {'/'.join(sorted(allowed))})"


def _terminal_pc_verdict(raw, low, entry=None, state=None):
    """ROMs that report their result through the CPU, not the screen.

    blargg's dmc_tests draw nothing at all: on success they start the APU's
    success tone and park in a terminal `JMP self` loop; on failure they spin
    in a wait loop (`BIT $4015` / `BNE`). The screen is blank either way, so
    the verdict has to come from where the CPU ended up.

    The config names the address of the ROM's terminal `JMP self`
    (`pass_pc`). The CPU's final PC must fall inside that three-byte
    instruction -- the opcode fetch or either operand fetch -- which is the
    only way to observe "the ROM reached its success state". A ROM stuck in
    its failure wait loop never gets there, so it fails.
    """
    want = _pass_pc(entry)
    if want is None or not state:
        return "RUNNING/blank", ""
    pc = state.get("pc")
    if pc is None:
        return "RUNNING/blank", ""
    if want <= pc <= want + 2:
        return "PASSED", f" PC=${pc:04X}"
    return "FAIL", f" PC=${pc:04X} (want ${want:04X}..${want + 2:04X})"


def _pass_pc(entry):
    """The entry's pass_pc config as an int, or None when it is not set."""
    if not entry:
        return None
    raw = entry.get("pass_pc")
    if raw is None:
        return None
    text = str(raw).strip().upper().replace("$", "")
    try:
        return int(text, 16)
    except ValueError:
        return None


def _allowed_crcs(entry):
    """Normalise an entry's `crc` config into a set of uppercase hex strings.

    Accepts a single string or a list, so the config can spell "one
    checksum" and "several acceptable checksums" the same way.
    """
    if not entry:
        return set()
    raw = entry.get("crc")
    if not raw:
        return set()
    if isinstance(raw, str):
        raw = [raw]
    return {str(c).strip().upper() for c in raw if str(c).strip()}


def _last_crc(raw):
    """The last 8-hex-digit run in the screen text, or None."""
    hits = re.findall(r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{8}(?![0-9A-Fa-f])", raw)
    return hits[-1].upper() if hits else None


def _first_int(low, pattern):
    m = re.search(pattern, low)
    return int(m.group(1)) if m else None


# name -> verdict fn(raw, low, entry, state); unknown name -> RUNNING/blank
DETECTORS = {"blargg": _blargg_verdict, "joy3": _joy3_verdict,
             "crc": _crc_verdict, "terminal_pc": _terminal_pc_verdict}


def judge_result(result):
    """Compare one result against its expectation -> (label, is_bad).

    is_bad is what turns the run red. The launcher only runs must-pass
    (expected="pass") entries, so this only has to decide pass vs gate-fail.

    TIMEOUT/CRASH/ERROR count as real failures: a must-pass ROM that hangs,
    crashes or errors did not pass. The specific verdict is preserved as the
    label so the report stays perceptible instead of collapsing to a generic
    FAIL. They stay non-fatal to the *sweep* -- the watchdog only kills the
    offending worker, so the remaining ROMs still run.
    """
    v = result["verdict"]
    if v in ("TIMEOUT", "CRASH", "ERROR"):
        return v, True
    if v == "MISSING":
        return "FAIL_MISSING", True   # claimed pass but ROM can't be found
    return ("PASSED", False) if v == "PASSED" else ("GATEFAIL", True)
