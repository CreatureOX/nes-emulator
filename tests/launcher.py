"""Run the self-check suite -- the single test entry point.

Orchestration only: pick entries, fan them out over a process pool, render
results, set the exit code. No judgement here -- every pass/fail rule lives in
test_judge.py (the single judge), so changing expectations
never touches this file.

Gating: every expected=pass ROM must pass; a hung ROM is killed (TIMEOUT) and
a crashed worker is CRASH -- both non-fatal, so one bad ROM can't wedge the
sweep. Exit code is non-zero only when a must-pass ROM diverges.

Excluded ROMs (PAL, demo/other, no usable detector, unmapped mapper) are NEVER
run, by any invocation. A run report is written to tests/reports/latest.md;
failing to write it is never fatal.
"""
import os
import sys
import fnmatch
import argparse
import datetime
import json
import time
import multiprocessing as mp
import traceback

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Headless + OpenBLAS guard: numpy (via apu.pyx) pulls in scipy-openblas, which
# on some Win11 hosts pre-allocates 24 threads and aborts with "memory
# allocation" -- the local "black screen". Force 1 thread + dummy SDL BEFORE
# numpy/pygame load, so the suite runs headless and allocation-light.
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("GOTO_NUM_THREADS", "1")

import test_judge  # noqa: E402
import rom_runner  # noqa: E402
import test_picker  # noqa: E402

REPORT_DIR = os.path.join(ROOT, "tests", "reports")

# Suite dirs skipped by default even when they carry runnable .nes. apu_mixer's
# ROMs are audio-only with no screen verdict, so the blargg detector can't gate
# Run-layer dir opt-out, distinct from rom_scanner's ROM-intrinsic exclusions:
# these suites we deliberately choose not to gate, not because the ROM can't be
# judged. Override with --dir (whitelist wins) or --exclude-dir.
DEFAULT_EXCLUDE_DIRS = {"apu_mixer"}

# Per-ROM watchdog: a ROM running longer than this is killed and reported
# TIMEOUT instead of freezing the sweep / hitting the CI job limit.
DEFAULT_ROM_TIMEOUT = 300


def _run_one(entry):
    """Pool worker (module level so it pickles).

    A non-PASS at a cheap test_roms.xml budget is retried once at the full
    budget, so a too-short runframes can't manufacture a false failure.

    run_one re-raises programming errors (NameError/TypeError/...) so direct
    callers fail loud with a full traceback; here we catch them and fold the
    error into an ERROR verdict that carries the type + message + short
    traceback, so a harness bug still surfaces in the report instead of being
    swallowed as a bare "worker crashed" by the watchdog.
    """
    try:
        r = rom_runner.run_one(entry)
    except Exception as e:
        tb = "".join(traceback.format_tb(e.__traceback__)[-3:])
        return {"id": entry["id"], "verdict": "ERROR",
                "detail": " %s: %s | %s" % (type(e).__name__, e, tb.strip()),
                "path": entry.get("path")}
    retry = entry.get("retry_frames")
    if retry and r["verdict"] != "PASSED" and int(entry.get("frames", 0)) < retry:
        again = dict(entry)
        again["frames"] = retry
        r2 = rom_runner.run_one(again)
        if r2["verdict"] == "PASSED":
            return r2
    return r


# Upstream test-rom source; the local submodule mirrors this tree, so report
# columns can deep-link straight to each suite's directory.
REPO_BASE = "https://github.com/christopherpow/nes-test-roms/tree/master"


def _suite_link(d):
    """Markdown link from a suite name to its directory in the upstream repo."""
    return f"[{d}]({REPO_BASE}/{d})"


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
    NES_SELFTEST_WORKERS when set (each worker imports numpy/OpenBLAS and can
    exhaust RAM in a low-memory sandbox). Never widens past the CPU count."""
    env_w = os.environ.get("NES_SELFTEST_WORKERS")
    if env_w:
        try:
            env_w = max(1, min(int(env_w), mp.cpu_count()))
        except ValueError:
            env_w = None
    return env_w if env_w else min(total, mp.cpu_count())


def _watchdog_result(j, timeout, verdict):
    """Result dict for a ROM the watchdog had to stop (TIMEOUT) or that lost
    its worker (CRASH). `verdict` is "TIMEOUT" or "CRASH"."""
    detail = (f" >{int(timeout)}s (watchdog)" if verdict == "TIMEOUT"
              else " worker crashed")
    return {"id": j["id"], "verdict": verdict, "detail": detail,
            "path": j.get("path")}


def _drain_remaining(inflight, dir_label, timeout, counters, done, total, res):
    """After a pool kill, mark every still-inflight job TIMEOUT and emit progress.

    Shared by the TIMEOUT and CRASH sweep-downs so the bookkeeping lives in one
    place; a poisoned/terminated pool means the rest can't be trusted, so they
    are reported TIMEOUT (non-fatal) and retried next run.
    """
    for ar2 in list(inflight):
        j2, _ = inflight.pop(ar2)
        r2 = _watchdog_result(j2, timeout, "TIMEOUT")
        counters["done"] += 1
        counters["fail_n"] += 1
        done += 1
        _print_progress(done, total, dir_label, r2["id"], r2["verdict"],
                        counters["pass_n"], counters["fail_n"])
        res.append(r2)
    return done


def _run_batch_watched(pool, jobs, dir_label, timeout, counters):
    """Fan one directory's jobs across *pool* with a per-ROM watchdog.

    A ROM past `timeout` is killed (TIMEOUT); a worker that crashes is CRASH.
    Both are non-fatal, so one bad ROM can't wedge the sweep. The pool is
    per-directory, so a kill/restart in one suite stays local to it.
    """
    print(f"\n=== directory: {dir_label}  ({len(jobs)} ROMs) ===", flush=True)
    inflight = {pool.apply_async(_run_one, (j,)): (j, time.time())
                for j in jobs}
    res = []
    done = 0
    while inflight:
        progressed = False
        for ar in list(inflight):
            j, t0 = inflight[ar]
            try:
                r = ar.get(timeout=0.5)
            except mp.TimeoutError:
                if time.time() - t0 > timeout:
                    pool.terminate()
                    pool.join()
                    done = _drain_remaining(inflight, dir_label, timeout,
                                            counters, done, len(jobs), res)
                    return res
                continue
            except Exception:
                # Worker process died (segfault). It is CRASH; the rest of this
                # directory can't be trusted on a poisoned pool, so they are
                # reported TIMEOUT (non-fatal) and retried next run.
                inflight.pop(ar)
                r = _watchdog_result(j, timeout, "CRASH")
                counters["done"] += 1
                counters["fail_n"] += 1
                done += 1
                _print_progress(done, len(jobs), dir_label, r["id"],
                                r["verdict"], counters["pass_n"],
                                counters["fail_n"])
                res.append(r)
                pool.terminate()
                pool.join()
                done = _drain_remaining(inflight, dir_label, timeout,
                                        counters, done, len(jobs), res)
                return res
            inflight.pop(ar)
            counters["done"] += 1
            if r["verdict"] == "PASSED":
                counters["pass_n"] += 1
            else:
                counters["fail_n"] += 1
            done += 1
            _print_progress(done, len(jobs), dir_label, r["id"],
                            r["verdict"], counters["pass_n"], counters["fail_n"])
            res.append(r)
            progressed = True
        if not progressed:
            time.sleep(0.2)
    return res


def format_rows(rows):
    """Render result rows -> (lines, {label: count}).

    stdout is terse (id only); the written report adds the full ROM path, the
    one place the location is spelled out (launcher.toml stores just the id).
    """
    counts = {}
    lines = []
    for r, entry, label, bad in rows:
        marker = "!" if bad else " "
        line = (f"{marker} {label:20s} exp={entry.get('expected','skip'):5s} "
                f"{r['id']:44s} {r['verdict']:14s}{r['detail']}")
        lines.append(line)
        counts[label] = counts.get(label, 0) + 1
    return lines, counts


def _bucket(verdict):
    """Bucket a result row for the Markdown report: pass or fail only.

    PASSED -> pass ; anything else -> fail. The per-ROM verdict string in the
    failing list already says *why* it failed, so no extra label is needed.
    """
    return "pass" if verdict == "PASSED" else "fail"


def write_report(rows, args, any_bad, ignored=None):
    """Write a GitHub-flavoured Markdown run report to tests/reports/latest.md.

    Groups into Pass / Fail only; failing ids are listed inline with their
    real verdict. Never fatal: an unwritable reports dir must not flip green.
    """
    groups = {"pass": [], "fail": []}
    for r, entry, label, bad in rows:
        groups[_bucket(r["verdict"])].append((entry, r, label, bad))

    n = {k: len(v) for k, v in groups.items()}
    n_bad = sum(1 for _, _, _, bad in rows if bad)
    now = datetime.datetime.now()

    cmd = "python tests/launcher.py"
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
    L.append("# NES Emulator Test Report")
    L.append("")
    L.append(f"_Generated at {now:%Y-%m-%d %H:%M:%S} · `{cmd}`_")
    L.append("")
    L.append("## Summary")
    L.append("")
    L.append("| Result | Count |")
    L.append("|--------|------:|")
    L.append(f"| ✅ Pass (matches expectation) | {n['pass']} |")
    L.append(f"| ❌ Fail (does not match) | {n['fail']} |")
    L.append(f"| **Total run** | {len(rows)} |")
    L.append("")
    L.append(f"- Must-pass entries: **{len(rows)}**")
    L.append(f"- ROMs that did not pass (CI red line): "
             f"**{n_bad}**")
    L.append("")

    # Per-directory breakdown -- the main way to eyeball a run.
    dir_stats = {}
    for r, entry, label, bad in rows:
        d = test_judge.top_dir(entry["id"])
        s = dir_stats.setdefault(d, {"total": 0, "pass": 0, "fail": 0})
        s["total"] += 1
        if r["verdict"] == "PASSED":
            s["pass"] += 1
        else:
            s["fail"] += 1
    L.append("## By directory")
    L.append("")
    L.append("| Directory | Total | Pass | Fail |")
    L.append("|-----------|------:|-----:|-----:|")
    for d in sorted(dir_stats):
        s = dir_stats[d]
        L.append(f"| {_suite_link(d)} | {s['total']} | {s['pass']} | {s['fail']} |")
    L.append("")

    def block(title, key, icon):
        items = groups[key]
        if not items:
            return
        L.append("<details>")
        L.append(f"<summary>{icon} {title} &mdash; {len(items)}</summary>")
        L.append("")
        for entry, r, label, bad in items:
            mark = "!" if bad else " "
            L.append(f"- {mark} `{entry['id']}` &mdash; {r['verdict']}{r['detail']}")
        L.append("")
        L.append("</details>")
        L.append("")

    block("Passing", "pass", "✅")
    block("Failing", "fail", "❌")

    # Ignored suites: skipped because their ROMs have no machine-readable
    # verdict, so they can't gate. Document each with its pass condition.
    if ignored:
        seen = {}
        for e in ignored:
            seen.setdefault(test_judge.top_dir(e["id"]),
                            e.get("ignore_note", "correct result unknown"))
        L.append("## Ignored (correct result not machine-readable)")
        L.append("")
        L.append("Skipped on purpose: these ROMs do not emit a machine-readable "
                 "PASS/FAIL, so they cannot gate the run. The human pass "
                 "condition is noted for each.")
        L.append("")
        L.append("| Suite | Why skipped / pass condition |")
        L.append("|-------|-------------------------------|")
        for d in sorted(seen):
            L.append(f"| {_suite_link(d)} | {seen[d]} |")
        L.append("")

    text = "\n".join(L)
    try:
        os.makedirs(REPORT_DIR, exist_ok=True)
        # Sharded CI runs each write a UNIQUE file (shard-N.md) so the parallel
        # jobs never clobber one another; a non-sharded local run keeps
        # latest.md. Every run also emits shard-N.json / latest.json so the
        # `summarize` CI job can fold all shards into one tally.
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

    JSON mirror of the Markdown report so the aggregator can merge N shards
    without parsing Markdown; flattens each row to the fields it tallies.
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
                "must_pass": entry.get("expected") == "pass",
                "verdict": r["verdict"],
                "detail": r.get("detail", ""),
                "path": entry.get("path", ""),
            }
            for r, entry, label, bad in rows
        ],
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2)


def main():
    ap = argparse.ArgumentParser(description="Run the NES self-check suite.")
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
    ap.add_argument("--frames", type=int, default=None,
                    help="override the frame count for every selected test")
    ap.add_argument("--timeout", type=int, default=0,
                    help="override the per-ROM watchdog to N seconds (default "
                         "%d). A ROM that runs longer is killed and reported "
                         "TIMEOUT instead of freezing the sweep." % DEFAULT_ROM_TIMEOUT)
    ap.add_argument("--shard", nargs=2, type=int, metavar=("N", "TOTAL"),
                    help="split the selected ROMs into TOTAL shards and run "
                    "shard N (0-indexed). Partition is deterministic by id, "
                    "so every shard job sees the same split and the union of "
                    "all shards is exactly the full selection with no overlap. "
                    "CI uses this to fan the sweep across N machines; locally "
                    "it lets you time a single slice. Works with --list.")
    ap.add_argument("--platform", default="linux",
                    help="label for CI shard reports (linux/windows/macos). "
                    "Namespaces the per-shard JSON so parallel jobs on "
                    "different OSes never collide, and lets the summarize "
                    "job break the tally down per platform.")
    args = ap.parse_args()

    settings, tests = test_picker.build_test_list()
    if not tests:
        print("No ROMs found. Run `git submodule update --init` first.")
        return 0

    def match(t):
        return (fnmatch.fnmatch(t["id"], args.pattern)
                or fnmatch.fnmatch(t.get("path", ""), args.pattern))

    selected = [t for t in tests if match(t)]
    # Excluded ROMs (PAL/demo/other/no-detector/unmapped) are filtered out
    # unconditionally -- no flag opts them back in.
    selected = [t for t in selected if not t.get("excluded")]
    # Only must-pass (expected="pass") entries run; "skip" stays in config just
    # to stop discovery re-adding them.
    selected = [t for t in selected if t.get("expected") == "pass"]

    # --- directory scoping ------------------------------------------------
    # Group by top-level suite dir. --dir whitelists suites (run ONLY these);
    # without it, all run except DEFAULT_EXCLUDE_DIRS and --exclude-dir.
    if args.dir:
        wanted = set(args.dir)
        selected = [t for t in selected if test_judge.top_dir(t["id"]) in wanted]
        if args.exclude_dir:  # --exclude-dir still trims inside a whitelist
            drop = set(args.exclude_dir)
            selected = [t for t in selected if test_judge.top_dir(t["id"]) not in drop]
        scope = wanted - set(args.exclude_dir)
    else:
        skip = set(DEFAULT_EXCLUDE_DIRS) | set(args.exclude_dir)
        selected = [t for t in selected if test_judge.top_dir(t["id"]) not in skip]
        scope = None  # all suites except the run-time opt-outs

    # Ignored suites (discovery marks them excluded="unknown-result") are shown
    # in the report's Ignored section, never gate the run. Scoped to the same
    # dirs as the run so --dir X doesn't list every unknown-result suite.
    ignored = [t for t in tests
               if t.get("excluded") and t.get("reason") == "unknown-result"
               and (scope is None or test_judge.top_dir(t["id"]) in scope)]

    if args.shard:
        n, total = args.shard
        if not (0 <= n < total):
            print(f"--shard N TOTAL requires 0 <= N < TOTAL "
                  f"(got N={n} TOTAL={total})")
            return 2
        # Stable order so the partition is identical on every machine / job.
        selected.sort(key=lambda t: t["id"])
        selected = [t for i, t in enumerate(selected) if i % total == n]
        print(f"[shard {n}/{total}] selected {len(selected)} ROMs", flush=True)

    if args.list_dirs:
        # List suites that carry runnable ROMs under the current scope, so
        # --dir/--exclude-dir can be chosen by name.
        by_dir = {}
        for t in selected:
            by_dir[test_judge.top_dir(t["id"])] = by_dir.get(test_judge.top_dir(t["id"]), 0) + 1
        print("Runnable suites (top-level dirs):")
        for d in sorted(by_dir):
            print(f"  {d:28s} {by_dir[d]} ROM(s)")
        print(f"\n  {len(by_dir)} suite(s), {len(selected)} ROM(s) in scope")
        return 0

    if args.list:
        current = None
        for t in selected:
            d = test_judge.top_dir(t["id"])
            if d != current:
                current = d
                print(f"\n[{d}]")
            print(f"  {test_judge.label_of(t):16s}  {t['id']}")
        print(f"\n  {len(selected)} listed "
              f"(of {len(tests)} scanned, "
              f"{sum(1 for t in tests if t.get('excluded'))} excluded)")
        return 0

    if not selected:
        print(f"No tests match pattern '{args.pattern}'.")
        return 0

    # Group by top-level dir so each suite runs as one batch.
    default_frames = int(settings.get("frames", rom_runner.FRAMES))
    jobs_by_dir = {}
    for t in selected:
        j = rom_runner.prepare_run(t, settings)
        if args.frames:
            j["frames"] = args.frames
        elif int(j["frames"]) < default_frames:
            j["retry_frames"] = default_frames
        jobs_by_dir.setdefault(test_judge.top_dir(t["id"]), []).append(j)

    dirs = sorted(jobs_by_dir.keys())
    counters = {"done": 0, "pass_n": 0, "fail_n": 0}

    timeout = args.timeout if args.timeout and args.timeout > 0 else DEFAULT_ROM_TIMEOUT
    print(f"Running {len(selected)} ROMs across {len(dirs)} directories "
          f"(watchdog={timeout}s) ...", flush=True)
    results = []
    for d in dirs:
        with mp.Pool(_pick_workers(len(jobs_by_dir[d]))) as pool:
            results += _run_batch_watched(pool, jobs_by_dir[d], d, timeout,
                                          counters)
    results.sort(key=lambda r: r["id"])
    print(f"\nDone: {counters['done']}/{len(selected)}  "
          f"PASSED={counters['pass_n']} FAIL={counters['fail_n']}", flush=True)

    by_id = {t["id"]: t for t in selected}
    rows = []
    any_bad = False
    for r in results:
        entry = by_id[r["id"]]
        label, bad = test_judge.judge_result(r)
        any_bad = any_bad or bad
        rows.append((r, entry, label, bad))

    rows.sort(key=lambda x: (not x[3], x[2], x[0]["id"]))
    lines, counts = format_rows(rows)
    for line in lines:
        print(line)

    print(f"\n=== red-line {'FAIL' if any_bad else 'OK'}:  "
          f"{'  '.join(f'{k}={v}' for k, v in sorted(counts.items()))} ===")
    print(f"    {len(rows)} ROMs run, {len(rows)} must-pass, "
          f"{'GATEFAIL' if any_bad else 'all green'}")

    report = write_report(rows, args, any_bad, ignored)
    if report:
        print(f"    report -> {os.path.relpath(report, ROOT)}")
    return 1 if any_bad else 0


if __name__ == "__main__":
    mp.freeze_support()
    sys.exit(main())
