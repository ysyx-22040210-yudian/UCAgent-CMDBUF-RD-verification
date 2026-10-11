"""Run sealed portable proof packages from the existing authenticated GUI.

This adapter owns no proof semantics: the unchanged package runner produces the
evidence. Backend selection is a read-only UI operation; execution is explicit.
"""

from __future__ import annotations

from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import threading
import time
from typing import Any, Callable
from urllib.parse import urlsplit
import uuid

from fastapi import APIRouter, Depends, HTTPException, Request
import psutil


_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,95}$")
_BACKENDS = ("sby", "formalmc")
_ACTIVE = {"starting", "running", "cancelling"}
_LOG_LIMIT = 1024 * 1024


def _utc() -> str:
    """Return an unambiguous persisted UTC timestamp."""
    return datetime.now(timezone.utc).isoformat()


def _sha(path: Path) -> str:
    """Hash bytes without relying on timestamps or filenames."""
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()


def _read(path: Path) -> Any:
    """Read UTF-8 JSON, including files written by Windows administration tools."""
    return json.loads(path.read_text(encoding="utf-8-sig"))


def _save(path: Path, data: Any) -> None:
    """Atomically replace a service-owned state record."""
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(temporary, path)


def _inside(root: Path, name: str) -> Path:
    """Resolve a portable relative regular file without symlinks or traversal."""
    if not isinstance(name, str) or "\\" in name or ":" in name:
        raise ValueError("Invalid package-relative path")
    parts = PurePosixPath(name).parts
    if not parts or PurePosixPath(name).is_absolute() or any(p in {".", ".."} for p in parts):
        raise ValueError("Invalid package-relative path")
    current = root
    for part in parts:
        current = current / part
        if current.is_symlink():
            raise ValueError("Package symlinks are not permitted")
    if not current.is_file() or not current.resolve().is_relative_to(root):
        raise ValueError("Missing package file: " + name)
    return current


def _config(backend: str, value: Any) -> dict[str, Any]:
    """Validate the deliberately small non-secret tool configuration surface."""
    allowed = {"tool", "tool_dirs", "timeout"} | ({"sby_timeout"} if backend == "sby" else set())
    if backend not in _BACKENDS or not isinstance(value, dict) or set(value) - allowed:
        raise ValueError("Invalid backend configuration fields")
    result = {"tool": "sby" if backend == "sby" else "FormalMC", "tool_dirs": [], "timeout": 1200}
    if backend == "sby":
        result["sby_timeout"] = 900
    result.update(value)
    tool = result["tool"]
    dirs = result["tool_dirs"]
    if not isinstance(tool, str) or not tool or len(tool) > 4096 or any(ord(c) < 32 for c in tool):
        raise ValueError("tool must be an executable name or path")
    if not isinstance(dirs, list) or len(dirs) > 16 or any(
        not isinstance(p, str) or not p or len(p) > 4096 or any(ord(c) < 32 for c in p) for p in dirs
    ):
        raise ValueError("tool_dirs must contain at most 16 directory paths")
    timeout = result["timeout"]
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or not math.isfinite(timeout) or not 1 <= timeout <= 604800:
        raise ValueError("timeout must be between 1 and 604800 seconds")
    if backend == "sby" and (type(result["sby_timeout"]) is not int or not 1 <= result["sby_timeout"] <= 604800):
        raise ValueError("sby_timeout must be a positive integer up to 604800")
    return result


def _kill_owned(identities: list[dict[str, Any]]) -> None:
    """Stop only recorded PID/create-time identities, including detached sessions."""
    processes: dict[int, psutil.Process] = {}
    for item in identities:
        try:
            process = psutil.Process(item["pid"])
            if abs(process.create_time() - item["created"]) > 0.001:
                continue
            processes[process.pid] = process
            # Freeze spawning parents before collecting their descendants.
            process.suspend()
            for child in process.children(recursive=True):
                processes[child.pid] = child
                try:
                    child.suspend()
                except psutil.NoSuchProcess:
                    pass
        except (psutil.NoSuchProcess, psutil.AccessDenied, KeyError):
            continue
    for process in reversed(list(processes.values())):
        try:
            process.kill()
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass
    psutil.wait_procs(list(processes.values()), timeout=3)


class _StateLease:
    """Keep restart recovery exclusive to one live service owning the state directory."""

    def __init__(self, path: Path) -> None:
        """Take a nonblocking OS lock; a second manager must not recover a live run."""
        self.stream = path.open("a+b")
        try:
            if os.name == "nt":
                import msvcrt
                self.stream.seek(0, os.SEEK_END)
                if self.stream.tell() == 0:
                    self.stream.write(b"0")
                    self.stream.flush()
                self.stream.seek(0)
                msvcrt.locking(self.stream.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as error:
            self.stream.close()
            raise ValueError("Portable formal state is already owned by a running service") from error

    def close(self) -> None:
        """Release the operating-system lock only after worker shutdown."""
        if not self.stream.closed:
            self.stream.close()


class PortableFormalManager:
    """Serialize explicit runner launches and retain independent backend histories."""

    def __init__(self, registry_file: Path, state_dir: Path) -> None:
        """Load administrator-registered sealed packages and recover interrupted runs."""
        self.lock = threading.RLock()
        self.state_dir = Path(state_dir).resolve()
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.packages: dict[str, Any] = {}
        self.runs: dict[str, Any] = {}
        self.threads: dict[str, threading.Thread] = {}
        self.cancel_events: dict[str, threading.Event] = {}
        self.closed = False
        self.lease = _StateLease(self.state_dir / "manager.lock")
        try:
            self._restore(registry_file)
        except BaseException:
            self.lease.close()
            raise

    def _restore(self, registry_file: Path) -> None:
        """Restore packages and state while exclusive ownership prevents false recovery."""
        registry = _read(Path(registry_file))
        if registry.get("schema_version") != 1 or not isinstance(registry.get("packages"), list):
            raise ValueError("Invalid portable formal registry")
        settings_path = self.state_dir / "settings.json"
        self.settings = _read(settings_path) if settings_path.exists() else {}
        for item in registry["packages"]:
            identifier = item.get("id", "")
            if not _ID.fullmatch(identifier) or identifier in self.packages:
                raise ValueError("Invalid or duplicate package identifier")
            root = Path(item["root"]).expanduser().resolve(strict=True)
            if self.state_dir == root or self.state_dir.is_relative_to(root):
                raise ValueError("Run state must be outside the sealed package")
            manifest = _read(root / "manifest.json")
            package = dict(item, root=root, manifest=manifest, manifest_sha256=_sha(root / "manifest.json"),
                           release_sha256=_sha(root / "release_hashes.json"))
            self._integrity(package)
            self.packages[identifier] = package
            if identifier not in self.settings:
                self.settings[identifier] = {"revision": 1, "configs": {
                    backend: _config(backend, item.get("default_configs", {}).get(backend, {})) for backend in _BACKENDS}}
            else:
                for backend in _BACKENDS:
                    self.settings[identifier]["configs"][backend] = _config(backend, self.settings[identifier]["configs"][backend])
        _save(settings_path, self.settings)
        for directory in self.state_dir.glob("run-*"):
            if directory.is_symlink() or not directory.is_dir() or not _ID.fullmatch(directory.name):
                continue
            record_path = directory / "record.json"
            if not record_path.is_file() or record_path.is_symlink():
                continue
            record = _read(record_path)
            if record.get("id") != directory.name or record.get("package_id") not in self.packages:
                continue
            if record.get("status") in _ACTIVE:
                _kill_owned(record.get("processes", []))
                record.update(status="interrupted", completed_utc=_utc(), full_suite_passed=False,
                              diagnostic="Service restarted before this execution completed")
                _save(record_path, record)
            elif record.get("full_suite_passed"):
                package = self.packages[record["package_id"]]
                if record.get("manifest_sha256") != package["manifest_sha256"] or record.get("runner_sha256") != _sha(package["root"] / "run.py"):
                    record.update(status="stale", full_suite_passed=False,
                                  diagnostic="Historical result belongs to different package inputs")
                    _save(record_path, record)
            self.runs[record["id"]] = record

    def _integrity(self, package: dict[str, Any]) -> None:
        """Check both the complete release seal and the runner input manifest."""
        root = package["root"]
        if _sha(root / "release_hashes.json") != package["release_sha256"]:
            raise ValueError("Package release seal changed; administrator registration must be refreshed")
        release = _read(_inside(root, "release_hashes.json"))
        if not isinstance(release, dict) or not {"run.py", "manifest.json"}.issubset(release):
            raise ValueError("Release seal must include run.py and manifest.json")
        for name, expected in release.items():
            if not isinstance(expected, str) or _sha(_inside(root, name)) != expected:
                raise ValueError("Release integrity failure: " + name)
        if _sha(root / "manifest.json") != package["manifest_sha256"]:
            raise ValueError("Package manifest changed")
        manifest = package["manifest"]
        for name, expected in manifest["files"].items():
            if release.get(name) != expected:
                raise ValueError("Manifest/release integrity mismatch: " + name)
        jobs = manifest["jobs"]
        checks = manifest["checks"]
        if not jobs or len({j["id"] for j in jobs}) != len(jobs) or len({c["ck_id"] for c in checks}) != len(checks):
            raise ValueError("Invalid job/check inventory")
        expected = manifest["expected_counts"]
        counts = Counter(c["kind"] for c in checks)
        if len(checks) != expected["checks"] or any(counts[k] != expected[k] for k in ("assert", "cover", "assume")):
            raise ValueError("Check inventory does not match expected counts")

    def _package(self, identifier: str) -> dict[str, Any]:
        """Look up only administrator-registered package identifiers."""
        if identifier not in self.packages:
            raise HTTPException(404, "Unknown portable formal package")
        return self.packages[identifier]

    def _record(self, identifier: str, run_id: str) -> dict[str, Any]:
        """Resolve an owned run without accepting any caller-supplied filesystem path."""
        self._package(identifier)
        record = self.runs.get(run_id)
        if not record or record["package_id"] != identifier:
            raise HTTPException(404, "Unknown portable formal run")
        return record

    def _active(self) -> dict[str, Any] | None:
        """Return the sole active execution across all registered packages."""
        return next((r for r in self.runs.values() if r["status"] in _ACTIVE), None)

    def _public(self, record: dict[str, Any] | None) -> dict[str, Any] | None:
        """Project immutable JSON data without exposing live process-control identities."""
        return None if record is None else json.loads(json.dumps({k: v for k, v in record.items() if k != "processes"}))

    def projection(self, identifier: str) -> dict[str, Any]:
        """Read backend settings and fresh-run history without launching or switching state."""
        with self.lock:
            package = self._package(identifier)
            manifest = package["manifest"]
            result = {"id": identifier, "title": package.get("title", identifier),
                      "session_ids": package.get("session_ids", []), "manifest_sha256": package["manifest_sha256"],
                      "jobs": [{"id": j["id"], "mode": j["mode"],
                                "ck_ids": [c["ck_id"] for c in manifest["checks"] if c["job_id"] == j["id"]]} for j in manifest["jobs"]],
                      "counts": manifest["expected_counts"], **self.settings[identifier],
                      "active_run": self._public(self._active()), "backends": {}}
            for backend in _BACKENDS:
                runs = sorted((r for r in self.runs.values() if r["package_id"] == identifier and r["backend"] == backend),
                              key=lambda r: r["created_utc"], reverse=True)
                result["backends"][backend] = {"latest_run": self._public(runs[0]) if runs else None,
                    "latest_proof_run": self._public(next((r for r in runs if r["action"] == "run"), None)),
                    "run_count": len(runs)}
            return json.loads(json.dumps(result))

    def configure(self, identifier: str, body: dict[str, Any]) -> dict[str, Any]:
        """Update exactly one backend with optimistic concurrency and no execution."""
        with self.lock:
            self._package(identifier)
            if set(body) != {"backend", "config", "revision"}:
                raise HTTPException(422, "Expected backend, config, and revision")
            if type(body["revision"]) is not int or body["revision"] != self.settings[identifier]["revision"]:
                raise HTTPException(409, "Configuration revision changed; refresh before saving")
            try:
                config = _config(body["backend"], body["config"])
            except (ValueError, TypeError) as error:
                raise HTTPException(422, str(error)) from error
            self.settings[identifier]["configs"][body["backend"]] = config
            self.settings[identifier]["revision"] += 1
            _save(self.state_dir / "settings.json", self.settings)
            return self.projection(identifier)

    def launch(self, identifier: str, body: dict[str, Any]) -> dict[str, Any]:
        """Start one sealed runner invocation; retries with identical request IDs reuse it."""
        with self.lock:
            package = self._package(identifier)
            if self.closed:
                raise HTTPException(503, "Service is shutting down")
            if set(body) - {"backend", "action", "revision", "request_id", "jobs"} or not {"backend", "action", "revision", "request_id"}.issubset(body):
                raise HTTPException(422, "Invalid run request fields")
            backend, action, request_id = body["backend"], body["action"], body["request_id"]
            jobs = body.get("jobs", [])
            if not isinstance(backend, str) or not isinstance(action, str) or backend not in _BACKENDS or action not in {"run", "preflight", "self-test"} or (action == "self-test" and backend != "formalmc"):
                raise HTTPException(422, "Invalid backend/action combination")
            if not isinstance(request_id, str) or not _ID.fullmatch(request_id):
                raise HTTPException(422, "Invalid request_id")
            job_ids = {j["id"] for j in package["manifest"]["jobs"]}
            if not isinstance(jobs, list) or any(not isinstance(j, str) or j not in job_ids for j in jobs) or len(set(jobs)) != len(jobs):
                raise HTTPException(422, "Invalid job selection")
            signature = dict(body, jobs=jobs)
            for record in self.runs.values():
                if record["package_id"] == identifier and record["request_id"] == request_id:
                    if record["request"] != signature:
                        raise HTTPException(409, "request_id already identifies a different request")
                    return self._public(record)
            if type(body["revision"]) is not int or body["revision"] != self.settings[identifier]["revision"]:
                raise HTTPException(409, "Configuration revision changed; refresh before launch")
            if self._active():
                raise HTTPException(409, "Another portable formal execution is active")
            try:
                self._integrity(package)
            except (OSError, ValueError, KeyError) as error:
                raise HTTPException(409, "Package integrity check failed: " + str(error)) from error
            run_id = "run-" + uuid.uuid4().hex
            directory = self.state_dir / run_id
            directory.mkdir()
            output = directory / "output"
            config = self.settings[identifier]["configs"][backend]
            argv = [sys.executable, str(package["root"] / "run.py"), "--backend", backend,
                    "--output", str(output), "--tool", config["tool"], "--timeout", str(config["timeout"])]
            for tool_dir in config["tool_dirs"]:
                argv.extend(["--tool-dir", tool_dir])
            if backend == "sby":
                argv.extend(["--sby-timeout", str(config["sby_timeout"])])
            if action != "run":
                argv.append("--" + action)
            for job in jobs:
                argv.extend(["--job", job])
            record = {"id": run_id, "run_id": run_id, "package_id": identifier, "backend": backend,
                      "action": action, "request_id": request_id, "request": signature, "argv": argv,
                      "config": dict(config), "revision": body["revision"], "created_utc": _utc(),
                      "status": "starting", "full_suite_passed": False, "manifest_sha256": package["manifest_sha256"],
                      "runner_sha256": _sha(package["root"] / "run.py"), "processes": []}
            self.runs[run_id] = record
            self.cancel_events[run_id] = threading.Event()
            _save(directory / "record.json", record)
            worker = threading.Thread(target=self._execute, args=(record,), name=run_id, daemon=True)
            self.threads[run_id] = worker
            worker.start()
            return self._public(record)

    def _capture(self, stream: Any, path: Path) -> None:
        """Continuously drain output while bounding retained disk logs to the latest MiB."""
        tail = bytearray()
        with stream:
            # Buffered read() waits for a full block; read1() publishes short live progress.
            for block in iter(lambda: stream.read1(4096), b""):
                tail.extend(block)
                if len(tail) > _LOG_LIMIT:
                    del tail[:-_LOG_LIMIT]
                path.write_bytes(tail)

    def _execute(self, record: dict[str, Any]) -> None:
        """Supervise one child and validate its fresh report before showing any proof PASS."""
        directory = self.state_dir / record["id"]
        package = self.packages[record["package_id"]]
        event = self.cancel_events[record["id"]]
        process = None
        try:
            # The package was checked under the launch lock; check again at execution.
            self._integrity(package)
            if event.is_set():
                raise InterruptedError("Cancelled before process launch")
            kwargs: dict[str, Any] = {"start_new_session": True} if os.name != "nt" else {"creationflags": subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP}
            environment = dict(os.environ, PYTHONUNBUFFERED="1")
            process = subprocess.Popen(record["argv"], cwd=package["root"], stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, env=environment, **kwargs)
            parent = psutil.Process(process.pid)
            with self.lock:
                record.update(status="running", started_utc=_utc(), processes=[{"pid": parent.pid, "created": parent.create_time()}])
                _save(directory / "record.json", record)
            reader = threading.Thread(target=self._capture, args=(process.stdout, directory / "runner.log"), daemon=True)
            reader.start()
            while process.poll() is None:
                try:
                    identities = [{"pid": p.pid, "created": p.create_time()} for p in [parent, *parent.children(recursive=True)]]
                    with self.lock:
                        known = {(p["pid"], p["created"]) for p in record["processes"]}
                        new = [p for p in identities if (p["pid"], p["created"]) not in known]
                        if new:
                            record["processes"].extend(new)
                            _save(directory / "record.json", record)
                except psutil.NoSuchProcess:
                    pass
                if event.wait(0.1):
                    _kill_owned(record["processes"])
                    break
            exit_code = process.wait(timeout=10)
            _kill_owned(record["processes"])
            reader.join(timeout=5)
            if event.is_set():
                raise InterruptedError("Execution cancelled")
            self._integrity(package)
            result_files = list((directory / "output").glob("*/result.json"))
            result = _read(result_files[0]) if len(result_files) == 1 else None
            status, passed, diagnostic = self._validate_result(record, result, exit_code)
            with self.lock:
                record.update(status=status, exit_code=exit_code, full_suite_passed=passed, diagnostic=diagnostic)
                if result is not None:
                    _save(directory / "result.json", result)
        except InterruptedError as error:
            with self.lock:
                record.update(status="cancelled", full_suite_passed=False, diagnostic=str(error))
        except Exception as error:
            with self.lock:
                record.update(status="error", full_suite_passed=False, diagnostic=str(error))
        finally:
            if process is not None and process.poll() is None:
                _kill_owned(record.get("processes", []))
            with self.lock:
                record["completed_utc"] = _utc()
                _save(directory / "record.json", record)

    def _validate_result(self, record: dict[str, Any], result: Any, exit_code: int) -> tuple[str, bool, str]:
        """Require backend/hash/inventory bindings; capability checks never prove the DUT."""
        if not isinstance(result, dict):
            return "error", False, "Runner produced no unique fresh result; inspect the execution log"
        if result.get("backend") != record["backend"] or result.get("manifest_sha256") != record["manifest_sha256"] or result.get("runner_sha256") != record["runner_sha256"]:
            return "error", False, "Runner result backend or source hash does not match this execution"
        if exit_code != 0:
            return "failed", False, str(result.get("diagnostic") or result.get("status") or "Runner failed")
        if record["action"] != "run":
            expected = "preflight_passed" if record["action"] == "preflight" else "capability_check_passed"
            return (expected, False, "No DUT proof was executed") if result.get("status") == expected else ("error", False, "Unexpected non-proof action result")
        manifest = self.packages[record["package_id"]]["manifest"]
        jobs = result.get("jobs", [])
        checks = result.get("checks", [])
        selected = result.get("selected_jobs", [])
        known_jobs = {j["id"] for j in manifest["jobs"]}
        if not isinstance(jobs, list) or not isinstance(checks, list) or not isinstance(selected, list):
            return "error", False, "Malformed proof inventory"
        if len(set(selected)) != len(selected) or not set(selected).issubset(known_jobs) or not selected:
            return "error", False, "Invalid selected job inventory"
        if len(jobs) != len(selected) or {j.get("id") for j in jobs} != set(selected) or any(j.get("status") != "passed" for j in jobs):
            return "incomplete", False, "Not all selected jobs passed"
        expected_checks = {c["ck_id"]: c for c in manifest["checks"]}
        if len(checks) != len(expected_checks) or {c.get("ck_id") for c in checks} != set(expected_checks):
            return "error", False, "Proof check inventory differs from the sealed manifest"
        for check in checks:
            expected = expected_checks[check["ck_id"]]
            if any(check.get(k) != expected[k] for k in ("kind", "job_id", "label")):
                return "error", False, "Check identity does not match the sealed manifest"
            if expected["job_id"] in selected and check.get("status") != {"assert": "proven", "cover": "covered", "assume": "assumption"}[expected["kind"]]:
                return "incomplete", False, "A selected check has no accepted evidence"
        full = set(selected) == known_jobs
        if result.get("status") != "passed" or (full and result.get("full_suite_passed") is not True):
            return "incomplete", False, "Runner did not accept this proof suite"
        if not record["request"]["jobs"] and not full:
            return "error", False, "Full-suite request returned only a subset"
        return "passed", full, "Fresh full-suite proof passed" if full else "Selected jobs passed; full suite was not executed"

    def run_detail(self, identifier: str, run_id: str) -> dict[str, Any]:
        """Return a bounded log and the current runner report without execution side effects."""
        with self.lock:
            record = self._record(identifier, run_id)
            result = self._public(record)
            directory = self.state_dir / run_id
            log_path = directory / "runner.log"
            log = log_path.read_bytes()[-65536:] if log_path.is_file() else b""
            result.update(log=log.decode("utf-8", errors="replace"),
                          log_truncated=log_path.is_file() and log_path.stat().st_size >= 65536,
                          result=None)
            result_path = directory / "result.json"
            if not result_path.is_file() and record["status"] in _ACTIVE:
                candidates = list((directory / "output").glob("*/result.json"))
                if len(candidates) == 1:
                    result_path = candidates[0]
            if result_path.is_file():
                try:
                    result["result"] = _read(result_path)
                except (ValueError, OSError):
                    pass
            return result

    def cancel(self, identifier: str, run_id: str) -> dict[str, Any]:
        """Request cancellation of an owned run, preserving its logs and failed evidence."""
        with self.lock:
            record = self._record(identifier, run_id)
            if record["status"] in _ACTIVE:
                record["status"] = "cancelling"
                self.cancel_events[run_id].set()
                _save(self.state_dir / run_id / "record.json", record)
            return self._public(record)

    def shutdown(self) -> None:
        """Cancel and join only this manager's active worker/process trees."""
        with self.lock:
            self.closed = True
            for record in self.runs.values():
                if record["status"] in _ACTIVE:
                    self.cancel_events[record["id"]].set()
        for worker in list(self.threads.values()):
            worker.join(timeout=20)
        if any(worker.is_alive() for worker in self.threads.values()):
            raise RuntimeError("Portable formal worker has not stopped; state ownership is retained")
        self.lease.close()


def register_portable_formal_routes(app: Any, registry_file: Path, state_dir: Path,
                                   check_password: Callable[..., Any]) -> PortableFormalManager:
    """Mount authenticated same-origin APIs and return the shutdown-managed adapter."""
    manager = PortableFormalManager(registry_file, state_dir)
    router = APIRouter(prefix="/api/v1/portable-formal", dependencies=[Depends(check_password)])

    async def same_origin(request: Request) -> None:
        """Reject cross-origin browser writes while permitting authenticated API clients."""
        if request.headers.get("sec-fetch-site", "").casefold() in {"cross-site", "same-site"}:
            raise HTTPException(403, "Cross-origin state changes are not allowed")
        origin = request.headers.get("origin")
        if origin:
            parsed = urlsplit(origin)
            if parsed.scheme != request.url.scheme or parsed.netloc.casefold() != request.headers.get("host", "").casefold():
                raise HTTPException(403, "Cross-origin state changes are not allowed")

    @router.get("")
    def listing() -> dict[str, Any]:
        """List registered package projections without any EDA execution."""
        return {"items": [manager.projection(identifier) for identifier in manager.packages]}

    @router.get("/{identifier}")
    def detail(identifier: str) -> dict[str, Any]:
        """Read one package's backend-independent GUI projection."""
        return manager.projection(identifier)

    @router.post("/{identifier}/config", dependencies=[Depends(same_origin)])
    def configure(identifier: str, body: dict[str, Any]) -> dict[str, Any]:
        """Persist one backend's non-secret configuration without launching a tool."""
        return manager.configure(identifier, body)

    @router.post("/{identifier}/runs", dependencies=[Depends(same_origin)])
    def launch(identifier: str, body: dict[str, Any]) -> dict[str, Any]:
        """Launch the explicitly requested runner action once."""
        return manager.launch(identifier, body)

    @router.get("/{identifier}/runs/{run_id}")
    def run_detail(identifier: str, run_id: str) -> dict[str, Any]:
        """Read fresh execution status, bounded output, and proof evidence."""
        return manager.run_detail(identifier, run_id)

    @router.post("/{identifier}/runs/{run_id}/cancel", dependencies=[Depends(same_origin)])
    def cancel(identifier: str, run_id: str) -> dict[str, Any]:
        """Cancel one identified service-owned process tree."""
        return manager.cancel(identifier, run_id)

    app.include_router(router)
    return manager
