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

HERE = os.path.dirname(os.path.abspath(__file__))
# Built at run time so no key-shaped literal sits in the repository.
FAKE_KEY = "sk-" + "ant-test"


def every_id_but(*skip, status="PASS"):
    return "".join(f"CHECK {i} {status} ok\n" for i in checks.EXPECTED_IDS if i not in skip)


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

    def test_duplicate_keeps_the_last(self):
        text = every_id_but("ws-1") + "CHECK ws-1 FAIL first\nCHECK ws-1 PASS second\n"
        final = {c.id: c for c in checks.assemble(text, "", "")}
        self.assertEqual(final["ws-1"].status, "PASS")
        self.assertIn("second", final["ws-1"].evidence)

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
            self.assertEqual(lines[-1], f"CHECKS pass {len(checks.EXPECTED_IDS) - 1} fail 0 record 1 skip 0")
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


if __name__ == "__main__":
    unittest.main()
