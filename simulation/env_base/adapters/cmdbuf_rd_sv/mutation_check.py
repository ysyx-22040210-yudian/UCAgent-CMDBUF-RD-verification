#!/usr/bin/env python3
"""Check that current port-based tests reject the superseded RTL rules."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
BASE = HERE.parent.parent
ROOT = BASE.parent.parent
CHANGES = [
    ("retry_bubble", "20_retry_single.case", [
        ("candidate_mask = window_mask & bank_idle_mask;",
         "candidate_mask = window_mask & bank_idle_mask & ~current_issue_mask;")]),
    ("registered_count", "23_pending_delta.case", [
        ("assign pending_cnt = rst_n ? (pending_q + {3'b0, alloc_fire}\n"
         "                                            - {3'b0, issue_success}) : 4'b0;",
         "assign pending_cnt = pending_q;"),
        ("pending_q <= pending_cnt;",
         "pending_q <= pending_q + {3'b0,alloc_fire} - {3'b0,issue_success};")]),
    ("transposed_status", "24_all_bank_halves.case", [
        ("!rd_mem_status[addr_q[i][5:3]][addr_q[i][6]]",
         "!rd_mem_status[addr_q[i][6:4]][addr_q[i][3]]")]),
    ("late_refill", "22_nonhead_refill.case", [
        ("rank_pool = pending_mask & ~success_mask;", "rank_pool = pending_mask;"),
        ("candidate_mask = window_mask & bank_idle_mask;",
         "candidate_mask = window_mask & bank_idle_mask & ~success_mask;")]),
    ("busy_cancels_request", "01_pipeline.case", [
        ("assign req = (rst_n && issue_valid_q)",
         "assign req = (rst_n && issue_valid_q && !rd_mem_status[issue_bank_q][issue_addr_q[0]])")]),
    ("cap_only", "12_capacity_440.case", [
        ("((occ_after[x] == 0) || (shared_after < 6))", "(occ_after[x] < 7)")]),
]


def job(change, output):
    name, case, edits = change
    folder = output / name
    rtl = folder / "rtl"
    rtl.mkdir(parents=True, exist_ok=False)
    for p in (ROOT / "rtl").glob("*.sv"):
        shutil.copyfile(str(p), str(rtl / p.name))
    target = rtl / "cmdbuf_rd_cmd.sv"
    text = target.read_text(encoding="utf-8")
    for old, new in edits:
        if text.count(old) != 1:
            raise RuntimeError("Mutation no longer matches exactly once: " + name)
        text = text.replace(old, new)
    target.write_text(text, encoding="utf-8")
    cmd = ["make", "-f", str(BASE / "env/Makefile"),
           "PROJECT_CONFIG=" + str(BASE / "projects/cmdbuf_rd_sv.mk"),
           "RTL_ROOT=" + str(folder),
           "PARAM_ARGS=--language 1800-2017 -DSYNTHESIS -Wno-fatal",
           "CASE=" + str(BASE / "cases/cmdbuf_rd_sv" / case), "run-case"]
    with (folder / "console.log").open("w", encoding="utf-8") as stream:
        run = subprocess.run(cmd, stdout=stream, stderr=subprocess.STDOUT)
    log = (folder / "console.log").read_text(encoding="utf-8")
    # A build error is NOT a successful detection.
    failures = [line for line in log.splitlines() if "CHECK_FAILED " in line]
    record = dict(name=name, case=case, detected=bool(failures) and run.returncode != 0,
                  failure=failures, returncode=run.returncode,
                  mutant_sha256=hashlib.sha256(target.read_bytes()).hexdigest())
    (folder / "result.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(record), flush=True)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=2)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(lambda item: job(item, args.output), CHANGES))
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    return int(any(not item["detected"] for item in results))


if __name__ == "__main__":
    raise SystemExit(main())
