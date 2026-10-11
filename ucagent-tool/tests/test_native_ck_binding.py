"""Reject fabricated, stale, ambiguous and misclassified native CK proof evidence."""

import hashlib
import json
import sqlite3
from pathlib import Path

import pytest

from ucagent.eda.manifest import collect_artifacts, sha256_file, write_manifest
from ucagent.eda.native_binding import NativeEvidenceResolver, strip_cmdbuf_monitor, unique_result_rows, validate_native_review, apply_native_dependencies
from ucagent.eda.sby_guided import render_environment
from ucagent.lang.zh.skills.formal.lib.formal_tools import load_records, save_records
from ucagent.lang.zh.skills.formal.lib.models import CheckPoint, FormalRecords
from ucagent.platform.project import SbyOptions
from test_sby_guided_workflow import counter


@pytest.fixture
def native(tmp_path):
    """Build a private signed fixture using the same persisted run/Job/attempt contract."""
    state, project, session = (tmp_path / name for name in ("state", "project", "session"))
    for folder in (state, project, session):
        folder.mkdir()
    key = b"unit-test-only-key-never-production" * 2
    (state / "manifest.key").write_bytes(key)
    (state / "manifest.key").chmod(0o600)
    (project / "dut.sv").write_text("module dut; endmodule\n")
    (session / "dut.sv").write_bytes((project / "dut.sv").read_bytes())
    (project / "harness.sv").write_text("module harness; A_DATA: assert property (data == expected); endmodule\n")
    proof = project / "run"
    proof.mkdir()
    (proof / "log.txt").write_text("Unit fixture; no actual proof is claimed.\n")
    prop = {"name": "A_DATA", "status": "proven", "counterexample_path": None,
            "details": {"property_id": "A_DATA", "location": "inputs/harness.sv:1.1-1.80", "kind": "assert", "mode": "prove"}}
    payload = {"run_id": "run-1.formal", "execution_status": "completed", "metadata": {"adapter": "sby", "mode": "prove", "engine": "sby/smtbmc/z3"},
               "input_hashes": {name: sha256_file(project / name) for name in ("dut.sv", "harness.sv")},
               "artifacts": [a.model_dump(mode="json") for a in collect_artifacts("run-1.formal", proof, [Path("log.txt")])], "properties": [prop]}
    manifest = proof / "manifest.json"
    write_manifest(manifest, payload, key)
    with sqlite3.connect(state / "platform.db") as db:
        db.executescript("CREATE TABLE projects(project_id TEXT,source_root TEXT); CREATE TABLE runs(run_id TEXT,project_id TEXT,adapter TEXT,execution_status TEXT); CREATE TABLE jobs(job_id TEXT,run_id TEXT,execution_status TEXT); CREATE TABLE attempts(job_id TEXT,number INTEGER,execution_status TEXT,manifest_path TEXT);")
        db.execute("INSERT INTO projects VALUES (?,?)", ("project-1", str(project)))
        db.execute("INSERT INTO runs VALUES (?,?,?,?)", ("run-1", "project-1", "sby", "completed"))
        db.execute("INSERT INTO jobs VALUES (?,?,?)", ("job-1", "run-1", "completed"))
        db.execute("INSERT INTO attempts VALUES (?,?,?,?)", ("job-1", 1, "completed", str(manifest)))
    binding = {"run_id": "run-1", "property_id": "A_DATA", "source": "harness.sv", "source_sha256": sha256_file(project / "harness.sv"),
               "mode": "prove", "expected_kind": "assert", "input_map": {"dut.sv": "dut.sv"}, "scope": "end_to_end"}
    item = {"fg": "FG-DATA", "fc": "FC-DATA", "ck": "CK-DATA", "kind": "assert", "label": "A_CK_DATA", "native_binding": binding}
    return state, project, session, manifest, payload, key, item


def test_requirements_and_native_metadata_roundtrip(counter):
    """The ordinary checker save must never discard requirement or native contract fields."""
    paths, records = counter
    ck = records.spec.function_groups[1].functions[0].check_points[0]
    ck.requirements = ["R02", "R14"]
    ck.formal_obligation = "Every accepted command returns the original payload in source order."
    ck.fault_ids = ["F-order"]
    ck.existing_evidence_keys = ["prior-data-scope"]
    ck.spec_basis = "The accepted interface contract requires stable transaction identity."
    ck.evidence_gap = "The original local property does not establish end-to-end conservation."
    records.spec.function_groups[1].functions[0].name = "Counter transition"
    save_records(paths.records_yaml, records)
    restored = load_records(paths.records_yaml).spec.function_groups[1].functions[0].check_points[0]
    assert restored.requirements == ["R02", "R14"]
    assert restored.formal_obligation == ck.formal_obligation and restored.fault_ids == ["F-order"]
    assert restored.existing_evidence_keys == ck.existing_evidence_keys and restored.spec_basis == ck.spec_basis
    assert restored.evidence_gap == ck.evidence_gap
    assert load_records(paths.records_yaml).spec.function_groups[1].functions[0].name == "Counter transition"
    with pytest.raises(ValueError):
        CheckPoint(id="CK-X", style="Seq", description="x", requirementz=["R02"])


def test_registered_signed_property_and_review(native):
    """Accept exactly the signed property and require review bound to its manifest bytes."""
    state, _, session, manifest, _, _, item = native
    row = NativeEvidenceResolver(state).resolve(item, session, ["dut.sv"])
    assert row["status"] == "proven" and row["native_run_id"] == "run-1"
    assert row["manifest_sha256"] == sha256_file(manifest)
    review = {"native_runs": {"run-1": {"manifest_sha256": row["manifest_sha256"], "assumptions": "Only specification-authorized initial reset is constrained.", "scope": "The selected end-to-end payload property is checked, not all DUT behavior."}}}
    validate_native_review(review, [row])
    review["native_runs"]["run-1"]["manifest_sha256"] = "0" * 64
    with pytest.raises(ValueError, match="current verified manifest"):
        validate_native_review(review, [row])


@pytest.mark.parametrize("change", ["forged", "source", "artifact", "mode", "kind", "missing", "ambiguous", "wrong_run", "session_source", "unmapped", "disabled", "bounded_proven", "unknown_run"])
def test_native_invalid_evidence_fails_closed(native, change):
    """Neither authored bindings nor edited files can substitute for current signed execution."""
    state, project, session, manifest, payload, key, item = native
    if change == "forged":
        content = json.loads(manifest.read_text()); content["properties"][0]["status"] = "falsified"; manifest.write_text(json.dumps(content))
    elif change == "source":
        (project / "harness.sv").write_text("changed source")
    elif change == "artifact":
        (project / "run/log.txt").write_text("changed artifact")
    elif change == "session_source":
        (session / "dut.sv").write_text("different DUT")
    elif change == "unmapped":
        (session / "other.sv").write_text("new DUT source")
    elif change == "unknown_run":
        item["native_binding"]["run_id"] = "absent"
    else:
        if change == "mode": item["native_binding"]["mode"] = "bmc"
        elif change == "kind": item["native_binding"]["expected_kind"] = "cover"
        elif change == "missing": item["native_binding"]["property_id"] = "absent"
        elif change == "ambiguous": payload["properties"].append(payload["properties"][0].copy())
        elif change == "wrong_run": payload["run_id"] = "unrelated.formal"
        elif change == "disabled": payload["properties"][0]["status"] = "disabled"
        elif change == "bounded_proven":
            payload["metadata"]["mode"] = "bmc"; item["native_binding"]["mode"] = "bmc"
        write_manifest(manifest, payload, key)
    with pytest.raises(ValueError):
        NativeEvidenceResolver(state).resolve(item, session, ["dut.sv", "other.sv"] if change == "unmapped" else ["dut.sv"])


def test_native_bmc_remains_inconclusive(native):
    """A successful bounded run remains unresolved when consumed by the full workflow."""
    state, _, session, manifest, payload, key, item = native
    payload["metadata"]["mode"] = item["native_binding"]["mode"] = "bmc"
    payload["properties"][0]["status"] = "inconclusive"
    payload["properties"][0]["details"]["bounded_depth"] = 30
    write_manifest(manifest, payload, key)
    row = NativeEvidenceResolver(state).resolve(item, session, ["dut.sv"])
    assert row["status"] == "inconclusive" and row["bounded_depth"] == 30


def test_fixed_monitor_transform_checks_original_bytes(native):
    """Whole signed instrumented inputs and byte-identical underlying DUT are both mandatory."""
    state, project, session, manifest, payload, key, item = native
    original = (project / "dut.sv").read_bytes()
    block = b"// BEGIN CMDBUF CLOSURE FORMAL MONITOR\nwire observe;\n// END CMDBUF CLOSURE FORMAL MONITOR\n"
    (project / "dut.sv").write_bytes(block + original + block)
    payload["input_hashes"]["dut.sv"] = sha256_file(project / "dut.sv")
    write_manifest(manifest, payload, key)
    item["native_binding"]["input_map"]["dut.sv"] = {"session_source": "dut.sv", "transform": "strip_cmdbuf_monitor"}
    row = NativeEvidenceResolver(state).resolve(item, session, ["dut.sv"])
    assert row["transformed_inputs"][0]["stripped_sha256"] == hashlib.sha256(original).hexdigest()
    (session / "dut.sv").write_bytes(original + b"\n")
    with pytest.raises(ValueError, match="does not match"):
        NativeEvidenceResolver(state).resolve(item, session, ["dut.sv"])


@pytest.mark.parametrize("data", [b"no markers", b"// BEGIN CMDBUF NATIVE FORMAL MONITOR\n", b"// END CMDBUF CLOSURE FORMAL MONITOR\n", b"// BEGIN CMDBUF NATIVE FORMAL MONITOR\n// END CMDBUF CLOSURE FORMAL MONITOR\n", b"// BEGIN CMDBUF NATIVE FORMAL MONITOR\n// BEGIN CMDBUF NATIVE FORMAL MONITOR\n"])
def test_invalid_marker_layout_rejected(data):
    """An incomplete, nested or mismatched transform cannot attest DUT identity."""
    with pytest.raises(ValueError):
        strip_cmdbuf_monitor(data)


def test_native_generation_and_alias_dedup(counter, native):
    """A native CK is a real bound obligation, never a generated constant assertion."""
    paths, records = counter
    ck = CheckPoint(id="CK-NATIVE", style="Seq", description="Payload conservation", requirements=["R02"], formal_obligation="Every accepted payload survives to its response.", verification_route="native", native_binding=native[-1]["native_binding"])
    points = records.spec.function_groups[1].functions[0].check_points
    points.append(ck)
    generated = render_environment(paths, records)
    assert "A_CK_NATIVE" not in Path(paths.checker).read_text()
    assert len([p for p in generated["properties"] if p.get("route") == "native"]) == 1
    alias = ck.model_copy(deep=True); alias.id = "CK-ALIAS"
    points.append(alias)
    with pytest.raises(ValueError, match="duplicate native"):
        render_environment(paths, records)
    alias.native_binding.alias_of = ck.id
    alias.native_binding.alias_justification = "The single conjunctive assertion jointly checks both checkpoint fields."
    generated = render_environment(paths, records)
    assert len(unique_result_rows(generated["properties"])) == len(generated["properties"]) - 1
    ck.native_binding = None
    with pytest.raises(ValueError, match="require native_binding"):
        render_environment(paths, records)


@pytest.mark.parametrize("engine,mode", [("abc pdr", "prove"), ("smtbmc z3", "cover"), ("smtbmc yices", "bmc")])
def test_solver_engine_is_explicit_signed_input(tmp_path, engine, mode):
    """Accepted engine selections change both the exact control input and manifest metadata."""
    from ucagent.eda.adapters.sby import SbyAdapter
    (tmp_path / "dut.sv").write_text("module dut; endmodule")
    options = SbyOptions(mode=mode, engine=engine)
    adapter = SbyAdapter()
    plan = adapter.prepare(workspace=tmp_path, top="dut", sources=[Path("dut.sv")], **options.model_dump())
    assert "[engines]\n" + engine + "\n" in plan.content
    (tmp_path / "run.sby").write_text(plan.content, newline="\n")
    request = adapter.build_formal_request(workspace=tmp_path, output_dir=Path("run"), config_path=Path("run.sby"), plan=plan, mode=mode, depth=40, timeout_seconds=120, run_id="test")
    assert request.metadata["engine"] == "sby/" + engine.replace(" ", "/")
    assert request.prepared_input_hashes["run.sby"] == sha256_file(tmp_path / "run.sby")


@pytest.mark.parametrize("engine,mode", [("abc pdr", "cover"), ("abc pdr", "bmc"), ("smtbmc z3; shell", "prove")])
def test_invalid_solver_modes_rejected(engine, mode):
    """Unsupported modes and arbitrary engine text are rejected before tool execution."""
    with pytest.raises(ValueError):
        SbyOptions(engine=engine, mode=mode)


def test_supporting_proofs_cannot_be_assumed_or_circular():
    """An unresolved support stays unresolved, and circular or missing support fails closed."""
    support = {"ck": "CK-SUPPORT", "kind": "assert", "status": "inconclusive"}
    end = {"ck": "CK-END", "kind": "assert", "status": "proven", "native_binding": {"supporting_ck_ids": ["CK-SUPPORT"]}}
    apply_native_dependencies([support, end])
    assert end["status"] == "inconclusive" and end["native_property_status"] == "proven"
    support["native_binding"] = {"supporting_ck_ids": ["CK-END"]}
    with pytest.raises(ValueError, match="cycle"):
        apply_native_dependencies([support, end])
    with pytest.raises(ValueError, match="existing safety"):
        apply_native_dependencies([end])


@pytest.mark.parametrize("status", ["inconclusive", "falsified", "disabled", "bounded_pass"])
def test_native_cover_requires_proven_support_and_preserves_witness(status):
    """A reachable witness cannot close a cover relying on an unproved safety model."""
    support = {"ck": "CK-SUPPORT", "kind": "assert", "status": status}
    cover = {"ck": "CK-COVER", "kind": "cover", "status": "covered", "native_binding": {"supporting_ck_ids": ["CK-SUPPORT"]}}
    apply_native_dependencies([cover, support])
    assert cover["status"] == "inconclusive"
    assert cover["native_property_status"] == "covered"
    assert cover["dependency_status"] == "supporting_checkpoints_not_proven"
    apply_native_dependencies([cover, support])
    assert cover["native_property_status"] == "covered"


@pytest.mark.parametrize("supplier_kind", [None, "cover", "assume", "guard_witness"])
def test_native_cover_rejects_missing_or_non_safety_support(supplier_kind):
    """Only an existing safety checkpoint may supply a native cover's model premise."""
    cover = {"ck": "CK-COVER", "kind": "cover", "status": "covered", "native_binding": {"supporting_ck_ids": ["CK-SUPPORT"]}}
    rows = [cover]
    if supplier_kind is not None:
        rows.append({"ck": "CK-SUPPORT", "kind": supplier_kind, "status": "covered"})
    with pytest.raises(ValueError, match="existing safety"):
        apply_native_dependencies(rows)


@pytest.mark.parametrize("leaf_status,expected", [("proven", "covered"), ("inconclusive", "inconclusive")])
def test_native_cover_checks_transitive_safety_dependencies(leaf_status, expected):
    """The complete safety DAG must close, independent of report row order."""
    leaf = {"ck": "CK-LEAF", "kind": "assert", "status": leaf_status}
    support = {"ck": "CK-SUPPORT", "kind": "assert", "status": "proven", "native_binding": {"supporting_ck_ids": ["CK-LEAF"]}}
    cover = {"ck": "CK-COVER", "kind": "cover", "status": "covered", "native_binding": {"supporting_ck_ids": ["CK-SUPPORT"]}}
    apply_native_dependencies([cover, support, leaf])
    assert cover["status"] == expected
    if expected == "covered":
        assert "native_property_status" not in cover
    else:
        assert cover["native_property_status"] == "covered"


def test_native_cover_unreached_status_is_not_upgraded():
    """A proved supplier does not turn an inconclusive cover into a reached witness."""
    support = {"ck": "CK-SUPPORT", "kind": "assert", "status": "proven"}
    cover = {"ck": "CK-COVER", "kind": "cover", "status": "inconclusive", "native_binding": {"supporting_ck_ids": ["CK-SUPPORT"]}}
    apply_native_dependencies([cover, support])
    assert cover["status"] == "inconclusive"
    assert "native_property_status" not in cover
