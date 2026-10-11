"""Verify native platform evidence inside the canonical guided FG/FC/CK gates."""

from __future__ import annotations

import json
import hashlib
import os
from pathlib import Path
import sqlite3

from .manifest import sha256_file, verify_manifest
from .security import resolve_within


class NativeRunNotFound(ValueError):
    """Distinguish an absent registered run from evidence that fails authentication."""


def strip_cmdbuf_monitor(content: bytes) -> bytes:
    """Remove bounded non-nested blocks with two fixed marker spellings, preserving DUT bytes."""
    prefixes = (b"// BEGIN CMDBUF NATIVE FORMAL MONITOR", b"// BEGIN CMDBUF CLOSURE FORMAL MONITOR")
    suffixes = (b"// END CMDBUF NATIVE FORMAL MONITOR", b"// END CMDBUF CLOSURE FORMAL MONITOR")
    active, count, result = None, 0, []
    for line in content.splitlines(keepends=True):
        token = line.rstrip(b"\r\n")
        if token in prefixes:
            if active is not None or count >= 16:
                raise ValueError("Monitor blocks must be non-nested and no more than 16")
            active = prefixes.index(token)
            count += 1
        elif token in suffixes:
            if active != suffixes.index(token):
                raise ValueError("Monitor markers must be ordered and exactly paired")
            active = None
        elif active is None:
            result.append(line)
    if not count or active is not None:
        raise ValueError("strip_cmdbuf_monitor requires complete paired marker lines")
    return b"".join(result)


def unique_result_rows(rows: list[dict]) -> list[dict]:
    """Count a shared native proof once while preserving every CK's trace row."""
    return [row for row in rows if not row.get("native_binding", {}).get("alias_of")]


def apply_native_dependencies(rows: list[dict]) -> None:
    """Require proven safety suppliers for assertions and native cover witnesses."""
    safety = {row["ck"]: row for row in rows if row["kind"] == "assert"}
    obligations = dict(safety)
    obligations.update({row["ck"]: row for row in rows if row["kind"] == "cover" and row.get("native_binding")})
    visited, active = set(), set()

    def visit(ck_id):
        """Propagate unresolved dependencies while preserving each signed property's result."""
        if ck_id in active:
            raise ValueError("Native supporting_ck_ids must not contain a dependency cycle")
        if ck_id in visited:
            return
        active.add(ck_id)
        row = obligations[ck_id]
        dependencies = (row.get("native_binding") or {}).get("supporting_ck_ids", [])
        for dependency in dependencies:
            if dependency not in safety:
                raise ValueError(f"{ck_id}: supporting_ck_ids must name existing safety checkpoints")
            visit(dependency)
        if dependencies and row.get("status") in ("proven", "covered") and any(safety[dependency].get("status") != "proven" for dependency in dependencies):
            row["native_property_status"] = row["status"]
            row["status"] = "inconclusive"
            row["dependency_status"] = "supporting_checkpoints_not_proven"
        active.remove(ck_id)
        visited.add(ck_id)

    for ck_id in obligations:
        visit(ck_id)


class NativeEvidenceResolver:
    """Read an administrator-selected platform database without changing its state."""

    def __init__(self, state_dir: Path):
        """Use only the trusted host location, never a key or manifest supplied by a CK."""
        self.state_dir = state_dir.resolve(strict=True)
        key_path = self.state_dir / "manifest.key"
        if key_path.is_symlink() or not key_path.is_file():
            raise ValueError("Native evidence signing key must be a regular host file")
        if os.name != "nt" and key_path.stat().st_mode & 0o077:
            raise ValueError("Native evidence signing key requires owner-only permissions")
        self._key = key_path.read_bytes()
        if len(self._key) < 32:
            raise ValueError("Native evidence signing key is invalid")
        self._runs = {}

    def run(self, run_id: str) -> dict:
        """Resolve the actual completed run and its latest signed formal Job attempt."""
        if run_id in self._runs:
            return self._runs[run_id]
        database = (self.state_dir / "platform.db").resolve(strict=True)
        with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as db:
            db.row_factory = sqlite3.Row
            row = db.execute(
                "SELECT r.*,p.source_root FROM runs r JOIN projects p ON p.project_id=r.project_id WHERE r.run_id=?",
                (run_id,),
            ).fetchone()
            if row is None:
                raise NativeRunNotFound(f"Native run {run_id} is not registered with the trusted platform")
            jobs = db.execute("SELECT * FROM jobs WHERE run_id=?", (run_id,)).fetchall()
            if len(jobs) != 1:
                raise ValueError(f"Native run {run_id} must identify exactly one formal Job")
            job = jobs[0]
            attempt = db.execute("SELECT * FROM attempts WHERE job_id=? ORDER BY number DESC LIMIT 1", (job["job_id"],)).fetchone()
        if row["adapter"] != "sby" or any(item["execution_status"] != "completed" for item in (row, job)):
            raise ValueError(f"Native run {run_id} is not a completed SBY execution")
        if attempt is None or attempt["execution_status"] != "completed" or not attempt["manifest_path"]:
            raise ValueError(f"Native run {run_id} has no completed signed attempt")
        project = Path(row["source_root"]).resolve(strict=True)
        path = resolve_within(project, attempt["manifest_path"], must_exist=True)
        manifest = verify_manifest(path, self._key, workspace=project, verify_files=True)
        if manifest.get("run_id") != run_id + ".formal" or manifest.get("execution_status") != "completed":
            raise ValueError(f"Native run {run_id} manifest identity/execution does not match its registered Job")
        if manifest.get("metadata", {}).get("adapter") != "sby":
            raise ValueError(f"Native run {run_id} manifest is not native SBY evidence")
        result = {"manifest": manifest, "path": path, "project": project, "sha256": sha256_file(path)}
        self._runs[run_id] = result
        return result

    def resolve(self, item: dict, workspace: Path, required_sources: list[str]) -> dict:
        """Bind one exact compiled property to current DUT bytes and preserve its real status."""
        binding = item["native_binding"]
        run = self.run(binding["run_id"])
        manifest = run["manifest"]
        metadata = manifest["metadata"]
        if metadata.get("mode") != binding["mode"]:
            raise ValueError(f"{item['ck']}: native mode differs from its signed execution")
        source = resolve_within(run["project"], binding["source"], must_exist=True)
        relative = source.relative_to(run["project"]).as_posix()
        if manifest["input_hashes"].get(relative) != binding["source_sha256"]:
            raise ValueError(f"{item['ck']}: native property source hash is absent or changed")
        input_map = binding["input_map"]
        normalized = {resolve_within(workspace, value if isinstance(value, str) else value["session_source"], must_exist=True).relative_to(workspace).as_posix() for value in input_map.values()}
        expected = {resolve_within(workspace, value, must_exist=True).relative_to(workspace).as_posix() for value in required_sources}
        if not expected <= normalized:
            raise ValueError(f"{item['ck']}: native input_map must cover every current guided DUT source")
        transformed_inputs = []
        for native_path, mapping in input_map.items():
            current_path = mapping if isinstance(mapping, str) else mapping["session_source"]
            native = resolve_within(run["project"], native_path, must_exist=True)
            current = resolve_within(workspace, current_path, must_exist=True)
            native_name = native.relative_to(run["project"]).as_posix()
            signed_hash = manifest["input_hashes"].get(native_name)
            if signed_hash != sha256_file(native):
                raise ValueError(f"{item['ck']}: native DUT file is not an exact signed input: {native_name}")
            digest = signed_hash
            if isinstance(mapping, dict):
                if mapping.get("transform") != "strip_cmdbuf_monitor":
                    raise ValueError("Unsupported native input transform")
                digest = hashlib.sha256(strip_cmdbuf_monitor(native.read_bytes())).hexdigest()
                transformed_inputs.append({"source": native_name, "signed_sha256": signed_hash, "transform": mapping["transform"], "stripped_sha256": digest, "session_source": current_path})
            if digest != sha256_file(current):
                raise ValueError(f"{item['ck']}: native DUT source does not match current session: {native_name}")
        matches = [prop for prop in manifest.get("properties", [])
                   if prop.get("details", {}).get("property_id") == binding["property_id"]
                   and prop.get("details", {}).get("location", "").startswith("inputs/" + relative + ":")]
        if len(matches) != 1:
            raise ValueError(f"{item['ck']}: native compiled property is missing or ambiguous")
        prop = matches[0]
        if prop["details"].get("kind") != binding["expected_kind"] or item["kind"] != binding["expected_kind"]:
            raise ValueError(f"{item['ck']}: native property kind does not match the checkpoint")
        status = prop["status"]
        if binding["mode"] == "bmc" and status == "proven":
            raise ValueError(f"{item['ck']}: bounded evidence cannot establish an unbounded proof")
        if status == "disabled":
            raise ValueError(f"{item['ck']}: selected native property was disabled in this run")
        counterexample = prop.get("counterexample_path")
        return {**item, "status": status, "mode": binding["mode"], "evidence": str(run["path"]),
                "manifest_sha256": run["sha256"], "native_run_id": binding["run_id"],
                "native_property_id": binding["property_id"], "source_sha256": binding["source_sha256"],
                "scope": binding["scope"], "tool_name": prop["name"],
                "counterexample": str(resolve_within(run["path"].parent, counterexample, must_exist=True)) if counterexample else None,
                "bounded_depth": prop["details"].get("bounded_depth"), "engine": metadata.get("engine"),
                "verified_input_hashes": manifest["input_hashes"], "transformed_inputs": transformed_inputs}


def validate_native_review(review: dict, rows: list[dict]) -> None:
    """Require explicit current-manifest assumption/scope review for each native harness."""
    native = {row["native_run_id"]: row["manifest_sha256"] for row in rows if row.get("native_run_id")}
    reviews = review.get("native_runs", {})
    if not isinstance(reviews, dict) or set(reviews) != set(native):
        raise ValueError("review.native_runs must review every bound native run using its exact run_id")
    for run_id, digest in native.items():
        entry = reviews[run_id]
        if not isinstance(entry, dict) or entry.get("manifest_sha256") != digest:
            raise ValueError(f"Native run {run_id} review is not bound to its current verified manifest")
        for key in ("assumptions", "scope"):
            if not isinstance(entry.get(key), str) or len(entry[key].strip()) < 20 or "TODO" in entry[key]:
                raise ValueError(f"Native run {run_id} requires an explicit reviewed {key} statement")


class NativeEvidenceRegistry:
    """Resolve a run across explicit trusted platform stores without ambiguous identities."""

    def __init__(self, state_dirs: list[str]):
        """Construct read-only adapters for this service and configured external evidence stores."""
        self.resolvers = [NativeEvidenceResolver(Path(path)) for path in dict.fromkeys(state_dirs)]

    def resolve(self, item: dict, workspace: Path, required_sources: list[str]) -> dict:
        """Fail authentication rather than falling back when a registered run is corrupt."""
        matches = []
        for resolver in self.resolvers:
            try:
                resolver.run(item["native_binding"]["run_id"])
            except NativeRunNotFound:
                continue
            matches.append(resolver)
        if len(matches) != 1:
            raise ValueError(f"{item['ck']}: native run must exist in exactly one trusted platform store")
        return matches[0].resolve(item, workspace, required_sources)
