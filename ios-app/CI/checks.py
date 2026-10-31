#!/usr/bin/env python3
"""Assembles the phone checks of one CI run (docs/plans/2026-10-30-sim-phone-checks.md, Tasks 1.2-1.6 and 2.3).

Usage: checks.py <dir> [--network-key]

--network-key: the run had the CI key (run-shots.sh passes it with HAS_KEY=true), so a `SKIP no network key` line
means the key did not reach the tests and is FAIL unreadable.

Reads from <dir>:
- checks.txt: `CHECK <id> PASS|FAIL|RECORD|SKIP|PENDING <evidence>` lines written by UITests/PhoneChecksUITests.swift.
- ui-log.txt: `MARK <name> <epoch seconds>` lines (relaunch-before/-after, mem-start/-end).
- mem.txt: `<epoch> <pid> <method> <kb>` samples written by memsample.py (`<epoch> - none -` with no process).

Resolves the PENDING lines (6.8-9 relaunch, 6.8-10 memory) from the marks and the samples, and the network items'
PENDING lines (model output as `<group>#<try>="..."`) with the script rules in RULES; adds a FAIL `unreadable`
line for every expected ID without a line (and for every malformed line), sorts by ID, keeps the test's own lines in
checks-raw.txt and rewrites checks.txt with the final lines. Prints `CHECKS`, the lines and
`CHECKS pass N fail N record N skip N`. Exit 1 when any line is FAIL.
"""

import os
import re
import sys
import unicodedata
from dataclasses import dataclass

# Every ID of the plan's Task 1.3 table (Sprint 001) and Task 2.3 table (Sprint 002, network).
OFFLINE_IDS = [f"6.8-{i}" for i in range(1, 12)] + ["ws-1", "ws-2", "ws-3"] + [
    "8.5-1o", "8.5-2o", "8.5-6o", "8.5-7o", "8.5-8o", "8.5-9o", "icon"]
NETWORK_IDS = ["6.8-11"] + [f"8.5-{i}" for i in (1, 3, 4, 5, 6, 7, 8, 9, 10)] + [f"7.7-{i}" for i in range(1, 7)]
EXPECTED_IDS = OFFLINE_IDS + [i for i in NETWORK_IDS if i not in OFFLINE_IDS]

STATUSES = ("PASS", "FAIL", "RECORD", "SKIP", "PENDING")
# Preferred memory method first (memsample.py writes these names).
METHODS = ("footprint", "sudo-footprint", "vmmap", "rss")
# A sample further than this from its mark does not describe the moment of the mark.
MAX_SAMPLE_DISTANCE = 6.0
RELAUNCH_EXPECTED = "wyd "


@dataclass
class Check:
    id: str
    status: str
    evidence: str

    def line(self):
        return f"CHECK {self.id} {self.status} {self.evidence}".rstrip()


def unreadable(check_id, why):
    return Check(check_id, "FAIL", f"unreadable: {why}")


def parse_line(line):
    """One checks.txt line; None for a blank line. Anything malformed is FAIL unreadable."""
    text = line.strip()
    if not text:
        return None
    parts = text.split(" ", 3)
    if parts[0] != "CHECK" or len(parts) < 3:
        check_id = parts[1] if parts[0] == "CHECK" and len(parts) == 2 else "malformed"
        return unreadable(check_id, f"malformed line {text[:120]!r}")
    if parts[2] not in STATUSES:
        return unreadable(parts[1], f"malformed line {text[:120]!r}")
    evidence = parts[3] if len(parts) > 3 else ""
    if parts[2] == "PASS" and not evidence.strip():
        return unreadable(parts[1], "PASS without evidence")
    return Check(parts[1], parts[2], evidence)


def unescape(value):
    """Backslash escapes as the Swift side's q() writes them."""
    return re.sub(r"\\(.)", lambda e: "\n" if e.group(1) == "n" else e.group(1), value)


def quoted_field(text, name):
    """The value of name="..." in a line (backslash escapes as the Swift side writes them), or None."""
    m = re.search(name + r'="((?:[^"\\]|\\.)*)"', text)
    if not m:
        return None
    return unescape(m.group(1))


def same_text(a, b):
    return unicodedata.normalize("NFC", a) == unicodedata.normalize("NFC", b)


def sort_key(check_id):
    return [(0, int(p), "") if p.isdigit() else (1, 0, p) for p in re.findall(r"\d+|[A-Za-z]+", check_id)]


def summary(lines):
    n = {s: sum(1 for c in lines if c.status == s) for s in ("PASS", "FAIL", "RECORD", "SKIP")}
    return f"CHECKS pass {n['PASS']} fail {n['FAIL']} record {n['RECORD']} skip {n['SKIP']}"


def parse_marks(text):
    marks = {}
    for line in (text or "").splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0] == "MARK":
            try:
                marks[parts[1]] = float(parts[2])
            except ValueError:
                pass
    return marks


@dataclass
class Sample:
    t: float
    pid: int
    method: str
    kb: int


def parse_mem(text):
    samples = []
    for line in (text or "").splitlines():
        parts = line.split()
        if len(parts) != 4:
            continue
        try:
            samples.append(Sample(float(parts[0]), int(parts[1]), parts[2], int(parts[3])))
        except ValueError:
            continue  # "- none -" lines and junk
    return samples


def best_method(samples):
    present = {s.method for s in samples}
    return next((m for m in METHODS if m in present), None)


def nearest(samples, t, method=None):
    """Samples of the time nearest t (one per pid) within MAX_SAMPLE_DISTANCE, for one method."""
    pool = [s for s in samples if method is None or s.method == method]
    if not pool:
        return []
    best = min(pool, key=lambda s: abs(s.t - t))
    if abs(best.t - t) > MAX_SAMPLE_DISTANCE:
        return []
    return sorted((s for s in pool if s.t == best.t), key=lambda s: s.pid)


def mb(kb):
    return f"{kb / 1024:.1f} MB"


def pids(samples):
    return ",".join(str(s.pid) for s in samples)


def resolve_relaunch(check, marks, samples):
    field = quoted_field(check.evidence, "field")
    if field is None:
        return unreadable(check.id, f"no field text in {check.evidence!r}")
    if not same_text(field, RELAUNCH_EXPECTED):
        return Check(check.id, "FAIL", f"field={field!r} expected {RELAUNCH_EXPECTED!r}")
    if "relaunch-before" not in marks or "relaunch-after" not in marks:
        return unreadable(check.id, f"field matched, relaunch marks missing ({sorted(marks)})")
    before = nearest(samples, marks["relaunch-before"], "rss")
    after = nearest(samples, marks["relaunch-after"], "rss")
    if not before or not after:
        return unreadable(check.id, "field matched, no keyboard pid sampled near a relaunch mark")
    span = f"pid {pids(before)} -> {pids(after)}"
    if {s.pid for s in before} & {s.pid for s in after}:
        return Check(check.id, "RECORD", f"same process: field={field!r} {span}")
    return Check(check.id, "PASS", f"field={field!r} {span} (new process)")


def resolve_memory(check, marks, samples):
    if "mem-start" not in marks or "mem-end" not in marks:
        return unreadable(check.id, f"mem-start/mem-end marks missing ({sorted(marks)})")
    method = best_method(samples)
    start = nearest(samples, marks["mem-start"], method)
    end = nearest(samples, marks["mem-end"], method)
    if method is None or not start or not end:
        return unreadable(check.id, "no keyboard memory sample near a mark")
    if len(start) != 1 or len(end) != 1:
        return Check(check.id, "RECORD", f"several keyboard processes: start pid {pids(start)} "
                     f"end pid {pids(end)} ({method}), not comparable")
    s, e = start[0], end[0]
    if s.pid != e.pid:
        return Check(check.id, "RECORD", f"pid changed, not comparable: start pid {s.pid} {mb(s.kb)}, "
                     f"end pid {e.pid} {mb(e.kb)} ({method})")
    growth = (e.kb - s.kb) / 1024
    resolution = "; footprint prints whole MB, so growth under 1 MB reads as zero" if "footprint" in method else ""
    return Check(check.id, "RECORD", f"start {mb(s.kb)} end {mb(e.kb)} growth {growth:+.1f} MB over "
                 f"{check.evidence or 'the presentations'} ({method}, pid {s.pid}; macOS-side, not the phone's "
                 f"limit{resolution})")


# Script rules for model output (plan Task 2.3). Text is NFC first: conjoining jamo compose into syllables.
def _nfc(s):
    return unicodedata.normalize("NFC", s)


def has_cyrillic(s):
    return any(0x0400 <= ord(c) <= 0x04FF for c in _nfc(s))


def has_hangul(s):
    return any(0xAC00 <= ord(c) <= 0xD7A3 or 0x3131 <= ord(c) <= 0x318E for c in _nfc(s))


def has_kana_or_kanji(s):
    return any(0x3040 <= ord(c) <= 0x30FF or 0x4E00 <= ord(c) <= 0x9FFF for c in _nfc(s))


def is_latin(s):
    return any(c.isascii() and c.isalpha() for c in s) and not has_hangul(s)


def contains(sub, case=True):
    if case:
        return (f"contains {sub!r}", lambda s: _nfc(sub) in _nfc(s))
    return (f"contains {sub!r}", lambda s: _nfc(sub).casefold() in _nfc(s).casefold())


def contains_word(word):
    """Case-insensitive, whole word: `comprastes` is not `compraste`."""
    pattern = re.compile(r"(?<!\w)" + re.escape(word) + r"(?!\w)", re.IGNORECASE)
    return (f"contains the word {word!r}", lambda s: pattern.search(_nfc(s)) is not None)


def lacks(sub):
    """Case-insensitive: `KO:` and `Pottery` count."""
    return (f"no {sub!r}", lambda s: _nfc(sub).casefold() not in _nfc(s).casefold())


CYRILLIC = ("Cyrillic", has_cyrillic)
HANGUL = ("Hangul", has_hangul)
NO_HANGUL = ("no Hangul", lambda s: not has_hangul(s))
KANA_OR_KANJI = ("kana or kanji", has_kana_or_kanji)
LATIN = ("Latin", is_latin)
ABOUT_ME = [contains("Moonbeam Kiln"), lacks("pottery"), lacks("Victoria"), NO_HANGUL]

# ID -> output group -> the rules every try of that group is held to. The test writes `<group>#<n>="..."` per try
# (n = 1, and 2 after a retry); a group passes when one try passes all its rules. "No Hangul" on a translation into
# another script is how the field shows only the translation (the draft was Hangul).
RULES = {
    "6.8-11": {"out": [LATIN]},
    "8.5-1": {"out": [CYRILLIC, NO_HANGUL, lacks("ru:"), contains("спасла")]},
    "8.5-3": {"out": [KANA_OR_KANJI, NO_HANGUL, lacks("ㅋ"), lacks("lol")]},
    "8.5-4": {"out": [contains("cansado", case=False), lacks("cansada"), NO_HANGUL]},
    "8.5-5": {"out": [LATIN]},
    "8.5-6": {"out": [LATIN]},
    "8.5-7": {"out": [HANGUL, contains("ㅋㅋ"), contains("돼"), contains("말해줘"), lacks("ko:")]},
    "8.5-8": {"out": [HANGUL, lacks("ko:")]},
    "8.5-9": {"out": [contains("color", case=False), contains_word("compraste"), contains("jaja", case=False),
                      lacks("colour"), lacks("conprastes")]},
    "7.7-2": {"out": ABOUT_ME},
    "7.7-3": {"panel": [HANGUL], "out": ABOUT_ME},
}

TRY = re.compile(r'(?<![\w#])([a-z]+)#(\d+)="((?:[^"\\]|\\.)*)"')


def tries(evidence):
    """{group: [(n, text), ...]} from the `<group>#<n>="..."` pairs of a line, in order."""
    found = {}
    for m in TRY.finditer(evidence):
        found.setdefault(m.group(1), []).append((int(m.group(2)), unescape(m.group(3))))
    return found


def resolve_rules(check, marks, samples):
    found = tries(check.evidence)
    missing = [g for g in RULES[check.id] if g not in found]
    if missing:
        return unreadable(check.id, f"no {'/'.join(missing)} output in {check.evidence[:200]!r}")
    verdicts = []
    passed = True
    for group, rules in RULES[check.id].items():
        group_ok = False
        for n, text in found[group]:
            fails = [name for name, ok in rules if not ok(text)]
            verdicts.append(f"{group}#{n} " + ("ok" if not fails else "fails " + ", ".join(fails)))
            group_ok = group_ok or not fails
        passed = passed and group_ok
    return Check(check.id, "PASS" if passed else "FAIL", f"{check.evidence} => {'; '.join(verdicts)}")


RESOLVERS = {"6.8-9": resolve_relaunch, "6.8-10": resolve_memory, **{i: resolve_rules for i in RULES}}


NO_KEY = "no network key"


def guard_network(c, network_key):
    """A RULES item passes only through its model output; with the key a missing key is the CI's failure."""
    if c.id in RULES and c.status == "PASS":
        return unreadable(c.id, f"PASS without model output to judge: {c.evidence[:200]!r}")
    if network_key and c.status == "SKIP" and c.evidence.startswith(NO_KEY):
        return unreadable(c.id, f"the run had the key but the test wrote {c.evidence[:120]!r}")
    return c


def assemble(checks_text, log_text, mem_text, network_key=False):
    """The final, sorted lines. None for checks_text means the test wrote no checks.txt."""
    by_id = {}
    extra = []
    if checks_text is None:
        extra.append("no checks.txt")
    for raw in (checks_text or "").splitlines():
        c = parse_line(raw)
        if c is None:
            continue
        if c.id == "malformed":
            c.id = f"malformed-{len(extra) + 1}"
            extra.append(c.id)
        if c.id in by_id:
            # A test writes each ID once: a second line must not hide the first (a FAIL, a malformed line).
            first = by_id[c.id]
            c = unreadable(c.id, f"duplicate CHECK lines: {first.status} {first.evidence[:80]!r}; "
                                 f"{c.status} {c.evidence[:80]!r}")
        by_id[c.id] = c
    marks = parse_marks(log_text)
    samples = parse_mem(mem_text)
    for check_id, c in list(by_id.items()):
        if c.status != "PENDING":
            continue
        resolver = RESOLVERS.get(check_id)
        by_id[check_id] = resolver(c, marks, samples) if resolver else unreadable(check_id, f"unresolved PENDING {c.evidence}")
    for check_id, c in list(by_id.items()):
        if c.evidence.startswith("unreadable") or c.status not in ("PASS", "SKIP"):
            continue
        # Lines the test wrote PASS directly; resolved PENDING lines carry their verdict after " => ".
        if c.status == "PASS" and " => " in c.evidence:
            continue
        by_id[check_id] = guard_network(c, network_key)
    for check_id in EXPECTED_IDS:
        if check_id not in by_id:
            why = "no checks.txt" if checks_text is None else "no CHECK line"
            by_id[check_id] = unreadable(check_id, why)
    return sorted(by_id.values(), key=lambda c: sort_key(c.id))


def read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    network_key = "--network-key" in argv
    argv = [a for a in argv if a != "--network-key"]
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    d = argv[0]
    raw = read(os.path.join(d, "checks.txt"))
    final = assemble(raw, read(os.path.join(d, "ui-log.txt")), read(os.path.join(d, "mem.txt")), network_key)
    raw_copy = os.path.join(d, "checks-raw.txt")
    if raw is not None and not os.path.exists(raw_copy):
        with open(raw_copy, "w", encoding="utf-8") as f:
            f.write(raw)
    lines = [c.line() for c in final]
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "checks.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("CHECKS")
    for line in lines:
        print(line)
    print(summary(final))
    return 1 if any(c.status == "FAIL" for c in final) else 0


if __name__ == "__main__":
    sys.exit(main())
