"""Exercise GUI orchestration with explicitly synthetic sealed runner fixtures.

These tests do not run FormalMC or establish any RTL proof result.
"""

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import time

from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
import psutil
import pytest


_MODULE = Path(__file__).resolve().parents[1] / "ucagent/server/portable_formal.py"
_SPEC = importlib.util.spec_from_file_location("portable_formal_under_test", _MODULE)
service = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(service)


_FAKE = '''"""Synthetic test runner; it produces test data, never RTL proof evidence."""
import argparse, hashlib, json, os, pathlib, subprocess, sys, time
p = argparse.ArgumentParser()
p.add_argument('--backend'); p.add_argument('--output'); p.add_argument('--tool')
p.add_argument('--timeout'); p.add_argument('--sby-timeout'); p.add_argument('--tool-dir', action='append')
p.add_argument('--preflight', action='store_true'); p.add_argument('--self-test', action='store_true')
p.add_argument('--job', action='append')
a = p.parse_args()
root = pathlib.Path(__file__).parent
out = pathlib.Path(a.output) / 'synthetic-test-run'
out.mkdir(parents=True)
print('synthetic fixture ' + a.backend, flush=True)
if a.tool == 'missing':
    print('ERROR: Tool not found: FormalMC', file=sys.stderr, flush=True)
    sys.exit(2)
if a.tool == 'sleep':
    time.sleep(60)
if a.tool == 'spawn':
    child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'], start_new_session=True)
    (out / 'child.json').write_text(json.dumps({'pid': child.pid}))
    time.sleep(60)
m = json.loads((root / 'manifest.json').read_text())
selected = a.job or [j['id'] for j in m['jobs']]
checks = [dict(c, status={'assert':'proven','cover':'covered','assume':'assumption'}[c['kind']]
               if c['job_id'] in selected else 'not_run') for c in m['checks']]
result = {'backend': a.backend, 'manifest_sha256': hashlib.sha256((root/'manifest.json').read_bytes()).hexdigest(),
 'runner_sha256': hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),
 'status':'passed', 'full_suite_passed': len(selected)==len(m['jobs']), 'selected_jobs':selected,
 'jobs':[{'id': j, 'status':'passed'} for j in selected], 'checks':checks}
if a.preflight: result.update(status='preflight_passed', full_suite_passed=False)
if a.self_test: result.update(status='capability_check_passed', full_suite_passed=False)
if a.tool == 'bad-backend': result['backend'] = 'formalmc' if a.backend == 'sby' else 'sby'
if a.tool == 'bad-hash': result['manifest_sha256'] = '0' * 64
if a.tool == 'bad-runner': result['runner_sha256'] = '0' * 64
if a.tool == 'missing-check': result['checks'].pop()
if a.tool == 'failed-cover': result['checks'][1]['status']='uncovered'
if a.tool == 'missing-job': result['jobs'].pop()
if a.tool == 'wrong-label': result['checks'][0]['label']='different'
if a.tool == 'fake-preflight': result.update(status='passed', full_suite_passed=True)
if a.tool == 'only-subset':
    result['selected_jobs'] = selected[:1]; result['jobs'] = result['jobs'][:1]
if a.tool == 'long-log': print('x' * 1200000, flush=True)
(out/'result.json').write_text(json.dumps(result))
'''


def _dump(path, value):
    """Write fixture JSON explicitly outside production evidence trees."""
    path.write_text(json.dumps(value), encoding="utf-8")


def _seal(root):
    """Create the synthetic package's release inventory."""
    _dump(root / "release_hashes.json", {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                        for p in root.iterdir() if p.name != "release_hashes.json"})


@pytest.fixture
def configured(tmp_path):
    """Register a temporary synthetic package with three representative check kinds."""
    root = tmp_path / "package"
    root.mkdir()
    (root / "run.py").write_text(_FAKE, encoding="utf-8")
    (root / "source.sv").write_text("// synthetic fixture", encoding="utf-8")
    manifest = {"jobs": [{"id": "safety", "mode": "prove"}, {"id": "witness", "mode": "cover"}],
                "checks": [{"ck_id": "C1", "kind": "assert", "job_id": "safety", "label": "P1"},
                           {"ck_id": "C2", "kind": "cover", "job_id": "witness", "label": "P2"},
                           {"ck_id": "C3", "kind": "assume", "job_id": "safety", "label": "A1"}],
                "expected_counts": {"checks": 3, "assert": 1, "cover": 1, "assume": 1},
                "files": {"source.sv": hashlib.sha256((root / "source.sv").read_bytes()).hexdigest()}}
    _dump(root / "manifest.json", manifest)
    _seal(root)
    registry = tmp_path / "registry.json"
    _dump(registry, {"schema_version": 1, "packages": [{"id": "dut", "title": "Synthetic DUT", "root": str(root),
            "session_ids": ["test-session"], "default_configs": {"sby": {"tool": "ok"}, "formalmc": {"tool": "ok"}}}]})
    manager = service.PortableFormalManager(registry, tmp_path / "state")
    yield manager, root, registry
    manager.shutdown()


def _launch(manager, **changes):
    """Submit a new synthetic run with current optimistic concurrency metadata."""
    body = {"backend": "sby", "action": "run", "revision": manager.projection("dut")["revision"],
            "request_id": "test-" + str(time.time_ns())}
    body.update(changes)
    return manager.launch("dut", body)


def _finish(manager, record):
    """Wait briefly for a real fixture subprocess to finish and read its API projection."""
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        result = manager.run_detail("dut", record["id"])
        if result["status"] not in service._ACTIVE:
            manager.threads[record["id"]].join(timeout=5)
            return manager.run_detail("dut", record["id"])
        time.sleep(0.03)
    pytest.fail("Synthetic process failed to finish")


def _tool(manager, value, backend="sby"):
    """Change a single synthetic tool selector without affecting the other backend."""
    current = manager.projection("dut")
    config = dict(current["configs"][backend], tool=value)
    return manager.configure("dut", {"backend": backend, "config": config, "revision": current["revision"]})


def test_switch_reads_never_launch_and_configs_are_isolated(configured):
    """GUI reads and backend-local saves leave execution and the other settings untouched."""
    manager, root, _ = configured
    before = manager.projection("dut")
    for _ in range(4):
        assert manager.projection("dut")["backends"]["formalmc"]["latest_run"] is None
    after = _tool(manager, "my-formalmc", "formalmc")
    assert not manager.runs
    assert after["configs"]["sby"] == before["configs"]["sby"]
    assert after["configs"]["formalmc"]["tool"] == "my-formalmc"
    assert not (root / "results").exists()


def test_fresh_backend_argv_and_full_inventory(configured):
    """Selected backend reaches the unchanged runner and all synthetic checks are bound."""
    manager, _, _ = configured
    result = _finish(manager, _launch(manager, backend="formalmc"))
    assert result["status"] == "passed" and result["full_suite_passed"] is True
    assert result["argv"][result["argv"].index("--backend") + 1] == "formalmc"
    assert len(result["result"]["checks"]) == 3
    assert "synthetic fixture formalmc" in result["log"]
    projection = manager.projection("dut")
    assert projection["backends"]["sby"]["latest_run"] is None
    assert projection["backends"]["formalmc"]["latest_run"]["id"] == result["id"]


def test_idempotency_conflicts_and_cancel(configured):
    """Identical retries reuse a run; differing or concurrent requests cannot double-launch."""
    manager, _, _ = configured
    _tool(manager, "sleep")
    body = {"backend": "sby", "action": "run", "revision": 2, "request_id": "retry-1"}
    first = manager.launch("dut", body)
    assert manager.launch("dut", body)["id"] == first["id"]
    with pytest.raises(HTTPException) as conflict:
        manager.launch("dut", dict(body, backend="formalmc"))
    assert conflict.value.status_code == 409
    with pytest.raises(HTTPException) as conflict:
        _launch(manager, backend="formalmc")
    assert conflict.value.status_code == 409
    manager.cancel("dut", first["id"])
    assert _finish(manager, first)["status"] == "cancelled"


def test_short_log_streams_while_tool_is_running(configured):
    """A short flushed progress line reaches the GUI before a long process exits."""
    manager, _, _ = configured
    _tool(manager, "sleep")
    record = _launch(manager)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        result = manager.run_detail("dut", record["id"])
        if "synthetic fixture" in result["log"]:
            break
        time.sleep(0.02)
    assert "synthetic fixture" in result["log"] and result["status"] == "running"
    manager.cancel("dut", record["id"])
    assert _finish(manager, record)["status"] == "cancelled"


def test_stale_revision_rejected(configured):
    """A stale browser cannot overwrite settings or launch using a different configuration."""
    manager, _, _ = configured
    _tool(manager, "ok")
    with pytest.raises(HTTPException) as conflict:
        _launch(manager, revision=1)
    assert conflict.value.status_code == 409
    with pytest.raises(HTTPException) as conflict:
        manager.configure("dut", {"backend": "sby", "config": {}, "revision": 1})
    assert conflict.value.status_code == 409


@pytest.mark.parametrize("action", ["preflight", "self-test"])
def test_nonproof_actions_never_show_dut_pass(configured, action):
    """A successful process/tool capability check has no full-suite proof meaning."""
    manager, _, _ = configured
    result = _finish(manager, _launch(manager, backend="formalmc", action=action))
    assert result["status"] in {"preflight_passed", "capability_check_passed"}
    assert result["full_suite_passed"] is False


def test_missing_tool_preserves_actual_error_log(configured):
    """Missing-tool exit codes and stderr remain visible instead of becoming a PASS."""
    manager, _, _ = configured
    _tool(manager, "missing", "formalmc")
    result = _finish(manager, _launch(manager, backend="formalmc", action="preflight"))
    assert result["status"] == "error"
    assert result["exit_code"] == 2
    assert "Tool not found: FormalMC" in result["log"]
    assert result["full_suite_passed"] is False


@pytest.mark.parametrize("tool", ["bad-backend", "bad-hash", "bad-runner", "missing-check", "failed-cover", "missing-job", "wrong-label", "only-subset"])
def test_incomplete_or_wrong_proof_cannot_pass(configured, tool):
    """Synthetic corrupt reports exercise proof identity and complete-inventory gates."""
    manager, _, _ = configured
    _tool(manager, tool)
    result = _finish(manager, _launch(manager))
    assert result["status"] in {"error", "incomplete"}
    assert result["full_suite_passed"] is False


def test_fake_preflight_fullpass_is_rejected(configured):
    """A preflight cannot inject a proof-PASS banner through its result JSON."""
    manager, _, _ = configured
    _tool(manager, "fake-preflight", "formalmc")
    result = _finish(manager, _launch(manager, backend="formalmc", action="preflight"))
    assert result["status"] == "error" and not result["full_suite_passed"]


def test_partial_selection_is_distinct(configured):
    """Passing selected checks does not claim the omitted coverage job passed."""
    manager, _, _ = configured
    result = _finish(manager, _launch(manager, jobs=["safety"]))
    assert result["status"] == "passed" and not result["full_suite_passed"]


@pytest.mark.parametrize("filename", ["run.py", "source.sv", "manifest.json", "release_hashes.json"])
def test_integrity_checked_before_every_launch(configured, filename):
    """Post-registration changes to the runner, source, manifest, or seal block execution."""
    manager, root, _ = configured
    with (root / filename).open("a") as stream:
        stream.write(" ")
    with pytest.raises(HTTPException) as conflict:
        _launch(manager)
    assert conflict.value.status_code == 409
    assert not manager.runs


def test_restart_preserves_backend_settings_and_interrupts_stale_run(configured):
    """Restart keeps both histories/settings but never converts unfinished work to PASS."""
    manager, _, registry = configured
    _tool(manager, "saved", "formalmc")
    completed = _finish(manager, _launch(manager))
    manager.shutdown()
    run_dir = manager.state_dir / "run-stale"
    run_dir.mkdir()
    _dump(run_dir / "record.json", {"id": "run-stale", "package_id": "dut", "backend": "formalmc", "action": "run",
            "created_utc": "9999", "status": "running", "processes": [], "full_suite_passed": True})
    resumed = service.PortableFormalManager(registry, manager.state_dir)
    try:
        detail = resumed.projection("dut")
        assert detail["configs"]["formalmc"]["tool"] == "saved"
        assert detail["backends"]["sby"]["latest_run"]["id"] == completed["id"]
        assert detail["backends"]["formalmc"]["latest_run"]["status"] == "interrupted"
        assert not detail["backends"]["formalmc"]["latest_run"]["full_suite_passed"]
    finally:
        resumed.shutdown()


def test_second_service_cannot_recover_a_live_managers_process(configured):
    """Starting another GUI service with the same state must not kill the first proof."""
    manager, _, registry = configured
    _tool(manager, "sleep")
    record = _launch(manager)
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and manager.run_detail("dut", record["id"])["status"] != "running":
        time.sleep(0.02)
    with pytest.raises(ValueError, match="already owned"):
        service.PortableFormalManager(registry, manager.state_dir)
    assert manager.run_detail("dut", record["id"])["status"] == "running"
    manager.cancel("dut", record["id"])
    assert _finish(manager, record)["status"] == "cancelled"


@pytest.mark.skipif(os.name == "nt", reason="This process-session test exercises POSIX detached descendants")
def test_cancel_stops_separate_session_descendant(configured):
    """Cancellation reaches child processes even if the proof runner gave them a new session."""
    manager, _, _ = configured
    _tool(manager, "spawn")
    record = _launch(manager)
    child_path = manager.state_dir / record["id"] / "output/synthetic-test-run/child.json"
    deadline = time.monotonic() + 5
    while not child_path.exists() and time.monotonic() < deadline:
        time.sleep(0.03)
    child_pid = json.loads(child_path.read_text())["pid"]
    time.sleep(0.15)
    manager.cancel("dut", record["id"])
    assert _finish(manager, record)["status"] == "cancelled"
    if psutil.pid_exists(child_pid):
        assert psutil.Process(child_pid).status() == psutil.STATUS_ZOMBIE


def test_bounded_log_output(configured):
    """Large subprocess output is bounded both on disk and in API responses."""
    manager, _, _ = configured
    _tool(manager, "long-log")
    result = _finish(manager, _launch(manager))
    assert result["status"] == "passed"
    assert len(result["log"]) <= 65536 and result["log_truncated"]
    assert (manager.state_dir / result["id"] / "runner.log").stat().st_size <= service._LOG_LIMIT


def test_routes_require_auth_and_same_origin(configured, tmp_path):
    """The existing GUI authentication protects reads and cross-origin writes are denied."""
    old, _, registry = configured
    app = FastAPI()

    async def auth():
        """Provide an overridable authentication dependency for the API fixture."""
        raise HTTPException(401, "Authentication required")

    manager = service.register_portable_formal_routes(app, registry, tmp_path / "api-state", auth)
    try:
        with TestClient(app) as client:
            assert client.get("/api/v1/portable-formal").status_code == 401
            app.dependency_overrides[auth] = lambda: None
            assert client.get("/api/v1/portable-formal").json()["items"][0]["id"] == "dut"
            body = {"backend": "sby", "config": {}, "revision": 1}
            for headers in ({"origin": "https://evil.example"}, {"sec-fetch-site": "cross-site"}, {"origin": "https://testserver"}):
                assert client.post("/api/v1/portable-formal/dut/config", json=body, headers=headers).status_code == 403
            assert client.post("/api/v1/portable-formal/dut/config", json=body,
                               headers={"origin": "http://testserver"}).status_code == 200
            assert not manager.runs and not old.runs
    finally:
        manager.shutdown()


@pytest.mark.parametrize("config", [{"environment": {"SECRET": "x"}}, {"tool": "bad\ncommand"},
                                     {"tool_dirs": "not-a-list"}, {"timeout": 0}, {"timeout": True},
                                     {"timeout": float("inf")}, {"sby_timeout": -1}])
def test_invalid_config_is_rejected(configured, config):
    """Only bounded non-secret tool options are accepted through the GUI."""
    manager, _, _ = configured
    with pytest.raises(HTTPException) as invalid:
        manager.configure("dut", {"backend": "sby", "config": config, "revision": 1})
    assert invalid.value.status_code == 422


def test_path_and_unknown_job_rejected(configured):
    """Caller IDs and selected jobs cannot be interpreted as filesystem paths."""
    manager, _, _ = configured
    with pytest.raises(HTTPException) as invalid:
        manager.run_detail("dut", "../../settings.json")
    assert invalid.value.status_code == 404
    with pytest.raises(HTTPException) as invalid:
        _launch(manager, jobs=["../../runner"])
    assert invalid.value.status_code == 422
