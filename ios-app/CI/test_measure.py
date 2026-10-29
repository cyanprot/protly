"""Offline tests for measure.py on synthetic screenshots: python3 -m unittest discover -s ios-app/CI -p 'test_*.py'"""

import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import measure  # noqa: E402

POINTS = 390
HEIGHT = 844
SCALE = 3
BG = measure.HOST_BG
KB = (28, 28, 30)
KEY = (108, 108, 112)
TEXT = (235, 235, 235)
SIDE = 11 / 3
PITCH_X = (POINTS - 2 * SIDE) / 10


def shot(top=512.0, band=52.0, pitch=54.0, key=43.0, texts=(), corners=True):
    """A 1170x2532 screenshot: host background, keyboard from `top` down, rows of keys, bar text blocks.
    texts: (center_x_pt, width_pt) blocks in the bar, 14 pt tall, centered in the bar's 29 pt row."""
    img = Image.new("RGB", (POINTS * SCALE, HEIGHT * SCALE), BG)
    d = ImageDraw.Draw(img)

    def rect(x0, y0, x1, y1, color):
        d.rectangle([round(x0 * SCALE), round(y0 * SCALE), round(x1 * SCALE) - 1, round(y1 * SCALE) - 1], fill=color)

    rect(0, top, POINTS, HEIGHT, KB)
    if corners:  # iOS 26's glass has round top corners: host background shows through in the bar band
        rect(0, top, 12, top + 12, BG)
        rect(POINTS - 12, top, POINTS, top + 12, BG)
    centers = [
        [POINTS / 2 + (i - 4.5) * PITCH_X for i in range(10)],
        [POINTS / 2 + (i - 4) * PITCH_X for i in range(9)],
        [POINTS / 2 + (i - 3) * PITCH_X for i in range(7)],
    ]
    for r, row in enumerate(centers):
        y = top + band + r * pitch
        for cx in row:
            rect(cx - (PITCH_X - 2 * SIDE) / 2, y, cx + (PITCH_X - 2 * SIDE) / 2, y + key, KEY)
    y = top + band + 3 * pitch
    rect(SIDE * 2, y, POINTS - SIDE * 2, y + key, KEY)
    bar_mid = top + band - (pitch - key) / 2 - 14.5
    for cx, w in texts:
        rect(cx - w / 2, bar_mid - 7, cx + w / 2, bar_mid + 7, TEXT)
    return img


class MeasureImageTests(unittest.TestCase):
    def test_finds_top_edge_band_pitch_and_key_height(self):
        m = measure.measure_image(shot(top=512.0), POINTS)
        self.assertAlmostEqual(m.top, 512.0, delta=0.34)
        self.assertAlmostEqual(m.row1, 564.0, delta=0.34)
        self.assertAlmostEqual(m.band, 52.0, delta=0.34)
        self.assertAlmostEqual(m.pitch, 54.0, delta=0.34)
        self.assertAlmostEqual(m.key, 43.0, delta=0.34)

    def test_bar_text_in_the_key_column_is_not_row_1(self):
        # The left slot's text crosses the second key's column; it is shorter than 30 pt, so row 1 stays the key.
        m = measure.measure_image(shot(texts=[(POINTS / 6, 90)]), POINTS)
        self.assertAlmostEqual(m.band, 52.0, delta=0.34)

    def test_bar_text_clusters(self):
        m = measure.measure_image(shot(texts=[(POINTS / 6, 60), (POINTS / 2, 50)]), POINTS)
        self.assertEqual(len(m.bar_text), 2)
        self.assertAlmostEqual(m.bar_center(), POINTS / 2, delta=0.34)

    def test_round_glass_corners_are_not_bar_text(self):
        m = measure.measure_image(shot(texts=[]), POINTS)
        self.assertEqual(m.bar_text, [])

    def test_no_keyboard(self):
        img = Image.new("RGB", (POINTS * SCALE, HEIGHT * SCALE), BG)
        m = measure.measure_image(img, POINTS)
        self.assertIsNone(m.top)
        self.assertIsNone(m.band)


def write_run(directory, overrides=None):
    overrides = overrides or {}
    for name in measure.SCENARIOS:
        kwargs = {"texts": [(POINTS / 2, 50)]} if name == "07-empty-left-slot" else {}
        kwargs.update(overrides.get(name, {}))
        if kwargs.get("skip"):
            continue
        shot(**kwargs).save(os.path.join(directory, name + ".png"))


def run_main(directory):
    out = io.StringIO()
    with redirect_stdout(out):
        code = measure.main([directory, "--points", str(POINTS)])
    return code, out.getvalue().splitlines()


class ReportTests(unittest.TestCase):
    def test_all_equal_passes(self):
        with tempfile.TemporaryDirectory() as d:
            write_run(d)
            code, lines = run_main(d)
        self.assertEqual(lines[-1], "RESULT PASS")
        self.assertEqual(code, 0)
        self.assertFalse([l for l in lines if " FAIL" in l])

    def test_emoji_round_trip_that_moves_the_top_fails(self):
        # Sprint 5 on the phone: 17.5 pt less above row 1 after an Emoji round-trip.
        with tempfile.TemporaryDirectory() as d:
            write_run(d, {"03-after-emoji": {"top": 529.5, "band": 34.5}})
            code, lines = run_main(d)
        self.assertEqual(lines[-1], "RESULT FAIL")
        self.assertEqual(code, 1)
        self.assertTrue(any(l.startswith("CHECK top-edge FAIL") for l in lines))
        self.assertTrue(any(l.startswith("CHECK band-03-after-emoji FAIL") for l in lines))
        self.assertTrue(any(l.startswith("CHECK band-02-first-open PASS") for l in lines))

    def test_wrong_pitch_fails(self):
        with tempfile.TemporaryDirectory() as d:
            write_run(d, {"06-word-typed": {"pitch": 56.0, "key": 47.0}})
            _, lines = run_main(d)
        self.assertTrue(any(l.startswith("CHECK pitch-06-word-typed FAIL") for l in lines))
        self.assertTrue(any(l.startswith("CHECK key-06-word-typed FAIL") for l in lines))

    def test_center_text_in_the_left_quarter_fails(self):
        # Sprint 5 on the phone: an empty left slot collapsed and Translate slid to the left quarter.
        with tempfile.TemporaryDirectory() as d:
            write_run(d, {"07-empty-left-slot": {"texts": [(POINTS / 4, 50)]}})
            _, lines = run_main(d)
        self.assertTrue(any(l.startswith("CHECK bar-center-07 FAIL") for l in lines))
        self.assertEqual(lines[-1], "RESULT FAIL")

    def test_missing_screenshot_fails(self):
        with tempfile.TemporaryDirectory() as d:
            write_run(d, {"05-after-second-emoji": {"skip": True}})
            _, lines = run_main(d)
        self.assertTrue(any("05-after-second-emoji" in l and "FAIL" in l for l in lines))
        self.assertEqual(lines[-1], "RESULT FAIL")

    def test_apple_band_is_the_reference(self):
        with tempfile.TemporaryDirectory() as d:
            write_run(d, {"01-apple": {"top": 515.0, "band": 50.5}})
            _, lines = run_main(d)
        self.assertTrue(any(l.startswith("CHECK band-02-first-open FAIL") for l in lines))


if __name__ == "__main__":
    unittest.main()
