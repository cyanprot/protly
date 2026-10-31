"""Offline tests for checks.py, memsample.py and leak-guard.sh (python3 -m unittest discover -s ios-app/CI)."""

import os
import subprocess
import sys
import tempfile
import unicodedata
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import checks  # noqa: E402
import memsample  # noqa: E402
import prefsdump  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
# Split so no key-shaped literal sits in the source file (the compiled .pyc, gitignored, may fold it).
FAKE_KEY = "sk-" + "ant-test"


def every_id_but(*skip, status="PASS"):
    """A line per expected ID; the IDs checks.py judges by model output (RULES) as a key-less run writes them."""
    return "".join(f"CHECK {i} SKIP no network key\n" if i in checks.RULES else f"CHECK {i} {status} ok\n"
                   for i in checks.EXPECTED_IDS if i not in skip)


class ParseTests(unittest.TestCase):
    def test_well_formed_line(self):
        c = checks.parse_line('CHECK 6.8-1 PASS field="the "')
        self.assertEqual((c.id, c.status, c.evidence), ("6.8-1", "PASS", 'field="the "'))

    def test_line_without_evidence(self):
        c = checks.parse_line("CHECK icon RECORD")
        self.assertEqual((c.id, c.status, c.evidence), ("icon", "RECORD", ""))

    def test_blank_line_is_ignored(self):
        self.assertIsNone(checks.parse_line("   "))

    def test_unknown_status_is_fail_unreadable(self):
        c = checks.parse_line("CHECK 6.8-2 MAYBE something")
        self.assertEqual((c.id, c.status), ("6.8-2", "FAIL"))
        self.assertIn("unreadable", c.evidence)

    def test_line_without_id_is_fail_unreadable(self):
        c = checks.parse_line("CHECK")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_other_text_is_fail_unreadable(self):
        c = checks.parse_line("garbage from a crashed runner")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_quoted_field_round_trip(self):
        self.assertEqual(checks.quoted_field('CHECK x PENDING field="a \\"b\\"\\nc "', "field"), 'a "b"\nc ')
        self.assertIsNone(checks.quoted_field("CHECK x PENDING", "field"))


class SortAndCountTests(unittest.TestCase):
    def test_natural_sort(self):
        ids = ["6.8-10", "ws-1", "6.8-2", "8.5-1o", "icon", "6.8-1"]
        self.assertEqual(sorted(ids, key=checks.sort_key), ["6.8-1", "6.8-2", "6.8-10", "8.5-1o", "icon", "ws-1"])

    def test_counts(self):
        lines = [checks.Check("a", "PASS", ""), checks.Check("b", "FAIL", ""), checks.Check("c", "RECORD", ""),
                 checks.Check("d", "SKIP", ""), checks.Check("e", "PASS", "")]
        self.assertEqual(checks.summary(lines), "CHECKS pass 2 fail 1 record 1 skip 1")


class AssembleTests(unittest.TestCase):
    def test_all_present_sorted(self):
        final = checks.assemble(every_id_but(), "", "")
        self.assertEqual([c.id for c in final], sorted(checks.EXPECTED_IDS, key=checks.sort_key))

    def test_missing_id_is_fail_unreadable(self):
        final = {c.id: c for c in checks.assemble(every_id_but("ws-2"), "", "")}
        self.assertEqual(final["ws-2"].status, "FAIL")
        self.assertIn("unreadable", final["ws-2"].evidence)

    def test_missing_file_fails_every_id(self):
        final = checks.assemble(None, None, None)
        self.assertEqual(len(final), len(checks.EXPECTED_IDS))
        self.assertTrue(all(c.status == "FAIL" and "unreadable" in c.evidence for c in final))

    def test_duplicate_id_is_fail(self):
        # A later PASS must not hide an earlier FAIL (or a malformed line for the same ID).
        text = every_id_but("ws-1") + "CHECK ws-1 FAIL first\nCHECK ws-1 PASS second\n"
        final = {c.id: c for c in checks.assemble(text, "", "")}
        self.assertEqual(final["ws-1"].status, "FAIL")
        self.assertIn("duplicate", final["ws-1"].evidence)
        self.assertIn("first", final["ws-1"].evidence)

    def test_malformed_then_valid_line_is_fail(self):
        text = every_id_but("ws-1") + "CHECK ws-1 PASSED x\nCHECK ws-1 PASS y\n"
        final = {c.id: c for c in checks.assemble(text, "", "")}
        self.assertEqual(final["ws-1"].status, "FAIL")

    def test_pass_without_evidence_is_fail(self):
        c = checks.parse_line("CHECK 6.8-1 PASS")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_unresolved_pending_is_fail(self):
        text = every_id_but("6.8-3") + "CHECK 6.8-3 PENDING whatever\n"
        final = {c.id: c for c in checks.assemble(text, "", "")}
        self.assertEqual(final["6.8-3"].status, "FAIL")

    def test_unexpected_id_is_kept(self):
        final = {c.id: c for c in checks.assemble(every_id_but() + "CHECK extra RECORD x\n", "", "")}
        self.assertEqual(final["extra"].status, "RECORD")


class TextTests(unittest.TestCase):
    def test_nfc_and_nfd_hangul_compare_equal(self):
        nfc = "안녕하세요"
        nfd = unicodedata.normalize("NFD", nfc)
        self.assertNotEqual(nfc, nfd)
        self.assertTrue(checks.same_text(nfc, nfd))
        self.assertFalse(checks.same_text(nfc, "안녕"))

    def test_relaunch_compares_nfd_field(self):
        nfd = unicodedata.normalize("NFD", "wyd ")
        text = every_id_but("6.8-9") + f'CHECK 6.8-9 PENDING field="{nfd}"\n'
        marks = "MARK relaunch-before 100.0\nMARK relaunch-after 110.0\n"
        mem = "100.0 41 rss 9000\n110.0 52 rss 9100\n"
        final = {c.id: c for c in checks.assemble(text, marks, mem)}
        self.assertEqual(final["6.8-9"].status, "PASS")


def relaunch(field, mem, marks="MARK relaunch-before 100.0\nMARK relaunch-after 110.5\n"):
    text = every_id_but("6.8-9") + f'CHECK 6.8-9 PENDING field="{field}"\n'
    return {c.id: c for c in checks.assemble(text, marks, mem)}["6.8-9"]


class RelaunchTests(unittest.TestCase):
    def test_pid_changed_is_pass(self):
        c = relaunch("wyd ", "99.0 41 rss 9000\n101.0 41 rss 9000\n110.0 52 rss 9100\n")
        self.assertEqual(c.status, "PASS")
        self.assertIn("41", c.evidence)
        self.assertIn("52", c.evidence)

    def test_same_pid_is_record(self):
        c = relaunch("wyd ", "100.0 41 rss 9000\n110.0 41 rss 9100\n")
        self.assertEqual(c.status, "RECORD")
        self.assertIn("same process", c.evidence)

    def test_field_mismatch_is_fail(self):
        c = relaunch("죵 ", "100.0 41 rss 9000\n110.0 52 rss 9100\n")
        self.assertEqual(c.status, "FAIL")

    def test_no_samples_is_fail_unreadable(self):
        c = relaunch("wyd ", "")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_missing_mark_is_fail_unreadable(self):
        c = relaunch("wyd ", "100.0 41 rss 9000\n", marks="MARK relaunch-before 100.0\n")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_sample_far_from_the_mark_is_unreadable(self):
        c = relaunch("wyd ", "10.0 41 rss 9000\n200.0 52 rss 9100\n")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)


def memory(mem, marks="MARK mem-start 100.0\nMARK mem-end 160.0\n"):
    text = every_id_but("6.8-10") + "CHECK 6.8-10 PENDING presentations=30\n"
    return {c.id: c for c in checks.assemble(text, marks, mem)}["6.8-10"]


class MemoryTests(unittest.TestCase):
    def test_same_pid_records_both_numbers_and_growth(self):
        c = memory("100.5 41 rss 30720\n100.5 41 footprint 20480\n159.0 41 rss 31744\n159.0 41 footprint 25600\n")
        self.assertEqual(c.status, "RECORD")
        self.assertIn("20.0 MB", c.evidence)
        self.assertIn("25.0 MB", c.evidence)
        self.assertIn("+5.0 MB", c.evidence)
        self.assertIn("footprint", c.evidence)
        self.assertIn("whole MB", c.evidence)  # footprint prints MB: growth under 1 MB reads as zero

    def test_falls_back_to_rss(self):
        c = memory("100.0 41 rss 10240\n160.0 41 rss 12288\n")
        self.assertEqual(c.status, "RECORD")
        self.assertIn("+2.0 MB", c.evidence)
        self.assertIn("rss", c.evidence)

    def test_changed_pid_is_not_comparable(self):
        c = memory("100.0 41 rss 10240\n160.0 77 rss 12288\n")
        self.assertEqual(c.status, "RECORD")
        self.assertIn("pid changed, not comparable", c.evidence)

    def test_no_samples_is_fail_unreadable(self):
        c = memory("100.0 - none -\n160.0 - none -\n")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_no_marks_is_fail_unreadable(self):
        c = memory("100.0 41 rss 10240\n", marks="")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_malformed_sample_lines_are_ignored(self):
        c = memory("junk\n100.0 41 rss abc\n100.0 41 rss 10240\n160.0 41 rss 10240\n")
        self.assertEqual(c.status, "RECORD")
        self.assertIn("+0.0 MB", c.evidence)


class MainTests(unittest.TestCase):
    def test_writes_final_checks_and_keeps_the_raw(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "checks.txt"), "w", encoding="utf-8") as f:
                f.write(every_id_but("icon") + "CHECK icon RECORD found\n")
            out = subprocess.run([sys.executable, os.path.join(HERE, "checks.py"), d],
                                 capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stderr)
            lines = out.stdout.splitlines()
            self.assertEqual(lines[0], "CHECKS")
            ruled = len(checks.RULES)
            self.assertEqual(lines[-1], f"CHECKS pass {len(checks.EXPECTED_IDS) - 1 - ruled} fail 0 record 1 skip {ruled}")
            with open(os.path.join(d, "checks.txt"), encoding="utf-8") as f:
                self.assertEqual(f.read().splitlines(), lines[1:-1])
            self.assertTrue(os.path.exists(os.path.join(d, "checks-raw.txt")))

    def test_exit_1_on_a_fail(self):
        with tempfile.TemporaryDirectory() as d:
            out = subprocess.run([sys.executable, os.path.join(HERE, "checks.py"), d],
                                 capture_output=True, text=True)
            self.assertEqual(out.returncode, 1)
            self.assertIn("unreadable", out.stdout)


class MemsampleParseTests(unittest.TestCase):
    def test_footprint(self):
        text = ("======\nProtlyCIKeyboard [5432]: 64-bit    Footprint: 21 MB (16384 bytes per page)\n======\n")
        self.assertEqual(memsample.parse_footprint(text), 21 * 1024)
        self.assertEqual(memsample.parse_footprint("phys_footprint: 9584 KB"), 9584)
        self.assertEqual(memsample.parse_footprint("Footprint: 1.5 GB"), int(1.5 * 1024 * 1024))
        self.assertIsNone(memsample.parse_footprint("footprint: permission denied"))

    def test_vmmap(self):
        self.assertEqual(memsample.parse_vmmap("Physical footprint:         10.5M\n"), int(10.5 * 1024))
        self.assertEqual(memsample.parse_vmmap("Physical footprint:         900K\n"), 900)
        self.assertIsNone(memsample.parse_vmmap("vmmap: no process"))

    def test_rss(self):
        self.assertEqual(memsample.parse_rss("  12345\n"), 12345)
        self.assertIsNone(memsample.parse_rss(""))

    def test_wait_for_text(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "ui-log.txt")
            self.assertFalse(memsample.has_text(path, "== PhoneChecksUITests"))
            with open(path, "w", encoding="utf-8") as f:
                f.write("== KeyboardShotsUITests.testScenarios\n")
            self.assertFalse(memsample.has_text(path, "== PhoneChecksUITests"))
            with open(path, "a", encoding="utf-8") as f:
                f.write("== PhoneChecksUITests.test1_68\n")
            self.assertTrue(memsample.has_text(path, "== PhoneChecksUITests"))

    def test_probe_skips_vmmap(self):
        # Run 8: vmmap --summary hung 20 s on the keyboard process (it suspends its target).
        self.assertNotIn("vmmap", [m[0] for m in memsample.METHODS])

    def test_pids(self):
        self.assertEqual(memsample.parse_pids("41\n52\n"), [41, 52])
        self.assertEqual(memsample.parse_pids(""), [])


class LeakGuardTests(unittest.TestCase):
    def guard(self, d):
        return subprocess.run(["bash", os.path.join(HERE, "leak-guard.sh"), d], capture_output=True, text=True)

    def test_clean_folder_passes(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "report.txt"), "w") as f:
                f.write("STATUS measured\nRESULT PASS\n")
            out = self.guard(d)
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)

    def test_key_in_a_nested_file_is_refused_without_printing_it(self):
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "sub"))
            with open(os.path.join(d, "sub", "build.log"), "w") as f:
                f.write(f"let apiKey = \"{FAKE_KEY}-123\"\n")
            out = self.guard(d)
            self.assertEqual(out.returncode, 1)
            self.assertIn("build.log", out.stdout)
            self.assertNotIn(FAKE_KEY, out.stdout + out.stderr)

    def test_key_in_a_binary_file_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "c-x.png"), "wb") as f:
                f.write(b"\x89PNG\x00\x01" + FAKE_KEY.encode() + b"\x00")
            self.assertEqual(self.guard(d).returncode, 1)

    def test_missing_folder_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertNotEqual(self.guard(os.path.join(d, "nope")).returncode, 0)


def resolve(line):
    """One PENDING network line through assemble(), the way checks.py sees it."""
    return {c.id: c for c in checks.assemble(line + "\n", "", "")}[line.split()[1]]


class ScriptRuleTests(unittest.TestCase):
    """Plan Task 2.3: the script rules for model output."""

    def test_cyrillic(self):
        self.assertTrue(checks.has_cyrillic("Спасибо"))
        self.assertTrue(checks.has_cyrillic("Ѐ"))
        self.assertTrue(checks.has_cyrillic("ӿ"))
        self.assertFalse(checks.has_cyrillic("spasibo"))
        self.assertFalse(checks.has_cyrillic("Ԁ"))

    def test_hangul_syllables_and_compatibility_jamo(self):
        self.assertTrue(checks.has_hangul("안녕"))
        self.assertTrue(checks.has_hangul("ㅋㅋ"))
        self.assertTrue(checks.has_hangul("가"))
        self.assertTrue(checks.has_hangul("힣"))
        self.assertTrue(checks.has_hangul("ㄱ"))
        self.assertTrue(checks.has_hangul("ㆎ"))
        self.assertFalse(checks.has_hangul("hello"))
        self.assertFalse(checks.has_hangul("㄰"))

    def test_nfd_hangul_counts_as_hangul(self):
        # Conjoining jamo (U+1100...) are outside the plan's ranges; NFC composes them into syllables first.
        self.assertTrue(checks.has_hangul(unicodedata.normalize("NFD", "봐")))

    def test_kana_or_kanji(self):
        self.assertTrue(checks.has_kana_or_kanji("あした"))
        self.assertTrue(checks.has_kana_or_kanji("カタカナ"))
        self.assertTrue(checks.has_kana_or_kanji("明日"))
        self.assertTrue(checks.has_kana_or_kanji("぀"))
        self.assertTrue(checks.has_kana_or_kanji("鿿"))
        self.assertFalse(checks.has_kana_or_kanji("ashita"))
        self.assertFalse(checks.has_kana_or_kanji("내일"))

    def test_latin_needs_a_letter_and_no_hangul(self):
        self.assertTrue(checks.is_latin("See you at 3 tomorrow"))
        self.assertFalse(checks.is_latin("3:00"))
        self.assertFalse(checks.is_latin("See you 내일"))
        self.assertFalse(checks.is_latin("ㅋ ok"))
        self.assertFalse(checks.is_latin(""))

    def test_every_network_id_has_rules_or_is_written_by_the_test(self):
        written = {"7.7-1", "7.7-4", "7.7-5", "7.7-6", "8.5-10"}  # not model output: the test writes the status
        for i in checks.NETWORK_IDS:
            self.assertIn(i, checks.EXPECTED_IDS)
            self.assertTrue(i in checks.RULES or i in written, i)


class NetworkResolveTests(unittest.TestCase):
    """PENDING network lines: the test's `group#n="..."` outputs against RULES; one retry, two FAILs is a FAIL."""

    def test_russian_insert_passes(self):
        c = resolve('CHECK 8.5-1 PENDING translating=yes out#1="Спасибо за конспект, ты меня спасла." undo=ok')
        self.assertEqual(c.status, "PASS", c.evidence)
        self.assertIn("out#1 ok", c.evidence)
        self.assertIn("undo=ok", c.evidence)

    def test_russian_with_the_code_left_in_fails(self):
        c = resolve('CHECK 8.5-1 PENDING out#1="ru: Спасибо, ты меня спасла."')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("ru:", c.evidence)

    def test_russian_with_the_draft_left_in_fails(self):
        c = resolve('CHECK 8.5-1 PENDING out#1="누나 노트 Спасибо, ты меня спасла."')
        self.assertEqual(c.status, "FAIL")

    def test_masculine_spas_is_not_spasla(self):
        self.assertEqual(resolve('CHECK 8.5-1 PENDING out#1="Ты меня спас."').status, "FAIL")

    def test_retry_that_passes_is_pass_with_both_outputs(self):
        c = resolve('CHECK 8.5-4 PENDING out#1="Estoy muy cansada hoy" out#2="Hoy estoy muy cansado"')
        self.assertEqual(c.status, "PASS", c.evidence)
        self.assertIn("cansada", c.evidence)
        self.assertIn("out#1 fails", c.evidence)
        self.assertIn("out#2 ok", c.evidence)

    def test_two_fails_is_fail(self):
        c = resolve('CHECK 8.5-9 PENDING out#1="the colour" out#2="el colour, jaja"')
        self.assertEqual(c.status, "FAIL")
        self.assertIn("out#2 fails", c.evidence)

    def test_no_output_is_fail_unreadable(self):
        c = resolve("CHECK 8.5-5 PENDING translating=yes")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_escaped_output_is_unescaped(self):
        self.assertEqual(resolve(r'CHECK 8.5-5 PENDING out#1="He said \"see you\" at 3"').status, "PASS")

    def test_japanese(self):
        self.assertEqual(resolve('CHECK 8.5-3 PENDING out#1="明日時間ある？一緒にご飯食べよう笑"').status, "PASS")
        self.assertEqual(resolve('CHECK 8.5-3 PENDING out#1="明日時間ある？ご飯行こう lol"').status, "FAIL")
        self.assertEqual(resolve('CHECK 8.5-3 PENDING out#1="明日時間ある？ご飯行こう ㅋㅋ"').status, "FAIL")
        self.assertEqual(resolve('CHECK 8.5-3 PENDING out#1="ashita jikan aru?"').status, "FAIL")

    def test_no_prefix_and_ok_prefix_are_latin(self):
        self.assertEqual(resolve('CHECK 8.5-5 PENDING out#1="See you at 3 tomorrow"').status, "PASS")
        self.assertEqual(resolve('CHECK 8.5-6 PENDING out#1="ok: see you tomorrow"').status, "PASS")
        self.assertEqual(resolve('CHECK 8.5-6 PENDING out#1="내일 봐"').status, "FAIL")
        self.assertEqual(resolve('CHECK 6.8-11 PENDING flip=ok out#1="See you tomorrow"').status, "PASS")

    def test_korean_polish(self):
        good = 'CHECK 8.5-7 PENDING polishing=yes out#1="낼 시간 돼? 같이 밥 먹자 ㅋㅋ 안 되면 말해줘"'
        self.assertEqual(resolve(good).status, "PASS")
        self.assertEqual(resolve(good.replace("ㅋㅋ ", "")).status, "FAIL")
        self.assertEqual(resolve(good.replace("말해줘", "말해죠")).status, "FAIL")
        self.assertEqual(resolve(good.replace('out#1="', 'out#1="ko: ')).status, "FAIL")
        self.assertEqual(resolve('CHECK 8.5-7 PENDING out#1="Are you free tomorrow? lol"').status, "FAIL")

    def test_long_korean_polish(self):
        self.assertEqual(resolve('CHECK 8.5-8 PENDING out#1="오늘 진짜 길었어.\\n\\n내일 아침에 전화할게."').status, "PASS")
        self.assertEqual(resolve('CHECK 8.5-8 PENDING out#1="KO: 오늘 진짜 길었어"').status, "FAIL")

    def test_spanish_polish(self):
        good = 'CHECK 8.5-9 PENDING out#1="Me encanta el color de tu chaqueta, ¿dónde la compraste? Jaja"'
        self.assertEqual(resolve(good).status, "PASS")
        self.assertEqual(resolve(good.replace("compraste", "conprastes")).status, "FAIL")

    def test_about_me_name_and_nothing_else(self):
        good = 'CHECK 7.7-2 PENDING out#1="Moonbeam Kiln opens next week"'
        self.assertEqual(resolve(good).status, "PASS")
        self.assertEqual(resolve('CHECK 7.7-2 PENDING out#1="Moonbeam kiln opens next week"').status, "FAIL")
        self.assertEqual(resolve('CHECK 7.7-2 PENDING out#1="Our pottery studio Moonbeam Kiln opens"').status, "FAIL")
        self.assertEqual(resolve('CHECK 7.7-2 PENDING out#1="Moonbeam Kiln opens in Victoria"').status, "FAIL")
        self.assertEqual(resolve('CHECK 7.7-2 PENDING out#1="Munbim Killeun opens next week"').status, "FAIL")

    def test_two_groups_must_both_pass(self):
        line = 'CHECK 7.7-3 PENDING panel#1="어제 사진 보내줄 수 있어?" four=ok out#1="Moonbeam Kiln opens next week"'
        self.assertEqual(resolve(line).status, "PASS")
        self.assertEqual(resolve(line.replace("어제 사진 보내줄 수 있어?", "Can you send me the photos?")).status, "FAIL")
        self.assertEqual(resolve(line.replace("Moonbeam Kiln", "Munbim Kilreun")).status, "FAIL")
        missing = resolve('CHECK 7.7-3 PENDING panel#1="어제 사진 보내줄 수 있어?"')
        self.assertEqual(missing.status, "FAIL")
        self.assertIn("unreadable", missing.evidence)

    def test_status_the_test_wrote_is_kept(self):
        # A FAIL for a step the test judged itself (Undo, a missing label) is not overturned by good output.
        c = resolve('CHECK 8.5-1 FAIL out#1="Ты меня спасла." undo="ru: x" want "ru: y"')
        self.assertEqual(c.status, "FAIL")
        self.assertEqual(resolve("CHECK 8.5-3 SKIP no network key").status, "SKIP")


class NetworkGuardTests(unittest.TestCase):
    """A network item can PASS only through its model output, and a run with the key cannot SKIP for want of one."""

    def test_pass_without_model_output_is_fail_unreadable(self):
        c = resolve("CHECK 8.5-5 PASS field looked fine")
        self.assertEqual(c.status, "FAIL")
        self.assertIn("unreadable", c.evidence)

    def test_no_key_skip_is_kept_without_the_key(self):
        c = {x.id: x for x in checks.assemble("CHECK 8.5-5 SKIP no network key\n", "", "")}["8.5-5"]
        self.assertEqual(c.status, "SKIP")

    def test_no_key_skip_with_the_key_is_fail_unreadable(self):
        lines = checks.assemble("CHECK 8.5-5 SKIP no network key\nCHECK 7.7-6 SKIP needs a phone reinstall\n",
                                "", "", network_key=True)
        by_id = {c.id: c for c in lines}
        self.assertEqual(by_id["8.5-5"].status, "FAIL")
        self.assertIn("unreadable", by_id["8.5-5"].evidence)
        self.assertEqual(by_id["7.7-6"].status, "SKIP")

    def test_main_takes_the_network_key_flag(self):
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "checks.txt"), "w", encoding="utf-8") as f:
                f.write("CHECK 8.5-5 SKIP no network key\n")
            out = subprocess.run([sys.executable, os.path.join(HERE, "checks.py"), d, "--network-key"],
                                 capture_output=True, text=True)
            self.assertIn("CHECK 8.5-5 FAIL unreadable", out.stdout)


class WriteSecretsTests(unittest.TestCase):
    """write-secrets.sh: the key reaches Secrets.swift through make-secrets.sh in a temporary HOME, never output."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        # A throwaway copy of the two scripts in a git repo shaped like this one, so the real Secrets.swift is
        # never touched.
        self.repo = os.path.join(root, "repo")
        for sub in ("ios-app/CI", "ios-app/scripts", "ios-app/Sources/ProtlyKeyboard"):
            os.makedirs(os.path.join(self.repo, sub))
        for rel in ("ios-app/CI/write-secrets.sh", "ios-app/scripts/make-secrets.sh"):
            with open(os.path.join(HERE, "..", "..", rel), encoding="utf-8") as src, \
                    open(os.path.join(self.repo, rel), "w", encoding="utf-8") as dst:
                dst.write(src.read())
        with open(os.path.join(self.repo, ".gitignore"), "w", encoding="utf-8") as f:
            f.write("ios-app/Sources/ProtlyKeyboard/Secrets.swift\n")
        subprocess.run(["git", "init", "-q", self.repo], check=True)
        self.secrets = os.path.join(self.repo, "ios-app/Sources/ProtlyKeyboard/Secrets.swift")
        self.env_file = os.path.join(root, "github-env")
        open(self.env_file, "w").close()
        self.tmpdir = os.path.join(root, "t")
        os.makedirs(self.tmpdir)

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, key):
        env = {"PATH": os.environ["PATH"], "HOME": os.path.join(self.tmp.name, "home"), "GITHUB_ENV": self.env_file,
               "TMPDIR": self.tmpdir}
        if key is not None:
            env["PROTLY_API_KEY"] = key
        return subprocess.run(["bash", os.path.join(self.repo, "ios-app/CI/write-secrets.sh")],
                              capture_output=True, text=True, env=env)

    def github_env(self):
        with open(self.env_file, encoding="utf-8") as f:
            return f.read()

    def test_key_is_written_and_never_printed(self):
        key = FAKE_KEY + "-Abc_123"
        out = self.run_script(key)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertNotIn(key, out.stdout + out.stderr)
        self.assertNotIn("ant-", out.stdout + out.stderr)
        with open(self.secrets, encoding="utf-8") as f:
            self.assertIn(f'apiKey = "{key}"', f.read())
        self.assertEqual(self.github_env(), "HAS_KEY=true\n")
        self.assertNotIn(key, self.github_env())
        # The temporary HOME with the key file is gone.
        self.assertEqual(os.listdir(self.tmpdir), [])

    def test_empty_secret_keeps_the_stand_in(self):
        for key in (None, ""):
            out = self.run_script(key)
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            self.assertFalse(os.path.exists(self.secrets))
            self.assertIn("no network key", out.stdout)
        self.assertEqual(self.github_env(), "HAS_KEY=false\nHAS_KEY=false\n")

    def test_malformed_key_fails_without_printing_it(self):
        out = self.run_script("not-a-key-SECRETVALUE")
        self.assertNotEqual(out.returncode, 0)
        self.assertNotIn("SECRETVALUE", out.stdout + out.stderr)
        self.assertFalse(os.path.exists(self.secrets))
        self.assertNotIn("HAS_KEY=true", self.github_env())
        self.assertEqual(os.listdir(self.tmpdir), [])


class WorkflowTests(unittest.TestCase):
    """keyboard-shots.yml (plan Task 2.1): the key reaches one step, and a run with the key never saves the cache."""

    @classmethod
    def setUpClass(cls):
        import yaml  # the verify command and the workflow's test step install it
        with open(os.path.join(HERE, "..", "..", ".github", "workflows", "keyboard-shots.yml"), encoding="utf-8") as f:
            cls.text = f.read()
        cls.steps = yaml.safe_load(cls.text)["jobs"]["shots"]["steps"]

    def test_secret_goes_to_the_write_secrets_step_only(self):
        self.assertEqual(self.text.count("secrets.PROTLY_API_KEY"), 1)
        users = [s for s in self.steps if "secrets.PROTLY_API_KEY" in str(s)]
        self.assertEqual(len(users), 1)
        self.assertEqual(users[0]["env"], {"PROTLY_API_KEY": "${{ secrets.PROTLY_API_KEY }}"})
        self.assertIn("write-secrets.sh", users[0]["run"])

    def test_cache_is_restore_then_save_without_the_key(self):
        uses = [s.get("uses", "") for s in self.steps]
        self.assertFalse([u for u in uses if u.startswith("actions/cache@")], "the combined action saves on its own")
        restore = [i for i, u in enumerate(uses) if u.startswith("actions/cache/restore@")]
        save = [i for i, u in enumerate(uses) if u.startswith("actions/cache/save@")]
        self.assertEqual((len(restore), len(save)), (1, 1))
        secrets_step = next(i for i, s in enumerate(self.steps) if "write-secrets.sh" in s.get("run", ""))
        # The cache key is hashed before Secrets.swift exists.
        self.assertLess(restore[0], secrets_step)
        self.assertIn("env.HAS_KEY == 'false'", self.steps[save[0]]["if"])  # unset (the step failed) never saves

    def test_publish_goes_through_the_leak_guard(self):
        publish = [s for s in self.steps if "bash ios-app/CI/publish-shots.sh" in s.get("run", "")]
        self.assertEqual(len(publish), 1)
        with open(os.path.join(HERE, "publish-shots.sh"), encoding="utf-8") as f:
            script = f.read()
        self.assertLess(script.index("leak-guard.sh"), script.index("git push"))


class PrefsDumpTests(unittest.TestCase):
    """prefsdump.py (plan Task 2.2 step 1): what changed in a shut-down device's data folder around Full Access."""

    def setUp(self):
        import plistlib
        import sqlite3
        self.plistlib, self.sqlite3 = plistlib, sqlite3
        self.tmp = tempfile.TemporaryDirectory()
        self.data = os.path.join(self.tmp.name, "data")
        self.prefs = os.path.join(self.data, "Library", "Preferences")
        os.makedirs(self.prefs)
        os.makedirs(os.path.join(self.data, "Library", "TCC"))
        self.write_plist("com.apple.keyboard.preferences.plist", {"KeyboardPrediction": True})
        self.write_plist("com.apple.other.plist", {"x": 1})
        db = sqlite3.connect(os.path.join(self.data, "Library", "TCC", "TCC.db"))
        db.execute("create table access (service text, client text, auth_value integer)")
        db.execute("insert into access values ('kTCCServiceCamera', 'com.x', 0)")
        db.commit()
        db.close()

    def tearDown(self):
        self.tmp.cleanup()

    def write_plist(self, name, value):
        with open(os.path.join(self.prefs, name), "wb") as f:
            self.plistlib.dump(value, f, fmt=self.plistlib.FMT_BINARY)

    def snap(self, name):
        dest = os.path.join(self.tmp.name, name)
        prefsdump.snapshot(self.data, dest)
        return dest

    def test_changed_key_new_file_and_tcc_row(self):
        before = self.snap("before")
        self.write_plist("com.apple.keyboard.preferences.plist",
                         {"KeyboardPrediction": True, "KeyboardsWithFullAccess": ["com.northprot.protly.cihost.keyboard"]})
        self.write_plist("com.apple.new.plist", {"y": "z"})
        db = self.sqlite3.connect(os.path.join(self.data, "Library", "TCC", "TCC.db"))
        db.execute("insert into access values ('kTCCServiceKeyboardNetwork', 'com.northprot.protly.cihost.keyboard', 2)")
        db.commit()
        db.close()
        after = self.snap("after")
        text = prefsdump.diff(before, after)
        self.assertIn("Library/Preferences/com.apple.keyboard.preferences.plist", text)
        self.assertIn("+ KeyboardsWithFullAccess", text)
        self.assertIn("com.northprot.protly.cihost.keyboard", text)
        self.assertIn("new Library/Preferences/com.apple.new.plist", text)
        self.assertIn("kTCCServiceKeyboardNetwork", text)
        self.assertNotIn("kTCCServiceCamera", text)  # unchanged rows are not repeated
        self.assertNotIn("com.apple.other.plist", text)
        self.assertIn("create table access", text.lower())

    def test_nothing_changed(self):
        before = self.snap("before")
        after = self.snap("after")
        self.assertIn("no plist or TCC change", prefsdump.diff(before, after))

    def test_unreadable_plist_is_reported_not_raised(self):
        before = self.snap("before")
        with open(os.path.join(self.prefs, "com.apple.other.plist"), "wb") as f:
            f.write(b"not a plist")
        after = self.snap("after")
        self.assertIn("unreadable", prefsdump.diff(before, after))

    def test_snapshot_of_a_missing_folder_fails(self):
        with self.assertRaises(SystemExit):
            prefsdump.snapshot(os.path.join(self.tmp.name, "nope"), os.path.join(self.tmp.name, "x"))
        code = subprocess.run([sys.executable, os.path.join(HERE, "prefsdump.py"), "snapshot",
                               os.path.join(self.tmp.name, "nope"), os.path.join(self.tmp.name, "y")],
                              capture_output=True).returncode
        self.assertNotEqual(code, 0)

    def test_diff_states_how_much_each_snapshot_held(self):
        before = self.snap("before")
        after = self.snap("after")
        self.assertIn("snapshots: before 2 plists", prefsdump.diff(before, after))

    def test_main_writes_the_diff(self):
        before = self.snap("before")
        self.write_plist("com.apple.other.plist", {"x": 2})
        out = os.path.join(self.tmp.name, "probe-prefs.txt")
        code = subprocess.run([sys.executable, os.path.join(HERE, "prefsdump.py"), "snapshot", self.data,
                               os.path.join(self.tmp.name, "after")]).returncode
        self.assertEqual(code, 0)
        code = subprocess.run([sys.executable, os.path.join(HERE, "prefsdump.py"), "diff", before,
                               os.path.join(self.tmp.name, "after"), out]).returncode
        self.assertEqual(code, 0)
        with open(out, encoding="utf-8") as f:
            self.assertIn("~ x: 1 -> 2", f.read())


if __name__ == "__main__":
    unittest.main()
