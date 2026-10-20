#!/usr/bin/env python3
"""Collect this revision's VM results without changing historical evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tarfile

ROOT = Path(__file__).resolve().parent.parent.parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    sim = ROOT / "build/protocol_20261021/simulation"
    formal = ROOT / "build/formal_final"
    mutations = ROOT / "build/mutations_01"
    compilation = ROOT / "build/compilation"
    cases = [read(p) for p in sorted(sim.glob("*.json")) if p.name != "regression.json"]
    runs = read(formal / "results.json")
    injected = read(mutations / "results.json")
    coverage = {}
    for case in cases:
        for key, value in case["coverage"].items():
            coverage[key] = coverage.get(key, 0) + value
    counts = {}
    for run in runs:
        text = (formal / run["name"] / "run/model/design_prep.il").read_text(encoding="utf-8")
        counts[run["name"]] = {kind: len(re.findall(r"cell \$" + kind + r"\b", text))
                               for kind in ("assert", "assume", "cover")}
    source_dirs = [
        "rtl", "formal/protocol_20261021",
        "simulation/env_base/adapters/cmdbuf_rd_sv",
        "simulation/env_base/cases/cmdbuf_rd_sv",
    ]
    sources = []
    for folder in source_dirs:
        sources += [p for p in (ROOT / folder).glob("*") if p.is_file()
                    and (folder != "rtl" or p.suffix in (".sv", ".f"))]
    sources += [ROOT / "simulation/env_base/projects/cmdbuf_rd_sv.mk"]
    manifest = {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(sources)}
    (args.output / "source_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    summary = {
        "revision": "2026-10-21", "rtl_entry": "rtl/files.f",
        "vm_workspace": str(ROOT),
        "compilation": read(compilation / "results.json"),
        "simulation": {
            "passed": sum(c["status"] == "pass" for c in cases), "total": len(cases),
            "cycles": sum(c["cycles"] for c in cases),
            "checks": sum(c["checks"] for c in cases),
            "accepted": coverage["accepted"], "retired": coverage["retired"],
            "coverage_events": coverage,
        },
        "formal": {"jobs": runs, "elaborated_properties": counts,
                   "bmc_note": "118 assertion instances include 19 DUT obligations and 99 reference-model self-checks; 10 sampled steps, not unbounded proof.",
                   "base_assumptions": "First sampled reset, subsequent release; legal src/arresp when arvalid; zero arready implies no arvalid; 8 same-cycle success-implies-busy assumptions.",
                   "covers": "All 31 current correction cover instances reached under the base assumptions; no PERF always-idle assumptions.",
                   "backend": "SBY with native SystemVerilog read_slang frontend; no replacement flat-port RTL."},
        "mutations": {"detected": sum(c["detected"] for c in injected), "total": len(injected), "cases": injected},
        "earlier_attempts": {
            "formal_01": "Frontend rejected $onehot0; replaced checker expression with width-explicit equivalent.",
            "formal_02": "SMT backend loop from inferred checker memory; disabled implicit memory inference in the SV frontend.",
            "formal_03": "All-assertion depth-12 BMC TIMEOUT at 240-second limit; protocol proof and covers passed. Full logs preserved.",
        },
        "limitations": [
            "No new equivalence check against the target encrypted RTL.",
            "No actual FormalMC 2024 execution on target equipment.",
            "Only five named protocol properties have unbounded proof; full functional unbounded proof is not claimed.",
            "This is a corrected-specification regression, not reclosure of the historical 200-testpoint / 1415-cover catalog.",
            "RR initialization, idle/error payload defaults and reset details retain the previous implementation choices pending target alignment.",
        ],
    }
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    files = set(sources)
    files.update(p for p in sim.rglob("*") if p.is_file())
    files.update(p for p in formal.rglob("*") if p.is_file())
    files.update(p for p in compilation.rglob("*") if p.is_file() and p.suffix != ".vvp")
    files.add(ROOT / "regression.log")
    files.add(ROOT / "build/native_sva_compile_final.log")
    for folder in ("formal_01", "formal_02", "formal_03"):
        for p in (ROOT / "build" / folder).rglob("*"):
            if p.is_file() and (p.suffix in (".sv", ".svh", ".sby", ".json", ".log", ".txt")
                               or p.name in ("status", "PASS", "ERROR", "TIMEOUT")):
                files.add(p)
    for p in mutations.rglob("*"):
        if p.is_file() and (p.suffix in (".sv", ".json", ".log", ".vcd")):
            files.add(p)
    members = {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(files)}
    (args.output / "evidence_manifest.json").write_text(json.dumps(members, indent=2) + "\n", encoding="utf-8")
    archive = args.output / "vm_evidence.tar.gz"
    with tarfile.open(str(archive), "w:gz") as tf:
        for p in sorted(files):
            tf.add(str(p), arcname=p.relative_to(ROOT).as_posix(), recursive=False)
    (args.output / "vm_evidence.sha256").write_text(sha(archive) + "  vm_evidence.tar.gz\n", encoding="ascii")
    print(json.dumps({"cases": len(cases), "cycles": summary["simulation"]["cycles"],
                      "checks": summary["simulation"]["checks"], "cover_instances": counts["corrections_cover"]["cover"],
                      "mutations_detected": summary["mutations"]["detected"],
                      "archive_bytes": archive.stat().st_size}), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
