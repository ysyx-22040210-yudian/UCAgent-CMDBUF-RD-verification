"""Test fixture copied beside the generated runner; not real FormalMC evidence."""
import re
import unittest
import run


class FormalMc2024Tests(unittest.TestCase):
    """Keep typed Cover compatibility separate from generic success inference."""

    def parse(self, text, kind="cover", label="C_CHECK", exit_code=0):
        """Use an explicit compiled-property inventory for each parser scenario."""
        job = {"mode": "cover" if kind == "cover" else "prove",
               "properties": [{"label": label, "kind": kind}]}
        return run.parse_formalmc(text, job, exit_code)

    def test_known_summary_cover_pass(self):
        """Summary Pass is a witness only after binding to a typed Cover."""
        properties, status, _ = self.parse("1 checker_inst.C_CHECK : Pass")
        self.assertEqual((properties[0]["status"], status), ("covered", "passed"))

    def test_known_info_cover_true(self):
        """The recognized FormalMC TRUE diagnostic has typed Cover semantics."""
        properties, status, _ = self.parse("Info-P016: property checker_inst.C_CHECK is TRUE")
        self.assertEqual((properties[0]["status"], status), ("covered", "passed"))

    def test_known_cover_false_is_uncovered(self):
        """Failed Cover reachability is not an assertion counterexample."""
        properties, status, _ = self.parse("Info-P016: property checker_inst.C_CHECK is FALSE")
        self.assertEqual((properties[0]["status"], status), ("uncovered", "inconclusive"))

    def test_generic_pass_is_not_a_witness(self):
        """Generic status text cannot establish a Cover witness."""
        self.assertEqual(self.parse("C_CHECK: Pass")[1], "inconclusive")

    def test_proven_is_not_a_witness(self):
        """An assertion-style proof word must not become a reachable witness."""
        self.assertEqual(self.parse("Info-P016: property C_CHECK is PROVEN")[1], "inconclusive")

    def test_name_does_not_override_assert_type(self):
        """A Cover-like name cannot replace the manifest's assertion kind."""
        properties, status, _ = self.parse("1 top.C_CHECK : Pass", kind="assert")
        self.assertEqual((properties[0]["status"], status), ("proven", "passed"))

    def test_missing_and_ambiguous_results_stay_unconfirmed(self):
        """Known formatting does not bypass complete unique property binding."""
        for text in ["1 top.C_OTHER : Pass", "1 a.C_CHECK : Pass\n2 b.C_CHECK : Pass"]:
            self.assertEqual(self.parse(text)[1], "inconclusive")

    def test_conflicting_cover_results_are_rejected(self):
        """A later PASS must not erase a Cover failure."""
        self.assertEqual(self.parse("1 top.C_CHECK : Pass\n2 top.C_CHECK : Fail")[1], "inconclusive")

    def test_license_error_blocks_success(self):
        """Recognized Cover results do not bypass infrastructure failures."""
        self.assertEqual(self.parse("1 top.C_CHECK : Pass\nError-LIC: license checkout failed", exit_code=1)[1], "error")

    def test_all_capability_initializers_are_zero(self):
        """No positive capability case can use unsupported nonzero initialization."""
        for case in run.CAPABILITY_CASES:
            for value in re.findall(r"\breg\b[^;]*?=\s*([^;]*);", case["body"]):
                self.assertRegex(value, r"^\d+'[bhdo]0+$")


if __name__ == "__main__":
    unittest.main(verbosity=2)
