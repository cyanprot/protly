#!/usr/bin/env python3
"""The test filter of a debug run: `[shots:<entry>,<entry>...]` in the head commit message (tower TOWER-SPEEDUP-1).

Usage (the message comes in the environment, never on a command line):
  SHOTS_MESSAGE=<commit message> shotsfilter.py            one -only-testing entry per line; nothing for a full run
  SHOTS_MESSAGE=<commit message> shotsfilter.py mem-wait   the ui-log line the memory sampler waits for
  SHOTS_MESSAGE=<commit message> shotsfilter.py unran <test-cases.txt>   selected entries with no passing test

An entry is a test class (`KeyboardShotsUITests`, `PhoneChecksUITests`) or a class and one of its methods
(`PhoneChecksUITests/test7_77`). A selected PhoneChecksUITests method brings `test0_access` first: the network and
clipboard methods read the Full Access it sets. Several `[shots:...]` tags join; a message without one is a full
run (`[shots]`). Anything else exits 2, so a typo never costs a run: an unknown class or method, an empty list,
other characters, a filter that measures no ID and no layout (test0_access or test0_probe alone), or a message
with both `[shots]` and a `[shots:...]` tag (a full run that quotes a tag must not quietly run part of the suite). A filtered run is a debug
run: the report says FILTER, IDs outside it are NOT-RUN (checks.py --ran), and run-shots.sh fails it when a selected
entry has no passing test case (`unran`).
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import checks  # noqa: E402

TAG = re.compile(r"\[shots:([^\]]*)\]")
ENTRY = re.compile(r"^(KeyboardShotsUITests|PhoneChecksUITests)(?:/([A-Za-z0-9_]+))?$")
ACCESS = "PhoneChecksUITests/test0_access"


def methods(cls):
    if cls == "PhoneChecksUITests":
        return set(checks.METHOD_IDS) | set(checks.OTHER_METHODS[cls])
    return set(checks.OTHER_METHODS[cls])


def parse(message):
    """The -only-testing entries, in order; None without a `[shots:...]` tag. ValueError on a bad entry."""
    tags = TAG.findall(message or "")
    if not tags:
        return None
    if "[shots]" in message:
        raise ValueError("both [shots] and a [shots:...] tag: a full run or a filtered one, not both")
    entries = []
    for tag in tags:
        for raw in tag.split(","):
            entry = raw.strip()
            if not entry:
                continue
            m = ENTRY.match(entry)
            if not m:
                raise ValueError(f"not a test class or class/method: {entry!r}")
            if m.group(2) is not None and m.group(2) not in methods(m.group(1)):
                raise ValueError(f"no method {m.group(2)!r} in {m.group(1)}")
            if entry not in entries:
                entries.append(entry)
    if not entries:
        raise ValueError("empty [shots:] filter")
    if not checks.covered_ids(entries):
        raise ValueError(f"the filter {','.join(entries)} measures no check ID and no layout")
    phone_methods = [e for e in entries if e.startswith("PhoneChecksUITests/")]
    if phone_methods and "PhoneChecksUITests" not in entries and ACCESS not in entries:
        entries.insert(entries.index(phone_methods[0]), ACCESS)
    return entries


def mem_wait(entries):
    """The `== ...` ui-log line that starts the memory sampler: test1 in a full run, else the selected phone method
    (after Full Access) that XCTest runs first; empty when no phone method runs."""
    if entries is None or "PhoneChecksUITests" in entries:
        return "== PhoneChecksUITests.test1"
    # XCTest runs a class's methods in name order, whatever order the tag lists them in.
    selected = sorted(m for c, _, m in (e.partition("/") for e in entries)
                      if c == "PhoneChecksUITests" and not m.startswith("test0_"))
    return f"== PhoneChecksUITests.{selected[0]}" if selected else ""


def unran(entries, test_cases):
    """The entries without a passing `Test Case` line in test-cases.txt: skipped, failed, renamed or never run."""
    passed = set(re.findall(r"^Test Case '-\[ProtlyCIUITests\.(\w+) (\w+)\]' passed", test_cases, re.M))
    missing = []
    for e in entries:
        cls, _, method = e.partition("/")
        if not any(c == cls and (not method or m == method) for c, m in passed):
            missing.append(e)
    return missing


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    try:
        entries = parse(os.environ.get("SHOTS_MESSAGE", ""))
    except ValueError as e:
        print(f"shotsfilter: {e}", file=sys.stderr)
        return 2
    if argv == ["mem-wait"]:
        print(mem_wait(entries))
    elif len(argv) == 2 and argv[0] == "unran":
        try:
            with open(argv[1], encoding="utf-8", errors="replace") as f:
                cases = f.read()
        except OSError:
            cases = ""
        for e in unran(entries or [], cases):
            print(e)
    elif not argv:
        for e in entries or []:
            print(e)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
