"""Run the self-check suite -- the single test entry point.

Orchestration only: pick entries, fan them out over a process pool, render
results, set the exit code. No judgement here -- every pass/fail rule lives in
test_judge.py (the single judge), so changing expectations
never touches this file.

Gating: every expected=pass ROM must pass. A ROM past its watchdog is TIMEOUT
and a crashed worker is CRASH; both are red-line failures, but stay non-fatal
to the sweep -- watchdog state is per-ROM, so the remaining ROMs still run.
Exit code is non-zero when any must-pass ROM fails to PASS.

Frame budgets: rom_runner.prepare_run supplies each ROM's official runframes
budget; tests/frame_budgets.json may shorten individual jobs to a calibrated
frame count. Every shortened job carries retry_frames back at its official
budget, so a RUNNING/blank at the short count still reaches its verdict.
Only the number of emulated frames changes -- the ROM set and the judge do not.

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
BUDGET_PATH = os.path.join(ROOT, "tests", "frame_budgets.json")

# Per-ROM watchdog: a ROM running longer than this is killed and reported
# TIMEOUT instead of freezing the sweep / hitting the CI job limit.
DEFAULT_ROM_TIMEOUT = 300


def _run_one(entry):
    """Pool worker (module level so it pickles).

    A non-PASS at a cheap frame budget is retried once at the full budget
    (retry_frames), so too-short runframes can't manufacture a false failure.

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
    # Don't retry a hang/crash/error at the full budget -- it would just burn
    # the watchdog again. Only "soft" non-passes (RUNNING/blank, FAIL) get the
    # second chance to rule out a too-short runframes.
    if (retry and r["verdict"] != "PASSED"
            and r["verdict"] not in ("TIMEOUT", "CRASH", "ERROR", "MISSING")
            and int(entry.get("frames", 0)) < retry):
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


def _effective_cpus():
    """CPU count actually granted to this process, not the host's total.

    Containers publish a quota in cgroup v2's cpu.max ("<quota> <period>");
    mp.cpu_count() ignores it and reports the host (32 on a 4-core sandbox),
    which oversubscribes the pool and loses throughput. Affinity is the next
    best signal; on a bare runner cpu_count() already matches real cores.
    Ref: Linux cgroup v2 cpu.max; os.sched_getaffinity(2).
    """
    try:
        with open("/sys/fs/cgroup/cpu.max", encoding="ascii") as f:
            quota, period = f.read().split()[:2]
        if quota != "max":
            return max(1, int(quota) // int(period))
    except (OSError, ValueError):
        pass
    try:
        return max(1, len(os.sched_getaffinity(0)))
    except (AttributeError, OSError):
        pass
    return max(1, mp.cpu_count())


def _load_frame_budgets():
    """Read tests/frame_budgets.json, or {} when the file is absent.

    The table is optional: without it every ROM keeps its official runframes
    budget, so a fresh clone or a stale checkout still gates correctly.
    """
    try:
        with open(BUDGET_PATH, encoding="utf-8") as f:
            payload = json.load(f)
        return {str(k): int(v) for k, v in payload["budgets"].items()}
    except (OSError, ValueError, KeyError, TypeError):
        return {}


def _pick_workers(total):
    """Worker count for the pool, capped by the CPU quota actually available.

    NES_SELFTEST_WORKERS narrows it further (each worker imports numpy/OpenBLAS
    and can exhaust RAM in a low-memory sandbox), but can never widen past the
    effective CPU count: oversubscription is what made the pool slower than a
    quarter of its size on quota-limited hosts.
    """
    cpus = _effective_cpus()
    env_w = os.environ.get("NES_SELFTEST_WORKERS")
    if env_w:
        try:
            return max(1, min(int(env_w), cpus, total))
        except ValueError:
            pass
    return max(1, min(total, cpus))


def _watchdog_result(j, timeout, verdict):
    """Result dict for a ROM the watchdog had to stop (TIMEOUT) or that lost
    its worker (CRASH). `verdict` is "TIMEOUT" or "CRASH"."""
    detail = (f" >{int(timeout)}s (watchdog)" if verdict == "TIMEOUT"
              else " worker crashed")
    return {"id": j["id"], "verdict": verdict, "detail": detail,
            "path": j.get("path")}


def _run_all_watched(pool, jobs, timeout, counters, workers):
    """Fan every ROM across one pool, with watchdog state on each future.

    One global pool removes the per-directory barrier: a suite with two ROMs
    used to hold its own pool while the rest of the machine sat idle. Only
    `workers` futures are in flight at once, so the watchdog clock starts when
    a ROM is actually picked up -- submitting all 165 at once made queued ROMs
    time out on a 2-core runner before they ever ran. ready() is non-blocking,
    so polling costs one short loop, not one wait per future. A ROM past
    `timeout` is TIMEOUT and a dead worker is CRASH, each on its own row: the
    pool is never terminated, so a slow ROM cannot turn the rest TIMEOUT.
    """
    total = len(jobs)
    pending = iter(jobs)
    inflight = {}

    def fill():
        """Keep the pool saturated without letting queued ROMs age."""
        while len(inflight) < workers:
            try:
                j = next(pending)
            except StopIteration:
                break
            inflight[pool.apply_async(_run_one, (j,))] = (j, time.time())

    fill()
    res = []
    done = 0
    while inflight:
        progressed = False
        for ar in list(inflight):
            j, t0 = inflight[ar]
            if not ar.ready():
                if time.time() - t0 > timeout:
                    inflight.pop(ar)
                    r = _watchdog_result(j, timeout, "TIMEOUT")
                else:
                    continue
            else:
                inflight.pop(ar)
                try:
                    r = ar.get()
                except Exception:
                    r = _watchdog_result(j, timeout, "CRASH")
            counters["done"] += 1
            if r["verdict"] == "PASSED":
                counters["pass_n"] += 1
            else:
                counters["fail_n"] += 1
            done += 1
            _print_progress(done, total, test_judge.top_dir(j["id"]),
                            r["id"], r["verdict"],
                            counters["pass_n"], counters["fail_n"])
            res.append(r)
            progressed = True
        fill()
        if not progressed:
            time.sleep(0.1)
    return res


def format_rows(rows):
    """Render result rows -> (lines, {label: count}).

    stdout is terse (id only); the written report adds the full ROM path, the
    one place the location is spelled out (launcher.toml stores just the id).
    No `exp=` column: the launcher only runs expected="pass", so it would print
    the same value on every row.
    """
    counts = {}
    lines = []
    for r, entry, label, bad in rows:
        marker = "!" if bad else " "
        line = (f"{marker} {label:20s} {r['id']:44s} "
                f"{r['verdict']:14s}{r['detail']}")
        lines.append(line)
        counts[label] = counts.get(label, 0) + 1
    return lines, counts


def _bucket(verdict):
    """Bucket a result row for the Markdown report: pass or fail only.

    PASSED -> pass ; anything else -> fail. The per-ROM verdict string in the
    failing list already says *why* it failed, so no extra label is needed.
    """
    return "pass" if verdict == "PASSED" else "fail"


def _reason_text(reason):
    """Human-readable explanation for a scanner/human exclusion reason.

    Falls back to None for reasons that always carry their own free-text note
    (human hang/interactive/known-fail), so the caller's `note` wins.
    """
    table = {
        "pal": "PAL ROM (cannot pass on an NTSC emulator)",
        "demo": "demo / homebrew ROM, not a self-checking test",
        "bad-header": "unusable iNES header",
        "no-detector": "no machine-readable verdict evidence",
        "unknown-result": "emits no readable on-screen verdict",
        "hang": "known to hang / never completes",
        "interactive": "requires manual input to run",
        "known-fail": "known emulator defect, not yet fixed",
    }
    if reason.startswith("mapper-"):
        return "unsupported mapper %s" % reason.split("-", 1)[1]
    return table.get(reason)


def write_report(rows, args, any_bad, ignored=None):
    """Write a GitHub-flavoured Markdown run report to tests/reports/latest.md.

    Groups into Pass / Fail only; failing ids are listed inline with their
    real verdict. Never fatal: an unwritable reports dir must not flip green.
    """
    groups = {"pass": [], "fail": []}
    for r, entry, label, bad in rows:
        groups[_bucket(r["verdict"])].append((entry, r, label, bad))

    n = {k: len(v) for k, v in groups.items()}
    now = datetime.datetime.now()

    cmd = "python tests/launcher.py"
    if args.pattern and args.pattern != "*":
        cmd += " " + args.pattern
    if args.timeout:
        cmd += " --timeout %d" % args.timeout
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
            # Scanner-intrinsic exclusions set ignore_note; human exclusions
            # (hang/interactive) carry a free-text note instead. Scanner
            # exclusions that only set `reason` (PAL/mapper/bad-header/...) get
            # a readable explanation from _reason_text instead of a vague
            # "correct result unknown".
            why = (e.get("ignore_note")
                   or e.get("note")
                   or _reason_text(e.get("reason", ""))
                   or "correct result unknown")
            seen.setdefault(test_judge.top_dir(e["id"]), why)
        L.append("## Ignored (not gated)")
        L.append("")
        L.append("Skipped on purpose: either the ROM emits no machine-readable "
                 "verdict (so it cannot gate), or we chose not to run it "
                 "(hangs, interactive input, or audio-only with no screen "
                 "output). Each is documented with its reason.")
        L.append("")
        L.append("| Suite | Why skipped |")
        L.append("|-------|-------------|")
        for d in sorted(seen):
            L.append(f"| {_suite_link(d)} | {seen[d]} |")
        L.append("")

    text = "\n".join(L)
    try:
        os.makedirs(REPORT_DIR, exist_ok=True)
        md_path = os.path.join(REPORT_DIR, "latest.md")
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(text)
        _write_json_report(os.path.join(REPORT_DIR, "latest.json"),
                           rows, args.platform, any_bad)
        return md_path
    except OSError as e:
        print(f"(report not written: {e})")
        return None


def _write_json_report(path, rows, platform, any_bad):
    """Emit the machine-readable run report (tests/reports/latest.json).

    JSON mirror of the Markdown report: a stable, parseable record of the run
    for tooling and later diffing. Flattens each row to the fields it tallies.
    `platform` is the CI runner's own label (--platform), since a json consumer
    cannot otherwise tell a windows pass from a macos one.
    """
    payload = {
        "platform": platform,
        "any_bad": any_bad,
        "rows": [
            {
                "id": entry["id"],
                "label": label,
                "bad": bad,
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
                         "trims an explicit --dir whitelist, or narrows a full "
                         "run when no --dir is given")
    ap.add_argument("--frames", type=int, default=None,
                    help="override the frame count for every selected test")
    ap.add_argument("--timeout", type=int, default=0,
                    help="override the per-ROM watchdog to N seconds (default "
                         "%d). A ROM that runs longer is killed and reported "
                         "TIMEOUT instead of freezing the sweep." % DEFAULT_ROM_TIMEOUT)
    ap.add_argument("--platform", default="linux",
                    help="OS label recorded in the report (linux/windows/macos)")
    args = ap.parse_args()

    settings, tests = test_picker.build_test_list()
    if not tests:
        print("No ROMs found. Run `git submodule update --init` first.")
        return 0

    def match(t):
        return (fnmatch.fnmatch(t["id"], args.pattern)
                or fnmatch.fnmatch(t.get("path", ""), args.pattern))

    selected = [t for t in tests if match(t)]
    # Excluded entries never run: rom_scanner tags every non-gated ROM with a
    # reason (PAL/demo/no-detector/no-verdict-dir) and test_picker may exclude
    # more from launcher.toml. No flag opts them back in -- the report's Ignored
    # section is where "why didn't this run" is answered.
    selected = [t for t in selected if not t.get("excluded")]
    # Only must-pass (expected="pass") entries run; "skip" stays in config just
    # to stop discovery re-adding them.
    selected = [t for t in selected if t.get("expected") == "pass"]

    # --- directory scoping ------------------------------------------------
    # Group by top-level suite dir. --dir whitelists suites (run ONLY these),
    # then --exclude-dir trims inside the whitelist. Without --dir, everything
    # runs except --exclude-dir. Skipped-by-default suites (audio-only, PAL,
    # demo, ...) never reach here: rom_scanner already excluded them.
    if args.dir:
        wanted = set(args.dir)
        selected = [t for t in selected if test_judge.top_dir(t["id"]) in wanted]
        if args.exclude_dir:  # --exclude-dir still trims inside a whitelist
            drop = set(args.exclude_dir)
            selected = [t for t in selected if test_judge.top_dir(t["id"]) not in drop]
        scope = wanted - set(args.exclude_dir)
    else:
        if args.exclude_dir:
            drop = set(args.exclude_dir)
            selected = [t for t in selected if test_judge.top_dir(t["id"]) not in drop]
        scope = None  # all suites except the ones just dropped

    # Every excluded entry that carries a reason shows up in the report's
    # Ignored section, whether the reason is ROM-intrinsic (scanner-set
    # reason) or human (launcher.toml), scoped to the same dirs as the run.
    ignored = [t for t in tests
               if t.get("excluded") and t.get("reason")
               and (scope is None or test_judge.top_dir(t["id"]) in scope)]

    if args.list_dirs:
        # List suites that carry runnable ROMs under the current scope, so
        # --dir/--exclude-dir can be chosen by name.
        by_dir = {}
        for t in selected:
            d = test_judge.top_dir(t["id"])
            by_dir[d] = by_dir.get(d, 0) + 1
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
            print(f"  {t.get('expected', 'skip'):16s}  {t['id']}")
        print(f"\n  {len(selected)} listed "
              f"(of {len(tests)} scanned, "
              f"{sum(1 for t in tests if t.get('excluded'))} excluded)")
        return 0

    if not selected:
        # An empty scope means the operator's --pattern/--dir resolved to zero
        # runnable ROMs (typo, wrong suite, or every match excluded). That is a
        # misconfiguration, not a green result: never let a no-op run report
        # success. 2 is distinct from 0 (green) / 1 (red-line failure).
        scope_desc = (f"--pattern '{args.pattern}'" if args.pattern != "*"
                      else (f"--dir {args.dir}" if args.dir else "current scope"))
        print(f"WARNING: no runnable ROMs in {scope_desc} -- nothing executed.",
              file=sys.stderr)
        return 2

    # One global job list: the pool stays saturated from the first ROM to the
    # last instead of draining between every directory.
    default_frames = int(settings["frames"])
    budgets = _load_frame_budgets()
    jobs = []
    for t in selected:
        j = rom_runner.prepare_run(t, settings)
        full = int(j["frames"])
        if args.frames:
            j["frames"] = int(args.frames)
        elif budgets.get(t["id"]):
            j["frames"] = max(1, min(int(budgets[t["id"]]), full))
        # A short budget ALWAYS carries a retry at the official budget, so a
        # RUNNING/blank at the short count can still reach its verdict. The old
        # if/elif only injected a retry below [settings].frames and skipped it
        # for explicit --frames overrides.
        if int(j["frames"]) < full:
            j["retry_frames"] = max(full, default_frames)
        elif int(j["frames"]) < default_frames:
            j["retry_frames"] = default_frames
        jobs.append(j)

    dirs = sorted({test_judge.top_dir(j["id"]) for j in jobs})
    counters = {"done": 0, "pass_n": 0, "fail_n": 0}
    workers = _pick_workers(len(jobs))

    timeout = args.timeout if args.timeout and args.timeout > 0 else DEFAULT_ROM_TIMEOUT
    print(f"Running {len(jobs)} ROMs across {len(dirs)} directories "
          f"({workers} workers, watchdog={timeout}s) ...", flush=True)
    with mp.Pool(workers) as pool:
        results = _run_all_watched(pool, jobs, timeout, counters, workers)
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
    print(f"    {len(rows)} must-pass ROMs run, "
          f"{'GATEFAIL' if any_bad else 'all green'}")

    report = write_report(rows, args, any_bad, ignored)
    if report:
        print(f"    report -> {os.path.relpath(report, ROOT)}")
    return 1 if any_bad else 0


if __name__ == "__main__":
    mp.freeze_support()
    sys.exit(main())
