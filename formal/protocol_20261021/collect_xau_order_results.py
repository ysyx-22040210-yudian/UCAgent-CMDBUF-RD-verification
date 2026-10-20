#!/usr/bin/env python3
"""Archive the explicit per-XAU response-order checks and their actual evidence."""
import argparse
import json
from pathlib import Path
import re
import tarfile
from collect_alignment_results import ROOT, read, save, sha


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--formal", type=Path, default=Path("build/formal_01"))
    parser.add_argument("--mutations", type=Path, default=Path("build/order_mutations_01"))
    parser.add_argument("--bmc", type=Path, help="Replacement all_bmc job folder; retain the earlier attempt")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    formal, mutations = ROOT / args.formal, ROOT / args.mutations
    sim = ROOT / "build/xau_order/simulation"
    original_runs = read(formal / "results.json")
    runs, injected = list(original_runs), read(mutations / "results.json")
    job_paths = {r["name"]: formal / r["name"] for r in runs}
    if args.bmc:
        job_paths["all_bmc"] = ROOT / args.bmc
        runs = [read(job_paths["all_bmc"] / "result.json") if r["name"] == "all_bmc" else r
                for r in runs]
    cases = {p.stem: read(p) for p in sorted(sim.glob("*.json")) if p.name != "regression.json"}
    checker = ROOT / "formal/protocol_20261021/cmdbuf_rd_port_sva.sv"
    text = checker.read_text(encoding="utf-8")
    if re.search(r"\b(started|active|previous_reset)\b", text):
        raise RuntimeError("Forbidden startup flag reintroduced")
    props = []
    multiple = {"E06_SUCCESS_BUSY": 8, "A_RR_BOUND": 3, "M_AGE_RANGE": 9,
                "M_CALENDAR": 9, "M_AGE_UNIQUE": 72, "C_SUCCESS_BUSY_TARGET": 16}
    for line_no, line in enumerate(text.splitlines(), 1):
        m = re.search(r"`TP_(ASSUME|ASSERT|COVER)\((\w+),\s*(.*)\)", line)
        if not m:
            continue
        kind, label, expression = m.groups()
        dep = re.findall(r"\[(NO_REF_MODEL_PORTS|NO_REF_MODEL_HISTORY|REF_MODEL|MODEL_SELF_CHECK)\]", line)
        if not dep:
            raise RuntimeError("Unclassified property " + label)
        instances = 3 if re.match(r"[AMC]_XAU_", label) else multiple.get(label, 1)
        props.append(dict(kind=kind.lower(), label=label, expression=expression,
                          dependency=dep[0], instances=instances, line=line_no))
    audit = {
        "source": str(checker.relative_to(ROOT)), "source_sha256": sha(checker),
        "properties": props, "clock_and_disable": "@(posedge clk) disable iff (!rst_n)",
        "new_assumptions": [],
        "assumption_instances": sum(p["instances"] for p in props if p["kind"] == "assume"),
        "dut_assertion_instances": sum(p["instances"] for p in props if p["kind"] == "assert" and p["dependency"] != "MODEL_SELF_CHECK"),
        "model_self_check_instances": sum(p["instances"] for p in props if p["kind"] == "assert" and p["dependency"] == "MODEL_SELF_CHECK"),
        "new_order_assertion_instances": sum(p["instances"] for p in props if p["label"].startswith("A_XAU_")),
    }
    assert (audit["assumption_instances"], audit["dut_assertion_instances"],
            audit["model_self_check_instances"], audit["new_order_assertion_instances"]) == (11, 40, 105, 24)
    save(args.output / "property_audit.json", audit)
    counts = {}
    for job in runs:
        il = (job_paths[job["name"]] / "run/model/design_prep.il").read_text(encoding="utf-8")
        counts[job["name"]] = {k: len(re.findall(r"cell \$" + k + r"\b", il))
                              for k in ("assert", "assume", "cover")}
    assert counts["all_bmc"] == {"assert": 145, "assume": 11, "cover": 0}
    assert counts["corrections_cover"] == {"assert": 0, "assume": 11, "cover": 46}
    cover_log = (formal / "corrections_cover/run/logfile.txt").read_text(encoding="utf-8")
    hits = [dict(step=int(s), property=p) for s, p in
            re.findall(r"Reached cover statement in step (\d+) at (.+)", cover_log)]
    assert len(hits) == 46 and sum("C_XAU_" in h["property"] for h in hits) == 15
    save(args.output / "cover_hits.json", hits)

    # These event records are printed after each actual-output/oracle comparison.
    # Preserve the raw log as well as the machine-readable sequence.
    sequences = {}
    pattern = (r"ORDER_EVENT cycle=(\d+) event=(\w+) command=(\d+) xau=(\d+) "
               r"addr=(\d+) raddr=(\d+) id=(\d+) port=(\d+) rresp=(\d+) data=([0-9a-f:]+)")
    fields = ["cycle", "event", "command", "xau", "addr", "raddr", "id", "port", "rresp", "data"]
    for name, case in cases.items():
        if not case["type"].startswith("xau_order_312"):
            continue
        events = []
        for match in re.findall(pattern, (sim / (name + ".log")).read_text(encoding="utf-8")):
            events.append({k: (v if k in ("event", "data") else int(v))
                           for k, v in zip(fields, match)})
        source = case["seed"] % 3
        groups = {event: [r for r in events if r["event"] == event and r["xau"] == source]
                  for event in ("AR", "ISSUE", "MEM", "R")}
        order = {event: [r["command"] for r in rows] for event, rows in groups.items()}
        assert order == {"AR": [1, 2, 3], "ISSUE": [3, 1, 2], "MEM": [3, 1, 2], "R": [1, 2, 3]}
        for command in (1, 2, 3):
            ar = next(r for r in groups["AR"] if r["command"] == command)
            mem = next(r for r in groups["MEM"] if r["command"] == command)
            response = next(r for r in groups["R"] if r["command"] == command)
            assert all(response[k] == ar[k] for k in ("raddr", "id", "port"))
            assert all(response[k] == mem[k] for k in ("data", "rresp"))
        if "repeat" in name:
            assert len({(r["raddr"], r["id"], r["port"]) for r in groups["AR"]}) == 1
            assert len({r["data"] for r in groups["MEM"]}) == 3
        sequences[name] = dict(xau=source, order=order, events=events,
                               payloads_checked=True, status=case["status"])
    assert len(sequences) == 6
    save(args.output / "directed_sequences.json", sequences)
    save(args.output / "mutations.json", injected)
    cov = {}
    for case in cases.values():
        for k, v in case["coverage"].items():
            cov[k] = cov.get(k, 0) + v
    summary = {
        "date": "2026-10-21", "vm_workspace": str(ROOT),
        "scope": "Explicit per-XAU acceptance-order FIFO; no RTL behavior change and no new assume.",
        "formal": dict(jobs=runs, elaborated_properties=counts,
                       job_paths={k: v.relative_to(ROOT).as_posix() for k, v in job_paths.items()},
                       earlier_attempts=original_runs if args.bmc else [],
                       cover_hits=len(hits), new_order_covers=15,
                       last_cover_step=max(h["step"] for h in hits)),
        "simulation": dict(total=len(cases),
                           passed=sum(c["status"] == "pass" for c in cases.values()),
                           cycles=sum(c["cycles"] for c in cases.values()),
                           checks=sum(c["checks"] for c in cases.values()),
                           accepted=cov["accepted"], retired=cov["retired"],
                           new_directed_cases=len(sequences), coverage=cov),
        "mutations": dict(total=len(injected), detected=sum(m["detected"] for m in injected)),
        "initialization": "Actual reset simulation writes initial state; all native properties disable iff (!rst_n); no startup flag or reset-sequence assume.",
        "limitations": [
            "Only the three baseline interface properties have an unbounded proof in this run.",
            "New response-order assertions have bounded checks and directed simulation, not an unbounded proof.",
            "Cover witnesses demonstrate reachability, not universal correctness.",
            "Physical DUT entry identity and clearing are not directly observed; indistinguishable complete output tuples cannot expose an internal swap by ports alone.",
            "R address is the specified three-bit raddr=original araddr[2:0], not an added 18-bit output.",
            "No actual FormalMC 2024 execution or encrypted-target equivalence check.",
        ],
    }
    save(args.output / "summary.json", summary)
    sources = []
    for folder in ("rtl", "formal/protocol_20261021",
                   "simulation/env_base/adapters/cmdbuf_rd_sv",
                   "simulation/env_base/cases/cmdbuf_rd_sv"):
        sources.extend(p for p in (ROOT / folder).glob("*") if p.is_file()
                       and (folder != "rtl" or p.suffix in (".sv", ".f")))
    sources += [ROOT / p for p in ("simulation/env_base/projects/cmdbuf_rd_sva.mk",
                                   "simulation/env_base/projects/cmdbuf_rd_sv.mk",
                                   "simulation/env_base/env/Makefile",
                                   "simulation/env_base/scripts/run_cases.py")]
    save(args.output / "source_manifest.json",
         {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(sources)})
    files = set(sources)
    for folder in (sim, formal, mutations):
        files.update(p for p in folder.rglob("*") if p.is_file())
    if args.bmc:
        files.update(p for p in (ROOT / args.bmc).rglob("*") if p.is_file())
    files.update(p for p in (ROOT / "build").glob("*.log") if p.is_file())
    save(args.output / "evidence_manifest.json",
         {p.relative_to(ROOT).as_posix(): sha(p) for p in sorted(files)})
    archive = args.output / "vm_evidence.tar.gz"
    with tarfile.open(str(archive), "w:gz") as tf:
        for p in sorted(files):
            tf.add(str(p), arcname=p.relative_to(ROOT).as_posix(), recursive=False)
    (args.output / "vm_evidence.sha256").write_text(sha(archive) + "  vm_evidence.tar.gz\n",
                                                  encoding="ascii")
    print(json.dumps(dict(properties=counts, simulation=summary["simulation"]["passed"],
                          mutations=summary["mutations"], evidence_files=len(files),
                          archive_bytes=archive.stat().st_size)), flush=True)
    return int(any(not j["status"].startswith("PASS") for j in runs) or
               any(c["status"] != "pass" for c in cases.values()) or
               any(not m["detected"] for m in injected))


if __name__ == "__main__":
    raise SystemExit(main())
