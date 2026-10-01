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
    python test/regression_runner.py --list-dirs  # list runnable suites (top-level dirs)
    python test/regression_runner.py --frames N   # override frame count (no retry)
    python test/regression_runner.py --timeout N  # local only: abort a hung ROM after N s (TIMEOUT)
    python test/regression_runner.py --dir DIR            # run only suite(s) DIR (repeatable)
    python test/regression_runner.py --exclude-dir DIR    # skip suite(s) DIR (repeatable)

Excluded ROMs (PAL, demo/other, no usable detector, unmapped mapper) are
NEVER run, by any invocation -- not even an unqualified full sweep. A full
regression must stay limited to ROMs that actually look like tests.

Suites are grouped by their top-level directory and the runner batches each
suite together, so a run reads suite-by-suite. By default it also skips any
suite listed in DEFAULT_EXCLUDE_DIRS (currently apu_mixer -- audio-only mixer
probes with no screen verdict the blargg detector cannot gate). Pass --dir to
whitelist suites, or --exclude-dir to drop more; a suite containing no .nes at
all is excluded automatically and never needs listing.
"""
import os
import sys
import fnmatch
import argparse
import datetime
import json
import multiprocessing as mp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Headless + OpenBLAS guard: apu.pyx imports numpy for audio buffering, which
# pulls in scipy-openblas. On some Win11 hosts OpenBLAS pre-allocates a 24-thread
# pool and aborts with "memory allocation" -- the "black screen" seen when the
# suite is run locally. Force the thread count to 1 and a dummy SDL driver
# BEFORE numpy/pygame load, so the regression suite runs headless and
# allocation-light everywhere (local or CI).
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("GOTO_NUM_THREADS", "1")

import rom_runner  # noqa: E402
import suite  # noqa: E402

REPORT_DIR = os.path.join(ROOT, "test", "reports")

# Top-level (suite) directories the regression suite skips BY DEFAULT, even when
# they carry runnable .nes files. apu_mixer's ROMs are audio-only mixer probes
# with no screen verdict, so the blargg detector cannot gate them and they only
# add noise to the report. A directory with NO .nes at all is skipped
# automatically by selection (it contributes zero entries), so it never needs
# listing here. Override with --dir (whitelist wins) or --exclude-dir.
DEFAULT_EXCLUDE_DIRS = {"apu_mixer"}


def _run_one(entry):
    """Pool worker -- module level so it can be pickled.

    A non-PASS verdict at a cheap test_roms.xml frame budget is retried once
    at the full budget before being believed, so a too-short runframes value
    cannot manufacture a false failure.
    """
    r = rom_runner.run_one(entry)
    retry = entry.get("retry_frames")
    if retry and r["verdict"] != "PASSED" and int(entry.get("frames", 0)) < retry:
        again = dict(entry)
        again["frames"] = retry
        r2 = rom_runner.run_one(again)
        if r2["verdict"] == "PASSED":
            return r2
    return r


def _top_dir(rom_id):
    """Top-level (suite) directory of a ROM id: 'apu_reset' for both
    'apu_reset/works_immediately' and a bare 'apu_reset'."""
    return rom_id.split("/", 1)[0]


def _print_progress(done, total, d, rid, verdict, pass_n, fail_n):
    """One line of live progress, grouped by directory. Newline-per-ROM and
    flush=True so it shows in CI logs in real time (GitHub Actions block-buffers
    stdout otherwise, and a carriage-return progress bar renders poorly in the
    web UI).
    """
    print(f"[{done:>3}/{total}] {d:20s} {rid:42s} {verdict:9s} "
          f"PASSED={pass_n} FAIL={fail_n}", flush=True)


def _pick_workers(total):
    """Worker count for the process pool: one per CPU by default, narrowed by
    NES_REGRESSION_WORKERS when set (each worker imports numpy/OpenBLAS and can
    exhaust RAM in a low-memory sandbox). Never widens past the CPU count."""
    env_w = os.environ.get("NES_REGRESSION_WORKERS")
    if env_w:
        try:
            env_w = max(1, min(int(env_w), mp.cpu_count()))
        except ValueError:
            env_w = None
    return env_w if env_w else min(total, mp.cpu_count())


def _run_batch(pool, jobs, dir_label, counters):
    """Fan one directory's jobs across the shared pool, stream a per-ROM
    progress line, update `counters`, and return the results.

    Calling this per directory is what makes the run "batch by directory": a
    header prints before each suite so the log reads suite-by-suite and one
    suite's outcome can be eyeballed without scrolling a 188-line blob.
    Parallelism is preserved WITHIN a directory -- the pool reuses its workers.
    """
    print(f"\n=== directory: {dir_label}  ({len(jobs)} ROMs) ===", flush=True)
    res = []
    for r in pool.imap_unordered(_run_one, jobs):
        counters["done"] += 1
        if r["verdict"] == "PASSED":
            counters["pass_n"] += 1
        else:
            counters["fail_n"] += 1
        _print_progress(counters["done"], len(jobs), dir_label, r["id"],
                        r["verdict"], counters["pass_n"], counters["fail_n"])
        res.append(r)
    return res


def _run_sequential_timeout(jobs, dir_label, timeout, counters):
    """Local hang guard: one ROM per process, aborted at `timeout`. Sequential
    on purpose -- used when probing a few ROMs by hand, not for the CI sweep.
    Returns the results for one directory."""
    print(f"\n=== directory: {dir_label}  ({len(jobs)} ROMs, --timeout) ===",
          flush=True)
    res = []
    for j in jobs:
        r = _run_one_timeout(j, timeout)
        counters["done"] += 1
        if r["verdict"] == "PASSED":
            counters["pass_n"] += 1
        else:
            counters["fail_n"] += 1
        _print_progress(counters["done"], len(jobs), dir_label, j["id"],
                        r["verdict"], counters["pass_n"], counters["fail_n"])
        res.append(r)
    return res


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

    PASSED -> pass ; TIMEOUT -> timeout ; a gated expectation that diverged ->
    fail ; everything else (ERROR / MISSING / OBSERVE_* / SKIP) -> other.
    """
    if label == "PASSED":
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
    if args.shard:
        cmd += " --shard %d %d" % (args.shard[0], args.shard[1])
    if args.platform != "linux":
        cmd += " --platform %s" % args.platform
    if args.dir:
        cmd += " " + " ".join("--dir %s" % d for d in args.dir)
    if args.exclude_dir:
        cmd += " " + " ".join("--exclude-dir %s" % d for d in args.exclude_dir)

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

    # Per-directory (suite) breakdown: the primary way to eyeball a run, since
    # ROMs are grouped by their top-level directory.
    dir_stats = {}
    for r, entry, label, bad in rows:
        d = _top_dir(entry["id"])
        s = dir_stats.setdefault(
            d, {"total": 0, "pass": 0, "fail": 0,
                "timeout": 0, "other": 0, "bad": False})
        s["total"] += 1
        if label == "PASSED":
            s["pass"] += 1
        elif label == "REGRESSION" or label.startswith("FAIL"):
            s["fail"] += 1
        elif r["verdict"] == "TIMEOUT":
            s["timeout"] += 1
        else:
            s["other"] += 1
        if bad:
            s["bad"] = True
    L.append("## By directory")
    L.append("")
    L.append("| Directory | Total | Pass | Fail | Timeout | Other | Regression |")
    L.append("|-----------|------:|-----:|-----:|--------:|------:|-----------:|")
    for d in sorted(dir_stats):
        s = dir_stats[d]
        L.append(f"| `{d}` | {s['total']} | {s['pass']} | {s['fail']} | "
                 f"{s['timeout']} | {s['other']} | "
                 f"{'⚠️' if s['bad'] else '—'} |")
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
        # Sharded CI runs each write a UNIQUE file (shard-N.md) so the 20
        # parallel jobs never clobber one another's report; a non-sharded
        # local run keeps the classic latest.md. Every run also emits a
        # machine-readable shard-N.json / latest.json so the `summarize` CI
        # job can fold all shards into one tally.
        if args.shard:
            base = "shard-%s-%d" % (args.platform, args.shard[0])
        else:
            base = "latest"
        md_path = os.path.join(REPORT_DIR, base + ".md")
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(text)
        json_path = os.path.join(REPORT_DIR, base + ".json")
        _write_json_report(json_path, rows, args, any_bad)
        return md_path
    except OSError as e:
        print(f"(report not written: {e})")
        return None


def _write_json_report(path, rows, args, any_bad):
    """Emit a machine-readable shard report for the `summarize` CI job.

    Mirrors the Markdown report but as JSON so the aggregator can merge N
    shards without parsing Markdown. `rows` carries (r, entry, label, bad);
    we flatten each into the fields summarize needs to tally verdicts and
    spot regressions.
    """
    payload = {
        "shard": args.shard[0] if args.shard else 0,
        "total_shards": args.shard[1] if args.shard else 1,
        "platform": args.platform,
        "any_bad": any_bad,
        "rows": [
            {
                "id": entry["id"],
                "label": label,
                "bad": bad,
                "gated": bool(suite.gated(entry)),
                "verdict": r["verdict"],
                "detail": r.get("detail", ""),
                "status": r.get("status", ""),
                "path": entry.get("path", ""),
            }
            for r, entry, label, bad in rows
        ],
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)


def main():
    ap = argparse.ArgumentParser(description="Run the NES regression suite.")
    ap.add_argument("pattern", nargs="?", default="*",
                    help="glob matched against test id or path")
    ap.add_argument("--list", action="store_true", help="list the suite and exit")
    ap.add_argument("--list-dirs", action="store_true",
                    help="list runnable top-level suites (dirs) and exit")
    ap.add_argument("--dir", action="append", default=[], metavar="DIR",
                    help="only run ROMs under top-level suite DIR (repeatable); "
                         "whitelist -- wins over the default exclusions")
    ap.add_argument("--exclude-dir", action="append", default=[], metavar="DIR",
                    help="skip ROMs under top-level suite DIR (repeatable); "
                         "applied on top of DEFAULT_EXCLUDE_DIRS")
    ap.add_argument("--gated", action="store_true",
                    help="only run confirmed entries (those without `basis`)")
    ap.add_argument("--frames", type=int, default=None,
                    help="override the frame count for every selected test")
    ap.add_argument("--timeout", type=int, default=0,
                    help="local-only: run each ROM in its own process and abort "
                         "it after N seconds as TIMEOUT (kills hangs instead of "
                         "freezing the machine). CI does NOT use this -- known "
                         "hangs are pre-excluded in regression.toml")
    ap.add_argument("--shard", nargs=2, type=int, metavar=("N", "TOTAL"),
                    help="split the selected ROMs into TOTAL shards and run "
                         "shard N (0-indexed). Partition is deterministic by id, "
                         "so every shard job sees the same split and the union of "
                         "all shards is exactly the full selection with no overlap. "
                         "CI uses this to fan the sweep across N machines; locally "
                         "it lets you time a single slice. Works with --gated and "
                         "--list.")
    ap.add_argument("--platform", default="linux",
                    help="label for CI shard reports (linux/windows/macos). "
                         "Namespaces the per-shard JSON so parallel jobs on "
                         "different OSes never collide, and lets the summarize "
                         "job break the tally down per platform.")
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

    # --- directory scoping ------------------------------------------------
    # Group ROMs by their top-level (suite) directory. --dir is a whitelist
    # (run ONLY these suites). Without it, every suite runs except the built-in
    # DEFAULT_EXCLUDE_DIRS and any --exclude-dir. A suite with zero .nes in the
    # submodule contributes no entries, so it is excluded automatically and
    # never needs to be listed.
    if args.dir:
        wanted = set(args.dir)
        selected = [t for t in selected if _top_dir(t["id"]) in wanted]
        if args.exclude_dir:  # --exclude-dir still trims inside a whitelist
            drop = set(args.exclude_dir)
            selected = [t for t in selected if _top_dir(t["id"]) not in drop]
    else:
        skip = set(DEFAULT_EXCLUDE_DIRS) | set(args.exclude_dir)
        selected = [t for t in selected if _top_dir(t["id"]) not in skip]

    if args.shard:
        n, total = args.shard
        if not (0 <= n < total):
            print(f"--shard N TOTAL requires 0 <= N < TOTAL "
                  f"(got N={n} TOTAL={total})")
            return 2
        # Stable order so the partition is identical on every machine / job
        # regardless of how suite.build() ordered the merged list.
        selected.sort(key=lambda t: t["id"])
        selected = [t for i, t in enumerate(selected) if i % total == n]
        print(f"[shard {n}/{total}] selected {len(selected)} ROMs", flush=True)

    if args.list_dirs:
        # Enumerate suites that actually carry runnable ROMs under the current
        # scope (after exclusions and --gated), so --dir/--exclude-dir can be
        # chosen by name. Suites with no .nes are skipped implicitly.
        by_dir = {}
        for t in selected:
            by_dir[_top_dir(t["id"])] = by_dir.get(_top_dir(t["id"]), 0) + 1
        print("Runnable suites (top-level dirs):")
        for d in sorted(by_dir):
            print(f"  {d:28s} {by_dir[d]} ROM(s)")
        print(f"\n  {len(by_dir)} suite(s), {len(selected)} ROM(s) in scope")
        return 0

    if args.list:
        current = None
        for t in selected:
            d = _top_dir(t["id"])
            if d != current:
                current = d
                print(f"\n[{d}]")
            print(f"  {suite.tag(t):16s}  {t['id']}")
        print(f"\n  {len(selected)} listed "
              f"(of {len(tests)} scanned, "
              f"{sum(1 for t in tests if t.get('excluded'))} excluded)")
        return 0

    if not selected:
        print(f"No tests match pattern '{args.pattern}'.")
        return 0

    # Group jobs by top-level directory so each suite runs as one batch.
    default_frames = int(settings.get("frames", rom_runner.FRAMES))
    jobs_by_dir = {}
    for t in selected:
        j = rom_runner.normalize(t, settings)
        if args.frames:
            j["frames"] = args.frames
        elif int(j["frames"]) < default_frames:
            j["retry_frames"] = default_frames
        jobs_by_dir.setdefault(_top_dir(t["id"]), []).append(j)

    dirs = sorted(jobs_by_dir.keys())
    counters = {"done": 0, "pass_n": 0, "fail_n": 0}

    if args.timeout and args.timeout > 0:
        # Local hang guard: each ROM in its own process, aborted at the
        # timeout. Sequential on purpose -- this path is for probing a few
        # ROMs by hand, not for the CI sweep.
        results = []
        for d in dirs:
            results += _run_sequential_timeout(jobs_by_dir[d], d,
                                                args.timeout, counters)
    elif len(selected) == 1:
        d = dirs[0]
        j = jobs_by_dir[d][0]
        print(f"\n=== directory: {d}  (1 ROM) ===", flush=True)
        r = rom_runner.run_one(j)
        counters["done"] = 1
        if r["verdict"] == "PASSED":
            counters["pass_n"] = 1
        else:
            counters["fail_n"] = 1
        _print_progress(1, 1, d, j["id"], r["verdict"],
                        counters["pass_n"], counters["fail_n"])
        results = [r]
    else:
        workers = _pick_workers(len(selected))
        print(f"Running {len(selected)} ROMs across {workers} workers "
              f"in {len(dirs)} directories...", flush=True)
        results = []
        with mp.Pool(workers) as pool:
            for d in dirs:
                results += _run_batch(pool, jobs_by_dir[d], d, counters)
        results.sort(key=lambda r: r["id"])
        print(f"\nDone: {counters['done']}/{len(selected)}  "
              f"PASSED={counters['pass_n']} FAIL={counters['fail_n']}",
              flush=True)

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
