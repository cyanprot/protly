#!/usr/bin/env python3
"""Samples the keyboard extension's memory from the macOS side while the UI tests run (plan Task 1.4).

Usage: memsample.py <mem.txt> <probe-mem.txt> [--name ProtlyCIKeyboard] [--interval 2] [--wait-for FILE TEXT]

With --wait-for it touches nothing until FILE contains TEXT (run-shots.sh: the phone checks' first line in
ui-log.txt), so the layout scenarios run with no tool attached to the keyboard process.
Every interval: `pgrep -x <name>`, then per pid one `<epoch> <pid> rss <kb>` line (`ps -o rss=`) and, when one of
them worked on the first pid, one `<epoch> <pid> <method> <kb>` line for the best footprint method
(`footprint -p`, `sudo -n footprint -p`). `<epoch> - none -` when no process runs. `vmmap --summary` is not tried:
in run 8 it hung 20 s on the keyboard process (it suspends its target).
The first time a pid is seen, every method's exit code, first lines and parsed value go to probe-mem.txt
(plan Task 1.0 step 3). Runs until SIGTERM or SIGINT; every line is flushed at once.
"""

import argparse
import re
import signal
import subprocess
import sys
import time

UNITS = {"B": 1 / 1024, "KB": 1, "K": 1, "MB": 1024, "M": 1024, "GB": 1024 * 1024, "G": 1024 * 1024}


def parse_footprint(text):
    m = re.search(r"(?i)footprint:\s*([\d.]+)\s*(GB|MB|KB|B)\b", text or "")
    return int(float(m.group(1)) * UNITS[m.group(2).upper()]) if m else None


def parse_vmmap(text):
    m = re.search(r"Physical footprint:\s*([\d.]+)([KMG])", text or "")
    return int(float(m.group(1)) * UNITS[m.group(2)]) if m else None


def parse_rss(text):
    m = re.fullmatch(r"\s*(\d+)\s*", text or "")
    return int(m.group(1)) if m else None


def parse_pids(text):
    return [int(p) for p in (text or "").split() if p.isdigit()]


METHODS = [
    ("footprint", lambda pid: ["footprint", "-p", str(pid)], parse_footprint),
    ("sudo-footprint", lambda pid: ["sudo", "-n", "footprint", "-p", str(pid)], parse_footprint),
    ("rss", lambda pid: ["ps", "-o", "rss=", "-p", str(pid)], parse_rss),
]


def has_text(path, text):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return text in f.read()
    except OSError:
        return False


def run(cmd, timeout=20):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout + p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return -1, f"{type(e).__name__}: {e}"


def probe(pid, out):
    """Tries every method on one pid, logs each, and returns the name of the best footprint method or None."""
    chosen = None
    for name, cmd, parse in METHODS:
        code, text = run(cmd(pid))
        value = parse(text)
        head = "\n".join("    " + line for line in text.splitlines()[:8])
        out.write(f"{name}: `{' '.join(cmd(pid))}` exit {code} value_kb {value}\n{head}\n")
        if value is not None and chosen is None and name != "rss":
            chosen = name
    out.write(f"chosen footprint method: {chosen or 'none (rss only)'}\n")
    out.flush()
    return chosen


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("mem")
    ap.add_argument("probe")
    ap.add_argument("--name", default="ProtlyCIKeyboard")
    ap.add_argument("--interval", type=float, default=2.0)
    ap.add_argument("--wait-for", nargs=2, metavar=("FILE", "TEXT"))
    args = ap.parse_args(argv)

    stop = []
    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, lambda *_: stop.append(True))

    method = None
    probed = False
    with open(args.mem, "a", encoding="utf-8") as mem, open(args.probe, "a", encoding="utf-8") as pr:
        pr.write(f"memsample: process name {args.name}, interval {args.interval} s\n")
        pr.flush()
        if args.wait_for:
            while not stop and not has_text(*args.wait_for):
                time.sleep(0.5)
            pr.write(f"memsample: started at {time.time():.3f} after {args.wait_for[1]!r} in {args.wait_for[0]}\n")
            pr.flush()
        while not stop:
            t = time.time()
            code, text = run(["pgrep", "-x", args.name], timeout=10)
            pids = parse_pids(text) if code == 0 else []
            if not pids:
                mem.write(f"{t:.3f} - none -\n")
            if pids and not probed:
                pr.write(f"pgrep -x {args.name}: {' '.join(map(str, pids))}\n")
                method = probe(pids[0], pr)
                probed = True
            for pid in pids:
                rss = parse_rss(run(["ps", "-o", "rss=", "-p", str(pid)])[1])
                if rss is not None:
                    mem.write(f"{t:.3f} {pid} rss {rss}\n")
                if method:
                    name, cmd, parse = next(m for m in METHODS if m[0] == method)
                    kb = parse(run(cmd(pid))[1])
                    if kb is not None:
                        mem.write(f"{t:.3f} {pid} {name} {kb}\n")
            mem.flush()
            while not stop and time.time() - t < args.interval:
                time.sleep(0.1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
