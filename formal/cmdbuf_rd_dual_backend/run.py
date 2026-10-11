#!/usr/bin/env python3
"""Run fresh cmdbuf_rd formal proofs; Python 3.9+, standard library only.

This is a standalone runner, not a UCAgent signed acceptance service. Historical
proof statuses are never inputs. Every selected job and all safety suppliers run
again, in dependency order, in a new output directory.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET

SUCCESS = {"proven", "covered"}
ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$")
KINDS = {"assert", "cover", "assume"}
MAX_REPORT_BYTES = 64 * 1024 * 1024


class InputError(ValueError):
    pass


def sha256(path):
    result = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def relative_path(root, value, must_exist=True):
    """Reject absolute paths, traversal and symlink escapes on either host OS."""
    if not isinstance(value, str) or not value or "\\" in value or ":" in value:
        raise InputError("Expected a relative POSIX path: %r" % value)
    item = PurePosixPath(value)
    if item.is_absolute() or any(p in {"", ".", ".."} for p in value.split("/")):
        raise InputError("Unsafe package path: " + value)
    root = Path(root).resolve()
    result = root.joinpath(*item.parts)
    if any(p.is_symlink() for p in [result, *list(result.parents)[:len(item.parts)-1]]):
        raise InputError("Symlinks are not accepted in package inputs: " + value)
    resolved = result.resolve()
    if root != resolved and root not in resolved.parents:
        raise InputError("Package path escapes root: " + value)
    if must_exist and not resolved.is_file():
        raise InputError("Missing package input: " + value)
    return resolved


def read_text(path, limit=MAX_REPORT_BYTES):
    path = Path(path)
    if path.stat().st_size > limit:
        raise InputError("Report exceeds size limit: " + str(path))
    return path.read_text(encoding="utf-8", errors="replace")


def save_json(path, value):
    path = Path(path)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def verify_hashes(root, manifest):
    files = manifest.get("files")
    if not isinstance(files, dict) or not files:
        raise InputError("manifest.files must be a nonempty path-to-SHA256 map")
    for name, expected in files.items():
        path = relative_path(root, name)
        if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
            raise InputError("Invalid SHA256 for " + name)
        if sha256(path) != expected:
            raise InputError("SHA256 mismatch: " + name)


def load_manifest(path):
    path = Path(path).resolve()
    manifest = json.loads(read_text(path))
    if manifest.get("schema_version") != 1:
        raise InputError("Unsupported manifest schema_version")
    jobs = manifest.get("jobs")
    checks = manifest.get("checks")
    if not isinstance(jobs, list) or not jobs or not isinstance(checks, list) or not checks:
        raise InputError("Manifest must contain nonempty jobs and checks arrays")
    by_id = {}
    for job in jobs:
        name = job.get("id", "")
        if not ID.fullmatch(name) or name in by_id:
            raise InputError("Invalid or duplicate job id: " + name)
        if job.get("mode") not in {"prove", "cover"}:
            raise InputError(name + ": only unbounded prove and cover jobs are supported")
        if not isinstance(job.get("depends_on", []), list):
            raise InputError(name + ": depends_on must be an array")
        if len(set(job.get("depends_on", []))) != len(job.get("depends_on", [])):
            raise InputError(name + ": duplicate dependencies")
        properties = job.get("properties")
        if not isinstance(properties, list) or not properties:
            raise InputError(name + ": property inventory is missing")
        seen = set()
        for prop in properties:
            label = prop.get("label")
            if not isinstance(label, str) or not label or label in seen or prop.get("kind") not in KINDS:
                raise InputError(name + ": invalid/duplicate property")
            seen.add(label)
        expected = "assert" if job["mode"] == "prove" else "cover"
        if not any(p["kind"] == expected for p in properties):
            raise InputError(name + ": no properties for its mode")
        for backend, entry in (("sby", "config"), ("formalmc", "tcl")):
            settings = job.get(backend, {})
            referenced = [settings.get(entry), *settings.get("sources", [])]
            for value in referenced:
                if value not in manifest.get("files", {}):
                    raise InputError(name + ": backend input has no hash: " + str(value))
                relative_path(path.parent, value)
        by_id[name] = job
    for job in jobs:
        for dependency in job.get("depends_on", []):
            if dependency not in by_id or by_id[dependency]["mode"] != "prove":
                raise InputError(job["id"] + ": dependency must be an existing safety job: " + dependency)
    ordered_jobs(by_id, list(by_id))
    seen = set()
    for check in checks:
        name = check.get("ck_id")
        if not isinstance(name, str) or not name or name in seen or check.get("kind") not in KINDS:
            raise InputError("Invalid or duplicate CK: " + str(name))
        seen.add(name)
        job = by_id.get(check.get("job_id"))
        if job is None:
            raise InputError(name + ": missing job mapping")
        matches = [p for p in job["properties"] if p["label"] == check.get("label") and p["kind"] == check["kind"]]
        if len(matches) != 1:
            raise InputError(name + ": property mapping is missing or kind disagrees")
    by_check = {c["ck_id"]: c for c in checks}
    expected_counts = manifest.get("expected_counts")
    actual_counts = {"checks": len(checks), **{kind: sum(c["kind"] == kind for c in checks) for kind in KINDS}}
    if expected_counts != actual_counts:
        raise InputError("Checkpoint inventory does not match expected_counts: " + str(actual_counts))
    for check in checks:
        if not isinstance(check.get("supporting_ck_ids", []), list):
            raise InputError(check["ck_id"] + ": supporting_ck_ids must be an array")
        suppliers = check.get("supporting_ck_ids", [])
        if len(suppliers) != len(set(suppliers)):
            raise InputError(check["ck_id"] + ": duplicate CK suppliers")
        for supplier in check.get("supporting_ck_ids", []):
            if supplier not in by_check or by_check[supplier]["kind"] != "assert":
                raise InputError(check["ck_id"] + ": CK supplier must be a known safety assertion")
    active, done = set(), set()
    def check_dependency(name):
        if name in active:
            raise InputError("CK dependency cycle at " + name)
        if name in done:
            return
        active.add(name)
        for supplier in by_check[name].get("supporting_ck_ids", []):
            check_dependency(supplier)
        active.remove(name)
        done.add(name)
    for name in by_check:
        check_dependency(name)
    verify_hashes(path.parent, manifest)
    return manifest, by_id


def ordered_jobs(jobs, selected):
    ordered, active, done = [], set(), set()
    def visit(name):
        if name not in jobs:
            raise InputError("Unknown job: " + name)
        if name in active:
            raise InputError("Dependency cycle at " + name)
        if name in done:
            return
        active.add(name)
        for dependency in jobs[name].get("depends_on", []):
            visit(dependency)
        active.remove(name)
        done.add(name)
        ordered.append(name)
    for name in selected:
        visit(name)
    return ordered


def selected_job_closure(jobs, checks, requested):
    """Include CK review suppliers without confusing them with proof imports.

    Two jobs can prove different independent properties used by one another's
    final CKs. Aggregating those CK edges into execution edges would invent a
    cycle. Only jobs.depends_on orders real assumption imports; both sets of
    jobs are selected and final CK acceptance checks the original acyclic CK
    dependency graph against this run's actual results.
    """
    selected = ordered_jobs(jobs, requested)
    by_ck = {check["ck_id"]: check for check in checks}
    while True:
        included = set(selected)
        extra = []
        for check in checks:
            if check["job_id"] not in included:
                continue
            for supplier in check.get("supporting_ck_ids", []):
                name = by_ck[supplier]["job_id"]
                if name not in included and name not in extra:
                    extra.append(name)
        if not extra:
            return ordered_jobs(jobs, selected)
        selected = ordered_jobs(jobs, selected + extra)


def execute(argv, cwd, logfile, timeout, environment):
    """Capture exact argv/exit, and stop the process group on POSIX timeout."""
    started = time.monotonic()
    result = {"argv": [str(a) for a in argv], "cwd": str(cwd), "timeout_seconds": timeout}
    with Path(logfile).open("wb") as output:
        try:
            process = subprocess.Popen(argv, cwd=cwd, env=environment, stdout=output,
                                       stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                                       start_new_session=(os.name != "nt"))
        except OSError as error:
            result.update(returncode=None, execution_status="error", diagnostic=str(error))
        else:
            try:
                code = process.wait(timeout=timeout)
                result.update(returncode=code, execution_status="completed")
            except (subprocess.TimeoutExpired, KeyboardInterrupt) as error:
                if os.name != "nt":
                    os.killpg(process.pid, signal.SIGKILL)
                else:
                    # taskkill terminates spawned solver processes as well as the parent.
                    subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                    if process.poll() is None:
                        process.kill()
                process.wait()
                result.update(returncode=process.returncode,
                              execution_status="timeout" if isinstance(error, subprocess.TimeoutExpired) else "interrupted")
    result["elapsed_seconds"] = round(time.monotonic() - started, 3)
    result["log_sha256"] = sha256(logfile)
    return result


def match_name(observed, expected):
    """Allow exact names or an unambiguous hierarchy leaf, never substring IDs."""
    if observed == expected or observed.lstrip("\\") == expected.lstrip("\\"):
        return True
    return re.split(r"[./:]", observed)[-1].lstrip("\\") == expected.lstrip("\\")


def base_property(prop):
    return {"label": prop["label"], "kind": prop["kind"],
            "status": "assumption" if prop["kind"] == "assume" else "not_run"}


def parse_sby(work, job, returncode):
    """Trust fresh typed JUnit plus matching status/exit, not a console PASS."""
    work = Path(work)
    output = [base_property(p) for p in job["properties"]]
    try:
        fields = read_text(work / "status", 1024).split()
        if len(fields) not in {1, 3} or fields[0] not in {"PASS", "FAIL", "UNKNOWN", "ERROR", "TIMEOUT"}:
            raise InputError("Invalid SBY status")
        status = fields[0]
        if len(fields) == 3:
            if int(fields[1]) != returncode or not 0 <= float(fields[2]) < float("inf"):
                raise InputError("SBY status/exit/runtime disagree")
        if status == "PASS" and returncode != 0:
            raise InputError("SBY PASS conflicts with exit code")
        if status in {"ERROR", "TIMEOUT"}:
            return output, status.lower(), ["SBY " + status]
        reports = sorted(work.glob("*.xml"))
        if len(reports) != 1:
            raise InputError("Expected exactly one fresh SBY JUnit report")
        content = read_text(reports[0], 16 * 1024 * 1024)
        if "<!DOCTYPE" in content.upper() or "<!ENTITY" in content.upper():
            raise InputError("JUnit entities/DTDs are forbidden")
        root = ET.fromstring(content)
        suites = [root] if root.tag == "testsuite" else root.findall("testsuite")
        if len(suites) != 1:
            raise InputError("Expected exactly one SBY task in JUnit")
        suite = suites[0]
        declared = suite.find("properties/property[@name='status']")
        if declared is None or declared.get("value") != status:
            raise InputError("SBY JUnit and status file disagree")
        cases = [c for c in suite.findall("testcase") if c.get("type", "").lower() in {"assert", "cover"}]
        if not cases:
            raise InputError("SBY report lacks typed property results; aggregate PASS is insufficient")
        seen = set()
        relevant = "assert" if job["mode"] == "prove" else "cover"
        if status == "PASS" and any(c.get("type", "").lower() == relevant and any(c.find(tag) is not None for tag in ("failure", "error", "skipped")) for c in cases):
            raise InputError("SBY PASS contradicts a typed property failure/error/skipped result")
        for index, prop in enumerate(job["properties"]):
            if prop["kind"] == "assume":
                continue
            if prop["kind"] != relevant:
                output[index]["status"] = "disabled"
                continue
            label = prop.get("sby_label", prop["label"])
            matches = [c for c in cases if c.get("type", "").lower() == prop["kind"] and
                       any(match_name(c.get(field, ""), label) for field in ("id", "name"))]
            if len(matches) != 1:
                output[index].update(status="missing" if not matches else "ambiguous",
                                     diagnostic="No unique typed JUnit identity for " + label)
                continue
            case = matches[0]
            identity = (case.get("id"), case.get("name"), case.get("location"))
            if identity in seen:
                raise InputError("Two expected properties bind the same SBY property")
            seen.add(identity)
            failed = case.find("failure") is not None
            unresolved = case.find("error") is not None or case.find("skipped") is not None
            if status == "UNKNOWN" or unresolved:
                state = "inconclusive"
            elif failed:
                state = "falsified" if prop["kind"] == "assert" else "uncovered"
            elif status == "PASS":
                state = "proven" if prop["kind"] == "assert" else "covered"
            else:
                # A partial failed run is not a completed proof of its other assertions.
                state = "inconclusive"
            output[index].update(status=state, observed_id=case.get("id"),
                                 observed_name=case.get("name"), location=case.get("location"),
                                 evidence=reports[0].name, tracefile=case.get("tracefile"))
        expected_results = [p for p in output if p["kind"] == relevant]
        unmatched = [c for c in cases if c.get("type", "").lower() == relevant and
                     (c.get("id"), c.get("name"), c.get("location")) not in seen]
        if status == "PASS" and unmatched:
            raise InputError("SBY has relevant compiled properties outside the expected inventory")
        if status == "PASS" and any(p["status"] in {"falsified", "uncovered"} for p in expected_results):
            raise InputError("SBY PASS contradicts JUnit failures")
        verdict = "passed" if status == "PASS" and all(p["status"] in SUCCESS for p in expected_results) else "inconclusive"
        if any(p["status"] == "falsified" for p in expected_results):
            verdict = "failed"
        return output, verdict, []
    except (OSError, ValueError, TypeError, ET.ParseError) as error:
        return [base_property(p) for p in job["properties"]], "error", [str(error)]


FORMAL_STATUSES = {
    "proven": "proven", "proved": "proven", "pass": "proven", "passed": "proven", "true": "proven",
    "falsified": "falsified", "fail": "falsified", "failed": "falsified", "false": "falsified", "cex": "falsified",
    "covered": "covered", "cover_pass": "covered", "reachable": "covered",
    "uncovered": "uncovered", "cover_fail": "uncovered", "unreachable": "uncovered", "uncoverable": "uncovered",
    "undec": "inconclusive", "undecided": "inconclusive", "undetermined": "inconclusive",
    "unknown": "inconclusive", "timeout": "inconclusive", "inconclusive": "inconclusive", "not_run": "inconclusive",
    "trivially_true": "vacuous", "trivial_true": "vacuous", "trivt": "vacuous", "vacuous": "vacuous",
    "trivially_false": "falsified", "disabled": "disabled", "waived": "disabled",
}
FORMAL_WORDS = "|".join(sorted(FORMAL_STATUSES, key=len, reverse=True))
FORMAL_PATTERNS = [
    re.compile(r"Info-P016:\s*property\s+([^\s:]+)\s+is\s+(" + FORMAL_WORDS + r")\b", re.I),
    re.compile(r"^\s*\d+\s+([A-Za-z_$\\][\w.$:/\[\]\\-]*)\s*(?:\s*:\s*|\s+)(" + FORMAL_WORDS + r")\b", re.I),
    re.compile(r"^\s*([A-Za-z_$\\][\w.$:/\[\]\\-]*)\s*(?:\||:|=)\s*(" + FORMAL_WORDS + r")\b", re.I),
]
INFRA_ERROR = re.compile(r"(?im)(?:Error-[A-Z][A-Z0-9_-]*|\b(?:syntax|parse|elaboration|compilation)\s+error\b|"
                         r"license\s+(?:checkout|check[- ]?out).*(?:fail|denied|unable)|"
                         r"(?:no|cannot find|unable to obtain).{0,40}(?:valid\s+)?license|"
                         r"NOT_ENOUGH_APP_LIC|flexnet licensing error|^\s*(?:fatal|error)\s*[:\[])" )


def parse_formalmc(text, job, returncode):
    """Known property reports only; no exit-zero, summary or COI-to-proof inference."""
    output = [base_property(p) for p in job["properties"]]
    if returncode != 0 or INFRA_ERROR.search(text):
        return output, "error", ["FormalMC process/compile/license error; inspect retained raw log"]
    observed = collections.defaultdict(list)
    for line in text.splitlines():
        for pattern in FORMAL_PATTERNS:
            match = pattern.search(line)
            if match:
                observed[match.group(1)].append(FORMAL_STATUSES[match.group(2).lower()])
                break
    relevant = "assert" if job["mode"] == "prove" else "cover"
    bound = set()
    for index, prop in enumerate(job["properties"]):
        if prop["kind"] == "assume":
            continue
        if prop["kind"] != relevant:
            output[index]["status"] = "disabled"
            continue
        label = prop.get("formalmc_label", prop["label"])
        names = [name for name in observed if match_name(name, label)]
        if len(names) != 1:
            output[index].update(status="missing" if not names else "ambiguous",
                                 diagnostic="No unique FormalMC property result for " + label)
            continue
        name = names[0]
        if name in bound:
            return output, "error", ["Multiple expected properties bind " + name]
        bound.add(name)
        outcomes = set(observed[name])
        # A reported failure is never erased by a later PASS. Unknown/progress
        # may precede a conclusive outcome; two contradictory conclusions fail.
        conclusive = outcomes & {"proven", "falsified", "covered", "uncovered", "vacuous", "disabled"}
        if len(conclusive) > 1:
            state = "conflict"
        elif conclusive:
            state = next(iter(conclusive))
        else:
            state = "inconclusive"
        # A prove/PASS on an assertion is not a witness for a cover. Only the
        # tool's explicit covered/reachable/cover_pass status counts for covers.
        if prop["kind"] == "cover" and state == "proven":
            state = "inconclusive"
        if prop["kind"] == "assert" and state == "covered":
            state = "inconclusive"
        output[index].update(status=state, observed_name=name, raw_outcomes=sorted(outcomes))
    expected_results = [p for p in output if p["kind"] == relevant]
    verdict = "passed" if expected_results and all(p["status"] in SUCCESS for p in expected_results) else "inconclusive"
    if any(p["status"] == "falsified" for p in expected_results):
        verdict = "failed"
    diagnostics = []
    for name, reports in observed.items():
        if name in bound:
            continue
        outcomes = set(reports)
        conclusive = outcomes & {"proven", "falsified", "covered", "uncovered", "vacuous", "disabled"}
        # Tool-generated assertions or unexpected properties cannot silently
        # fail outside the manifest. Retain their identity and block acceptance.
        if outcomes & {"falsified", "uncovered"} or len(conclusive) > 1:
            state = "conflict" if len(conclusive) > 1 else next(iter(conclusive))
            output.append({"label": name, "kind": "unmapped", "status": state,
                           "observed_name": name, "raw_outcomes": sorted(outcomes),
                           "diagnostic": "Reported property is outside the expected inventory"})
            diagnostics.append("Unmapped FormalMC property %s reported %s" % (name, ", ".join(sorted(outcomes))))
            if "falsified" in outcomes:
                verdict = "failed"
            elif verdict == "passed":
                verdict = "inconclusive"
    return output, verdict, diagnostics


def copy_job_inputs(root, manifest, job, backend, destination):
    """Copy the complete hashed backend subtree; refuse unmanifested files."""
    key = "config" if backend == "sby" else "tcl"
    entry = PurePosixPath(job[backend][key])
    prefix = entry.parent.as_posix() + "/"
    source_dir = relative_path(root, entry.as_posix()).parent
    allowed = {name for name in manifest["files"] if name.startswith(prefix)}
    for path in source_dir.rglob("*"):
        if path.is_dir() and not path.is_symlink():
            continue
        name = path.relative_to(root).as_posix()
        if name not in allowed:
            raise InputError("Unmanifested backend input: " + name)
    for name in sorted(allowed):
        source = relative_path(root, name)
        target = destination.joinpath(*PurePosixPath(name[len(prefix):]).parts)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    for name in job[backend].get("sources", []):
        if not name.startswith(prefix):
            raise InputError("Backend source is outside its portable job directory: " + name)
    return destination / entry.name


def override_sby_timeout(path, seconds):
    """Change only the execution budget of a fresh copied config, never depth."""
    if not isinstance(seconds, int) or seconds <= 0:
        raise InputError("SBY timeout override must be a positive integer")
    original_hash = sha256(path)
    lines = read_text(path).splitlines()
    sections = [i for i, line in enumerate(lines) if line.strip() == "[options]"]
    if len(sections) != 1:
        raise InputError("SBY timeout override requires exactly one [options] section")
    start = sections[0] + 1
    end = next((i for i in range(start, len(lines)) if re.fullmatch(r"\s*\[.*\]\s*", lines[i])), len(lines))
    indices = [i for i in range(start, end) if re.match(r"\s*timeout\s+", lines[i])]
    if len(indices) > 1:
        raise InputError("Duplicate SBY timeout options")
    if indices:
        lines[indices[0]] = "timeout " + str(seconds)
    else:
        lines.insert(end, "timeout " + str(seconds))
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    return {"parameter": "sby.options.timeout", "seconds": seconds,
            "original_sha256": original_hash, "effective_sha256": sha256(path),
            "scope": "Fresh copied configuration only; proof depth, sources and assertions unchanged"}


def run_job(root, manifest, job, backend, executable, output, timeout, environment, sby_timeout=None):
    output.mkdir()
    inputs = output / "inputs"
    inputs.mkdir()
    entry = copy_job_inputs(root, manifest, job, backend, inputs)
    override = override_sby_timeout(entry, sby_timeout) if backend == "sby" and sby_timeout is not None else None
    work = output / "work"
    if backend == "sby":
        argv = [executable, "-d", str(work), str(entry)]
    else:
        argv = [executable, "-f", str(entry), "-override", "-work_dir", str(work)]
    result = execute(argv, inputs, output / "console.log", timeout, environment)
    result.update(id=job["id"], backend=backend, mode=job["mode"], depends_on=job.get("depends_on", []))
    result["effective_entry_sha256"] = sha256(entry)
    if override:
        result["input_overrides"] = [override]
    if result["execution_status"] != "completed":
        result.update(status=result["execution_status"], properties=[base_property(p) for p in job["properties"]])
    else:
        if backend == "sby":
            properties, status, diagnostics = parse_sby(work, job, result["returncode"])
        else:
            text = read_text(output / "console.log")
            # Reports must come from this freshly created job work tree.
            paths = sorted(output.rglob("avis.log"))
            result["additional_logs"] = [{"path": p.relative_to(output).as_posix(), "sha256": sha256(p)} for p in paths]
            for path in paths:
                if path.is_symlink() or output.resolve() not in path.resolve().parents:
                    raise InputError("FormalMC log escapes the fresh work directory")
                text += "\n" + read_text(path)
            properties, status, diagnostics = parse_formalmc(text, job, result["returncode"])
        result.update(properties=properties, status=status, diagnostics=diagnostics)
    save_json(output / "result.json", result)
    return result


def check_results(manifest, results):
    checks = []
    for check in manifest["checks"]:
        value = dict(check)
        result = results.get(check["job_id"])
        if check["kind"] == "assume":
            value.update(status="assumption", note="Environment constraint, not a proved checkpoint")
        elif result is None:
            value["status"] = "not_run"
        elif result["status"] == "blocked":
            value["status"] = "blocked"
        else:
            matches = [p for p in result.get("properties", []) if p["label"] == check["label"]]
            value["status"] = matches[0]["status"] if len(matches) == 1 else "missing"
            if result["status"] != "passed" and value["status"] in SUCCESS:
                value.update(property_status=value["status"], status="inconclusive")
        checks.append(value)
    by_id = {c["ck_id"]: c for c in checks}
    # Propagate unresolved assertion dependencies, including across aliases.
    for _ in range(len(checks)):
        changed = False
        for check in checks:
            if check["status"] not in SUCCESS:
                continue
            unresolved = [s for s in check.get("supporting_ck_ids", []) if by_id[s]["status"] != "proven"]
            if unresolved:
                check.update(property_status=check["status"], status="blocked", unresolved_ck_dependencies=unresolved)
                changed = True
        if not changed:
            break
    return checks


def configure(args):
    settings = {}
    if args.config:
        settings = json.loads(read_text(args.config))
        unknown = set(settings) - {"tool_paths", "environment", "timeout_seconds"}
        if unknown:
            raise InputError("Unknown runner configuration keys: " + ", ".join(sorted(unknown)))
    environment = dict(os.environ)
    for key, value in settings.get("environment", {}).items():
        if not isinstance(key, str) or not isinstance(value, str) or "=" in key or "\0" in key + value:
            raise InputError("Invalid environment override")
        environment[key] = value
    if args.tool_dir:
        environment["PATH"] = os.pathsep.join(str(Path(p).resolve()) for p in args.tool_dir) + os.pathsep + environment.get("PATH", "")
    default = "sby" if args.backend == "sby" else "FormalMC"
    env_name = "SBY_BIN" if args.backend == "sby" else "FORMALMC_BIN"
    requested = args.tool or settings.get("tool_paths", {}).get(args.backend) or environment.get(env_name) or default
    executable = shutil.which(requested, path=environment.get("PATH"))
    if executable is None:
        raise InputError("Tool not found: %s; set --tool or %s" % (requested, env_name))
    timeout = args.timeout if args.timeout is not None else settings.get("timeout_seconds", 14400)
    if not isinstance(timeout, (int, float)) or not 0 < timeout < float("inf"):
        raise InputError("timeout_seconds must be a positive finite number")
    return str(Path(executable).resolve()), float(timeout), environment


def preflight_tool(executable, backend, output, environment):
    option = "--version" if backend == "sby" else "-version"
    result = execute([executable, option], output, output / "tool_version.log", 30, environment)
    text = read_text(output / "tool_version.log")
    result["version_output"] = text[:8192]
    if result["execution_status"] != "completed" or result["returncode"] != 0 or not text.strip() or INFRA_ERROR.search(text):
        raise InputError("Tool version probe failed; inspect " + str(output / "tool_version.log"))
    return result


CAPABILITY_CASES = [
    {"id": "capability_immediate_safety", "mode": "prove", "expected_status": "passed",
     "properties": [{"label": "PORTABLE_IM_INITIAL", "kind": "assert"},
                    {"label": "PORTABLE_IM_CONSTANT", "kind": "assert"}],
     "body": """reg first = 1'b1;
reg [3:0] count = 4'b0;
reg [3:0] first_value;
reg [3:0] previous_value;
always @(posedge clk) begin
  first <= 1'b0;
  count <= count + 4'd1;
  previous_value <= arbitrary;
  if (first) first_value <= arbitrary;
end
always_comb begin
  if (!first) PORTABLE_IM_STABLE: assume (arbitrary == previous_value);
  if (first) PORTABLE_IM_INITIAL: assert (count == 4'd0);
  if (!first) PORTABLE_IM_CONSTANT: assert (arbitrary == first_value);
end
"""},
    {"id": "capability_immediate_negative", "mode": "prove", "expected_status": "failed",
     "properties": [{"label": "PORTABLE_IM_MUST_FAIL", "kind": "assert"}],
     "body": "always_comb begin PORTABLE_IM_MUST_FAIL: assert (arbitrary == 4'd0); end\n"},
    {"id": "capability_immediate_cover", "mode": "cover", "expected_status": "passed",
     "properties": [{"label": "PORTABLE_IM_NONZERO", "kind": "cover"},
                    {"label": "PORTABLE_IM_CONSTANT_COVER", "kind": "cover"}],
     "body": """reg first = 1'b1;
reg [3:0] count = 4'b0;
reg [3:0] previous_value;
always @(posedge clk) begin
  first <= 1'b0;
  count <= count + 4'd1;
  previous_value <= arbitrary;
end
always_comb begin
  if (!first) PORTABLE_IM_COVER_STABLE: assume (arbitrary == previous_value);
  if (first) PORTABLE_IM_NONZERO: cover (arbitrary == 4'ha && count == 4'd0);
  if (!first) PORTABLE_IM_CONSTANT_COVER: cover (count == 4'd3 && arbitrary == 4'ha);
end
"""},
    {"id": "capability_safety", "mode": "prove", "expected_status": "passed",
     "properties": [{"label": "PORTABLE_INITIAL", "kind": "assert"},
                    {"label": "PORTABLE_STEP", "kind": "assert"}],
     "body": """reg first = 1'b1;
reg [3:0] count = 4'b0;
always @(posedge clk) begin first <= 1'b0; count <= count + 4'd1; end
PORTABLE_INITIAL: assert property (@(posedge clk) first |-> count == 4'd0);
PORTABLE_STEP: assert property (@(posedge clk) !first |-> count == $past(count) + 4'd1);
"""},
    {"id": "capability_negative", "mode": "prove", "expected_status": "failed",
     "properties": [{"label": "PORTABLE_MUST_FAIL", "kind": "assert"}],
     "body": "PORTABLE_MUST_FAIL: assert property (@(posedge clk) arbitrary == 4'd0);\n"},
    {"id": "capability_cover", "mode": "cover", "expected_status": "passed",
     "properties": [{"label": "PORTABLE_NONZERO", "kind": "cover"},
                    {"label": "PORTABLE_INITIAL_COVER", "kind": "cover"}],
     "body": """reg first = 1'b1;
reg [3:0] count = 4'b0;
always @(posedge clk) begin first <= 1'b0; count <= count + 4'd1; end
PORTABLE_NONZERO: cover property (@(posedge clk) arbitrary == 4'ha);
PORTABLE_INITIAL_COVER: cover property (@(posedge clk) first && count == 4'd0);
"""},
]


def formal_capabilities(output, executable, timeout, environment):
    """Verify positive, known-false and reachable-cover outcomes on the target.

    This gates real FormalMC runs. Its success demonstrates these tiny tool
    capabilities only, never cmdbuf_rd correctness or full version support.
    """
    directory = output / "capabilities"
    directory.mkdir()
    results = []
    for case in CAPABILITY_CASES:
        destination = directory / case["id"]
        destination.mkdir()
        source = destination / "capability.sv"
        source.write_text("module PORTABLE_CAPABILITY(input wire clk, input wire [3:0] arbitrary);\n" +
                          case["body"] + "endmodule\n", encoding="utf-8")
        tcl = destination / "formal.tcl"
        tcl.write_text("set source_file [file join [file dirname [file normalize [info script]]] capability.sv]\n"
                       "read_design -top PORTABLE_CAPABILITY -sysv -mfcu [list $source_file]\n"
                       "def_clk clk\nprove\nshow_prop -summary\nexit\n", encoding="utf-8")
        work = destination / "work"
        process = execute([executable, "-f", str(tcl), "-override", "-work_dir", str(work)],
                          destination, destination / "console.log", min(timeout, 120), environment)
        text = read_text(destination / "console.log")
        logs = sorted(destination.rglob("avis.log"))
        for logfile in logs:
            if logfile.is_symlink() or destination.resolve() not in logfile.resolve().parents:
                raise InputError("Capability log escapes its fresh directory")
            text += "\n" + read_text(logfile)
        properties, status, diagnostics = parse_formalmc(text, case, process.get("returncode"))
        if process["execution_status"] != "completed":
            status = process["execution_status"]
        expected = {"assert": "falsified"} if case["expected_status"] == "failed" else {"assert": "proven", "cover": "covered"}
        accepted = status == case["expected_status"] and all(p["kind"] in expected and p["status"] == expected[p["kind"]] for p in properties)
        result = {"id": case["id"], "accepted": accepted, "status": status,
                  "expected_status": case["expected_status"], "properties": properties,
                  "process": process, "diagnostics": diagnostics,
                  "source_sha256": sha256(source), "tcl_sha256": sha256(tcl)}
        save_json(destination / "result.json", result)
        results.append(result)
    save_json(directory / "result.json", {"passed": all(r["accepted"] for r in results), "cases": results,
                                          "scope": "Target-tool capability check, not DUT proof"})
    return results


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--backend", choices=("sby", "formalmc"), default="sby")
    parser.add_argument("--manifest", type=Path, default=Path(__file__).resolve().with_name("manifest.json"))
    parser.add_argument("--config", type=Path, help="Optional target tool_paths/environment/timeout JSON")
    parser.add_argument("--tool", help="Executable path; overrides config and SBY_BIN/FORMALMC_BIN")
    parser.add_argument("--tool-dir", action="append", default=[], help="Prepend a tool directory to PATH (repeatable)")
    parser.add_argument("--timeout", type=float, help="Timeout seconds per proof job")
    parser.add_argument("--sby-timeout", type=int, help="Override SBY's internal timeout in each fresh config copy; leaves sources/depth unchanged")
    parser.add_argument("--output", type=Path, help="Parent of new result directory, default package/results")
    parser.add_argument("--job", action="append", help="Run named job(s) plus all transitive suppliers; repeatable")
    parser.add_argument("--list", action="store_true", help="Verify package hashes and list jobs, without a tool")
    parser.add_argument("--preflight", action="store_true", help="Verify hashes and probe tool version, without proofs")
    parser.add_argument("--self-test", action="store_true", help="FormalMC: run positive/negative/cover capability checks only")
    args = parser.parse_args(argv)
    output = None
    try:
        manifest, jobs = load_manifest(args.manifest)
        root = args.manifest.resolve().parent
        selected = selected_job_closure(jobs, manifest["checks"], args.job or list(jobs))
        if args.list:
            for name in selected:
                job = jobs[name]
                print("%s\t%s\t%s\tdepends=%s" % (name, job["mode"], job.get("top", ""), ",".join(job.get("depends_on", []))))
            return 0
        executable, timeout, environment = configure(args)
        if args.sby_timeout is not None and (args.backend != "sby" or args.sby_timeout <= 0):
            raise InputError("--sby-timeout requires the SBY backend and a positive integer")
        parent = (args.output or root / "results").resolve()
        # Never write results into a hashed backend/source subtree.
        for name in manifest["files"]:
            source_parent = relative_path(root, name).parent
            if parent == source_parent and parent != root or source_parent in parent.parents and source_parent != root:
                raise InputError("Output directory overlaps package inputs: " + str(parent))
        parent.mkdir(parents=True, exist_ok=True)
        run_id = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "_" + args.backend + "_" + uuid.uuid4().hex[:10]
        output = parent / run_id
        output.mkdir()
        report = {"schema_version": 1, "run_id": run_id, "backend": args.backend,
                  "evidence_type": "fresh_standalone_execution_not_ucagent_signed",
                  "runner_sha256": sha256(Path(__file__).resolve()),
                  "runner_arguments": list(argv if argv is not None else sys.argv[1:]),
                  "manifest_sha256": sha256(args.manifest), "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                  "python": sys.version, "selected_jobs": selected, "all_jobs_selected": set(selected) == set(jobs),
                  "requested_jobs": args.job or list(jobs), "sby_internal_timeout_override": args.sby_timeout,
                  "source_archive": manifest.get("source_archive"), "status": "running", "jobs": [], "checks": []}
        save_json(output / "result.json", report)
        report["tool_probe"] = preflight_tool(executable, args.backend, output, environment)
        if args.self_test and args.backend != "formalmc":
            raise InputError("--self-test is for the FormalMC target capability check; use tests/test_run.py for runner unit tests")
        if args.self_test and args.preflight:
            raise InputError("--self-test and --preflight are mutually exclusive")
        if args.preflight:
            report.update(status="preflight_passed", checks=check_results(manifest, {}),
                          note="Tool discovery and input integrity only; no RTL proof has run")
            save_json(output / "result.json", report)
            print(str(output / "result.json"))
            return 0
        if args.backend == "formalmc":
            report["capabilities"] = formal_capabilities(output, executable, timeout, environment)
            if not all(r["accepted"] for r in report["capabilities"]):
                report.update(status="capability_check_failed", checks=check_results(manifest, {}), full_suite_passed=False)
                save_json(output / "result.json", report)
                print("FormalMC capability checks did not pass; no DUT jobs were started. " + str(output / "result.json"))
                return 1
            if args.self_test:
                report.update(status="capability_check_passed", checks=check_results(manifest, {}), full_suite_passed=False,
                              note="Tool capabilities only; no cmdbuf_rd proof has run")
                save_json(output / "result.json", report)
                print(str(output / "result.json"))
                return 0
        results = {}
        for name in selected:
            verify_hashes(root, manifest)
            unresolved = [s for s in jobs[name].get("depends_on", []) if results[s]["status"] != "passed"]
            if unresolved:
                results[name] = {"id": name, "status": "blocked", "unresolved_jobs": unresolved,
                                 "properties": [base_property(p) for p in jobs[name]["properties"]]}
            else:
                print("Running %s (%s)..." % (name, args.backend), flush=True)
                results[name] = run_job(root, manifest, jobs[name], args.backend, executable,
                                        output / name, timeout, environment, args.sby_timeout)
            print("%s: %s" % (name, results[name]["status"]), flush=True)
            report.update(jobs=list(results.values()), checks=check_results(manifest, results))
            save_json(output / "result.json", report)
        verify_hashes(root, manifest)
        report["counts"] = dict(collections.Counter(c["status"] for c in report["checks"]))
        report["status"] = "passed" if all(r["status"] == "passed" for r in results.values()) else "incomplete"
        if any(c["job_id"] in results and c["kind"] != "assume" and c["status"] not in SUCCESS for c in report["checks"]):
            report["status"] = "incomplete"
        report["completed_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        report["full_suite_passed"] = (report["all_jobs_selected"] and report["status"] == "passed" and
                                       len(report["checks"]) == manifest["expected_counts"]["checks"])
        save_json(output / "result.json", report)
        print(str(output / "result.json"))
        return 0 if report["status"] == "passed" else 1
    except (InputError, OSError, ValueError, KeyError, TypeError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        if output is not None:
            save_json(output / "runner_error.json", {"status": "error", "diagnostic": str(error)})
            result_path = output / "result.json"
            if result_path.is_file():
                try:
                    partial = json.loads(read_text(result_path))
                    partial.update(status="error", full_suite_passed=False, diagnostic=str(error))
                    save_json(result_path, partial)
                except (OSError, ValueError):
                    pass
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
