#!/usr/bin/env python3
"""Cross-check a zero-init candidate with fresh SBY executions on the development VM.

This validates emitted model behavior with SBY, not target FormalMC acceptance.
All output is written to a fresh directory outside sealed input subtrees.
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET


def sha(path):
    """Hash the bytes actually passed to a frontend or solver."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    """Require complete, uniquely identified results for every generated model."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--sby", required=True)
    parser.add_argument("--tool-dir", required=True)
    parser.add_argument("--timeout", type=int, default=1200)
    parser.add_argument("--job", action="append", help="Validate only named models for a targeted retry")
    parser.add_argument("--sby-timeout", type=int, help="Override only the fresh SBY timeout, retaining depth and properties")
    args = parser.parse_args()
    package, out = args.package.resolve(strict=True), args.output.resolve()
    if out.exists() or package == out or package in out.parents:
        raise ValueError("Use a fresh output directory outside the sealed package")
    out.mkdir(parents=True)
    spec = importlib.util.spec_from_file_location("candidate_runner", package / "run.py")
    runner = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(runner)
    manifest, jobs = runner.load_manifest(package / "manifest.json")
    report = {"suite": "formalmc2024_zero_init_models_via_sby", "formalmc_executed": False,
              "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "manifest_sha256": sha(package / "manifest.json"), "runs": []}
    environment = dict(os.environ, PATH=args.tool_dir + ":" + os.environ.get("PATH", ""))
    selected = [job for job in manifest["jobs"] if not args.job or job["id"] in args.job]
    if args.job and set(args.job) != {job["id"] for job in selected}:
        raise ValueError("Unknown selected model")
    for job in selected:
        name = job["id"]
        directory = out / name
        inputs = directory / "inputs"
        shutil.copytree(package / "jobs" / name / "formalmc", inputs)
        source_config_sha = sha(inputs / "validate.sby")
        if args.sby_timeout is not None:
            if args.sby_timeout <= 0:
                raise ValueError("SBY timeout must be positive")
            config = inputs / "validate.sby"
            text, count = re.subn(r"^timeout \d+$", "timeout " + str(args.sby_timeout), config.read_text(), flags=re.MULTILINE)
            if count != 1:
                raise ValueError("Expected one SBY timeout option")
            config.write_text(text)
        command = [args.sby, "-d", str(directory / "work"), str(inputs / "validate.sby")]
        row = {"id": name, "mode": job["mode"], "command": command,
               "model_sha256": sha(inputs / "model.sv"), "config_sha256": sha(inputs / "validate.sby"),
               "source_config_sha256": source_config_sha, "sby_timeout_override": args.sby_timeout}
        print("START " + name, flush=True)
        with (directory / "console.log").open("w") as log:
            try:
                result = subprocess.run(command, cwd=inputs, env=environment, stdout=log,
                                        stderr=subprocess.STDOUT, timeout=args.timeout)
                row["returncode"] = result.returncode
            except subprocess.TimeoutExpired:
                row["returncode"] = 124
        status = directory / "work/status"
        row["raw_status"] = status.read_text().strip() if status.exists() else "missing"
        kind = "assert" if job["mode"] == "prove" else "cover"
        wanted = {p["formalmc_label"] for p in job["properties"] if p["kind"] == kind}
        xml = directory / "work/validate.xml"
        observed = {}
        if xml.exists():
            for case in ET.parse(xml).findall(".//testcase"):
                if case.get("type", "").lower() != kind:
                    continue
                observed.setdefault(case.get("id"), []).append({
                    "failure": case.find("failure") is not None, "error": case.find("error") is not None,
                    "skipped": case.find("skipped") is not None})
        good = {label for label, states in observed.items()
                if len(states) == 1 and not any(states[0].values())}
        row.update(expected_count=len(wanted), observed_count=len(observed),
                   missing_labels=sorted(wanted - good), unexpected_labels=sorted(set(observed) - wanted),
                   properties=observed)
        row["passed"] = (row["returncode"] == 0 and row["raw_status"].split()[0] == "PASS" and
                         good == wanted and set(observed) == wanted)
        report["runs"].append(row)
        (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
        print("DONE " + name + " passed=" + str(row["passed"]) + " properties=" + str(len(good)), flush=True)
    report["selected_passed"] = len(report["runs"]) == len(selected) and all(r["passed"] for r in report["runs"])
    report["all_passed"] = len(report["runs"]) == len(jobs) and report["selected_passed"]
    report["finished_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"all_passed": report["all_passed"], "models": len(report["runs"]),
                      "formalmc_executed": False}), flush=True)
    return 0 if report["selected_passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
