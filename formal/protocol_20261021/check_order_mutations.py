#!/usr/bin/env python3
"""Require actual SBY counterexamples from the newly named per-XAU assertions."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import re
import run

ORDER_ASSERTIONS = [
    "A_XAU_R_HAS_PENDING", "A_XAU_R_HEAD_COMPLETE", "A_XAU_R_NO_EARLY_BYPASS",
    "A_XAU_R_ADDR_ORDER", "A_XAU_R_ID_ORDER", "A_XAU_R_PORT_ORDER",
    "A_XAU_R_DATA_ORDER", "A_XAU_R_RESP_ORDER",
]
MUTANTS = [
    dict(name="skip_incomplete_head", file="cmdbuf_rd_cmd.sv",
         before="src_mask[x][i] = valid_q[i] && (src_q[i] == x[1:0]);",
         after="src_mask[x][i] = valid_q[i] && done_q[i] && (src_q[i] == x[1:0]);",
         expected=["A_XAU_R_HEAD_COMPLETE", "A_XAU_R_NO_EARLY_BYPASS"]),
    dict(name="younger_completed_bundle", file="cmdbuf_rd_cmd.sv",
         before="rsp_entry = head_entry[winner];",
         after=("rsp_entry = head_entry[winner];\n"
                "            for(offset=0;offset<ENTRIES;offset=offset+1)\n"
                "                if(valid_q[offset] && done_q[offset] && src_q[offset]==winner &&\n"
                "                   older_q[offset][head_entry[winner]]) rsp_entry=offset[3:0];"),
         expected=["A_XAU_R_ADDR_ORDER", "A_XAU_R_ID_ORDER",
                   "A_XAU_R_PORT_ORDER", "A_XAU_R_DATA_ORDER", "A_XAU_R_RESP_ORDER"]),
    dict(name="wrong_raddr", file="cmdbuf_rd_cmd.sv",
         before="raddr = addr_q[rsp_entry][2:0];",
         after="raddr = addr_q[rsp_entry][2:0] ^ 3'b001;",
         expected=["A_XAU_R_ADDR_ORDER"]),
    dict(name="wrong_rid", file="cmdbuf_rd_cmd.sv",
         before="rid = id_q[rsp_entry];",
         after="rid = id_q[rsp_entry] ^ 8'h01;",
         expected=["A_XAU_R_ID_ORDER"]),
    dict(name="wrong_port", file="cmdbuf_rd_cmd.sv",
         before="r_port_id = port_q[rsp_entry];",
         after="r_port_id = port_q[rsp_entry] ^ 5'b00001;",
         expected=["A_XAU_R_PORT_ORDER"]),
    dict(name="wrong_data", file="cmdbuf_rd.sv",
         before="assign rdata = (|rvalid) ? rsp_data : 128'b0;",
         after="assign rdata = (|rvalid) ? (rsp_data ^ 128'b1) : 128'b0;",
         expected=["A_XAU_R_DATA_ORDER"]),
    dict(name="wrong_error", file="cmdbuf_rd_cmd.sv",
         before="else if (rsp_pc_err)\n                rresp = 2'b01;",
         after="else if (rsp_pc_err)\n                rresp = 2'b00;",
         expected=["A_XAU_R_RESP_ORDER"]),
]


def execute(mutant, output):
    cfg = dict(name=mutant["name"], mode="bmc", depth=12,
               engine="smtbmc yices", assertions=ORDER_ASSERTIONS,
               timeout=240, mutation=mutant)
    result = run.run_job(cfg, output)
    log = (output / mutant["name"] / "run/logfile.txt").read_text(encoding="utf-8")
    failures = re.findall(r"Assert failed in (.+)", log)
    named = [name for name in ORDER_ASSERTIONS
             if any(name in failure for failure in failures)]
    traces = list((output / mutant["name"] / "run/engine_0").glob("trace*.vcd"))
    detected = (result["status"].startswith("FAIL") and bool(traces) and
                any(name in named for name in mutant["expected"]))
    return dict(name=mutant["name"], detected=detected,
                expected=mutant["expected"], failed_order_assertions=named,
                counterexamples=[str(p.relative_to(output)) for p in traces],
                run=result)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tools", type=Path, required=True)
    args = parser.parse_args()
    os.environ["PATH"] = str(args.tools) + os.pathsep + os.environ.get("PATH", "")
    args.output.mkdir(parents=True, exist_ok=False)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda m: execute(m, args.output), MUTANTS))
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n",
                                              encoding="utf-8")
    print(json.dumps({"detected": sum(r["detected"] for r in results),
                      "total": len(results)}), flush=True)
    return int(any(not r["detected"] for r in results))


if __name__ == "__main__":
    raise SystemExit(main())
