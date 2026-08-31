#!/usr/bin/env python3
"""Run a UVM regression list.

Simulations are single-threaded, so the machine is only busy if several run
at once - which is the main reason this is a script and not a shell loop in a
makefile. It also expands seed sweeps and writes JUnit XML so CI can show
per-test results instead of one opaque pass/fail.

List format, one run per line:

    # comment
    <testbench> <test> [seed|seed-range] [key=value ...]

    apb  apb_rw_test
    apb  apb_random_test   1-10                  # ten seeds
    apb  apb_reg_test      7    TRACE=fst        # per-run make overrides
    apb  apb_smoke_test    *    UVM_VERBOSITY=UVM_HIGH

A seed of '*' or 'random' picks a random seed and reports it, so a failure is
always reproducible from the log. Omitted seed means 1.
"""

import argparse
import concurrent.futures
import os
import random
import re
import shlex
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field


@dataclass
class Run:
    testbench: str
    test: str
    seed: int
    overrides: list = field(default_factory=list)

    @property
    def name(self):
        return f"{self.testbench}/{self.test}#{self.seed}"


@dataclass
class Result:
    run: Run
    passed: bool
    seconds: float
    reason: str
    log: str


def parse_seeds(token):
    """'7' -> [7]; '1-10' -> [1..10]; '*'/'random' -> one random seed."""
    if token in ("*", "random"):
        return [random.randrange(1, 2**31 - 1)]
    match = re.fullmatch(r"(\d+)-(\d+)", token)
    if match:
        low, high = int(match.group(1)), int(match.group(2))
        if high < low:
            raise ValueError(f"empty seed range '{token}'")
        return list(range(low, high + 1))
    if token.isdigit():
        return [int(token)]
    raise ValueError(f"bad seed '{token}'")


def read_list(path):
    runs = []
    with open(path, encoding="utf-8") as handle:
        for lineno, raw in enumerate(handle, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            tokens = shlex.split(line)
            if len(tokens) < 2:
                raise ValueError(f"{path}:{lineno}: need at least <testbench> <test>")
            testbench, test = tokens[0], tokens[1]
            rest = tokens[2:]

            seeds = [1]
            if rest and "=" not in rest[0]:
                try:
                    seeds = parse_seeds(rest[0])
                except ValueError as exc:
                    raise ValueError(f"{path}:{lineno}: {exc}") from exc
                rest = rest[1:]

            for seed in seeds:
                runs.append(Run(testbench, test, seed, list(rest)))
    return runs


def find_tb_dir(name, tb_dirs):
    for base in tb_dirs:
        candidate = os.path.join(base, name)
        if os.path.isfile(os.path.join(candidate, "Makefile")):
            return candidate
    return None


def execute(run, tb_dirs, common, quiet):
    tb_dir = find_tb_dir(run.testbench, tb_dirs)
    if tb_dir is None:
        return Result(run, False, 0.0,
                      f"no testbench '{run.testbench}' under {', '.join(tb_dirs)}", "")

    command = ["make", "--no-print-directory", "-C", tb_dir, "run",
               f"TEST={run.test}", f"SEED={run.seed}"] + common + run.overrides

    start = time.monotonic()
    completed = subprocess.run(command, capture_output=True, text=True)
    elapsed = time.monotonic() - start

    log = os.path.join(tb_dir, "build", "logs", f"{run.test}-{run.seed}", "sim.log")

    if completed.returncode == 0:
        reason = "ok"
    else:
        # Prefer the checker's one-line verdict; fall back to the last
        # meaningful line of make's output.
        reason = ""
        for line in completed.stdout.splitlines():
            if "FAIL:" in line:
                reason = line.split("FAIL:", 1)[1].strip()
                break
        if not reason:
            tail = [l for l in (completed.stdout + completed.stderr).splitlines() if l.strip()]
            reason = tail[-1][:200] if tail else f"exit status {completed.returncode}"

    if not quiet and completed.returncode != 0:
        sys.stdout.write(completed.stdout[-4000:])
        sys.stdout.write(completed.stderr[-2000:])

    return Result(run, completed.returncode == 0, elapsed, reason, log)


def write_junit(path, results, total_seconds):
    suite = ET.Element("testsuite", {
        "name": "uvmake",
        "tests": str(len(results)),
        "failures": str(sum(1 for r in results if not r.passed)),
        "time": f"{total_seconds:.2f}",
    })
    for result in results:
        case = ET.SubElement(suite, "testcase", {
            "classname": result.run.testbench,
            "name": f"{result.run.test}#{result.run.seed}",
            "time": f"{result.seconds:.2f}",
        })
        if not result.passed:
            failure = ET.SubElement(case, "failure", {"message": result.reason})
            failure.text = f"log: {result.log}"
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    ET.ElementTree(suite).write(path, encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--list", required=True)
    parser.add_argument("--project-root", default=os.getcwd())
    parser.add_argument("--tb-dir", action="append", default=[],
                        help="directory holding testbenches (repeatable)")
    parser.add_argument("--jobs", type=int, default=os.cpu_count() or 4)
    parser.add_argument("--set", action="append", default=[], metavar="VAR=VALUE",
                        help="make variable applied to every run")
    parser.add_argument("--seeds", type=int, default=0,
                        help="override every entry to run this many seeds")
    parser.add_argument("--junit", help="write JUnit XML here")
    parser.add_argument("--quiet", action="store_true",
                        help="do not echo output from failing runs")
    args = parser.parse_args()

    tb_dirs = args.tb_dir or [os.path.join(args.project_root, "tb")]

    if not os.path.isfile(args.list):
        print(f"error: no regression list at {args.list}", file=sys.stderr)
        return 2
    try:
        runs = read_list(args.list)
    except ValueError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    if args.seeds > 0:
        expanded = []
        for run in runs:
            for index in range(args.seeds):
                expanded.append(Run(run.testbench, run.test, run.seed + index,
                                    list(run.overrides)))
        runs = expanded

    if not runs:
        print("error: regression list is empty", file=sys.stderr)
        return 2

    # Strip the quoting make added when forwarding VAR='value'.
    common = [item.replace("'", "") for item in args.set]

    print(f"[regress] {len(runs)} run(s) from {args.list}, {args.jobs} at a time")
    started = time.monotonic()
    results = []

    # Builds are not thread-safe against each other inside one testbench, so
    # make sure every testbench is built once, serially, before fanning out.
    for testbench in sorted({run.testbench for run in runs}):
        tb_dir = find_tb_dir(testbench, tb_dirs)
        if tb_dir is None:
            continue
        print(f"[regress] building {testbench}")
        build = subprocess.run(["make", "--no-print-directory", "-C", tb_dir, "build"]
                               + common, capture_output=True, text=True)
        if build.returncode != 0:
            sys.stdout.write(build.stdout[-4000:])
            sys.stderr.write(build.stderr[-2000:])
            print(f"[regress] build FAILED for {testbench}")
            return 1

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(execute, run, tb_dirs, common, args.quiet): run
                   for run in runs}
        for future in concurrent.futures.as_completed(futures):
            result = future.result()
            results.append(result)
            status = "PASS" if result.passed else "FAIL"
            detail = "" if result.passed else f"  ({result.reason})"
            print(f"[regress] {status}  {result.run.name}  {result.seconds:.1f}s{detail}")

    total = time.monotonic() - started
    results.sort(key=lambda r: (r.run.testbench, r.run.test, r.run.seed))
    failures = [r for r in results if not r.passed]

    if args.junit:
        write_junit(args.junit, results, total)
        print(f"[regress] JUnit XML: {args.junit}")

    print(f"[regress] {len(results) - len(failures)} passed, "
          f"{len(failures)} failed, {total:.1f}s wall")
    if failures:
        print("[regress] failures:")
        for result in failures:
            print(f"  {result.run.name}: {result.reason}")
            print(f"    {result.log}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
