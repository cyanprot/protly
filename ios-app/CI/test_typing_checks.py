"""Offline tests for the typing-fixes 004 rules in checks.py: dark-1, ret-*, menu-*, pad-*
(docs/plans/2026-10-30-typing-fixes.md, Sprint 004). Run with python3 -m unittest discover -s ios-app/CI."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import checks  # noqa: E402

try:
    from PIL import Image, ImageDraw
except ImportError:  # the CI installs Pillow; the image tests need it
    Image = None


def resolve(line, run_dir=None):
    """One PENDING line through assemble(), the way checks.py sees it."""
    final = {c.id: c for c in checks.assemble(line + "\n", "", "", run_dir=run_dir)}
    return final[line.split()[1]]


class IdTests(unittest.TestCase):
    def test_every_new_id_is_expected_and_has_a_method(self):
        ids = ["dark-1", "menu-0", "menu-1", "menu-4", "pad-1", "pad-2", "pad-3"]
        ids += [f"ret-{s}-{f}" for s in range(1, 6) for f in ("textarea", "input", "composer")]
        self.assertEqual(len(ids), 22)
        owned = {i for v in checks.METHOD_IDS.values() for i in v}
        for i in ids:
            self.assertIn(i, checks.EXPECTED_IDS)
            self.assertIn(i, owned)
            self.assertIn(i, checks.RESOLVERS)

    def test_a_missing_line_is_fail_unreadable(self):
        final = {c.id: c for c in checks.assemble("", "", "")}
        self.assertEqual(final["ret-3-composer"].status, "FAIL")
        self.assertIn("no CHECK line", final["ret-3-composer"].evidence)

    def test_filtered_run_marks_the_other_web_ids_not_run(self):
        ran = checks.covered_ids(["PhoneChecksUITests/test0_access", "PhoneChecksUITests/test5c_pad"])
        final = {c.id: c for c in checks.assemble("", "", "", ran=ran)}
        self.assertEqual(final["ret-1-textarea"].status, checks.NOT_RUN)
        self.assertEqual(final["pad-1"].status, "FAIL")

    def test_natural_sort_keeps_steps_in_order(self):
        final = [c.id for c in checks.assemble("", "", "") if c.id.startswith("ret-")]
        self.assertEqual(final[:3], ["ret-1-composer", "ret-1-input", "ret-1-textarea"])
        self.assertEqual(final[-1], "ret-5-textarea")


class ReturnTests(unittest.TestCase):
    def test_textarea_keeps_the_text_and_adds_a_line(self):
        c = resolve('CHECK ret-1-textarea PENDING want="안녕" before="안녕" value="안녕\\n" sent-count=0 '
                    'submit-count=0')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_textarea_that_lost_the_word_fails(self):
        c = resolve('CHECK ret-1-textarea PENDING want="안녕" before="안녕" value="\\n" sent-count=0 submit-count=0')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("value", c.evidence)

    def test_textarea_without_the_line_fails(self):
        c = resolve('CHECK ret-2-textarea PENDING want="hello 안녕" before="hello 안녕" value="hello 안녕" '
                    'sent-count=0 submit-count=0')
        self.assertEqual(c.status, "FAIL")

    def test_input_keeps_the_text_and_submits_it(self):
        c = resolve('CHECK ret-2-input PENDING want="hello 안녕" before="hello 안녕" value="hello 안녕" '
                    'sent-count=0 submit-count=1 submitted="hello 안녕"')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_input_without_a_submit_still_keeps_the_text(self):
        c = resolve('CHECK ret-5-input PENDING want="ㅇㅋ" before="ㅇㅋ" value="ㅇㅋ" sent-count=0 submit-count=0')
        self.assertEqual(c.status, "PASS", c.evidence)
        self.assertIn("no submit", c.evidence)

    def test_input_that_submitted_a_cut_word_fails(self):
        c = resolve('CHECK ret-1-input PENDING want="안녕" before="안녕" value="안녕" sent-count=0 submit-count=1 '
                    'submitted="안"')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("submitted", c.evidence)

    def test_composer_sends_exactly_and_empties(self):
        c = resolve('CHECK ret-3-composer PENDING want="hello 안녕 " before="hello 안녕 " value="" sent-count=1 '
                    'sent="hello 안녕 " submit-count=0')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_composer_keeping_a_bare_line_break_is_empty(self):
        c = resolve('CHECK ret-1-composer PENDING want="안녕" before="안녕" value="\\n" sent-count=1 sent="안녕" '
                    'submit-count=0')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_composer_that_never_sent_fails(self):
        c = resolve('CHECK ret-1-composer PENDING want="안녕" before="안녕" value="안녕\\n" sent-count=0 '
                    'submit-count=0')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("nothing sent", c.evidence)

    def test_composer_that_sent_twice_fails(self):
        c = resolve('CHECK ret-4-composer PENDING want="hello 안녕" before="hello 안녕" value="" sent-count=2 '
                    'sent="hello 안녕" submit-count=0')
        self.assertEqual(c.status, "FAIL")

    def test_composer_that_sent_a_cut_message_fails(self):
        c = resolve('CHECK ret-2-composer PENDING want="hello 안녕" before="hello 안녕" value="" sent-count=1 '
                    'sent="hello " submit-count=0')
        self.assertEqual(c.status, "FAIL")

    def test_typed_text_that_differs_before_return_fails(self):
        c = resolve('CHECK ret-5-textarea PENDING want="ㅇㅋ" before="dz" value="dz\\n" sent-count=0 submit-count=0')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("before Return", c.evidence)

    def test_no_return_event_is_noted_not_failed(self):
        c = resolve('CHECK ret-1-textarea PENDING want="안녕" value="안녕\\n" sent-count=0 submit-count=0')
        self.assertEqual(c.status, "PASS", c.evidence)
        self.assertIn("no Return event", c.evidence)

    def test_nfd_text_compares_equal(self):
        import unicodedata
        nfd = unicodedata.normalize("NFD", "안녕")
        c = resolve(f'CHECK ret-1-input PENDING want="안녕" before="{nfd}" value="{nfd}" sent-count=0 submit-count=0')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_missing_value_is_unreadable(self):
        c = resolve('CHECK ret-1-textarea PENDING want="안녕"')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)


class MenuTests(unittest.TestCase):
    def test_copy_in_the_menu_passes(self):
        c = resolve('CHECK menu-1 PENDING menu="Copy,Look Up,Paste" sel="3,2" field="안녕 오늘"')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_no_menu_fails(self):
        c = resolve('CHECK menu-0 PENDING menu="" sel="0,5" field="hello there"')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("no Copy", c.evidence)

    def test_paste_without_copy_fails(self):
        c = resolve('CHECK menu-1 PENDING menu="Paste,Select All" sel="5,0" field="안녕 오늘"')
        self.assertEqual(c.status, "FAIL")

    def test_missing_menu_field_is_unreadable(self):
        c = resolve('CHECK menu-0 PENDING sel="0,5"')
        self.assertIn("unreadable", c.evidence)

    def test_menu4_selection_replaced(self):
        self.assertEqual(resolve('CHECK menu-4 PENDING field="안녕 ㅎ" sel="4,0"').status, "PASS")

    def test_menu4_latin_reading_of_the_same_key_is_a_replacement_too(self):
        c = resolve('CHECK menu-4 PENDING field="안녕 g" sel="4,0"')
        self.assertEqual(c.status, "PASS", c.evidence)
        self.assertIn("Latin", c.evidence)

    def test_menu4_appended_to_the_word_fails(self):
        c = resolve('CHECK menu-4 PENDING field="안녕 오늘ㅎ" sel="6,0"')
        self.assertEqual(c.status, "FAIL")

    def test_menu4_appended_as_a_new_syllable_fails(self):
        self.assertEqual(resolve('CHECK menu-4 PENDING field="안녕 오늟" sel="5,0"').status, "FAIL")


class PadTests(unittest.TestCase):
    TEXT = "hello world hello world "

    def test_pad1_cursor_moved_left(self):
        c = resolve(f'CHECK pad-1 PENDING want="{self.TEXT}" field="{self.TEXT}" sel0=24 sel1="9,0"')
        self.assertEqual(c.status, "PASS", c.evidence)
        self.assertIn("moved 15", c.evidence)

    def test_pad1_cursor_still_fails(self):
        c = resolve(f'CHECK pad-1 PENDING want="{self.TEXT}" field="{self.TEXT}" sel0=24 sel1="24,0"')
        self.assertEqual(c.status, "FAIL")

    def test_pad1_text_changed_fails(self):
        c = resolve(f'CHECK pad-1 PENDING want="{self.TEXT}" field="{self.TEXT} " sel0=24 sel1="9,0"')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("field", c.evidence)

    def test_pad1_selection_instead_of_a_caret_fails(self):
        c = resolve(f'CHECK pad-1 PENDING want="{self.TEXT}" field="{self.TEXT}" sel0=24 sel1="9,4"')
        self.assertEqual(c.status, "FAIL")

    def test_pad2_keeps_moving_while_rising(self):
        c = resolve(f'CHECK pad-2 PENDING want="{self.TEXT}" field="{self.TEXT}" sel0=24 sel1="10,0" ref=15')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_pad2_frozen_halfway_fails(self):
        c = resolve(f'CHECK pad-2 PENDING want="{self.TEXT}" field="{self.TEXT}" sel0=24 sel1="15,0" ref=15')
        self.assertEqual(c.status, "FAIL")

    def test_pad2_without_a_reference_is_unreadable(self):
        c = resolve(f'CHECK pad-2 PENDING want="{self.TEXT}" field="{self.TEXT}" sel0=24 sel1="10,0" ref=0')
        self.assertIn("unreadable", c.evidence)

    def test_pad3_one_syllable_left(self):
        self.assertEqual(resolve('CHECK pad-3 PENDING want="안녕" field="안녕" sel0=2 sel1="1,0" want-sel=1').status,
                         "PASS")

    def test_pad3_two_steps_fails(self):
        self.assertEqual(resolve('CHECK pad-3 PENDING want="안녕" field="안녕" sel0=2 sel1="0,0" want-sel=1').status,
                         "FAIL")

    def test_pad3_space_typed_fails(self):
        self.assertEqual(resolve('CHECK pad-3 PENDING want="안녕" field="안녕 " sel0=2 sel1="1,0" want-sel=1').status,
                         "FAIL")

    def test_unreadable_selection(self):
        c = resolve(f'CHECK pad-1 PENDING want="{self.TEXT}" field="{self.TEXT}" sel0=24 sel1="<unreadable>"')
        self.assertIn("unreadable", c.evidence)

    def test_skip_line_stays_skip(self):
        c = resolve("CHECK pad-1 SKIP XCUITest cannot drag on the keyboard")
        self.assertEqual(c.status, "SKIP")


@unittest.skipIf(Image is None, "Pillow is not installed")
class DarkTests(unittest.TestCase):
    """Synthetic 3x screenshots: a black page with light glyph strokes in a field rect at (20, 100) 200 x 40 pt."""

    RECT = "20,100,200,40"

    def shot(self, d, name, glyphs=True, underline=False, color=(242, 242, 242), shift=0):
        img = Image.new("RGB", (390 * 3, 400 * 3), (0, 0, 0))
        draw = ImageDraw.Draw(img)
        if glyphs:
            for i, x in enumerate((90, 160)):  # two syllables, 51 px wide, no stroke longer than 45 px
                x += shift
                draw.rectangle([x, 320, x + 44, 326], fill=color)
                draw.rectangle([x + 20, 320, x + 26, 380], fill=color)
                draw.ellipse([x + 5, 340, x + 40, 375], outline=color, width=5)
        if underline:
            draw.rectangle([88, 392, 88 + 125, 397], fill=(10, 132, 255))
        img.save(os.path.join(d, name))

    def run_dark(self, typing, space, rect=RECT, before="안녕", after="안녕 "):
        with tempfile.TemporaryDirectory() as d:
            if typing:
                typing(d, "c-dark-1-1-typing.png")
            if space:
                space(d, "c-dark-1-2-space.png")
            return resolve(f'CHECK dark-1 PENDING typing="c-dark-1-1-typing.png" space="c-dark-1-2-space.png" '
                           f'rect={rect} points=390 before="{before}" after="{after}"', run_dir=d)

    def test_same_ink_no_underline_passes(self):
        c = self.run_dark(self.shot, self.shot)
        self.assertEqual(c.status, "PASS", c.evidence)
        self.assertIn("ink typing", c.evidence)

    def test_underline_while_typing_fails(self):
        c = self.run_dark(lambda d, n: self.shot(d, n, underline=True), self.shot)
        self.assertEqual(c.status, "FAIL")
        self.assertIn("underline", c.evidence)

    def test_invisible_word_while_typing_fails(self):
        c = self.run_dark(lambda d, n: self.shot(d, n, glyphs=False), self.shot)
        self.assertEqual(c.status, "FAIL")

    def test_dim_word_while_typing_fails(self):
        c = self.run_dark(lambda d, n: self.shot(d, n, color=(60, 60, 60)), self.shot)
        self.assertEqual(c.status, "FAIL")

    def test_small_antialiasing_difference_passes(self):
        c = self.run_dark(lambda d, n: self.shot(d, n, shift=1), self.shot)
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_missing_png_is_unreadable(self):
        c = self.run_dark(self.shot, None)
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_no_run_dir_is_unreadable(self):
        c = resolve('CHECK dark-1 PENDING typing="a.png" space="b.png" rect=1,2,3,4 points=390')
        self.assertIn("unreadable", c.evidence)

    def test_bad_rect_is_unreadable(self):
        c = self.run_dark(self.shot, self.shot, rect="1,2")
        self.assertIn("unreadable", c.evidence)

    def test_word_changed_by_the_space_fails(self):
        c = self.run_dark(self.shot, self.shot, before="안녕", after="안녀 ")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("typed", c.evidence)

    def test_measure_counts_ink_and_runs(self):
        with tempfile.TemporaryDirectory() as d:
            self.shot(d, "u.png", underline=True)
            m = checks.measure_word(Image.open(os.path.join(d, "u.png")), (20, 100, 200, 40), 390)
        self.assertGreater(m["ink"], 1000)
        self.assertGreaterEqual(m["run"], 120)
        self.assertTrue(m["underline"])


if __name__ == "__main__":
    unittest.main()
