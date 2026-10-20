#!/usr/bin/env python3
"""Collect the readable-native-SVA regression without rewriting old evidence."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import tarfile
from property_catalog import properties

ROOT = Path(__file__).resolve().parent.parent.parent


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def save(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    formal = ROOT / "build/formal_02"
    sim = ROOT / "build/readability/simulation"
    mutations = ROOT / "build/order_mutations_01"
    equivalence = ROOT / "build/equivalence_02"
    runs, injected = read(formal/"results.json"), read(mutations/"results.json")
    cases = {p.stem: read(p) for p in sorted(sim.glob("*.json")) if p.name != "regression.json"}
    checker = ROOT/"formal/protocol_20261021/cmdbuf_rd_port_sva.sv"
    props = properties(checker.read_text(encoding="utf-8"))
    for p in props:
        p.pop("start")
        p.pop("end")
    counts = {k: sum(p["instances"] for p in props if p["kind"] == k)
              for k in ("assume", "assert", "cover")}
    assert counts == {"assume": 11, "assert": 145, "cover": 46}
    baseline = read(ROOT/"baseline/property_audit.json")["properties"]
    assert {(p["label"], p["kind"], p["instances"], p["dependency"]) for p in props} == {
        (p["label"], p["kind"], p["instances"], p["dependency"]) for p in baseline}
    audit = dict(source=checker.relative_to(ROOT).as_posix(), source_sha256=sha(checker),
                 properties=props, instances=counts, labels=len(props),
                 dut_assertion_instances=sum(p["instances"] for p in props
                                            if p["kind"] == "assert" and p["dependency"] != "MODEL_SELF_CHECK"),
                 model_self_check_instances=sum(p["instances"] for p in props
                                                if p["dependency"] == "MODEL_SELF_CHECK"),
                 labels_and_dependencies_unchanged=True)
    save(args.output/"property_audit.json", audit)
    elaborated = {}
    for job in runs:
        text = (formal/job["name"]/"run/model/design_prep.il").read_text(encoding="utf-8")
        elaborated[job["name"]] = {k: len(re.findall(r"cell \$"+k+r"\b", text))
                                   for k in ("assert", "assume", "cover")}
    assert elaborated == {
        "protocol_prove": {"assert": 3, "assume": 11, "cover": 0},
        "all_bmc": {"assert": 145, "assume": 11, "cover": 0},
        "corrections_cover": {"assert": 0, "assume": 11, "cover": 46},
    }
    cover_log = (formal/"corrections_cover/run/logfile.txt").read_text(encoding="utf-8")
    hits = [dict(step=int(step), property=prop) for step, prop in
            re.findall(r"Reached cover statement in step (\d+) at (.+)", cover_log)]
    assert len(hits) == 46
    save(args.output/"cover_hits.json", hits)
    save(args.output/"mutations.json", injected)
    save(args.output/"simulation_cases.json", cases)
    equal = read(equivalence/"result.json")
    history = read(equivalence/"state_update_audit.json")
    assert equal["status"].startswith("PASS") and equal["compared_instances"] == 202
    assert all(history.values())
    save(args.output/"checker_equivalence.json", dict(result=equal, state_update_audit=history))
    lowering = read(formal/"all_bmc/sby_lowering.json")
    assert len(lowering["changed_properties"]) == 25
    save(args.output/"sby_lowering.json", lowering)
    coverage = {}
    for c in cases.values():
        for key, value in c["coverage"].items():
            coverage[key] = coverage.get(key, 0)+value
    earlier = {
        "native_frontend_attempt": read(ROOT/"build/formal_01/results.json"),
        "separate_histories_equivalence_attempt": read(ROOT/"build/equivalence_01/result.json"),
    }
    summary = dict(
        date="2026-10-21", vm_workspace=str(ROOT),
        scope="Readable native SVA; unchanged RTL, property labels, environment obligations and history updates.",
        formal=dict(jobs=runs, elaborated_properties=elaborated,
                    cover_hits=len(hits), last_cover_step=max(h["step"] for h in hits)),
        checker_equivalence=equal, history_update_audit=history,
        sby_adaptation=dict(converted_labels=len(lowering["changed_properties"]),
                            rule=lowering["rule"], native_source_kept=True),
        simulation=dict(total=len(cases), passed=sum(c["status"] == "pass" for c in cases.values()),
                        cycles=sum(c["cycles"] for c in cases.values()),
                        checks=sum(c["checks"] for c in cases.values()),
                        accepted=coverage["accepted"], retired=coverage["retired"],
                        native_sva=True, coverage=coverage),
        mutations=dict(total=len(injected), detected=sum(m["detected"] for m in injected)),
        compile=read(ROOT/"build/compile_01/results.json"),
        earlier_attempts=earlier,
        limitations=[
            "Only the three baseline DUT interface properties have an unbounded proof in this run.",
            "The all-assertion DUT run is a 10-step BMC, not an unbounded proof of all design properties.",
            "Checker equivalence compares two-state sampled predicates on shared histories after a state-update token audit; not encrypted-target RTL equivalence.",
            "The VM SBY frontend needs generated Boolean lowering of single-sample |->; Verilator compiles the human-readable native source directly.",
            "No actual FormalMC 2024 execution was performed.",
        ],
    )
    save(args.output/"summary.json", summary)
    sources = []
    for directory in ("rtl", "formal/protocol_20261021",
                      "simulation/env_base/adapters/cmdbuf_rd_sv",
                      "simulation/env_base/cases/cmdbuf_rd_sv"):
        sources += [p for p in (ROOT/directory).glob("*") if p.is_file()
                    and (directory != "rtl" or p.suffix in (".sv", ".f"))]
    sources += [ROOT/p for p in ("simulation/env_base/projects/cmdbuf_rd_sva.mk",
                                 "simulation/env_base/projects/cmdbuf_rd_sv.mk",
                                 "simulation/env_base/env/Makefile",
                                 "simulation/env_base/scripts/run_cases.py")]
    save(args.output/"source_manifest.json", {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(sources)})
    files = set(sources)
    for directory in (formal, sim, mutations, equivalence, ROOT/"baseline",
                      ROOT/"build/equivalence_01", ROOT/"build/formal_01",
                      ROOT/"build/frontend_probe", ROOT/"build/compile_01"):
        files.update(p for p in directory.rglob("*") if p.is_file())
    files.update((ROOT/"build").glob("*.log"))
    save(args.output/"evidence_manifest.json", {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(files)})
    archive = args.output/"vm_evidence.tar.gz"
    with tarfile.open(str(archive), "w:gz") as tf:
        for p in sorted(files):
            tf.add(str(p), arcname=p.relative_to(ROOT).as_posix(), recursive=False)
    (args.output/"vm_evidence.sha256").write_text(sha(archive)+"  vm_evidence.tar.gz\n", encoding="ascii")
    print(json.dumps(dict(properties=counts, checker_equivalence=equal["status"],
                         simulation=summary["simulation"]["passed"], mutations=summary["mutations"],
                         archive_bytes=archive.stat().st_size)), flush=True)
    return int(any(not j["status"].startswith("PASS") for j in runs)
               or len(cases) != 33 or any(c["status"] != "pass" for c in cases.values())
               or len(injected) != 7 or any(not m["detected"] for m in injected))


if __name__ == "__main__":
    raise SystemExit(main())
