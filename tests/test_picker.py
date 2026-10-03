"""Pick which tests to run: merge the curated config over the scanner's list.

Owns launcher.toml (read + render) and the merge that turns scan records into
runnable entries. It does not judge results -- that is test_judge.py's single
rule -- and it does not run anything (rom_runner.py / launcher.py).

Curated launcher.toml always wins over rom_scanner.scan_all(); an empty config
still runs every ROM that looks like a test. Every runnable ROM is expected to
pass; non-PASSED fails the run. Excluded ROMs are never run.
"""
import os
import sys

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - python < 3.11
    tomllib = None

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rom_scanner  # noqa: E402
import test_judge  # noqa: E402

CONFIG_PATH = os.path.join(ROOT, "tests", "launcher.toml")

CONFIG_HEADER = '''# NES emulator self-check suite configuration.
#
# Consumed by tests/launcher.py. ROMs not listed here are still scanned
# automatically by rom_scanner (tests/rom_scanner.py) -- an empty
# config means "run everything that looks like a test". Listed entries
# override scanned values and record human judgement.
#
# [settings]
#   frames   : frame count used when a test supplies none
#
# [[tests]]
#   id       : submodule-relative ROM path minus .nes -- the ONLY key. It stays
#              unique even where basenames collide across suites. No `path` field:
#              the location is derived from the id at run time
#              (rom_scanner.path_of), so the two can never disagree. Run
#              reports print the full path.
#   frames   : optional frame budget, in NES frames. Listed tests pin the
#              count they were verified at; discovered ones use
#              test_roms.xml's `runframes`, falling back to
#              [settings].frames when the XML omits it.
#   detector : optional per-ROM judge override. "blargg" (default) reads the
#              nametable PASS/FAIL text; "joy3" is the read_joy3 tally
#              (N/1000, 0 = pass). Omit to use the suite default
#              (test_judge.DETECTOR_BY_DIR, else "blargg"). This per-ROM knob
#              is the ONLY detector setting -- there is deliberately no global
#              [settings] detector (nothing consumed it); don't reintroduce one.
#   expected : "pass" -- the only meaningful value. Every kept ROM is gated: a
#              non-PASS verdict fails the run. Do NOT use "skip"/"fail" to keep
#              a ROM out of the red line -- those silently drop it (never run)
#              WITHOUT listing it in the report's Ignored section. To not run a
#              ROM, use excluded = true below.
#   excluded : true -> the ROM is NOT run and NOT gated, and it is listed in the
#              report's Ignored section with its reason. This is the ONLY
#              "don't run this ROM" switch (document a hang / interactive /
#              known-fail, or keep a suite out of the sweep). Prefer it over any
#              expected value so nothing ever disappears silently.
#   reason   : required alongside excluded -- a short code + free text saying
#              why it isn't gated (e.g. "hang", "interactive", "known-fail").
#              Shown in the report's Ignored section; without it the exclusion
#              is undocumented.
#   note     : optional free text
#
# No "reference" field on purpose: test_roms.xml's `testresult` records what
# OTHER emulators do, and trusting it once mislabelled a ROM that actually
# passes here as expected=fail. Cross-emulator results belong in `note`.

[settings]
frames = %d
''' % (test_judge.DEFAULT_FRAMES,)


def _default_settings():
    # Single source: test_judge owns the canonical frame default; build a fresh
    # dict so callers can't mutate the shared one. No dependency on the executor
    # layer (rom_runner) -- the config layer stays above only rom_scanner/judge.
    # No "detector" key on purpose: nothing consumed settings["detector"], so a
    # global detector looked editable but did nothing. Per-ROM `detector` (read
    # by test_judge.detector_for) is the only detector knob.
    return {"frames": test_judge.DEFAULT_FRAMES}


def load_check_config():
    """Load tests/launcher.toml.

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


def render_toml(entries):
    """Render suite entries as the text of launcher.toml."""

    def esc(value):
        return str(value).replace("\\", "\\\\").replace('"', '\\"')

    lines = [CONFIG_HEADER]
    for e in entries:
        lines.append("[[tests]]")
        lines.append('id = "%s"' % esc(e["id"]))
        det = e.get("detector")
        if det and det != test_judge.DEFAULT_DETECTOR:
            lines.append('detector = "%s"' % esc(det))
        if e.get("frames"):
            lines.append("frames = %d" % int(e["frames"]))
        if e.get("excluded"):
            # excluded=true alone decides "don't run"; an expected value would
            # be dead (the launcher filters excluded before it reads expected)
            # and double-writing both is what created the old drift.
            lines.append("excluded = true")
            if e.get("reason"):
                lines.append('reason = "%s"' % esc(e["reason"]))
        else:
            lines.append('expected = "%s"' % esc(e.get("expected", "pass")))
        if e.get("note"):
            lines.append('note = "%s"' % esc(e["note"]))
        lines.append("")
    return "\n".join(lines) + "\n"


def apply_config(configured, discovered):
    """Overlay config entries onto discovered ones, keyed by id.

    Config always wins -- it is the human-curated record, trusted even over
    rom_scanner's exclusions.
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
        merged.append(e)
    merged.extend(by_id.values())
    merged.sort(key=lambda e: e["id"])

    # Config-only entries arrive without a path (e.g. submodule not checked
    # out). Fill it from the id so every consumer sees a complete entry; an
    # unresolvable id keeps a plausible path and reports MISSING at run time.
    for e in merged:
        if not e.get("path"):
            e["path"] = (rom_scanner.path_of(e["id"])
                         or "nes-test-roms/%s.nes" % e["id"])
    return merged


def build_test_list():
    """The whole suite: (settings, merged entries)."""
    settings, configured = load_check_config()
    return settings, apply_config(configured, rom_scanner.scan_all())


def summarize(argv):
    """Report the suite, or rewrite launcher.toml with --write-config.

    Bootstrap aid only: the suite is discovered at run time, so the config
    needs regenerating only to spell out every entry for hand-editing.
    """
    write = "--write-config" in argv

    discovered = rom_scanner.scan_all()
    if not discovered:
        print("No ROMs found under nes-test-roms/.")
        print("Run `git submodule update --init` first, then retry.")
        return 1

    _, configured = load_check_config()
    merged = apply_config(configured, discovered)

    # Keep human-curated exclusions (hang/interactive ROMs) so --write-config
    # stays idempotent instead of silently re-admitting them to the red line.
    # Scanner-intrinsic exclusions (PAL/demo/mapper/no-detector) are re-derived
    # every run and need no entry in the file.
    configured_ids = {c["id"] for c in configured}
    keep = [e for e in merged
            if not e.get("excluded") or e["id"] in configured_ids]

    # Red line = expected=pass AND actually runnable (not scanner-excluded).
    # Excluded entries (PAL/demo/IGNORE_DIRS/hang) never gate, so they must not
    # inflate this count -- a stale "expected=pass" on an excluded ROM would
    # otherwise make the number lie about the real gating set.
    n_must = sum(1 for e in keep
                 if e.get("expected") == "pass" and not e.get("excluded"))

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
    print("    must-pass %d  (expected=pass, fails the run)" % n_must)

    if not write:
        print("\n(dry run -- pass --write-config to rewrite %s)" % CONFIG_PATH)
        return 0

    with open(CONFIG_PATH, "w", encoding="utf-8") as f:
        f.write(render_toml(keep))
    print("\nwrote %s (%d entries)" % (CONFIG_PATH, len(keep)))
    return 0


if __name__ == "__main__":
    sys.exit(summarize(sys.argv[1:]))
