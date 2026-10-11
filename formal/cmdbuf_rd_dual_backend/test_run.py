"""Runner contract tests. Fake reports/processes are NOT cmdbuf_rd formal evidence."""
from __future__ import annotations
import contextlib
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import xml.etree.ElementTree as ET

import run


def property_(label="P_OK", kind="assert", **extra):
    return dict(label=label, kind=kind, **extra)


def job_(name="prove", dependencies=(), properties=None, mode="prove"):
    return {"id": name, "mode": mode, "top": "test", "depends_on": list(dependencies),
            "sby": {"config": "jobs/" + name + "/sby/run.sby", "sources": ["jobs/" + name + "/sby/input.sv"]},
            "formalmc": {"tcl": "jobs/" + name + "/formalmc/run.tcl", "sources": ["jobs/" + name + "/formalmc/input.sv"]},
            "properties": properties or [property_()]}


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def package(self, jobs=None, checks=None):
        jobs = jobs or [job_()]
        manifest = {"schema_version": 1, "jobs": jobs, "checks": checks or [
            {"ck_id": "CK-" + job["id"], "kind": job["properties"][0]["kind"], "job_id": job["id"],
             "label": job["properties"][0]["label"], "supporting_ck_ids": []} for job in jobs], "files": {}}
        for job in jobs:
            for backend, key in (("sby", "config"), ("formalmc", "tcl")):
                for value in [job[backend][key], *job[backend]["sources"]]:
                    path = self.root / value
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("test input\n", encoding="utf-8")
                    manifest["files"][value] = run.sha256(path)
        path = self.root / "manifest.json"
        manifest["expected_counts"] = {"checks": len(manifest["checks"]),
                                       **{kind: sum(c["kind"] == kind for c in manifest["checks"]) for kind in run.KINDS}}
        run.save_json(path, manifest)
        return path, manifest

    def junit(self, status="PASS", cases=None, exit_code=0):
        work = self.root / "work"
        work.mkdir(exist_ok=True)
        (work / "status").write_text("%s %s 0.1\n" % (status, exit_code), encoding="utf-8")
        testsuites = ET.Element("testsuites")
        suite = ET.SubElement(testsuites, "testsuite")
        props = ET.SubElement(suite, "properties")
        ET.SubElement(props, "property", name="status", value=status)
        for case in cases if cases is not None else [{"id": "P_OK", "name": "top.P_OK", "type": "assert"}]:
            case = dict(case)
            child = case.pop("child", None)
            element = ET.SubElement(suite, "testcase", case)
            if child:
                ET.SubElement(element, child)
        (work / "result.xml").write_bytes(ET.tostring(testsuites))
        return work


class ManifestTests(Base):
    def test_valid_manifest_and_hashes(self):
        path, _ = self.package()
        manifest, jobs = run.load_manifest(path)
        self.assertEqual(list(jobs), ["prove"])
        self.assertEqual(len(manifest["checks"]), 1)

    def test_changed_input_rejected(self):
        path, manifest = self.package()
        (self.root / next(iter(manifest["files"]))).write_text("modified")
        with self.assertRaisesRegex(run.InputError, "SHA256 mismatch"):
            run.load_manifest(path)

    def test_traversal_and_windows_absolute_rejected(self):
        for value in ["../x", "a/../x", "/tmp/x", "C:/x", "a\\x", "a//x", "a/./x"]:
            with self.subTest(value=value), self.assertRaises(run.InputError):
                run.relative_path(self.root, value, False)

    def test_symlink_input_rejected(self):
        source = self.root / "source"
        source.write_text("hi")
        try:
            (self.root / "link").symlink_to(source)
        except OSError:
            self.skipTest("Host does not allow test symlinks")
        with self.assertRaisesRegex(run.InputError, "Symlinks"):
            run.relative_path(self.root, "link")

    def test_duplicate_job_rejected(self):
        path, manifest = self.package()
        manifest["jobs"].append(copy.deepcopy(manifest["jobs"][0]))
        run.save_json(path, manifest)
        with self.assertRaisesRegex(run.InputError, "duplicate job"):
            run.load_manifest(path)

    def test_dag_orders_suppliers_and_includes_transitive(self):
        jobs = {j["id"]: j for j in [job_("c", ["b"]), job_("a"), job_("b", ["a"])]}
        self.assertEqual(run.ordered_jobs(jobs, ["c"]), ["a", "b", "c"])

    def test_dag_cycle_rejected(self):
        jobs = {j["id"]: j for j in [job_("a", ["b"]), job_("b", ["a"])]}
        with self.assertRaisesRegex(run.InputError, "cycle"):
            run.ordered_jobs(jobs, ["a"])

    def test_unknown_job_rejected(self):
        with self.assertRaisesRegex(run.InputError, "Unknown job"):
            run.ordered_jobs({}, ["absent"])

    def test_cover_cannot_supply_safety(self):
        path, _ = self.package([job_("cover", mode="cover", properties=[property_("C", "cover")]), job_("prove", ["cover"])])
        with self.assertRaisesRegex(run.InputError, "safety job"):
            run.load_manifest(path)

    def test_missing_property_mapping_rejected(self):
        path, manifest = self.package()
        manifest["checks"][0]["label"] = "ABSENT"
        run.save_json(path, manifest)
        with self.assertRaisesRegex(run.InputError, "property mapping"):
            run.load_manifest(path)

    def test_unhashed_source_rejected(self):
        path, manifest = self.package()
        manifest["files"].pop(manifest["jobs"][0]["sby"]["sources"][0])
        run.save_json(path, manifest)
        with self.assertRaisesRegex(run.InputError, "no hash"):
            run.load_manifest(path)

    def test_copy_rejects_unmanifested_backend_file(self):
        _, manifest = self.package()
        job = manifest["jobs"][0]
        (self.root / "jobs/prove/sby/extra.sv").write_text("untracked")
        with self.assertRaisesRegex(run.InputError, "Unmanifested"):
            run.copy_job_inputs(self.root, manifest, job, "sby", self.root / "new")

    def test_expected_inventory_loss_rejected(self):
        path, manifest = self.package([job_("one"), job_("two")])
        manifest["checks"].pop()
        run.save_json(path, manifest)
        with self.assertRaisesRegex(run.InputError, "expected_counts"):
            run.load_manifest(path)

    def test_ck_review_dependency_need_not_order_independent_proofs(self):
        path, manifest = self.package([job_("one"), job_("two")])
        manifest["checks"][1]["supporting_ck_ids"] = ["CK-one"]
        run.save_json(path, manifest)
        run.load_manifest(path)
        jobs = {j["id"]: j for j in manifest["jobs"]}
        self.assertEqual(set(run.selected_job_closure(jobs, manifest["checks"], ["two"])), {"one", "two"})

    def test_ck_dependency_self_cycle_rejected(self):
        path, manifest = self.package()
        manifest["checks"][0]["supporting_ck_ids"] = ["CK-prove"]
        run.save_json(path, manifest)
        with self.assertRaisesRegex(run.InputError, "CK dependency cycle"):
            run.load_manifest(path)

    def test_ck_dependency_dag_valid(self):
        path, manifest = self.package([job_("one"), job_("two", ["one"])])
        manifest["checks"][1]["supporting_ck_ids"] = ["CK-one"]
        run.save_json(path, manifest)
        run.load_manifest(path)

    def test_ck_aggregation_does_not_invent_job_cycle(self):
        jobs = [job_("a", properties=[property_("A1"), property_("A2")]),
                job_("b", properties=[property_("B1"), property_("B2")])]
        checks = [{"ck_id": "A1", "kind": "assert", "job_id": "a", "label": "A1", "supporting_ck_ids": ["B2"]},
                  {"ck_id": "A2", "kind": "assert", "job_id": "a", "label": "A2", "supporting_ck_ids": []},
                  {"ck_id": "B1", "kind": "assert", "job_id": "b", "label": "B1", "supporting_ck_ids": ["A2"]},
                  {"ck_id": "B2", "kind": "assert", "job_id": "b", "label": "B2", "supporting_ck_ids": []}]
        path, manifest = self.package(jobs, checks)
        run.load_manifest(path)
        selected = run.selected_job_closure({j["id"]: j for j in jobs}, checks, ["a"])
        self.assertEqual(set(selected), {"a", "b"})


class SbyParserTests(Base):
    def test_actual_sby_uppercase_kind_with_witness_identity(self):
        prop = property_("dut._witness_.check_assert_inputs_rtl_cmdbuf_rd_sv_54_1513",
                         sby_label="check_assert_inputs_rtl_cmdbuf_rd_sv_54_1513")
        work = self.junit(cases=[{"id": "_witness_.check_assert_inputs_rtl_cmdbuf_rd_sv_54_1513",
                                 "name": "Property ASSERT in cmdbuf_rd_formal/dut at inputs/rtl/cmdbuf_rd.sv:54.9-55.65",
                                 "type": "ASSERT", "location": "inputs/rtl/cmdbuf_rd.sv:54.9-55.65"},
                                {"id": "unused_cover", "type": "COVER", "child": "skipped"}])
        props, status, errors = run.parse_sby(work, job_(properties=[prop]), 0)
        self.assertEqual((status, props[0]["status"], errors), ("passed", "proven", []))

    def test_typed_unbounded_proof(self):
        props, status, errors = run.parse_sby(self.junit(), job_(), 0)
        self.assertEqual((status, props[0]["status"], errors), ("passed", "proven", []))

    def test_no_typed_inventory_no_aggregate_pass(self):
        props, status, _ = run.parse_sby(self.junit(cases=[{"name": "aggregate"}]), job_(), 0)
        self.assertEqual(status, "error")
        self.assertNotIn(props[0]["status"], run.SUCCESS)

    def test_exit_conflict(self):
        _, status, _ = run.parse_sby(self.junit(), job_(), 1)
        self.assertEqual(status, "error")

    def test_unknown_failed_induction_not_dut_failure(self):
        work = self.junit("UNKNOWN", [{"id": "P_OK", "type": "assert", "child": "failure"}], exit_code=4)
        props, status, _ = run.parse_sby(work, job_(), 4)
        self.assertEqual((props[0]["status"], status), ("inconclusive", "inconclusive"))

    def test_counterexample_falsified(self):
        work = self.junit("FAIL", [{"id": "P_OK", "type": "assert", "child": "failure"}], exit_code=2)
        props, status, _ = run.parse_sby(work, job_(), 2)
        self.assertEqual((props[0]["status"], status), ("falsified", "failed"))

    def test_cover_witness(self):
        job = job_(properties=[property_("C_OK", "cover")], mode="cover")
        work = self.junit(cases=[{"id": "C_OK", "type": "cover"}])
        props, status, _ = run.parse_sby(work, job, 0)
        self.assertEqual((props[0]["status"], status), ("covered", "passed"))

    def test_missing_property_blocks(self):
        props, status, _ = run.parse_sby(self.junit(cases=[{"id": "DIFFERENT", "type": "assert"}]), job_(), 0)
        self.assertEqual(status, "error")
        self.assertNotIn(props[0]["status"], run.SUCCESS)

    def test_alias_inventories_use_sby_label(self):
        job = job_(properties=[property_("PORTABLE_SAFE", sby_label="P_OK")])
        props, status, _ = run.parse_sby(self.junit(), job, 0)
        self.assertEqual((props[0]["label"], status), ("PORTABLE_SAFE", "passed"))

    def test_ambiguous_hierarchy_not_selected(self):
        work = self.junit(cases=[{"id": "a.P_OK", "type": "assert"}, {"id": "b.P_OK", "type": "assert"}])
        props, status, _ = run.parse_sby(work, job_(), 0)
        self.assertEqual(status, "error")
        self.assertNotIn(props[0]["status"], run.SUCCESS)

    def test_xml_entity_rejected(self):
        work = self.junit()
        (work / "result.xml").write_text('<!DOCTYPE x [<!ENTITY e SYSTEM "private">]><x/>')
        _, status, errors = run.parse_sby(work, job_(), 0)
        self.assertEqual(status, "error")
        self.assertIn("forbidden", errors[0])

    def test_status_junit_disagreement(self):
        work = self.junit()
        (work / "status").write_text("UNKNOWN 0 0.1")
        _, status, errors = run.parse_sby(work, job_(), 0)
        self.assertEqual(status, "error")
        self.assertIn("disagree", errors[0])

    def test_pass_with_failure_rejected(self):
        work = self.junit(cases=[{"id": "P_OK", "type": "assert", "child": "failure"}])
        _, status, _ = run.parse_sby(work, job_(), 0)
        self.assertEqual(status, "error")

    def test_extra_compiled_property_cannot_be_ignored(self):
        work = self.junit(cases=[{"id": "P_OK", "type": "assert"}, {"id": "P_OTHER", "type": "assert"}])
        _, status, _ = run.parse_sby(work, job_(), 0)
        self.assertEqual(status, "error")

    def test_extra_failed_property_conflicts_with_pass(self):
        work = self.junit(cases=[{"id": "P_OK", "type": "assert"}, {"id": "P_OTHER", "type": "assert", "child": "failure"}])
        _, status, errors = run.parse_sby(work, job_(), 0)
        self.assertEqual(status, "error")
        self.assertIn("contradicts", errors[0])


class FormalMcParserTests(unittest.TestCase):
    def parse(self, text, properties=None, mode="prove", exit_code=0):
        return run.parse_formalmc(text, job_(properties=properties, mode=mode), exit_code)

    def test_known_info_format(self):
        props, status, _ = self.parse("Info-P016: property top.P_OK is proven")
        self.assertEqual((props[0]["status"], status), ("proven", "passed"))

    def test_table_format(self):
        props, status, _ = self.parse("  1 top.P_OK : proven")
        self.assertEqual((props[0]["status"], status), ("proven", "passed"))

    def test_no_summary_or_exit_zero_inference(self):
        for text in ["all passed", "PASS", "total proven 1", "fanin coverage 100%"]:
            with self.subTest(text=text):
                props, status, _ = self.parse(text)
                self.assertEqual((props[0]["status"], status), ("missing", "inconclusive"))

    def test_cover_requires_explicit_witness_status(self):
        props, status, _ = self.parse("C_OK: proven", [property_("C_OK", "cover")], "cover")
        self.assertEqual((props[0]["status"], status), ("inconclusive", "inconclusive"))
        props, status, _ = self.parse("C_OK: covered", [property_("C_OK", "cover")], "cover")
        self.assertEqual((props[0]["status"], status), ("covered", "passed"))

    def test_no_falsified_overwrite_by_later_pass(self):
        props, status, _ = self.parse("P_OK: falsified\nP_OK: proven")
        self.assertEqual((props[0]["status"], status), ("conflict", "inconclusive"))

    def test_progress_may_precede_result(self):
        props, status, _ = self.parse("P_OK: unknown\nP_OK: proven")
        self.assertEqual((props[0]["status"], status), ("proven", "passed"))

    def test_bad_exit_blocks(self):
        _, status, _ = self.parse("P_OK: proven", exit_code=1)
        self.assertEqual(status, "error")

    def test_license_error_blocks(self):
        _, status, _ = self.parse("P_OK: proven\nlicense checkout failed")
        self.assertEqual(status, "error")

    def test_vacuous_never_proven(self):
        props, status, _ = self.parse("P_OK: trivially_true")
        self.assertEqual((props[0]["status"], status), ("vacuous", "inconclusive"))

    def test_ambiguous_hierarchical_leaf_blocks(self):
        props, status, _ = self.parse("a.P_OK: proven\nb.P_OK: proven")
        self.assertEqual((props[0]["status"], status), ("ambiguous", "inconclusive"))

    def test_alias_binding(self):
        props, status, _ = self.parse("P_OK: proven", [property_("portable", formalmc_label="P_OK")])
        self.assertEqual((props[0]["label"], status), ("portable", "passed"))

    def test_environment_constraint_not_counted_proved(self):
        props, status, _ = self.parse("P_OK: proven", [property_("P_OK"), property_("A_RESET", "assume")])
        self.assertEqual([p["status"] for p in props], ["proven", "assumption"])
        self.assertEqual(status, "passed")

    def test_unmapped_failure_blocks_expected_pass(self):
        props, status, errors = self.parse("P_OK: proven\nINTERNAL_ASSERT: falsified")
        self.assertEqual(status, "failed")
        self.assertEqual(props[-1]["kind"], "unmapped")
        self.assertEqual(props[-1]["status"], "falsified")
        self.assertIn("INTERNAL_ASSERT", errors[0])

    def test_unmapped_uncovered_blocks_expected_pass(self):
        props, status, errors = self.parse("P_OK: proven\nUNEXPECTED_COVER: uncovered")
        self.assertEqual(status, "inconclusive")
        self.assertEqual(props[-1]["status"], "uncovered")
        self.assertTrue(errors)

    def test_unmapped_conflicting_results_block_expected_pass(self):
        props, status, errors = self.parse("P_OK: proven\nEXTRA: proven\nEXTRA: covered")
        self.assertEqual(status, "inconclusive")
        self.assertEqual(props[-1]["status"], "conflict")
        self.assertTrue(errors)

    def test_unmapped_failure_cannot_be_erased_by_pass(self):
        props, status, errors = self.parse("P_OK: proven\nEXTRA: falsified\nEXTRA: proven")
        self.assertEqual(status, "failed")
        self.assertEqual(props[-1]["status"], "conflict")
        self.assertTrue(errors)


class ExecutionTests(Base):
    def test_sby_timeout_override_changes_only_budget(self):
        path = self.root / "run.sby"
        before = "[options]\nmode prove\ndepth 20\ntimeout 180\n[engines]\nsmtbmc yices\n"
        path.write_text(before)
        record = run.override_sby_timeout(path, 900)
        self.assertEqual(path.read_text(), before.replace("timeout 180", "timeout 900"))
        self.assertNotEqual(record["original_sha256"], record["effective_sha256"])
        self.assertEqual(record["seconds"], 900)

    def test_sby_timeout_override_rejects_duplicate_options(self):
        path = self.root / "run.sby"
        path.write_text("[options]\ntimeout 1\ntimeout 2\n")
        with self.assertRaisesRegex(run.InputError, "Duplicate"):
            run.override_sby_timeout(path, 900)

    def test_actual_subprocess_exit_and_log(self):
        log = self.root / "console.log"
        result = run.execute([sys.executable, "-c", "print('runner execution test')"], self.root, log, 10, dict(os.environ))
        self.assertEqual((result["execution_status"], result["returncode"]), ("completed", 0))
        self.assertIn("runner execution test", log.read_text())

    def test_actual_subprocess_timeout(self):
        result = run.execute([sys.executable, "-c", "import time; time.sleep(30)"], self.root,
                             self.root / "timeout.log", 0.1, dict(os.environ))
        self.assertEqual(result["execution_status"], "timeout")

    def test_list_does_not_need_tool(self):
        path, _ = self.package()
        with contextlib.redirect_stdout(io.StringIO()) as capture:
            self.assertEqual(run.main(["--manifest", str(path), "--list"]), 0)
        self.assertIn("prove", capture.getvalue())

    def test_missing_tool_is_actionable(self):
        path, _ = self.package()
        with contextlib.redirect_stderr(io.StringIO()) as capture:
            self.assertEqual(run.main(["--manifest", str(path), "--tool", "no_such_eda_binary_999"]), 2)
        self.assertIn("Tool not found", capture.getvalue())

    def test_preflight_does_not_run_jobs(self):
        path, _ = self.package()
        with mock.patch.object(run, "configure", return_value=(sys.executable, 1, dict(os.environ))), \
             mock.patch.object(run, "preflight_tool", return_value={"returncode": 0}), \
             mock.patch.object(run, "run_job") as job, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run.main(["--manifest", str(path), "--preflight"]), 0)
            job.assert_not_called()
        result = json.loads(next((self.root / "results").glob("*/result.json")).read_text())
        self.assertEqual(result["status"], "preflight_passed")
        self.assertEqual(result["checks"][0]["status"], "not_run")

    def test_dependency_failure_blocks_consumer(self):
        path, _ = self.package([job_("supplier"), job_("consumer", ["supplier"])])
        def fake_job(root, manifest, job, *args):
            return {"id": job["id"], "status": "inconclusive", "properties": [{"label": "P_OK", "kind": "assert", "status": "inconclusive"}]}
        with mock.patch.object(run, "configure", return_value=(sys.executable, 1, dict(os.environ))), \
             mock.patch.object(run, "preflight_tool", return_value={"returncode": 0}), \
             mock.patch.object(run, "run_job", side_effect=fake_job) as execute_job, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run.main(["--manifest", str(path), "--job", "consumer"]), 1)
            self.assertEqual(execute_job.call_count, 1)
        result = json.loads(next((self.root / "results").glob("*/result.json")).read_text())
        self.assertEqual([j["status"] for j in result["jobs"]], ["inconclusive", "blocked"])
        self.assertFalse(result["full_suite_passed"])

    def test_two_runs_never_reuse_output(self):
        path, _ = self.package()
        with mock.patch.object(run, "configure", return_value=(sys.executable, 1, dict(os.environ))), \
             mock.patch.object(run, "preflight_tool", return_value={"returncode": 0}), contextlib.redirect_stdout(io.StringIO()):
            for _ in range(2):
                self.assertEqual(run.main(["--manifest", str(path), "--preflight"]), 0)
        self.assertEqual(len(list((self.root / "results").iterdir())), 2)

    def test_formalmc_capability_failure_stops_dut(self):
        path, _ = self.package()
        with mock.patch.object(run, "configure", return_value=(sys.executable, 1, dict(os.environ))), \
             mock.patch.object(run, "preflight_tool", return_value={"returncode": 0}), \
             mock.patch.object(run, "formal_capabilities", return_value=[{"accepted": False}]), \
             mock.patch.object(run, "run_job") as job, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run.main(["--manifest", str(path), "--backend", "formalmc"]), 1)
            job.assert_not_called()

    def test_all_check_rows_retained_for_partial_runs(self):
        path, manifest = self.package([job_("one"), job_("two")])
        rows = run.check_results(manifest, {"one": {"status": "passed", "properties": [{"label": "P_OK", "status": "proven"}]}})
        self.assertEqual(len(rows), 2)
        self.assertEqual([row["status"] for row in rows], ["proven", "not_run"])

    def test_supporting_ck_dependency_propagates(self):
        _, manifest = self.package([job_("supplier"), job_("consumer")])
        manifest["checks"][1]["supporting_ck_ids"] = ["CK-supplier"]
        rows = run.check_results(manifest, {"consumer": {"status": "passed", "properties": [{"label": "P_OK", "status": "proven"}]}})
        self.assertEqual(rows[1]["status"], "blocked")

    def mock_capability_execution(self, override=None):
        def fake(argv, cwd, logfile, timeout, environment):
            case = next(c for c in run.CAPABILITY_CASES if c["id"] == Path(cwd).name)
            lines = []
            for prop in case["properties"]:
                state = "falsified" if case["expected_status"] == "failed" else ("covered" if prop["kind"] == "cover" else "proven")
                if override:
                    state = override(case, prop, state)
                lines.append("Info-P016: property %s is %s" % (prop["label"], state))
            Path(logfile).write_text("\n".join(lines), encoding="utf-8")
            return {"execution_status": "completed", "returncode": 0}
        return fake

    def test_capability_positive_negative_cover_classified(self):
        with mock.patch.object(run, "execute", side_effect=self.mock_capability_execution()):
            results = run.formal_capabilities(self.root, "FAKE_TOOL_NOT_A_FORMAL_RUN", 10, {})
        self.assertEqual(len(results), 6)
        self.assertTrue(all(r["accepted"] for r in results))
        self.assertEqual(sum(r["status"] == "failed" for r in results), 2)
        for path in (self.root / "capabilities").glob("*/formal.tcl"):
            self.assertTrue(path.read_text().endswith("show_prop -summary\nexit\n"))

    def test_capability_negative_must_actually_fail(self):
        with mock.patch.object(run, "execute", side_effect=self.mock_capability_execution(
                lambda case, prop, state: "proven" if case["expected_status"] == "failed" else state)):
            results = run.formal_capabilities(self.root, "FAKE_TOOL_NOT_A_FORMAL_RUN", 10, {})
        self.assertFalse(all(r["accepted"] for r in results))
        self.assertEqual(sum(not r["accepted"] for r in results), 2)

    def test_capability_cover_generic_pass_not_witness(self):
        with mock.patch.object(run, "execute", side_effect=self.mock_capability_execution(
                lambda case, prop, state: "proven" if prop["kind"] == "cover" else state)):
            results = run.formal_capabilities(self.root, "FAKE_TOOL_NOT_A_FORMAL_RUN", 10, {})
        self.assertFalse(all(r["accepted"] for r in results))
        self.assertEqual(sum(not r["accepted"] for r in results), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
