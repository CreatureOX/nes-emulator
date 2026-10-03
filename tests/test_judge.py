"""Judge a test result -- both stages -- and never run the emulator.

Stage 1, screen -> verdict:
    classify_screen(raw, low, detector) turns decoded nametable text into a
    raw verdict. The DETECTORS registry holds one fn per suite type; an unknown
    detector falls back to RUNNING/blank so a bad config can't crash the sweep.

Stage 2, verdict -> pass/fail:
    judge_result(result) is the single place the pass/fail rule lives.
    It reads only `verdict` off the result and `expected` off the entry, so it
    stays a pure function of (result, entry).

A run fails only when a must-pass test (expected="pass") does not PASS.

Zero project imports: this module only judges; rom_runner reads the screen
and calls classify_screen().
"""
import re

DEFAULT_DETECTOR = "blargg"
# Top-level dir -> detector; anything else falls back to DEFAULT_DETECTOR.
DETECTOR_BY_DIR = {"read_joy3": "joy3"}

# name -> verdict fn(raw, low); unknown name -> RUNNING/blank (no crash).


def top_dir(rom_id):
    """Top-level (suite) directory of a ROM id: 'apu_reset' for both
    'apu_reset/works_immediately' and a bare 'apu_reset'."""
    return rom_id.split("/", 1)[0]


def detector_for(entry):
    """Which detector judges this entry: per-entry override, else the suite
    directory, else the global default."""
    top = top_dir(entry.get("id", ""))
    return entry.get("detector") or DETECTOR_BY_DIR.get(top) or DEFAULT_DETECTOR


def classify_screen(raw, low, detector):
    """Turn decoded nametable text into a raw verdict. Unknown detector ->
    RUNNING/blank so a misconfigured suite can't wedge the sweep."""
    fn = DETECTORS.get(detector)
    if fn is None:
        return "RUNNING/blank", ""
    return fn(raw, low)


def _blargg_verdict(raw, low):
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


def _joy3_verdict(raw, low):
    # Yerrick controller tests: pass iff conflicts/errors tally is 0/1000;
    # thorough_test prints "Passed" with no tally. Self-contained, so blargg
    # "errors: N" can't be misread.
    m = re.search(r"conflicts?\s*:\s*(\d+)\s*/\s*1000", low)
    if m:
        return _pass_if_zero(m.group(1))
    m = re.search(r"errors?\s*:\s*(\d+)\s*/\s*1000", low)
    if m:
        return _pass_if_zero(m.group(1))
    if re.search(r"\bpassed\b", low):
        return "PASSED", ""
    return "RUNNING/blank", ""


def _pass_if_zero(n):
    return ("PASSED", "") if n == "0" else ("FAIL", f" #N={n}")


def _first_int(low, pattern):
    m = re.search(pattern, low)
    return int(m.group(1)) if m else None


DETECTORS = {"blargg": _blargg_verdict, "joy3": _joy3_verdict}


def label_of(entry):
    """Short classification for --list: excluded:<reason> or the expectation."""
    if entry.get("excluded"):
        return "excluded:" + entry.get("reason", "?")
    return entry.get("expected", "skip")


def judge_result(result):
    """Compare one result against its expectation -> (label, is_bad).

    Only expected=pass entries are ever run (launcher filters the rest), so
    this only has to decide pass vs gate-fail. is_bad is what turns the run
    red. TIMEOUT/CRASH/ERROR are reported for visibility only -- never a
    self-check failure, so they must not turn the run red (the per-ROM
    watchdog produces them instead of wedging the sweep).
    """
    v = result["verdict"]
    if v in ("TIMEOUT", "CRASH", "ERROR"):
        return v, False
    if v == "MISSING":
        return "FAIL_MISSING", True   # claimed pass but ROM can't be found
    # expected == "pass" by construction
    return ("PASSED", False) if v == "PASSED" else ("GATEFAIL", True)
