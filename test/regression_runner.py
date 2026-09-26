"""
Run the regression suite -- the SINGLE test entry point.

This module is ORCHESTRATION ONLY: pick entries, fan them out over a process
pool, render results, set the exit code. It deliberately owns no judgement --
every rule about what an entry means lives in test/suite.py (gated(), tag(),
evaluate() all read the same `expected` / `basis` pair), so changing how the
suite gates can never require touching this file.

Executable entry points in test/ (everything else is a library):
    test/regression_runner.py   run the suite, assert, write a report
    test/suite.py               bootstrap only: --write-config

ROMs come from two sources, merged by id:

  * test/regression.toml  -- hand-curated entries (always win)
  * test/discovery.py     -- automatic scan of the nes-test-roms submodule

so an empty config still runs every ROM that looks like a test.

Gating
------
An expectation gates only when it is authoritative, i.e. the entry carries no
`basis`. `basis` marks an expectation we have not confirmed on this build
("assumed", or a real-hardware claim never run here). Those entries are run
and reported but never allowed to fail the run -- otherwise the first full
sweep would be permanently red. Removing `basis` by hand after confirming a
ROM passes is the intended promotion; there is deliberately no automatic
write-back, since recording a FAIL would cement the bug as an expectation.

Exit code is non-zero only when a gated test diverges from its expectation.
A run report is written to test/reports/latest.txt; failing to write it is
never fatal and never changes the exit code.

To inspect a single ROM instead of the whole suite, run it as a one-entry
sweep and read its verdict:
    python test/regression_runner.py <idglob>     # e.g. 03-dummy_reads

Usage (from repo root):
    python test/regression_runner.py              # run every non-excluded ROM
    python test/regression_runner.py --gated      # only the confirmed baseline
    python test/regression_runner.py <idglob>     # ids/paths matching the glob
    python test/regression_runner.py --list       # list the suite and exit
    python test/regression_runner.py --frames N   # override frame count (no retry)

Excluded ROMs (PAL, demo/other, no usable detector, unmapped mapper) are
NEVER run, by any invocation -- not even an unqualified full sweep. A full
regression must stay limited to ROMs that actually look like tests.
"""
import os
import sys
import fnmatch
import argparse
import datetime
import multiprocessing as mp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rom_runner  # noqa: E402
import suite  # noqa: E402

REPORT_DIR = os.path.join(ROOT, "test", "reports")


def _run_one(entry):
    """Pool worker -- module level so it can be pickled.

    A non-PASS verdict at a cheap test_roms.xml frame budget is retried once
    at the full budget before being believed, so a too-short runframes value
    cannot manufacture a false failure.
    """
    r = rom_runner.run_one(entry)
    retry = entry.get("retry_frames")
    if retry and r["verdict"] != "PASS" and int(entry.get("frames", 0)) < retry:
        again = dict(entry)
        again["frames"] = retry
        r2 = rom_runner.run_one(again)
        if r2["verdict"] == "PASS":
            return r2
    return r


def _parallel(results_needed, jobs):
    """Run *jobs* across a process pool.

    Workers are reused across jobs (no maxtasksperchild), which is safe here:
    the only module-level state in the nes/*.pyx extensions is four read-only
    lookup tables (apu LENGTH_TABLE / DMC_RATE_TABLE / DUTY_PATTERNS, and
    mapper_factory.mappers) -- all mutable state lives in the Console
    instance each job builds for itself. Re-verify this if anyone ever adds a
    module-level mutable global to the extension modules; the old
    subprocess-per-ROM approach existed precisely because that was once a
    real risk.
    """
    workers = min(len(jobs), mp.cpu_count())
    with mp.Pool(workers) as pool:
        results = list(pool.imap_unordered(_run_one, jobs))
    results.sort(key=lambda r: r["id"])
    return results


def format_rows(rows, with_path=False):
    """Render result rows. Returns (lines, {label: count}).

    stdout stays terse (id only). The written report adds the full ROM path,
    which is now the one place the location is spelled out -- regression.toml
    stores just the id and derives the path at run time.
    """
    counts = {}
    lines = []
    for r, entry, label, bad in rows:
        marker = "!" if bad else " "
        line = (f"{marker} {label:20s} exp={entry.get('expected','skip'):5s} "
                f"{r['id']:44s} {r['verdict']}{r['detail']:14s}  $6000={r['status']}")
        if with_path:
            line += "  " + (entry.get("path") or "-")
        lines.append(line)
        counts[label] = counts.get(label, 0) + 1
    return lines, counts


def write_report(rows, args, any_bad):
    """Write a plain-text run report. Returns the dated path, or None.

    Never fatal: a report is a convenience artifact, and an unwritable
    reports directory must not turn a green run red.
    """
    lines, counts = format_rows(rows, with_path=True)
    n_gated = sum(1 for _, e, _, _ in rows if suite.gated(e))
    now = datetime.datetime.now()

    head = [
        "NES regression report",
        f"run at : {now:%Y-%m-%d %H:%M:%S}",
        f"args   : pattern={args.pattern} gated={args.gated} "
        f"frames={args.frames or 'default'}",
        "columns: ! label | expected | id | verdict | $6000 | rom path",
        "         paths are repo-relative, so reports compare across machines",
        "",
    ]
    tail = [
        "",
        "=== regression %s:  %s ===" % ("FAIL" if any_bad else "OK",
                                        "  ".join(f"{k}={v}" for k, v in sorted(counts.items()))),
        f"    {len(rows)} run, {n_gated} gated, {len(rows) - n_gated} observed only",
        f"exit code {1 if any_bad else 0}",
        "",
    ]
    text = "\n".join(head + lines + tail)

    try:
        os.makedirs(REPORT_DIR, exist_ok=True)
        latest = os.path.join(REPORT_DIR, "latest.txt")
        with open(latest, "w", encoding="utf-8") as f:
            f.write(text)
        return latest
    except OSError as e:
        print(f"(report not written: {e})")
        return None


def main():
    ap = argparse.ArgumentParser(description="Run the NES regression suite.")
    ap.add_argument("pattern", nargs="?", default="*",
                    help="glob matched against test id or path")
    ap.add_argument("--list", action="store_true", help="list the suite and exit")
    ap.add_argument("--gated", action="store_true",
                    help="only run confirmed entries (those without `basis`)")
    ap.add_argument("--frames", type=int, default=None,
                    help="override the frame count for every selected test")
    args = ap.parse_args()

    settings, tests = suite.build()
    if not tests:
        print("No ROMs found. Run `git submodule update --init` first.")
        return 0

    def match(t):
        return (fnmatch.fnmatch(t["id"], args.pattern)
                or fnmatch.fnmatch(t.get("path", ""), args.pattern))

    selected = [t for t in tests if match(t)]
    # Excluded ROMs (PAL, demo/other, no usable detector, unmapped mapper) are
    # filtered out unconditionally -- there is deliberately no flag to opt back
    # in, so a full regression can never accidentally sweep them.
    selected = [t for t in selected if not t.get("excluded")]
    if args.gated:
        selected = [t for t in selected if suite.gated(t)]

    if args.list:
        for t in selected:
            print(f"  {suite.tag(t):16s}  {t['id']}")
        print(f"\n  {len(selected)} listed "
              f"(of {len(tests)} scanned, {sum(1 for t in tests if t.get('excluded'))} excluded)")
        return 0

    if not selected:
        print(f"No tests match pattern '{args.pattern}'.")
        return 0

    default_frames = int(settings.get("frames", rom_runner.FRAMES))
    jobs = []
    for t in selected:
        j = rom_runner.normalize(t, settings)
        if args.frames:
            j["frames"] = args.frames
        elif int(j["frames"]) < default_frames:
            j["retry_frames"] = default_frames
        jobs.append(j)

    if len(jobs) == 1:
        results = [rom_runner.run_one(jobs[0])]
    else:
        results = _parallel(len(jobs), jobs)

    by_id = {t["id"]: t for t in selected}
    rows = []
    any_bad = False
    for r in results:
        entry = by_id[r["id"]]
        label, bad = suite.evaluate(r, entry)
        any_bad = any_bad or bad
        rows.append((r, entry, label, bad))

    rows.sort(key=lambda x: (not x[3], x[2], x[0]["id"]))
    lines, counts = format_rows(rows)
    for line in lines:
        print(line)

    n_gated = sum(1 for _, e, _, _ in rows if suite.gated(e))
    print(f"\n=== regression {'FAIL' if any_bad else 'OK'}:  "
          f"{'  '.join(f'{k}={v}' for k, v in sorted(counts.items()))} ===")
    print(f"    {len(rows)} run, {n_gated} gated, "
          f"{len(rows) - n_gated} observed only")

    report = write_report(rows, args, any_bad)
    if report:
        print(f"    report -> {os.path.relpath(report, ROOT)}")
    return 1 if any_bad else 0


if __name__ == "__main__":
    mp.freeze_support()
    sys.exit(main())
