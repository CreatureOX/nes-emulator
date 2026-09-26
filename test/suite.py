"""
Assemble the regression suite: read the curated config, overlay it on the
automatic scan, and say what an entry means.

This is the definition layer and the home of all `expected` / `basis`
semantics: gated() decides whether an entry may fail a run, evaluate() decides
what its outcome means, tag() classifies it for listing. Those three are kept
together on purpose -- splitting them means every change to the gating rule
has to be made twice.

This is the definition layer. It owns no ROM knowledge -- finding and
classifying ROMs is test/discovery.py's job, and this module only consumes
its scan() output. Likewise it owns no execution -- test/rom_runner.py drives
ROMs and test/regression_runner.py orchestrates them.

Two feeds are merged, with the hand-curated one winning:

  * test/regression.toml  -- human judgement, always wins
  * discovery.scan()      -- automatic scan of nes-test-roms/

so an empty config still runs every ROM that looks like a test.

Gating is the other half of the job: an expectation gates only when it is
authoritative, i.e. the entry carries no `basis`. `basis` marks an
expectation we have not confirmed on this build ("assumed", or a real-hardware
claim never run here). Those entries are run and reported but never allowed to
fail the run -- otherwise the first full sweep would be permanently red.
Removing `basis` by hand after confirming a ROM passes is the intended
promotion; there is deliberately no automatic write-back, since recording a
FAIL would cement the bug as an expectation.

Usage (bootstrap only -- the suite scans at run time, so this is NOT needed
for normal use):
    python test/suite.py                 # report what the suite looks like
    python test/suite.py --write-config  # rewrite test/regression.toml
"""
import os
import sys

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - python < 3.11
    tomllib = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import discovery  # noqa: E402
import rom_runner  # noqa: E402

CONFIG_PATH = os.path.join(ROOT, "test", "regression.toml")

# The defaults belong to the code that consumes them: rom_runner owns the
# frame budget and the detector, so borrowing its values keeps "1200 frames"
# and "blargg" defined exactly once in the whole test tree.
DEFAULT_FRAMES = rom_runner.FRAMES
DEFAULT_DETECTOR = rom_runner.DETECTOR

CONFIG_HEADER = '''# NES emulator regression suite configuration.
#
# Consumed by test/regression_runner.py. ROMs that are not listed here are
# still discovered automatically by scanning the nes-test-roms submodule
# (see test/discovery.py) -- an empty config therefore means "run everything
# that looks like a test". Entries listed here override the discovered values
# and are the place to record human judgement.
#
# [settings]
#   frames   : frame count used when a test supplies none
#   detector : default detector -- "blargg" reads the nametable PASS/FAIL text
#
# [[tests]]
#   id       : submodule-relative ROM path minus the .nes extension. This is
#              the ONLY key; it stays unique even for the 31 ROM basenames
#              that collide across suites (instr_test-v3 vs nes_instr_test,
#              blargg_apu_2005.07.30 vs pal_apu_tests, ...).
#              There is no `path` field: the location is derived from the id
#              at run time (test/discovery.py:path_of), so the two can never
#              disagree. Run reports print the full path.
#   frames   : optional frame budget. Listed tests pin the count they were
#              verified at; discovered ones use test_roms.xml's runframes
#              (often 60 -- measured ~17x cheaper than the 1200 default).
#   expected : "pass" | "fail" | "skip"
#   basis    : OPTIONAL, and its presence means "this expectation is NOT yet
#              confirmed on this build". Such a test is run and reported but
#              never allowed to fail the run. Values:
#                "assumed"  -- no source; we merely assume it should pass
#                "hardware" -- upstream readme claims real-hardware pass, but
#                              we have never run it here
#              To promote a test to real gating, confirm it passes and DELETE
#              the basis line. There is no automatic write-back on purpose:
#              recording a FAIL would cement the bug as an expectation.
#   note     : optional free text
#
# There is deliberately no "reference" field. test_roms.xml's `testresult`
# records what OTHER emulators do, and treating it as an expectation is
# exactly how ppu_vbl_nmi/10-even_odd_timing came to be mislabelled
# expected=fail (it passes here). Cross-emulator results belong in `note`.

[settings]
frames = %d
detector = "%s"
''' % (DEFAULT_FRAMES, DEFAULT_DETECTOR)


def _default_settings():
    return {"frames": DEFAULT_FRAMES, "detector": DEFAULT_DETECTOR}


def load_regression():
    """Load test/regression.toml.

    Returns (settings dict, list of test entries). Missing file or missing
    tomllib degrades gracefully to an empty suite.
    """
    if tomllib is None:
        return _default_settings(), []
    if not os.path.exists(CONFIG_PATH):
        return _default_settings(), []
    with open(CONFIG_PATH, "rb") as f:
        cfg = tomllib.load(f)
    settings = dict(_default_settings(), **cfg.get("settings", {}))
    return settings, cfg.get("tests", [])


def load_settings():
    """Just the [settings] table."""
    return load_regression()[0]


def render_toml(entries):
    """Render suite entries as the text of regression.toml."""

    def esc(value):
        return str(value).replace("\\", "\\\\").replace('"', '\\"')

    lines = [CONFIG_HEADER]
    for e in entries:
        lines.append("[[tests]]")
        lines.append('id = "%s"' % esc(e["id"]))
        if e.get("frames"):
            lines.append("frames = %d" % int(e["frames"]))
        lines.append('expected = "%s"' % esc(e.get("expected", "skip")))
        if e.get("basis"):
            lines.append('basis = "%s"' % esc(e["basis"]))
        if e.get("note"):
            lines.append('note = "%s"' % esc(e["note"]))
        lines.append("")
    return "\n".join(lines) + "\n"


def merge(configured, discovered):
    """Overlay configuration entries onto discovered ones, keyed by id.

    Configuration always wins: it is the human-curated record. A configured
    entry for a ROM that discovery excluded is still honoured, since the
    human may know better than our heuristics.
    """
    by_id = {d["id"]: d for d in discovered}
    merged = []
    for c in configured:
        base = by_id.pop(c["id"], None)
        if base is None:
            merged.append(dict(c))
            continue
        e = dict(base)
        e.update(c)
        # Absence of `basis` in the config is meaningful: it means the human
        # has confirmed this expectation. Without this pop the discovered
        # "assumed"/"hardware" marker would survive the overlay and silently
        # demote a confirmed test back to observed-only.
        if "basis" not in c:
            e.pop("basis", None)
        merged.append(e)
    merged.extend(by_id.values())
    merged.sort(key=lambda e: e["id"])

    # regression.toml carries no `path`, so config-only entries (an id we
    # could not discover, e.g. the submodule is not checked out) arrive here
    # without one. Fill it from the id so every downstream consumer sees a
    # complete entry; an unresolvable id keeps a plausible path and simply
    # reports MISSING at run time.
    for e in merged:
        if not e.get("path"):
            e["path"] = (discovery.path_of(e["id"])
                         or "nes-test-roms/%s.nes" % e["id"])
    return merged


def gated(entry):
    """True when this entry participates in pass/fail gating.

    An expectation is gated only when it is authoritative -- i.e. it carries
    no `basis`. `basis` marks an expectation we have not confirmed on this
    build yet (pure guess, or real-hardware claim never run here), so those
    entries are observed but never allowed to fail the run.
    """
    return entry.get("expected") == "pass" and not entry.get("basis")


def tag(entry):
    """Short classification for listing: gated / basis / excluded / expected."""
    if entry.get("excluded"):
        return "excluded:" + entry.get("reason", "?")
    basis = entry.get("basis")
    if basis:
        return basis
    return ("gated" if entry.get("expected") == "pass"
            else entry.get("expected", "skip"))


def evaluate(result, entry):
    """Compare one result against its expectation. Returns (label, is_bad).

    Lives here rather than in regression_runner because it is the other half
    of gated(): gated() decides *whether* an entry may fail the run, this
    decides *what* an entry's outcome means. Both read the same `expected` /
    `basis` pair, so keeping them apart means a change to the gating rule has
    to be made twice.
    """
    v = result["verdict"]
    if v == "TIMEOUT":
        # A ROM the runner could not bound -- reported for visibility, never a
        # regression. Produced only by regression_runner's local --timeout
        # guard (CI pre-excludes known hangs instead), so it must not turn a
        # run red.
        return "TIMEOUT", False
    basis = entry.get("basis")
    expected = entry.get("expected", "skip")

    if basis:
        # Unconfirmed expectation: report what happened, never fail the run.
        return "OBSERVE_" + v.replace("/", "_").replace(" ", "_"), False

    if v == "MISSING":
        if expected == "pass":
            return "FAIL_MISSING", True   # claimed pass but ROM can't be found
        return "MISSING", False
    if expected == "pass":
        return ("PASS", False) if v == "PASS" else ("REGRESSION", True)
    if expected == "fail":
        if v == "PASS":
            return "UNEXPECTED_PASS", False   # improved -- good news
        if v == "FAIL":
            return "EXPECTED_FAIL", False
        return "UNCONFIRMED_FAIL", True       # error/running -> can't confirm
    return f"SKIP->{v}", False


def build():
    """The whole suite: (settings, merged entries)."""
    settings, configured = load_regression()
    return settings, merge(configured, discovery.scan())


def main(argv):
    """Report the suite, or rewrite regression.toml with --write-config.

    This is a bootstrap aid, not part of the normal workflow: the suite is
    discovered at run time, so the config only needs regenerating when you
    want every entry spelled out for hand-editing.
    """
    write = "--write-config" in argv

    discovered = discovery.scan()
    if not discovered:
        print("No ROMs found under nes-test-roms/.")
        print("Run `git submodule update --init` first, then retry.")
        return 1

    _, configured = load_regression()
    merged = merge(configured, discovered)

    # Only list entries worth editing: excluded ROMs are filtered out at run
    # time anyway and would just be noise in the file.
    keep = [e for e in merged if not e.get("excluded")]

    n_gated = sum(1 for e in keep if gated(e))
    hardware = sum(1 for e in keep if e.get("basis") == "hardware")
    assumed = sum(1 for e in keep if e.get("basis") == "assumed")

    print("discovered : %d" % len(discovered))
    print("excluded   : %d" % (len(merged) - len(keep)))
    reasons = {}
    for e in merged:
        if e.get("excluded"):
            reason = e.get("reason", "?")
            reasons[reason] = reasons.get(reason, 0) + 1
    for reason in sorted(reasons):
        print("    %-14s %d" % (reason, reasons[reason]))
    print("listed     : %d" % len(keep))
    print("    gated    %d  (no basis -- confirmed, fails the run)" % n_gated)
    print("    hardware %d  (observed only)" % hardware)
    print("    assumed  %d  (observed only)" % assumed)

    if not write:
        print("\n(dry run -- pass --write-config to rewrite %s)" % CONFIG_PATH)
        return 0

    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        f.write(render_toml(keep))
    print("\nwrote %s (%d entries)" % (CONFIG_PATH, len(keep)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
