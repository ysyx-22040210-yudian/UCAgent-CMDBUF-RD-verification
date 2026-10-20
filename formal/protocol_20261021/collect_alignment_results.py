#!/usr/bin/env python3
"""Collect the reset-disabled / valid-payload-only SVA run independently."""
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


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n",
                    encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--formal", type=Path, default=Path("build/formal_03"))
    args = parser.parse_args()
    formal = ROOT / args.formal
    sim = ROOT / "build/sva_alignment/simulation"
    args.output.mkdir(parents=True, exist_ok=False)
    runs = read(formal / "results.json")
    cases = [read(p) for p in sorted(sim.glob("*.json"))
             if p.name != "regression.json"]
    counts = {}
    for run in runs:
        text = (formal / run["name"] / "run/model/design_prep.il").read_text(encoding="utf-8")
        counts[run["name"]] = {kind: len(re.findall(r"cell \$" + kind + r"\b", text))
                               for kind in ("assert", "assume", "cover")}
    expected = {
        "protocol_prove": {"assert": 3, "assume": 11, "cover": 0},
        "all_bmc": {"assert": 115, "assume": 11, "cover": 0},
        "corrections_cover": {"assert": 0, "assume": 11, "cover": 31},
    }
    if counts != expected:
        raise RuntimeError("Unexpected elaborated property counts: " + str(counts))
    checker = ROOT / "formal/protocol_20261021/cmdbuf_rd_port_sva.sv"
    macros = checker.with_name("cmdbuf_rd_port_macros.svh")
    text = checker.read_text(encoding="utf-8")
    if re.search(r"\b(started|active|previous_reset)\b", text):
        raise RuntimeError("Removed reset/startup state has reappeared")
    native = macros.read_text(encoding="utf-8").split("`elsif CMDBUF_NATIVE_SVA\n")[1].split("`else\n")[0]
    if native.count("@(posedge clk) disable iff (!rst_n)") != 3:
        raise RuntimeError("Native property clock/reset gates differ")
    multiplicity = {"E06_SUCCESS_BUSY": 8, "A_RR_BOUND": 3,
                    "M_AGE_RANGE": 9, "M_CALENDAR": 9, "M_AGE_UNIQUE": 72,
                    "C_SUCCESS_BUSY_TARGET": 16}
    properties = []
    for line_no, line in enumerate(text.splitlines(), 1):
        m = re.search(r"`TP_(ASSUME|ASSERT|COVER)\((\w+),\s*(.*)\)", line)
        if not m:
            continue
        label = m.group(2)
        tags = re.findall(r"\[(NO_REF_MODEL_PORTS|NO_REF_MODEL_HISTORY|REF_MODEL|MODEL_SELF_CHECK)\]", line)
        if not tags:
            raise RuntimeError("Missing dependency label on " + label)
        properties.append({"kind": m.group(1).lower(), "label": label,
                           "line": line_no, "expression": m.group(3),
                           "dependency": tags[0],
                           "instances": multiplicity.get(label, 1)})
    audit = {
        "clock_and_disable": "@(posedge clk) disable iff (!rst_n)",
        "checker_sha256": sha(checker), "macros_sha256": sha(macros),
        "startup_or_reset_sequence_assumptions": False,
        "idle_payload_assertions": False,
        "rr": {"initial_source": 0, "scan": [0, 1, 2],
               "advance": "winner + 1 modulo 3 after actual R; hold otherwise"},
        "properties": properties,
        "assumption_instances": sum(p["instances"] for p in properties if p["kind"] == "assume"),
        "dut_assertion_instances": sum(p["instances"] for p in properties
                                      if p["kind"] == "assert" and p["dependency"] != "MODEL_SELF_CHECK"),
        "model_self_check_instances": sum(p["instances"] for p in properties
                                         if p["kind"] == "assert" and p["dependency"] == "MODEL_SELF_CHECK"),
    }
    save(args.output / "assumptions_assertions.json", audit)

    # Record what actual reset simulation produced; never force unknown bits to zero.
    initial = (formal / "all_bmc/run/model/design.il").read_text(encoding="utf-8")
    init_values = re.findall(r"attribute \\init (.+)", initial)
    initialization = {
        "method": "Yosys sim -clock clk -resetn rst_n -rstlen 1 -n 1 -w",
        "reset_waveform": "build/formal_03/all_bmc/run/src/reset_initialization.vcd",
        "init_attribute_count": len(init_values),
        "unknown_valued_attributes": sum("x" in v for v in init_values),
        "arbitrary_zero_initialization": False,
        "reset_assume_after_initialization": False,
        "scope": "Proof starts from the state established by reset; not arbitrary power-up state. rst_n is subsequently unconstrained.",
    }
    save(args.output / "initialization.json", initialization)
    cover_log = (formal / "corrections_cover/run/logfile.txt").read_text(encoding="utf-8")
    hits = re.findall(r"Reached cover statement in step (\d+) at (.+)", cover_log)
    if len(hits) != 31:
        raise RuntimeError("Expected 31 actual cover hits, found " + str(len(hits)))
    save(args.output / "cover_hits.json",
         [{"step": int(step), "property": prop} for step, prop in hits])
    coverage = {}
    for case in cases:
        for key, value in case["coverage"].items():
            coverage[key] = coverage.get(key, 0) + value
    summary = {
        "revision": "2026-10-21 SVA alignment after user clarification",
        "vm_workspace": str(ROOT), "rtl_entry": "rtl/files.f",
        "native_sva": True,
        "formal": {"jobs": runs, "elaborated_properties": counts,
                   "dut_assertion_instances": audit["dut_assertion_instances"],
                   "model_self_check_instances": audit["model_self_check_instances"],
                   "cover_hits": len(hits), "last_cover_step": max(int(s) for s, _ in hits),
                   "initialization": initialization},
        "simulation": {
            "passed": sum(c["status"] == "pass" for c in cases), "total": len(cases),
            "cycles": sum(c["cycles"] for c in cases),
            "cpp_oracle_checks": sum(c["checks"] for c in cases),
            "accepted": coverage["accepted"], "retired": coverage["retired"],
            "coverage_events": coverage,
            "tool": "Verilator 5.051 devel v5.050-99-gf8fb1d664 (mod)",
            "checker_exercise": "Nonzero idle arb_addr/R payload and illegal ordinary-protocol values during reset are injected only at checker inputs.",
            "command": "LIBRARY_PATH=<workspace>/build/link_lib make -f simulation/env_base/env/Makefile PROJECT_CONFIG=simulation/env_base/projects/cmdbuf_rd_sva.mk VERILATOR=<oss-cad-suite>/bin/verilator BUILD_DIR=<workspace>/build/sva_alignment/verilator_5051 run-all",
            "vm_link_workaround": "Project-local libatomic.so symlink to installed /usr/lib64/libatomic.so.1; no system files changed.",
        },
        "earlier_attempts": {
            "formal_01": "ERROR: frontend rejected combined async reset condition in bypass counter; reset branch separated.",
            "formal_final": "ERROR: reset simulator did not accept $check cells; chformal -lower now runs before sim.",
            "native_sva_04.log": "Verilator 5.024 C++ sampled-unpacked-array code generation error.",
            "native_sva_05.log": "Verilator 5.051 generated code successfully; link failed due to missing libatomic development symlink.",
            "native_sva_06.log": "Same Verilator 5.051 generated code linked with existing runtime library; 27 cases passed.",
        },
        "limits": [
            "Only A_REQ_ONEHOT, A_R_ONEHOT, A_R_READY have unbounded proof in this run.",
            "All 115 assertions passed depth-10 BMC; this does not prove full functional behavior for unbounded time.",
            "The 99 model self-checks do not inspect or prove physical DUT storage clearing.",
            "31 correction covers do not reclose the historical 200-testpoint / 1415-bin catalog.",
            "No actual FormalMC 2024 execution or encrypted-target equivalence check in this run.",
            "No eventual grant, idle bank, rready, upstream fairness, or unconditional completion assumption.",
            "No dedicated reset verification is claimed; disable iff suppresses properties during reset.",
        ],
    }
    save(args.output / "summary.json", summary)
    sources = []
    for folder in ("rtl", "formal/protocol_20261021",
                   "simulation/env_base/adapters/cmdbuf_rd_sv",
                   "simulation/env_base/cases/cmdbuf_rd_sv"):
        sources += [p for p in (ROOT / folder).glob("*") if p.is_file()
                    and (folder != "rtl" or p.suffix in (".sv", ".f"))]
    sources += [ROOT / "simulation/env_base/projects/cmdbuf_rd_sva.mk",
                ROOT / "simulation/env_base/env/Makefile",
                ROOT / "simulation/env_base/scripts/run_cases.py"]
    save(args.output / "source_manifest.json",
         {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(sources)})
    files = set(sources)
    files.update(p for p in sim.rglob("*") if p.is_file())
    files.update(p for p in formal.rglob("*") if p.is_file())
    files.update(p for p in (ROOT / "build").glob("*.log") if p.is_file())
    files.add(ROOT / "regression.log")
    for folder in ("formal_01", "formal_final"):
        for p in (ROOT / "build" / folder).rglob("*"):
            if p.is_file() and (p.suffix in (".sv", ".svh", ".sby", ".json", ".log", ".txt", ".vcd")
                               or p.name in ("status", "PASS", "ERROR", "TIMEOUT")):
                files.add(p)
    save(args.output / "evidence_manifest.json",
         {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(files)})
    archive = args.output / "vm_evidence.tar.gz"
    with tarfile.open(str(archive), "w:gz") as tf:
        for p in sorted(files):
            tf.add(str(p), arcname=p.relative_to(ROOT).as_posix(), recursive=False)
    (args.output / "vm_evidence.sha256").write_text(sha(archive) + "  vm_evidence.tar.gz\n", encoding="ascii")
    print(json.dumps({"formal": counts, "simulation_cases": len(cases),
                      "evidence_files": len(files), "archive_bytes": archive.stat().st_size}), flush=True)
    return int(any(not r["status"].startswith("PASS") for r in runs)
               or any(c["status"] != "pass" for c in cases))


if __name__ == "__main__":
    raise SystemExit(main())
