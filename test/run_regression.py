"""
Regression suite runner.

Loads test/regression.toml, runs every test whose `expected` is "pass" or
"fail", and asserts the observed verdict matches the expectation:

    expected=pass  -> must observe PASS            (else REGRESSION)
    expected=fail  -> must NOT observe PASS        (else UNEXPECTED_PASS / a fix)
                      ERROR/RUNNING => UNCONFIRMED_FAIL (treated as failure)

`skip` entries are only run with --all, and carry no assertion. A ROM that
cannot be located (submodule not initialised and no failed/ copy) is reported
as MISSING and does not fail the run unless we claimed it should pass.

Exit code is non-zero when any gated test diverges from its expectation or
errors out -- i.e. a regression was detected.

Usage (from repo root):
    python test/run_regression.py            # run gated (pass/fail) tests
    python test/run_regression.py <idglob>   # run tests whose id matches the glob
    python test/run_regression.py --list     # list the whole suite
    python test/run_regression.py --all      # also run skip entries (no assertion)
"""
import os
import sys
import fnmatch
import argparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

import judge  # noqa: E402


def evaluate(result, expected, include_skips):
    """Classify a single result against its expected outcome.

    Returns (label, is_bad) where is_bad=True means a regression/error that
    should fail the run.
    """
    v = result["verdict"]
    if v == "MISSING":
        if expected == "pass":
            return "FAIL_MISSING", True   # claimed pass but ROM can't be found
        return "MISSING", False          # can't confirm; not a regression
    if include_skips and expected == "skip":
        return f"SKIP->{v}", False
    if expected == "pass":
        return ("PASS", False) if v == "PASS" else ("REGRESSION", True)
    if expected == "fail":
        if v == "PASS":
            return "UNEXPECTED_PASS", False   # improved -- good news, not a failure
        if v == "FAIL":
            return "EXPECTED_FAIL", False
        return "UNCONFIRMED_FAIL", True       # error/running -> can't confirm
    # expected == "skip" without --all
    return f"SKIP->{v}", False


def main():
    ap = argparse.ArgumentParser(description="Run the NES regression suite.")
    ap.add_argument("pattern", nargs="?", default="*",
                    help="glob matched against test id or path")
    ap.add_argument("--list", action="store_true", help="list the suite and exit")
    ap.add_argument("--all", action="store_true",
                    help="also run skip entries (no assertion)")
    args = ap.parse_args()

    judge.SETTINGS, tests = judge.load_regression()
    if not tests:
        print("No regression.toml entries found.")
        return 0

    if args.list:
        for t in tests:
            print(f"  {t.get('expected', 'skip'):6s}  {t['id']:36s}  {t.get('path', '')}")
        return 0

    def match(t):
        return (fnmatch.fnmatch(t["id"], args.pattern)
                or fnmatch.fnmatch(t.get("path", ""), args.pattern))

    if args.all:
        selected = [t for t in tests if match(t)]
    else:
        selected = [t for t in tests
                    if t.get("expected") in ("pass", "fail") and match(t)]

    if not selected:
        print(f"No tests match pattern '{args.pattern}'.")
        return 0

    results = [judge.run_one(judge.normalize(t)) for t in selected]

    # attach the expectation used for classification
    exp_by_id = {t["id"]: t.get("expected", "skip") for t in selected}
    rows = []
    any_bad = False
    for r in results:
        exp = exp_by_id[r["id"]]
        label, bad = evaluate(r, exp, args.all)
        any_bad = any_bad or bad
        rows.append((r, exp, label, bad))

    rows.sort(key=lambda x: (not x[3], x[2], x[0]["id"]))
    counts = {}
    for r, exp, label, bad in rows:
        marker = "!" if bad else " "
        print(f"{marker} {label:16s} exp={exp:5s}  {r['id']:36s} "
              f"{r['verdict']}{r['detail']:14s}  $6000={r['status']}")
        counts[label] = counts.get(label, 0) + 1

    verdict = "FAIL" if any_bad else "OK"
    breakdown = "  ".join(f"{k}={v}" for k, v in sorted(counts.items()))
    print(f"\n=== regression {verdict}:  {breakdown} ===")
    return 1 if any_bad else 0


if __name__ == "__main__":
    sys.exit(main())
