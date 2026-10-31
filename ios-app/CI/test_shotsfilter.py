"""Tests for shotsfilter.py and the filtered-run parts of checks.py (tower TOWER-SPEEDUP-1)."""

import os
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import checks  # noqa: E402
import shotsfilter  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ACCESS = "PhoneChecksUITests/test0_access"


class ParseTests(unittest.TestCase):
    def test_no_tag_is_a_full_run(self):
        self.assertIsNone(shotsfilter.parse("ci(shots): fix [shots]"))
        self.assertIsNone(shotsfilter.parse(""))
        self.assertIsNone(shotsfilter.parse("[shots] [probe]"))

    def test_layout_only(self):
        self.assertEqual(shotsfilter.parse("fix [shots:KeyboardShotsUITests]"), ["KeyboardShotsUITests"])

    def test_a_phone_method_brings_full_access_first(self):
        self.assertEqual(shotsfilter.parse("fix [shots:PhoneChecksUITests/test7_77]"),
                         [ACCESS, "PhoneChecksUITests/test7_77"])

    def test_list_with_spaces_keeps_order_and_drops_repeats(self):
        got = shotsfilter.parse("x [shots: KeyboardShotsUITests, PhoneChecksUITests/test6_85net,"
                                "PhoneChecksUITests/test6_85net ]")
        self.assertEqual(got, ["KeyboardShotsUITests", ACCESS, "PhoneChecksUITests/test6_85net"])

    def test_access_named_once(self):
        got = shotsfilter.parse(f"[shots:{ACCESS},PhoneChecksUITests/test1_68]")
        self.assertEqual(got, [ACCESS, "PhoneChecksUITests/test1_68"])

    def test_whole_class_needs_no_extra_access(self):
        self.assertEqual(shotsfilter.parse("[shots:PhoneChecksUITests]"), ["PhoneChecksUITests"])

    def test_two_tags_join(self):
        got = shotsfilter.parse("[shots:KeyboardShotsUITests] and [shots:PhoneChecksUITests/test2_ws]")
        self.assertEqual(got, ["KeyboardShotsUITests", ACCESS, "PhoneChecksUITests/test2_ws"])

    def test_bad_entries_are_refused(self):
        for message in ("[shots:]", "[shots: , ]", "[shots:Foo]", "[shots:PhoneChecksUITests/test8_85]",
                        "[shots:KeyboardShotsUITests/testScenarios;rm -rf x]", "[shots:PhoneChecksUITests/]",
                        "[shots:../PhoneChecksUITests]", "[shots:PhoneChecksUITests/test1_68 $(id)]"):
            with self.assertRaises(ValueError, msg=message):
                shotsfilter.parse(message)

    def test_both_tags_are_refused(self):
        # A full-run commit that quotes a filter tag must not quietly run part of the suite.
        with self.assertRaises(ValueError):
            shotsfilter.parse("fix [shots] (closing run was [shots:KeyboardShotsUITests])")

    def test_a_filter_that_measures_nothing_is_refused(self):
        for message in ("[shots:PhoneChecksUITests/test0_access]", "[shots:PhoneChecksUITests/test0_probe]"):
            with self.assertRaises(ValueError, msg=message):
                shotsfilter.parse(message)

    def test_layout_method_by_name(self):
        self.assertEqual(shotsfilter.parse("[shots:KeyboardShotsUITests/testScenarios]"),
                         ["KeyboardShotsUITests/testScenarios"])


class MemWaitTests(unittest.TestCase):
    def test_full_run_waits_for_test1(self):
        self.assertEqual(shotsfilter.mem_wait(None), "== PhoneChecksUITests.test1")
        self.assertEqual(shotsfilter.mem_wait(["PhoneChecksUITests"]), "== PhoneChecksUITests.test1")

    def test_first_selected_method_after_access(self):
        self.assertEqual(shotsfilter.mem_wait([ACCESS, "PhoneChecksUITests/test4_memory"]),
                         "== PhoneChecksUITests.test4_memory")

    def test_no_phone_method(self):
        self.assertEqual(shotsfilter.mem_wait(["KeyboardShotsUITests"]), "")

    def test_xctest_order_not_tag_order(self):
        # XCTest runs a class's methods alphabetically: test4_memory comes before test6_85net.
        entries = [ACCESS, "PhoneChecksUITests/test6_85net", "PhoneChecksUITests/test4_memory"]
        self.assertEqual(shotsfilter.mem_wait(entries), "== PhoneChecksUITests.test4_memory")


class MainTests(unittest.TestCase):
    def run_main(self, message, *args):
        env = dict(os.environ, SHOTS_MESSAGE=message)
        return subprocess.run([sys.executable, os.path.join(HERE, "shotsfilter.py"), *args],
                              capture_output=True, text=True, env=env)

    def test_prints_entries(self):
        out = self.run_main("x [shots:PhoneChecksUITests/test7_77]")
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertEqual(out.stdout.splitlines(), [ACCESS, "PhoneChecksUITests/test7_77"])

    def test_full_run_prints_nothing(self):
        out = self.run_main("x [shots]")
        self.assertEqual((out.returncode, out.stdout), (0, ""))

    def test_bad_filter_exits_2(self):
        out = self.run_main("x [shots:PhoneChecksUITests/test8_85]")
        self.assertEqual(out.returncode, 2)
        self.assertIn("test8_85", out.stderr)

    def test_mem_wait(self):
        out = self.run_main("x [shots:PhoneChecksUITests/test6_85net]", "mem-wait")
        self.assertEqual(out.stdout.strip(), "== PhoneChecksUITests.test6_85net")


class SwiftNamesTests(unittest.TestCase):
    """The filter's method lists match the test methods in the Swift sources, so a rename cannot leave a name the
    filter accepts and -only-testing silently runs nothing for."""

    def swift_methods(self, cls):
        import re
        names = set()
        for name in os.listdir(os.path.join(HERE, "UITests")):
            with open(os.path.join(HERE, "UITests", name), encoding="utf-8") as f:
                src = f.read()
            m = re.search(r"final class " + cls + r"\b.*?\n}\n", src, re.S)
            if m:
                names |= set(re.findall(r"func (test\w+)\(", m.group(0)))
        return names

    def test_phone_methods(self):
        self.assertEqual(self.swift_methods("PhoneChecksUITests"), shotsfilter.methods("PhoneChecksUITests"))

    def test_layout_methods(self):
        self.assertEqual(self.swift_methods("KeyboardShotsUITests"), shotsfilter.methods("KeyboardShotsUITests"))


class CoveredIdsTests(unittest.TestCase):
    def test_methods_cover_every_id_once(self):
        ids = [i for v in checks.METHOD_IDS.values() for i in v]
        self.assertEqual(sorted(ids), sorted(checks.EXPECTED_IDS))
        self.assertEqual(len(ids), len(set(ids)))

    def test_cover(self):
        self.assertEqual(checks.covered_ids(None), set(checks.EXPECTED_IDS) | {"layout"})
        self.assertEqual(checks.covered_ids(["KeyboardShotsUITests"]), {"layout"})
        self.assertEqual(checks.covered_ids(["KeyboardShotsUITests/testScenarios"]), {"layout"})
        self.assertEqual(checks.covered_ids(["PhoneChecksUITests"]), set(checks.EXPECTED_IDS))
        self.assertEqual(checks.covered_ids([ACCESS, "PhoneChecksUITests/test7_77"]),
                         {f"7.7-{i}" for i in range(1, 7)})


class NotRunTests(unittest.TestCase):
    def test_ids_outside_the_filter_are_not_run(self):
        ran = checks.covered_ids([ACCESS, "PhoneChecksUITests/test5_icon"])
        final = {c.id: c for c in checks.assemble("CHECK icon RECORD found\n", "", "", ran=ran)}
        self.assertEqual(final["icon"].status, "RECORD")
        self.assertEqual(final["7.7-1"].status, "NOT-RUN")
        self.assertIn("filtered run", final["7.7-1"].evidence)
        self.assertEqual(final["6.8-1"].status, "NOT-RUN")

    def test_a_selected_id_without_a_line_still_fails(self):
        ran = checks.covered_ids([ACCESS, "PhoneChecksUITests/test2_ws"])
        final = {c.id: c for c in checks.assemble("CHECK ws-1 PASS ok\n", "", "", ran=ran)}
        self.assertEqual(final["ws-2"].status, "FAIL")
        self.assertEqual(final["ws-3"].status, "FAIL")

    def test_summary_counts_not_run_only_when_there_are_some(self):
        lines = [checks.Check("a", "PASS", ""), checks.Check("b", "NOT-RUN", "filtered run")]
        self.assertEqual(checks.summary(lines), "CHECKS pass 1 fail 0 record 0 skip 0 not-run 1")
        self.assertEqual(checks.summary(lines[:1]), "CHECKS pass 1 fail 0 record 0 skip 0")

    def test_main_refuses_a_bad_ran_list(self):
        import tempfile
        for ran in ("", ",", "PhoneCheckUITests/test1_68", "ProtlyCIUITests/PhoneChecksUITests",
                    "PhoneChecksUITests/test8_85"):
            with tempfile.TemporaryDirectory() as d:
                out = subprocess.run([sys.executable, os.path.join(HERE, "checks.py"), d, "--ran", ran],
                                     capture_output=True, text=True)
                self.assertEqual(out.returncode, 2, ran)

    def test_main_ran_flag(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            with open(os.path.join(d, "checks.txt"), "w", encoding="utf-8") as f:
                f.write("CHECK icon RECORD found\n")
            out = subprocess.run([sys.executable, os.path.join(HERE, "checks.py"), d,
                                  "--ran", f"{ACCESS},PhoneChecksUITests/test5_icon"],
                                 capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
            n = len(checks.EXPECTED_IDS) - 1
            self.assertEqual(out.stdout.splitlines()[-1], f"CHECKS pass 0 fail 0 record 1 skip 0 not-run {n}")

    def test_a_not_run_line_from_the_test_is_malformed(self):
        # Only checks.py writes NOT-RUN; a test line with it is not a status the tests use.
        final = {c.id: c for c in checks.assemble("CHECK icon NOT-RUN x\n", "", "")}
        self.assertEqual(final["icon"].status, "FAIL")


class UnranTests(unittest.TestCase):
    """A filtered run is test-failed when a selected entry has no passing test case (a skip, a rename, 0 tests)."""

    CASES = ("Test Case '-[ProtlyCIUITests.KeyboardShotsUITests testScenarios]' passed (115.105 seconds).\n"
             "Test Case '-[ProtlyCIUITests.PhoneChecksUITests test0_access]' passed (37.885 seconds).\n"
             "Test Case '-[ProtlyCIUITests.PhoneChecksUITests test0_probe]' skipped (0.166 seconds).\n"
             "Test Case '-[ProtlyCIUITests.PhoneChecksUITests test6_85net]' failed (725.760 seconds).\n")

    def test_passed_entries(self):
        self.assertEqual(shotsfilter.unran(["KeyboardShotsUITests", ACCESS], self.CASES), [])
        self.assertEqual(shotsfilter.unran(["PhoneChecksUITests"], self.CASES), [])

    def test_failed_skipped_and_missing_entries(self):
        entries = ["PhoneChecksUITests/test0_probe", "PhoneChecksUITests/test6_85net", "PhoneChecksUITests/test7_77"]
        self.assertEqual(shotsfilter.unran(entries, self.CASES), entries)
        self.assertEqual(shotsfilter.unran(["KeyboardShotsUITests"], ""), ["KeyboardShotsUITests"])

    def test_main(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "test-cases.txt")
            with open(path, "w", encoding="utf-8") as f:
                f.write(self.CASES)
            env = dict(os.environ, SHOTS_MESSAGE="x [shots:KeyboardShotsUITests,PhoneChecksUITests/test7_77]")
            out = subprocess.run([sys.executable, os.path.join(HERE, "shotsfilter.py"), "unran", path],
                                 capture_output=True, text=True, env=env)
            self.assertEqual((out.returncode, out.stdout.split()), (0, ["PhoneChecksUITests/test7_77"]))


class RunShotsBlockTests(unittest.TestCase):
    """run-shots.sh's filter block: -only-testing arguments, the FILTER note, the layout switch, a bad filter."""

    def run_block(self, message):
        import tempfile
        with open(os.path.join(HERE, "run-shots.sh"), encoding="utf-8") as f:
            src = f.read()
        block = src[src.index('filter=""\n'):]
        block = block[:block.index("# Newest iOS 26 runtime")]
        with tempfile.TemporaryDirectory() as work:
            script = (f'set -uo pipefail\nhere={HERE}; work={work}; status=measured\n'
                      'note() { echo "note: $1"; }\nfinish() { echo "finish $status"; exit 0; }\n'
                      f'{block}\nprintf "arg: %s\\n" ${{only_args[@]+"${{only_args[@]}}"}}\n'
                      'echo "layout=$layout"; echo "mem_wait=$mem_wait"\n')
            env = dict(os.environ, SHOTS_MESSAGE=message)
            return subprocess.run(["bash", "-c", script], capture_output=True, text=True, env=env, timeout=30).stdout

    def test_full_run(self):
        out = self.run_block("fix [shots]")
        self.assertNotIn("FILTER", out)
        self.assertNotIn("-only-testing", out)
        self.assertIn("layout=1", out)
        self.assertIn("mem_wait=== PhoneChecksUITests.test1", out)

    def test_phone_method(self):
        out = self.run_block("fix [shots:PhoneChecksUITests/test7_77]")
        self.assertIn("note: FILTER PhoneChecksUITests/test0_access PhoneChecksUITests/test7_77 (a debug run", out)
        self.assertIn("arg: -only-testing:ProtlyCIUITests/PhoneChecksUITests/test0_access\n"
                      "arg: -only-testing:ProtlyCIUITests/PhoneChecksUITests/test7_77\n", out)
        self.assertIn("layout=0", out)
        self.assertIn("mem_wait=== PhoneChecksUITests.test7_77", out)

    def test_layout_only(self):
        out = self.run_block("fix [shots:KeyboardShotsUITests]")
        self.assertIn("arg: -only-testing:ProtlyCIUITests/KeyboardShotsUITests\n", out)
        self.assertIn("layout=1", out)

    def test_bad_filter_finishes_before_the_build(self):
        out = self.run_block("fix [shots:PhoneChecksUITests/test8_85]")
        self.assertIn("note: bad [shots:...] filter: shotsfilter: no method 'test8_85'", out)
        self.assertIn("finish bad-filter", out)
        self.assertNotIn("layout=", out)


if __name__ == "__main__":
    unittest.main()
