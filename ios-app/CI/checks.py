#!/usr/bin/env python3
"""Assembles the phone checks of one CI run (docs/plans/2026-10-30-sim-phone-checks.md, Tasks 1.2-1.6 and 2.3, and
docs/plans/2026-10-30-typing-fixes.md, Sprint 004: dark-1, ret-*, menu-*, pad-*).

Usage: checks.py <dir> [--network-key] [--ran <entry>,<entry>...]

--network-key: the run had the CI key (run-shots.sh passes it with HAS_KEY=true), so a `SKIP no network key` line
means the key did not reach the tests and is FAIL unreadable.
--ran: a filtered run's -only-testing entries (shotsfilter.py); the IDs of methods outside them are NOT-RUN.

Reads from <dir>:
- checks.txt: `CHECK <id> PASS|FAIL|RECORD|SKIP|PENDING <evidence>` lines written by UITests/PhoneChecksUITests.swift.
- ui-log.txt: `MARK <name> <epoch seconds>` lines (relaunch-before/-after, mem-start/-end).
- mem.txt: `<epoch> <pid> <method> <kb>` samples written by memsample.py (`<epoch> - none -` with no process).

Resolves the PENDING lines (6.8-9 relaunch, 6.8-10 memory) from the marks and the samples, the network items'
PENDING lines (model output as `<group>#<try>="..."`) with the script rules in RULES, and the typing-fixes lines
(ret-*, menu-*, pad-* from their quoted readings; dark-1 from its two screenshots in <dir>, with Pillow); adds a FAIL `unreadable`
line for every expected ID without a line (and for every malformed line), sorts by ID, keeps the test's own lines in
checks-raw.txt and rewrites checks.txt with the final lines. Prints `CHECKS`, the lines and
`CHECKS pass N fail N record N skip N` (plus ` not-run N` in a filtered run). Exit 1 when any line is FAIL.
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
# typing-fixes 004: the web composer (dark-1, Return in three web fields), the edit menu and the space trackpad.
WEB_FIELDS = ("textarea", "input", "composer")
RET_IDS = [f"ret-{step}-{field}" for step in range(1, 6) for field in WEB_FIELDS]
TYPING_IDS = ["dark-1"] + RET_IDS + ["menu-0", "menu-1", "menu-4", "pad-1", "pad-2", "pad-3"]
EXPECTED_IDS = OFFLINE_IDS + [i for i in NETWORK_IDS if i not in OFFLINE_IDS] + TYPING_IDS
# The PhoneChecksUITests method that writes each ID. A filtered run (`[shots:...]`, shotsfilter.py) marks the IDs of
# methods it did not select NOT-RUN. Items inside one method depend on each other (6.8-9 on 6.8-8's learned word,
# 8.5-10 and 7.7-4 on earlier timings), so a method is the smallest unit a filter selects.
METHOD_IDS = {
    "test1_68": [f"6.8-{i}" for i in (1, 2, 3, 4, 5, 6, 7, 8, 9, 11)],
    "test2_ws": ["ws-1", "ws-2", "ws-3"],
    "test3_85offline": ["8.5-1o", "8.5-2o", "8.5-6o", "8.5-7o", "8.5-8o", "8.5-9o"],
    "test4_memory": ["6.8-10"],
    "test5_icon": ["icon"],
    "test5a_web": ["dark-1"] + RET_IDS,
    "test5b_menu": ["menu-0", "menu-1", "menu-4"],
    "test5c_pad": ["pad-1", "pad-2", "pad-3"],
    "test6_85net": [f"8.5-{i}" for i in (1, 3, 4, 5, 6, 7, 8, 9, 10)],
    "test7_77": [f"7.7-{i}" for i in range(1, 7)],
}
# Methods that write no ID of their own (Full Access, the probe) and the layout test.
OTHER_METHODS = {"PhoneChecksUITests": ("test0_access", "test0_probe"), "KeyboardShotsUITests": ("testScenarios",)}
NOT_RUN = "NOT-RUN"

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
    n = {s: sum(1 for c in lines if c.status == s) for s in ("PASS", "FAIL", "RECORD", "SKIP", NOT_RUN)}
    text = f"CHECKS pass {n['PASS']} fail {n['FAIL']} record {n['RECORD']} skip {n['SKIP']}"
    return text + (f" not-run {n[NOT_RUN]}" if n[NOT_RUN] else "")


def known_entry(entry):
    """A test class, or a class and one of its methods, as shotsfilter.py passes them."""
    cls, sep, method = entry.partition("/")
    if cls not in OTHER_METHODS:
        return False
    methods = set(OTHER_METHODS[cls]) | (set(METHOD_IDS) if cls == "PhoneChecksUITests" else set())
    return not sep or method in methods


def covered_ids(entries):
    """The IDs (and "layout") a run with these -only-testing entries writes; None is the full run."""
    if entries is None:
        return set(EXPECTED_IDS) | {"layout"}
    ids = set()
    for entry in entries:
        cls, _, method = entry.partition("/")
        if cls == "KeyboardShotsUITests":
            ids.add("layout")
        elif cls == "PhoneChecksUITests":
            ids.update(i for m, v in METHOD_IDS.items() if not method or m == method for i in v)
    return ids


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


def resolve_relaunch(check, marks, samples, run_dir=None):
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


def resolve_memory(check, marks, samples, run_dir=None):
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


def contains_any(*subs):
    """One of several spellings (8.5-7: the auxiliary verb spaced or joined)."""
    return (f"contains one of {list(subs)!r}", lambda s: any(_nfc(sub) in _nfc(s) for sub in subs))


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
    # 말해 줘 (spaced, the standard) or 말해줘 (joined): tower ruling 2026-10-31 after run 41.
    "8.5-7": {"out": [HANGUL, contains("ㅋㅋ"), contains("돼"), contains_any("말해 줘", "말해줘"), lacks("ko:")]},
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


def resolve_rules(check, marks, samples, run_dir=None):
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


# typing-fixes 004 (docs/plans/2026-10-30-typing-fixes.md, Sprint 004). UITests/TypingChecks.swift writes each line
# PENDING with its readings; the rules below decide. A resolver takes (check, marks, samples, run_dir).

def int_field(text, name):
    """The value of name=<int> in a line, or None."""
    m = re.search(r"(?<![\w-])" + re.escape(name) + r"=(-?\d+)(?![\w.])", text)
    return int(m.group(1)) if m else None


def verdict(check, problems, notes=()):
    """PASS without problems, FAIL with them; the evidence keeps the readings and says why after " => "."""
    why = "; ".join(list(problems) + list(notes)) or "ok"
    return Check(check.id, "FAIL" if problems else "PASS", f"{check.evidence} => {why}")


def resolve_ret(check, marks=None, samples=None, run_dir=None):
    """ret-<step>-<field> (enter-clears-web.md, Simulator scenario): the text typed before Return is kept. textarea:
    the text plus a line; input: the text, and a submit (if any) carries all of it; composer (Enter to send): sent
    exactly once, exactly the text, and the composer left with no text. `before` is the field when the page saw
    Return (keydown Enter, a line-break beforeinput or the submit): the keyboard's reading, which must be `want`."""
    field = check.id.rsplit("-", 1)[1]
    ev = check.evidence
    want = quoted_field(ev, "want")
    value = quoted_field(ev, "value")
    if want is None or value is None:
        return unreadable(check.id, f"no want/value in {ev[:200]!r}")
    problems, notes = [], []
    before = quoted_field(ev, "before")
    if before is None:
        notes.append("no Return event seen by the page")
    elif not same_text(before, want):
        problems.append(f"typed {before!r} before Return, not {want!r}")
    if field == "textarea":
        if not same_text(value, want + "\n"):
            problems.append(f"value {value!r}, want {want + chr(10)!r}")
    elif field == "input":
        if not same_text(value, want):
            problems.append(f"value {value!r}, want {want!r}")
        submits = int_field(ev, "submit-count") or 0
        submitted = quoted_field(ev, "submitted")
        if submits == 0:
            notes.append("no submit")
        elif submitted is None or not same_text(submitted, want):
            problems.append(f"submitted {submitted!r}, want {want!r}")
    else:
        sends = int_field(ev, "sent-count") or 0
        sent = quoted_field(ev, "sent")
        if sends == 0 or sent is None:
            problems.append(f"nothing sent (composer {value!r})")
        else:
            if sends != 1:
                problems.append(f"sent {sends} times")
            if not same_text(sent, want):
                problems.append(f"sent {sent!r}, want {want!r}")
            if value.strip():
                problems.append(f"composer kept {value!r}")
    return verdict(check, problems, notes)


def resolve_menu(check, marks=None, samples=None, run_dir=None):
    """menu-0 (Apple's keyboard, the control) and menu-1 (Protly, double-tap on the last word, no space): the edit
    menu offers Copy (edit-menu-missing.md 4.3, S0 and S1)."""
    menu = quoted_field(check.evidence, "menu")
    if menu is None:
        return unreadable(check.id, f"no menu reading in {check.evidence[:200]!r}")
    items = [m for m in menu.split(",") if m]
    return verdict(check, [] if "Copy" in items else [f"no Copy in the edit menu ({items or 'no menu'})"])


# S4: ㅎ typed over the double-tapped 오늘 replaces it. The same key read as Latin (`g`) replaces it too: the item is
# about the selection, not the language reading.
MENU4_OK = {"안녕 ㅎ": None, "안녕 g": "the key came out Latin, still a replacement"}


def resolve_menu4(check, marks=None, samples=None, run_dir=None):
    """menu-4 (S4, H3): after menu-1's selection, typing ㅎ replaces the selected word."""
    field = quoted_field(check.evidence, "field")
    if field is None:
        return unreadable(check.id, f"no field in {check.evidence[:200]!r}")
    match = next((k for k in MENU4_OK if same_text(field, k)), None)
    if match is None:
        return verdict(check, [f"field {field!r}, want {list(MENU4_OK)[0]!r} (the selection replaced)"])
    return verdict(check, [], [MENU4_OK[match]] if MENU4_OK[match] else [])


# pad-2 must move at least this share of pad-1's move: a drag that froze once the finger rose would stop early.
PAD_RISING_SHARE = 0.75


def resolve_pad(check, marks=None, samples=None, run_dir=None):
    """pad-1: a 1 s press on space, then a drag left moves the caret left. pad-2: the same drag with the finger rising
    80 pt keeps moving (at least PAD_RISING_SHARE of pad-1's move, `ref`). pad-3: `안녕`, one step left lands at
    `want-sel` (안|녕). In every one the text is unchanged and nothing is selected."""
    ev = check.evidence
    want, field = quoted_field(ev, "want"), quoted_field(ev, "field")
    sel0, sel1 = int_field(ev, "sel0"), quoted_field(ev, "sel1")
    m = re.fullmatch(r"(\d+),(\d+)", sel1 or "")
    if want is None or field is None or sel0 is None or not m:
        return unreadable(check.id, f"no want/field/sel0/sel1 in {ev[:200]!r}")
    loc, length = int(m.group(1)), int(m.group(2))
    problems, notes = [], []
    if not same_text(field, want):
        problems.append(f"field {field!r}, want {want!r} unchanged")
    if length:
        problems.append(f"a selection of {length}, not a caret")
    moved = sel0 - loc
    notes.append(f"moved {moved}")
    if check.id == "pad-1":
        if moved < 1:
            problems.append("the caret did not move left")
    elif check.id == "pad-2":
        ref = int_field(ev, "ref")
        if ref is None or ref < 1:
            return unreadable(check.id, f"no pad-1 move to compare with in {ev[:200]!r}")
        if moved < 1 or moved < PAD_RISING_SHARE * ref:
            problems.append(f"moved {moved} while rising, under {PAD_RISING_SHARE:.0%} of pad-1's {ref}")
    else:
        target = int_field(ev, "want-sel")
        if target is None:
            return unreadable(check.id, f"no want-sel in {ev[:200]!r}")
        if loc != target:
            problems.append(f"caret at {loc}, want {target}")
    return verdict(check, problems, notes)


# dark-1: a pixel is ink when its color is further than this from the field's background (measure.py's TEXT_DIFF).
INK_DIFF = 96
# Fewer ink pixels than this: no word drawn (a two-syllable word at 17 pt is thousands at 3x).
DARK_MIN_INK = 150
# Ink while typing and after the space may differ by this share (antialiasing), and their mean tone too.
DARK_TOLERANCE = 0.05
DARK_TONE_TOLERANCE = 0.15
# A row whose longest ink run spans this share of the word's width (and at least UNDERLINE_MIN px) is an underline:
# a glyph stroke spans one syllable at most.
UNDERLINE_SHARE = 0.6
UNDERLINE_MIN = 20


def measure_word(image, rect, points):
    """Ink in `rect` (points: x, y, w, h) of a screenshot `points` wide: the pixel count, the mean distance from the
    background (the crop's most common color), the ink's width, the longest horizontal ink run and whether that run
    is an underline."""
    img = image.convert("RGB")
    scale = img.width / points
    x, y, w, h = rect
    box = (int(round(x * scale)), int(round(y * scale)), int(round((x + w) * scale)), int(round((y + h) * scale)))
    crop = img.crop(box)
    cw, ch = crop.size
    raw = crop.tobytes()
    data = [tuple(raw[i:i + 3]) for i in range(0, len(raw), 3)]
    counts = {}
    for p in data:
        counts[p] = counts.get(p, 0) + 1
    bg = max(counts, key=counts.get) if counts else (0, 0, 0)
    ink = 0
    tone = 0
    xs = []
    longest = 0
    for row in range(ch):
        run = 0
        for col in range(cw):
            p = data[row * cw + col]
            d = abs(p[0] - bg[0]) + abs(p[1] - bg[1]) + abs(p[2] - bg[2])
            if d > INK_DIFF:
                ink += 1
                tone += d
                xs.append(col)
                run += 1
                longest = max(longest, run)
            else:
                run = 0
    width = (max(xs) - min(xs) + 1) if xs else 0
    underline = width > 0 and longest >= max(UNDERLINE_SHARE * width, UNDERLINE_MIN)
    return {"ink": ink, "tone": tone / ink if ink else 0.0, "width": width, "run": longest, "underline": underline}


def resolve_dark(check, marks=None, samples=None, run_dir=None):
    """dark-1 (marked-text-dark.md, Simulator scenario 2): on the dark web page the word being typed has the same ink
    as after a space (count and tone), and no underline. The screenshots are c-dark-1-*.png in the run folder."""
    ev = check.evidence
    names = (quoted_field(ev, "typing"), quoted_field(ev, "space"))
    m = re.search(r"(?<![\w-])rect=(-?[\d.]+),(-?[\d.]+),([\d.]+),([\d.]+)(?![\w,])", ev)
    points = int_field(ev, "points")
    if None in names or not m or not points:
        return unreadable(check.id, f"no typing/space/rect/points in {ev[:200]!r}")
    if run_dir is None:
        return unreadable(check.id, "no run folder to read the screenshots from")
    try:
        from PIL import Image
    except ImportError:
        return unreadable(check.id, "Pillow is not installed")
    rect = tuple(float(v) for v in m.groups())
    shots = []
    for name in names:
        try:
            with Image.open(os.path.join(run_dir, name)) as img:
                shots.append(measure_word(img, rect, points))
        except OSError as e:
            return unreadable(check.id, f"{name}: {e}")
    typing, space = shots
    problems = []
    before, after = quoted_field(ev, "before"), quoted_field(ev, "after")
    if before is not None and after is not None and not same_text(after, before + " "):
        problems.append(f"typed {before!r}, then {after!r} after the space")
    for name, s in (("typing", typing), ("space", space)):
        if s["ink"] < DARK_MIN_INK:
            problems.append(f"{name}: no word ({s['ink']} ink px)")
    if typing["underline"]:
        problems.append(f"underline while typing (a {typing['run']} px run under a {typing['width']} px word)")
    if space["ink"] >= DARK_MIN_INK:
        if abs(typing["ink"] - space["ink"]) > DARK_TOLERANCE * space["ink"]:
            problems.append(f"ink differs: typing {typing['ink']} px, after the space {space['ink']} px")
        if abs(typing["tone"] - space["tone"]) > DARK_TONE_TOLERANCE * space["tone"]:
            problems.append(f"tone differs: typing {typing['tone']:.0f}, after the space {space['tone']:.0f}")
    notes = [f"ink typing {typing['ink']} space {space['ink']}, tone {typing['tone']:.0f}/{space['tone']:.0f}, "
             f"longest run {typing['run']} of {typing['width']} px"]
    return verdict(check, problems, notes)


TYPING_RESOLVERS = {
    "dark-1": resolve_dark,
    **{i: resolve_ret for i in RET_IDS},
    "menu-0": resolve_menu,
    "menu-1": resolve_menu,
    "menu-4": resolve_menu4,
    **{i: resolve_pad for i in ("pad-1", "pad-2", "pad-3")},
}


RESOLVERS = {"6.8-9": resolve_relaunch, "6.8-10": resolve_memory, **{i: resolve_rules for i in RULES},
             **TYPING_RESOLVERS}


NO_KEY = "no network key"


def guard_network(c, network_key):
    """A RULES item passes only through its model output; with the key a missing key is the CI's failure."""
    if c.id in RULES and c.status == "PASS":
        return unreadable(c.id, f"PASS without model output to judge: {c.evidence[:200]!r}")
    if network_key and c.status == "SKIP" and c.evidence.startswith(NO_KEY):
        return unreadable(c.id, f"the run had the key but the test wrote {c.evidence[:120]!r}")
    return c


def assemble(checks_text, log_text, mem_text, network_key=False, ran=None, run_dir=None):
    """The final, sorted lines. None for checks_text means the test wrote no checks.txt. `ran` (covered_ids) is the
    set of IDs a filtered run selected: an expected ID outside it without a line is NOT-RUN, not FAIL. `run_dir`: the
    run folder, for the resolvers that read a screenshot (dark-1)."""
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
        by_id[check_id] = (resolver(c, marks, samples, run_dir) if resolver
                           else unreadable(check_id, f"unresolved PENDING {c.evidence}"))
    for check_id, c in list(by_id.items()):
        if c.evidence.startswith("unreadable") or c.status not in ("PASS", "SKIP"):
            continue
        # Lines the test wrote PASS directly; resolved PENDING lines carry their verdict after " => ".
        if c.status == "PASS" and " => " in c.evidence:
            continue
        by_id[check_id] = guard_network(c, network_key)
    for check_id in EXPECTED_IDS:
        if check_id not in by_id and ran is not None and check_id not in ran:
            by_id[check_id] = Check(check_id, NOT_RUN, "filtered run: its test method was not selected")
        elif check_id not in by_id:
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
    ran = None
    if "--ran" in argv:
        i = argv.index("--ran")
        if i + 1 >= len(argv):
            print(__doc__, file=sys.stderr)
            return 2
        entries = [e for e in argv[i + 1].split(",") if e]
        bad = [e for e in entries if not known_entry(e)]
        if not entries or bad:
            print(f"checks.py: --ran needs test entries, got {argv[i + 1]!r}", file=sys.stderr)
            return 2
        ran = covered_ids(entries)
        del argv[i:i + 2]
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    d = argv[0]
    raw = read(os.path.join(d, "checks.txt"))
    final = assemble(raw, read(os.path.join(d, "ui-log.txt")), read(os.path.join(d, "mem.txt")), network_key, ran,
                     run_dir=d)
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
