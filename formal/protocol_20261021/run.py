#!/usr/bin/env python3
"""Run the revised SV DUT directly through Yosys read_slang and SBY.

No flattened replacement RTL, internal DUT observations, or old proof results.
Requires a Yosys build with read_slang and SBY/ABC/Yices on PATH.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
from property_catalog import select_assertions, lower_overlapping_implications

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
PROTOCOL = [
    "A_REQ_ONEHOT", "A_R_ONEHOT", "A_R_READY",
]
JOBS = [
    dict(name="protocol_prove", mode="prove", depth=12, engine="abc pdr",
         assertions=PROTOCOL, timeout=120),
    dict(name="all_bmc", mode="bmc", depth=10, engine="abc bmc3",
         assertions=None, timeout=360),
    dict(name="corrections_cover", mode="cover", depth=24, engine="smtbmc yices",
         assertions=None, timeout=240),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_job(cfg, output):
    folder = output / cfg["name"]
    folder.mkdir(parents=True, exist_ok=False)
    source_files = [ROOT / "rtl" / (name + ".sv") for name in
                    ("cmdbuf_rd", "cmdbuf_rd_cmd", "cmdbuf_rd_otb")]
    source_files += [HERE / name for name in
                     ("cmdbuf_rd_port_sva.sv", "cmdbuf_rd_reference_model.svh",
                      "cmdbuf_rd_xau_order_model.svh", "formal_top.sv")]
    manifest = {}
    for src in source_files:
        dst = folder / src.name
        shutil.copyfile(str(src), str(dst))
        mutation = cfg.get("mutation")
        if mutation and src.name == mutation["file"]:
            content = dst.read_text(encoding="utf-8")
            if content.count(mutation["before"]) != 1:
                raise RuntimeError("Mutation anchor must occur exactly once")
            dst.write_text(content.replace(mutation["before"], mutation["after"]),
                           encoding="utf-8")
        manifest[src.name] = {"source": str(src.relative_to(ROOT)), "sha256": sha(src),
                              "executed_sha256": sha(dst)}
    checker = folder / "cmdbuf_rd_port_sva.sv"
    # Retain the exact human-readable native input as well as the executed copy.
    shutil.copyfile(str(checker), str(folder / "native_checker.sv"))
    if cfg["assertions"] is not None:
        # Change only the selected property set. No assumption is added.
        text = checker.read_text(encoding="utf-8")
        checker.write_text(select_assertions(text, cfg["assertions"]), encoding="utf-8")
    text, lowering = lower_overlapping_implications(checker.read_text(encoding="utf-8"))
    checker.write_text(text, encoding="utf-8")
    (folder / "sby_lowering.json").write_text(json.dumps({
        "reason": "Installed VM read_slang does not accept overlapping implication.",
        "rule": "Single-sample A |-> B becomes (!A || B), with clock/disable unchanged.",
        "source": "native_checker.sv", "executed": checker.name,
        "changed_properties": lowering,
    }, indent=2) + "\n", encoding="utf-8")
    manifest["sby_lowering_sha256"] = sha(folder / "sby_lowering.json")
    manifest["executed_checker_sha256"] = sha(checker)
    manifest["initial_state"] = "Actual reset simulation writes initial state; no -zinit and no reset-sequence assume. After initialization rst_n is unconstrained."
    (folder / "inputs.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    names = [p.name for p in source_files if p.suffix == ".sv"]
    script = ("read_slang --top cmdbuf_rd_formal --no-implicit-memories -D SYNTHESIS -I . " + " ".join(names) +
              "\nprep -top cmdbuf_rd_formal\n"
              "async2sync\ndffunmap\nchformal -lower\n"
              "sim -clock clk -resetn rst_n -rstlen 1 -n 1 -w -vcd reset_initialization.vcd\n")
    sby = "[options]\nmode {mode}\ndepth {depth}\ntimeout {timeout}\n".format(**cfg)
    sby += "\n[engines]\n" + cfg["engine"] + "\n\n[script]\n" + script
    sby += "\n[files]\n" + "\n".join(p.name for p in source_files) + "\n"
    (folder / "run.sby").write_text(sby, encoding="utf-8")
    start = time.time()
    with (folder / "console.log").open("w", encoding="utf-8") as log:
        proc = subprocess.run(["sby", "run.sby"], cwd=str(folder),
                              stdout=log, stderr=subprocess.STDOUT)
    status_file = folder / "run/status"
    status = status_file.read_text().strip() if status_file.exists() else "NO_STATUS"
    record = dict(cfg, status=status, returncode=proc.returncode,
                  elapsed_seconds=round(time.time() - start, 2),
                  inputs_sha256=sha(folder / "inputs.json"))
    (folder / "result.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record), flush=True)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tools", type=Path, help="SBY/Yosys tool bin directory")
    parser.add_argument("--only", choices=[j["name"] for j in JOBS])
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    if args.tools:
        os.environ["PATH"] = str(args.tools) + os.pathsep + os.environ.get("PATH", "")
    args.output.mkdir(parents=True, exist_ok=False)
    selected = [j for j in JOBS if not args.only or j["name"] == args.only]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda c: run_job(c, args.output), selected))
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    return int(any(not r["status"].startswith("PASS") for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
