"""Offline tests for the keyboard-ui 003 rules in checks.py: card-*, mem-stream, hit-1, bar-*, app-*
(docs/plans/2026-10-30-keyboard-ui.md, Task 3.5). Run with python3 -m unittest discover -s ios-app/CI."""

import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import checks  # noqa: E402

try:
    from PIL import Image, ImageDraw
except ImportError:  # the CI installs Pillow; the image tests need it
    Image = None

HERE = os.path.dirname(os.path.abspath(__file__))
OK = "Thanks so much for today, it really helped me out."
BACK = "오늘 정말 고마워, 큰 도움이 됐어."
ERROR = "The API is overloaded. Try again in a moment."


def resolve(line, run_dir=None, log="", mem=""):
    """One PENDING line through assemble(), the way checks.py sees it."""
    final = {c.id: c for c in checks.assemble(line + "\n", log, mem, run_dir=run_dir)}
    return final[line.split()[1]]


class IdTests(unittest.TestCase):
    def test_every_new_id_is_expected_and_has_a_method_and_a_rule(self):
        ids = [f"card-{s}-{look}" for look in ("dark", "light") for s in ("wait", "mid", "done", "err0", "err1")]
        ids += ["card-slow", "card-cancel", "mem-stream", "hit-1", "bar-dark", "bar-light", "bar-xxl", "app-dark",
                "app-light"]
        self.assertEqual(len(ids), 19)
        owned = {i for v in checks.METHOD_IDS.values() for i in v}
        for i in ids:
            self.assertIn(i, checks.EXPECTED_IDS)
            self.assertIn(i, owned)
            self.assertIn(i, checks.RESOLVERS)
        self.assertEqual(set(checks.METHOD_IDS["test5d_card"]) | set(checks.METHOD_IDS["test5e_bar"]), set(ids))

    def test_a_filtered_card_run_marks_the_bar_ids_not_run(self):
        ran = checks.covered_ids(["PhoneChecksUITests/test0_access", "PhoneChecksUITests/test5d_card"])
        final = {c.id: c for c in checks.assemble("", "", "", ran=ran)}
        self.assertEqual(final["bar-xxl"].status, checks.NOT_RUN)
        self.assertEqual(final["card-mid-light"].status, "FAIL")
        self.assertIn("no CHECK line", final["card-mid-light"].evidence)

    def test_the_methods_are_known_to_the_filter(self):
        self.assertTrue(checks.known_entry("PhoneChecksUITests/test5d_card"))
        self.assertTrue(checks.known_entry("PhoneChecksUITests/test5e_bar"))

    def test_the_stub_texts_match_the_ui_test_texts(self):
        def consts(path):
            with open(os.path.join(HERE, path), encoding="utf-8") as f:
                text = f.read()
            return dict(re.findall(r'static let (okTranslation|okBack|cutKept) = "([^"]*)"', text))
        stub = consts("../Sources/ProtlyKeyboard/StubActionClient.swift")
        test = consts("UITests/CardChecks.swift")
        self.assertEqual(set(stub), {"okTranslation", "okBack", "cutKept"})
        self.assertEqual(stub, test)
        self.assertEqual(stub["okTranslation"], OK)
        self.assertTrue(OK.startswith(stub["cutKept"]))


class StripTests(unittest.TestCase):
    def test_wait_names_the_call_and_has_a_big_xmark(self):
        c = resolve('CHECK card-wait-dark PENDING center="→ English" strip="Translating → English…" cancel=44.0x44.0 card=0')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_wait_with_a_small_xmark_fails(self):
        c = resolve('CHECK card-wait-light PENDING strip="Translating → English…" cancel=30.0x30.0 card=0')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("xmark hit area", c.evidence)

    def test_wait_with_a_card_or_without_the_target_fails(self):
        c = resolve('CHECK card-wait-dark PENDING strip="Translating…" cancel=44.0x44.0 card=3')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("English", c.evidence)
        self.assertIn("a card opened", c.evidence)

    def test_error_before_text_on_the_strip(self):
        ok = f'CHECK card-err0-dark PENDING strip="{ERROR}" cancel=44.0x44.0 card=0 want-error="{ERROR}" retry=52.0x44.0 closed=1'
        self.assertEqual(resolve(ok).status, "PASS", resolve(ok).evidence)
        no_retry = ok.replace("retry=52.0x44.0", "retry=none")
        self.assertIn("no Retry", resolve(no_retry).evidence)
        carded = ok.replace("card=0", "card=4")
        self.assertEqual(resolve(carded).status, "FAIL")

    def test_still_line_after_eight_seconds(self):
        c = resolve('CHECK card-slow PENDING strip="Translating → English… Still translating…" cancel=44.0x44.0 card=0 at=8.9s')
        self.assertEqual(c.status, "PASS", c.evidence)
        c = resolve('CHECK card-slow PENDING strip="Translating → English…" cancel=44.0x44.0 card=0 at=9.0s')
        self.assertEqual(c.status, "FAIL")


class CardTests(unittest.TestCase):
    BUTTONS = "Cancel 76.0x44.0,Copy 60.0x44.0,Replace 82.0x44.0"

    def test_mid_stream_shows_the_start_of_the_result(self):
        c = resolve(f'CHECK card-mid-dark PENDING text="Thanks so much " final="{OK}" copy=disabled '
                    f'header="→ English" texts=1 buttons="{self.BUTTONS}" strip=1')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_mid_stream_text_that_is_not_the_result_fails(self):
        c = resolve(f'CHECK card-mid-dark PENDING text="Something else" final="{OK}" header="→ English" strip=1')
        self.assertEqual(c.status, "FAIL")

    def test_mid_read_after_the_end_is_record(self):
        c = resolve(f'CHECK card-mid-light PENDING text="{OK}" final="{OK}" header="→ English" strip=0')
        self.assertEqual(c.status, "RECORD", c.evidence)

    def done(self, **over):
        fields = {"text": OK, "back": BACK, "want": OK, "want-back": BACK, "buttons": self.BUTTONS, "after": OK,
                  "want-after": OK}
        fields.update(over)
        quoted = " ".join(f'{k}="{v}"' for k, v in fields.items() if v is not None)
        return resolve(f"CHECK card-done-dark PENDING {quoted} strip=0")

    def test_done_with_replace(self):
        c = self.done()
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_done_without_the_back_translation_fails(self):
        self.assertIn("back translation", self.done(back="").evidence)

    def test_done_with_a_short_button_fails(self):
        c = self.done(buttons="Cancel 76.0x30.0,Copy 60.0x44.0,Replace 82.0x44.0")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("Cancel is 30 pt tall", c.evidence)

    def test_replace_that_left_the_draft_fails(self):
        c = self.done(after="protly-stub ok 오늘 정말 고마워")
        self.assertEqual(c.status, "FAIL")

    def test_done_light_copy_then_cancel(self):
        draft = "protly-stub ok 오늘 정말 고마워"
        line = (f'CHECK card-done-light PENDING text="{OK}" back="{BACK}" want="{OK}" want-back="{BACK}" '
                f'buttons="{self.BUTTONS}" strip=0 copied=1 closed=1 after="{draft}" want-after="{draft}"')
        self.assertEqual(resolve(line).status, "PASS", resolve(line).evidence)
        self.assertEqual(resolve(line.replace("copied=1", "copied=0")).status, "FAIL")

    def test_error_after_text_keeps_the_text_and_adds_the_line(self):
        line = (f'CHECK card-err1-dark PENDING kept="Thanks so much for today" want-kept="Thanks so much for today" '
                f'error="{ERROR}" want-error="{ERROR}" header="→ English" texts=2 '
                f'buttons="Cancel 76.0x44.0,Retry 60.0x44.0,Copy 60.0x44.0" strip=0 closed=1')
        self.assertEqual(resolve(line).status, "PASS", resolve(line).evidence)

    def test_error_after_text_that_lost_the_text_fails(self):
        line = (f'CHECK card-err1-light PENDING kept="{ERROR}" want-kept="Thanks so much for today" '
                f'error="{ERROR}" want-error="{ERROR}" buttons="Cancel 76.0x44.0,Retry 60.0x44.0,Copy 60.0x44.0" '
                f'strip=0 closed=1')
        self.assertEqual(resolve(line).status, "FAIL")

    def test_error_after_text_with_a_disabled_copy_fails(self):
        line = (f'CHECK card-err1-dark PENDING kept="Thanks so much for today" want-kept="Thanks so much for today" '
                f'error="{ERROR}" want-error="{ERROR}" '
                f'buttons="Cancel 76.0x44.0,Retry 60.0x44.0,Copy 60.0x44.0 disabled" strip=0 closed=1')
        c = resolve(line)
        self.assertEqual(c.status, "FAIL")
        self.assertIn("Copy is disabled", c.evidence)

    def test_error_after_text_offering_replace_fails(self):
        line = (f'CHECK card-err1-dark PENDING kept="Thanks so much for today" want-kept="Thanks so much for today" '
                f'error="{ERROR}" want-error="{ERROR}" '
                f'buttons="Cancel 76.0x44.0,Retry 60.0x44.0,Copy 60.0x44.0,Replace 82.0x44.0" strip=0 closed=1')
        c = resolve(line)
        self.assertEqual(c.status, "FAIL")
        self.assertIn("Replace offered", c.evidence)

    def test_cancel_closes_and_nothing_comes_back(self):
        draft = "protly-stub ok 오늘 정말 고마워"
        line = (f'CHECK card-cancel PENDING center="→ English" card-before=1 xmark=44.0x44.0 card-after=0 '
                f'strip-after=0 keys=1 card-late=0 field="{draft}" want-field="{draft}"')
        self.assertEqual(resolve(line).status, "PASS", resolve(line).evidence)
        late = resolve(line.replace("card-late=0", "card-late=1"))
        self.assertEqual(late.status, "FAIL")
        self.assertIn("came back", late.evidence)
        blind = resolve(line.replace("card-after=0", "card-after=-1"))
        self.assertEqual(blind.status, "FAIL")
        self.assertIn("could not be read", blind.evidence)
        self.assertEqual(resolve(line.replace("keys=1", "keys=0")).status, "FAIL")


class MemoryTests(unittest.TestCase):
    LOG = "MARK mem-stream-before 100.0\nMARK mem-stream-start 110.0\nMARK mem-stream-end 122.0\n"

    def mem(self, kbs, pid=7):
        lines = [f"{100.0 + 2 * i} {pid} footprint {kb}" for i, kb in enumerate(kbs)]
        return "\n".join(lines) + "\n"

    def test_small_growth_passes_with_the_numbers(self):
        mem = self.mem([61440] * 5 + [62464, 63488, 64512, 63488, 62464, 61440, 61440])
        c = resolve("CHECK mem-stream PENDING first=seen done=seen", log=self.LOG, mem=mem)
        self.assertEqual(c.status, "PASS", c.evidence)
        self.assertIn("peak 63.0 MB", c.evidence)
        self.assertIn("40 MB", c.evidence)

    def test_growth_over_the_line_fails(self):
        mem = self.mem([61440] * 5 + [75000] * 7)
        c = resolve("CHECK mem-stream PENDING first=seen done=seen", log=self.LOG, mem=mem)
        self.assertEqual(c.status, "FAIL")

    def test_too_few_samples_are_unreadable(self):
        c = resolve("CHECK mem-stream PENDING first=seen done=seen", log=self.LOG, mem=self.mem([61440] * 6))
        self.assertIn("not the whole stream", c.evidence)

    def test_missing_marks_or_samples_are_unreadable(self):
        c = resolve("CHECK mem-stream PENDING first=seen done=seen", log="", mem="")
        self.assertIn("unreadable", c.evidence)
        c = resolve("CHECK mem-stream PENDING first=seen done=seen", log=self.LOG, mem="")
        self.assertIn("unreadable", c.evidence)


class HitTests(unittest.TestCase):
    def test_three_slots_at_least_120_by_40(self):
        c = resolve('CHECK hit-1 PENDING slots="left 127.3x46.7 \\"ㅅ도\\", center 127.3x46.7 \\"Polish\\", '
                    'right 127.3x46.7 \\"the\\""')
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_a_narrow_or_missing_slot_fails(self):
        c = resolve('CHECK hit-1 PENDING slots="left 100.0x46.7 \\"x\\", center 127.3x46.7 \\"y\\", right none"')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("left hit frame", c.evidence)
        self.assertIn("no button in the right slot", c.evidence)


class XxlTests(unittest.TestCase):
    SLOT = "{131.3,512.0,127.3,46.7}"

    def line(self, ms_texts, ar_texts, ms_ocr="→ Bahasa Melayu", base="20.3"):
        return (f'CHECK bar-xxl PENDING base-h={base} ms-button={self.SLOT} ms-slot={self.SLOT} '
                f'ms-texts="{ms_texts}" ms-want="Bahasa Melayu" ms-ocr="{ms_ocr}" ar-button={self.SLOT} '
                f'ar-slot={self.SLOT} ar-texts="{ar_texts}" ar-want="العربية" ar-ocr="العربية"')

    MS = "→ {150.0,520.0,14.0,27.0}|Bahasa Melayu {168.0,520.0,80.0,27.0}"
    AR = "→ {160.0,520.0,14.0,27.0}|العربية {178.0,520.0,60.0,27.0}"

    def test_inside_the_slot_and_in_order_passes(self):
        c = resolve(self.line(self.MS, self.AR))
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_overflow_fails(self):
        c = resolve(self.line("→ {150.0,520.0,14.0,27.0}|Bahasa Melayu {168.0,520.0,130.0,27.0}", self.AR))
        self.assertEqual(c.status, "FAIL")
        self.assertIn("leaves the slot", c.evidence)

    def test_arrow_after_the_name_fails(self):
        c = resolve(self.line(self.MS, "العربية {150.0,520.0,60.0,27.0}|→ {215.0,520.0,14.0,27.0}"))
        self.assertEqual(c.status, "FAIL")
        self.assertIn("bidi", c.evidence)

    def test_cut_short_or_unscaled_is_record(self):
        self.assertEqual(resolve(self.line(self.MS, self.AR, ms_ocr="→ Bahasa M...")).status, "RECORD")
        self.assertEqual(resolve(self.line(self.MS, self.AR, base="27.0")).status, "RECORD")

    def test_no_base_height_or_no_ocr_never_passes(self):
        self.assertIn("unreadable", resolve(self.line(self.MS, self.AR, base="none")).evidence)
        line = self.line(self.MS, self.AR).replace('ms-ocr="→ Bahasa Melayu"', "ms-ocr=<unreadable>")
        self.assertEqual(resolve(line).status, "RECORD")


@unittest.skipIf(Image is None, "Pillow is not installed")
class ImageTests(unittest.TestCase):
    SLOT = (131.3, 512.0, 127.3, 46.7)

    def bar(self, d, name, keyboard, pill):
        img = Image.new("RGB", (390 * 3, 844 * 3), (32, 160, 96))
        draw = ImageDraw.Draw(img)
        draw.rectangle([0, 500 * 3, 390 * 3, 844 * 3], fill=keyboard)
        x, y, w, h = self.SLOT
        draw.rounded_rectangle([(x + 20) * 3, (y + 8) * 3, (x + w - 20) * 3, (y + h - 8) * 3], radius=40, fill=pill)
        img.save(os.path.join(d, name))

    def look(self, look, keyboard, pill):
        with tempfile.TemporaryDirectory() as d:
            for n in (1, 2):
                self.bar(d, f"c-bar-{look}-{n}.png", keyboard, pill)
            slot = "{%.1f,%.1f,%.1f,%.1f}" % self.SLOT
            return resolve(f'CHECK bar-{look} PENDING shot1="c-bar-{look}-1.png" slot1={slot} '
                           f'shot2="c-bar-{look}-2.png" slot2={slot} look={look} points=390', run_dir=d)

    def test_light_keyboard_with_an_ink_pill_passes(self):
        c = self.look("light", (209, 212, 217), checks.INK)
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_light_keyboard_with_a_paper_pill_fails(self):
        self.assertEqual(self.look("light", (209, 212, 217), checks.PAPER).status, "FAIL")

    def test_dark_keyboard_with_a_paper_pill_passes(self):
        c = self.look("dark", (43, 43, 45), checks.PAPER)
        self.assertEqual(c.status, "PASS", c.evidence)

    def test_a_dark_keyboard_in_the_light_check_fails(self):
        c = self.look("light", (43, 43, 45), checks.INK)
        self.assertEqual(c.status, "FAIL")
        self.assertIn("not light", c.evidence)

    def app(self, look, bg, hero=1):
        with tempfile.TemporaryDirectory() as d:
            img = Image.new("RGB", (390 * 3, 844 * 3), bg)
            ImageDraw.Draw(img).rectangle([40 * 3, 300 * 3, 350 * 3, 500 * 3], fill=(128, 128, 128))
            img.save(os.path.join(d, f"c-app-{look}-1.png"))
            return resolve(f'CHECK app-{look} PENDING hero={hero} shot1="c-app-{look}-1.png" '
                           f'shot2="c-app-{look}-2.png" look={look}', run_dir=d)

    def test_app_backgrounds(self):
        self.assertEqual(self.app("dark", checks.INK).status, "PASS")
        self.assertEqual(self.app("light", checks.PAPER).status, "PASS")
        self.assertEqual(self.app("light", checks.INK).status, "FAIL")
        self.assertIn("no hero", self.app("dark", checks.INK, hero=0).evidence)

    def card(self, look, keyboard):
        with tempfile.TemporaryDirectory() as d:
            img = Image.new("RGB", (390 * 3, 844 * 3), (32, 160, 96))
            ImageDraw.Draw(img).rectangle([0, 500 * 3, 390 * 3, 844 * 3], fill=keyboard)
            img.save(os.path.join(d, f"c-card-wait-{look}.png"))
            return resolve(f'CHECK card-wait-{look} PENDING strip="Translating → English…" cancel=44.0x44.0 card=0 '
                           f'look={look} side={{0.5,518.0,2.5,34.7}}', run_dir=d)

    def test_card_look_is_measured(self):
        self.assertEqual(self.card("light", (209, 212, 217)).status, "PASS")
        self.assertEqual(self.card("dark", (43, 43, 45)).status, "PASS")
        c = self.card("light", (43, 43, 45))
        self.assertEqual(c.status, "FAIL")
        self.assertIn("not light", c.evidence)

    def test_a_card_line_without_its_shot_fails(self):
        with tempfile.TemporaryDirectory() as d:
            c = resolve('CHECK card-wait-dark PENDING strip="Translating → English…" cancel=44.0x44.0 card=0 '
                        'look=dark side={0.5,518.0,2.5,34.7}', run_dir=d)
        self.assertEqual(c.status, "FAIL")

    def test_a_missing_shot_is_unreadable(self):
        with tempfile.TemporaryDirectory() as d:
            c = resolve('CHECK app-dark PENDING hero=1 shot1="c-app-dark-1.png" look=dark', run_dir=d)
        self.assertIn("unreadable", c.evidence)


if __name__ == "__main__":
    unittest.main()
