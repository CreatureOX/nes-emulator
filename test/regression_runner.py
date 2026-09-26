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
A run report is written to test/reports/latest.md (GitHub-flavoured Markdown);
failing to write it is never fatal and never changes the exit code.

To inspect a single ROM instead of the whole suite, run it as a one-entry
sweep and read its verdict:
    python test/regression_runner.py <idglob>     # e.g. 03-dummy_reads

Usage (from repo root):
    python test/regression_runner.py              # run every non-excluded ROM
    python test/regression_runner.py --gated      # only the confirmed baseline
    python test/regression_runner.py <idglob>     # ids/paths matching the glob
    python test/regression_runner.py --list       # list the suite and exit
    python test/regression_runner.py --frames N   # override frame count (no retry)
    python test/regression_runner.py --timeout N  # local only: abort a hung ROM after N s (TIMEOUT)

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


def _print_progress(done, total, rid, verdict, pass_n, fail_n):
    """One line of live progress. Newline-per-ROM and flush=True so it shows
    up in CI logs in real time (GitHub Actions block-buffers stdout otherwise,
    and a carriage-return progress bar renders poorly in the web UI).
    """
    print(f"[{done:>3}/{total}] {rid:42s} {verdict:9s} "
          f"PASS={pass_n} FAIL={fail_n}", flush=True)


def _parallel(total, jobs):
    """Run *jobs* across a process pool, streaming a progress line per ROM.

    Results arrive via imap_unordered as each worker finishes, so the log
    shows real progress instead of one blob at the end. Only the parent
    prints, which keeps the lines ordered and free of worker interleaving.

    Workers are reused across jobs (no maxtasksperchild), which is safe here:
    the only module-level state in the nes/*.pyx extensions is four read-only
    lookup tables (apu LENGTH_TABLE / DMC_RATE_TABLE / DUTY_PATTERNS, and
    mapper_factory.mappers) -- all mutable state lives in the Console
    instance each job builds for itself.
    """
    # Default: one worker per CPU. A low-memory / sandboxed environment can
    # cap this with NES_REGRESSION_WORKERS (e.g. 2) -- each worker imports
    # numpy/OpenBLAS, so spawning cpu_count() at once can exhaust RAM. The
    # knob only narrows the pool; it never widens past the CPU count.
    env_w = os.environ.get("NES_REGRESSION_WORKERS")
    if env_w:
        try:
            env_w = max(1, min(int(env_w), mp.cpu_count()))
        except ValueError:
            env_w = None
    workers = env_w if env_w else min(len(jobs), mp.cpu_count())
    print(f"Running {total} ROMs across {workers} workers...", flush=True)
    results = []
    done = 0
    pass_n = 0
    fail_n = 0
    with mp.Pool(workers) as pool:
        for r in pool.imap_unordered(_run_one, jobs):
            done += 1
            if r["verdict"] == "PASS":
                pass_n += 1
            else:
                fail_n += 1
            _print_progress(done, total, r["id"], r["verdict"], pass_n, fail_n)
            results.append(r)
    results.sort(key=lambda r: r["id"])
    print(f"Done: {done}/{total}  PASS={pass_n} FAIL={fail_n}", flush=True)
    return results


def _timeout_target(entry, q):
    """Worker for _run_one_timeout: run one ROM, push its result onto q."""
    try:
        q.put(rom_runner.run_one(entry))
    except Exception as e:  # noqa: BLE001 - surface any crash as ERROR
        q.put({"id": entry["id"], "verdict": "ERROR",
               "detail": " %r" % (e,), "status": "--",
               "path": entry.get("path")})


def _run_one_timeout(entry, timeout):
    """Run one ROM in a dedicated process so a hang can be killed.

    Local-only safeguard for probing ROMs one-by-one: a ROM that never
    finishes is reported as TIMEOUT (a verdict the suite treats as non-fatal)
    instead of freezing the machine. CI never calls this -- known hangs are
    pre-excluded in regression.toml -- so the extra process per ROM is fine.
    """
    q = mp.Queue()
    p = mp.Process(target=_timeout_target, args=(entry, q))
    p.start()
    p.join(timeout)
    if p.is_alive():
        p.terminate()
        p.join()
        return {"id": entry["id"], "verdict": "TIMEOUT",
                "detail": " >%ds" % timeout, "status": "--",
                "path": entry.get("path")}
    if not q.empty():
        return q.get()
    return {"id": entry["id"], "verdict": "TIMEOUT",
            "detail": " >%ds" % timeout, "status": "--",
            "path": entry.get("path")}


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


def _classify(label, verdict):
    """Bucket a result row for the Markdown report.

    PASS -> pass ; TIMEOUT -> timeout ; a gated expectation that diverged ->
    fail ; everything else (ERROR / MISSING / OBSERVE_* / SKIP) -> other.
    """
    if label == "PASS":
        return "pass"
    if verdict == "TIMEOUT":
        return "timeout"
    if label == "REGRESSION" or label.startswith("FAIL"):
        return "fail"
    return "other"


def write_report(rows, args, any_bad):
    """Write a GitHub-flavoured Markdown run report to test/reports/latest.md.

    Groups results into Pass / Fail / Timeout / Other. The failing and timeout
    ROM ids are listed inline (folded <details> blocks) so the report stays
    scannable on a PR. Never fatal: an unwritable reports directory must not
    flip a green run red.
    """
    groups = {"pass": [], "fail": [], "timeout": [], "other": []}
    for r, entry, label, bad in rows:
        groups[_classify(label, r["verdict"])].append((entry, r, label))

    n = {k: len(v) for k, v in groups.items()}
    n_gated = sum(1 for _, e, _, _ in rows if suite.gated(e))
    now = datetime.datetime.now()

    cmd = "python test/regression_runner.py"
    if args.gated:
        cmd += " --gated"
    if args.pattern and args.pattern != "*":
        cmd += " " + args.pattern
    if args.timeout:
        cmd += " --timeout %d" % args.timeout

    L = []
    L.append("# NES emulator regression report")
    L.append("")
    L.append(f"_Generated at {now:%Y-%m-%d %H:%M:%S} · `{cmd}`_")
    L.append("")
    L.append("## Summary")
    L.append("")
    L.append("| Result | Count |")
    L.append("|--------|------:|")
    L.append(f"| ✅ Pass | {n['pass']} |")
    L.append(f"| ❌ Fail (regression) | {n['fail']} |")
    L.append(f"| ⏱ Timeout | {n['timeout']} |")
    L.append(f"| 🔸 Other | {n['other']} |")
    L.append(f"| **Total run** | {len(rows)} |")
    L.append("")
    L.append(f"- Gated entries: **{n_gated}**")
    L.append(f"- Regression status: **{'FAIL' if any_bad else 'OK'}** "
             f"(local exit code `{1 if any_bad else 0}`)")
    L.append("")

    def block(title, key, icon):
        items = groups[key]
        if not items:
            return
        L.append("<details>")
        L.append(f"<summary>{icon} {title} &mdash; {len(items)}</summary>")
        L.append("")
        for entry, r, label in items:
            L.append(f"- `{entry['id']}` &mdash; {r['verdict']}{r['detail']}")
        L.append("")
        L.append("</details>")
        L.append("")

    block("Passing", "pass", "✅")
    block("Failing (regression)", "fail", "❌")
    block("Timeout", "timeout", "⏱")
    block("Other", "other", "🔸")

    text = "\n".join(L)
    try:
        os.makedirs(REPORT_DIR, exist_ok=True)
        latest = os.path.join(REPORT_DIR, "latest.md")
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
    ap.add_argument("--timeout", type=int, default=0,
                    help="local-only: run each ROM in its own process and abort "
                         "it after N seconds as TIMEOUT (kills hangs instead of "
                         "freezing the machine). CI does NOT use this -- known "
                         "hangs are pre-excluded in regression.toml")
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

    if args.timeout and args.timeout > 0:
        # Local hang guard: each ROM in its own process, aborted at the
        # timeout. Sequential on purpose -- this path is for probing a few
        # ROMs by hand, not for the CI sweep.
        results = []
        done = 0
        pass_n = 0
        fail_n = 0
        for j in jobs:
            r = _run_one_timeout(j, args.timeout)
            done += 1
            if r["verdict"] == "PASS":
                pass_n += 1
            else:
                fail_n += 1
            _print_progress(done, len(jobs), j["id"], r["verdict"], pass_n, fail_n)
            results.append(r)
    elif len(jobs) == 1:
        r = rom_runner.run_one(jobs[0])
        _print_progress(1, 1, jobs[0]["id"], r["verdict"],
                        1 if r["verdict"] == "PASS" else 0,
                        0 if r["verdict"] == "PASS" else 1)
        results = [r]
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
