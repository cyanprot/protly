#!/usr/bin/env python3
"""Measures the keyboard screenshots of one CI run against Apple's keyboard in the same simulator.

Usage: measure.py <dir> [--points 390]

<dir> holds the scenario PNGs written by UITests/KeyboardShotsUITests.swift. Prints one line per screenshot, one
line per check, and a final `RESULT PASS` or `RESULT FAIL` (exit 0 or 1). All values are points; the scale comes
from the PNG width and the device's point width.

How each value is found (docs/plans/2026-10-29-keyboard-visual.md, Task 3):
- Host background: sampled at (center, 30% of the height), where the host app draws only its solid color
  (HOST_BG; the field sits above it).
- Keyboard top edge: scanning down the center column from 35% of the height, the first pixel row that differs
  from the host background by more than 24 (sum of RGB) for 6 rows in a row.
- Keyboard background: sampled 6 pt below the top edge, in the band above the bar text.
- Row tops and key height: in the center column of each row's second key, the first run of at least 30 pt that
  differs from the keyboard background by more than 24 (keys are 43 pt tall; bar text is shorter).
- Bar text: columns between the top edge and row 1 with at least 3 pixels far (> 96) from both the keyboard
  background and the host color (not the glass's round corners or rim), grouped into words with gaps of 12 pt
  or less.
"""

import argparse
import os
import sys
from dataclasses import dataclass, field

from PIL import Image

# The host app's background (ios-app/CI/Host/HostApp.swift). Sampled from each PNG; this is only reported.
HOST_BG = (32, 160, 96)

SCENARIOS = [
    "01-apple",
    "02-first-open",
    "03-after-emoji",
    "04-after-background",
    "05-after-second-emoji",
    "06-word-typed",
    "07-empty-left-slot",
]
PROTLY = SCENARIOS[1:]

# Targets (ProtlyGeometry in ios-app/Sources/ProtlyKeyboard/ProtlyLayout.swift).
ROW_PITCH = 54.0
KEY_HEIGHT = 43.0
SIDE_INSET = 11.0 / 3

EDGE_DIFF = 24
EDGE_ROWS = 6
KEY_RUN_PT = 30.0
TEXT_DIFF = 96
TEXT_GAP_PT = 12.0
TEXT_MIN_PX = 3  # per column: the glass rim crosses a column in 1-2 px, a glyph stroke in more

TOP_TOLERANCE = 0.5
BAND_TOLERANCE = 1.0
GRID_TOLERANCE = 0.5
CENTER_TOLERANCE = 2.0


def diff(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


@dataclass
class Measurement:
    points: float
    top: float = None
    row1: float = None
    band: float = None
    pitch: float = None
    key: float = None
    bar_text: list = field(default_factory=list)  # (left, right) in points
    error: str = None

    def bar_center(self):
        """Center x of the bar word nearest the screen's center, or None."""
        if not self.bar_text:
            return None
        mid = self.points / 2
        return min(((l + r) / 2 for l, r in self.bar_text), key=lambda c: abs(c - mid))

    def line(self, name):
        if self.error:
            return f"{name}: {self.error}"
        words = " ".join(f"{(l + r) / 2:.2f}({r - l:.0f})" for l, r in self.bar_text) or "none"
        return (f"{name}: top {fmt(self.top)} row1 {fmt(self.row1)} band {fmt(self.band)} "
                f"pitch {fmt(self.pitch)} key {fmt(self.key)} bar-text-centers {words}")


def fmt(v):
    return "n/a" if v is None else f"{v:.2f}"


def measure_image(img, points):
    img = img.convert("RGB")
    w, h = img.size
    px = img.load()
    scale = w / points
    m = Measurement(points=points)

    cx = w // 2
    bg = px[cx, int(h * 0.30)]
    top = None
    for y in range(int(h * 0.35), h - EDGE_ROWS):
        if all(diff(px[cx, y + k], bg) > EDGE_DIFF for k in range(EDGE_ROWS)):
            top = y
            break
    if top is None:
        m.error = "no keyboard found"
        return m
    m.top = top / scale

    def column(pt):
        return min(w - 1, max(0, round(pt * scale)))

    pitch_x = (points - 2 * SIDE_INSET) / 10
    cols = [points / 2 - 3.5 * pitch_x, points / 2 - 3 * pitch_x, points / 2 - 2 * pitch_x]
    sample_y = top + round(6 * scale)
    if sample_y >= h:
        m.error = "keyboard too short"
        return m
    kx = column(cols[0])
    samples = sorted((px[x, sample_y] for x in range(max(0, kx - 3), min(w, kx + 4))), key=sum)
    kb = samples[len(samples) // 2]

    def key_run(x, start):
        run_min = KEY_RUN_PT * scale
        y = start
        while y < h:
            if diff(px[x, y], kb) > EDGE_DIFF:
                y0 = y
                while y < h and diff(px[x, y], kb) > EDGE_DIFF:
                    y += 1
                if y - y0 >= run_min:
                    return y0, y - y0
            y += 1
        return None

    tops, heights = [], []
    start = sample_y
    for c in cols:
        run = key_run(column(c), start)
        if run is None:
            break
        tops.append(run[0])
        heights.append(run[1])
        start = run[0] + run[1]
    if not tops:
        m.error = f"top {m.top:.2f}, no key row found"
        return m
    m.row1 = tops[0] / scale
    m.band = m.row1 - m.top
    if len(tops) == 3:
        m.pitch = (tops[2] - tops[0]) / 2 / scale
        m.key = sum(heights) / 3 / scale

    # Bar text: everything between the top edge and row 1, minus 2 pt at each side and each screen edge.
    # The glass's round top corners (host color) and their rim highlight (1-2 px per column) are not text.
    y0, y1 = top + round(2 * scale), tops[0] - round(2 * scale)
    text_cols = [
        x for x in range(round(2 * scale), w - round(2 * scale))
        if sum(diff(px[x, y], kb) > TEXT_DIFF and diff(px[x, y], bg) > TEXT_DIFF for y in range(y0, y1)) >= TEXT_MIN_PX
    ]
    words = []
    for x in text_cols:
        if words and x - words[-1][1] <= TEXT_GAP_PT * scale:
            words[-1][1] = x
        else:
            words.append([x, x])
    m.bar_text = [(l / scale, (r + 1) / scale) for l, r in words]
    return m


def check(name, ok, detail):
    return f"CHECK {name} {'PASS' if ok else 'FAIL'} {detail}"


def checks(results, points):
    lines = []
    tops = {n: results[n].top for n in PROTLY if n in results and results[n].top is not None}
    missing = [n for n in PROTLY if n not in tops]
    if missing:
        lines.append(check("top-edge", False, "no top edge in " + ", ".join(missing)))
    else:
        lo, hi = min(tops.values()), max(tops.values())
        lines.append(check("top-edge", hi - lo <= TOP_TOLERANCE, f"range {lo:.2f}..{hi:.2f} ({hi - lo:.2f} pt)"))

    apple = results.get("01-apple")
    apple_band = apple.band if apple else None
    for n in PROTLY:
        m = results.get(n)
        band = m.band if m else None
        if band is None or apple_band is None:
            lines.append(check(f"band-{n}", False, f"{fmt(band)} vs apple {fmt(apple_band)}"))
        else:
            d = band - apple_band
            lines.append(check(f"band-{n}", abs(d) <= BAND_TOLERANCE, f"{band:.2f} vs apple {apple_band:.2f} ({d:+.2f})"))

    for n in PROTLY:
        m = results.get(n)
        for label, value, target in (("pitch", m and m.pitch, ROW_PITCH), ("key", m and m.key, KEY_HEIGHT)):
            ok = value is not None and abs(value - target) <= GRID_TOLERANCE
            lines.append(check(f"{label}-{n}", ok, f"{fmt(value)} vs {target:.2f}"))

    m = results.get("07-empty-left-slot")
    c = m.bar_center() if m else None
    if c is None:
        lines.append(check("bar-center-07", False, "no bar text found"))
    else:
        d = c - points / 2
        lines.append(check("bar-center-07", abs(d) <= CENTER_TOLERANCE,
                           f"text center {c:.2f} vs {points / 2:.2f} ({d:+.2f}), words {len(m.bar_text)}"))
    return lines


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("dir")
    p.add_argument("--points", type=float, default=390.0, help="device width in points")
    args = p.parse_args(argv)

    results = {}
    for n in SCENARIOS:
        path = os.path.join(args.dir, n + ".png")
        if not os.path.exists(path):
            print(f"{n}: FAIL missing {n}.png")
            continue
        with Image.open(path) as img:
            if not results:
                w, h = img.size
                print(f"screen {w}x{h} px, {args.points:g} pt wide, scale {w / args.points:.2f}")
            m = measure_image(img, args.points)
        results[n] = m
        print(m.line(n))

    lines = checks(results, args.points)
    for line in lines:
        print(line)
    ok = all(" PASS " in l for l in lines) and all(n in results for n in SCENARIOS)
    print("RESULT PASS" if ok else "RESULT FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
