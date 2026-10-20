#!/usr/bin/env python3
"""Prove old/new checker predicates equal without assuming any DUT property.

The compared outputs are the sampled Boolean values of all 202 expanded
assume/assert/cover instances on shared port histories. First require the old
and new history-update code to match, ignoring comments, formatting and the
documented event-name substitutions. No DUT is instantiated. This validates the
readability refactor, not the design or encrypted-target RTL equivalence.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
from property_catalog import properties, sampled_boolean, instance_paths

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


RENAMES = {"accept": "ar_fire", "success": "issue_fire", "retire": "r_fire",
           "due": "mem_capture_due", "due_e": "mem_capture_slot"}


def rename_events(text):
    for old, new in RENAMES.items():
        text = re.sub(r"\b" + old + r"\b", new, text)
    return text


def tokens(text):
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.DOTALL)
    return re.sub(r"\s+", "", rename_events(text))


def audit_history_updates(old, new):
    """Fail closed if refactoring changed the historical state-update code."""
    before_model = old[old.index("    reg [8:0] m_live"):old.index("    // Environment assumptions")]
    before_model += old[old.index("    // Independent scoreboard:"):old.index("    // DUT obligations:")]
    before_model += old[old.index("    // Covers confirm"):old.index("    `TP_COVER(C_RETRY")]
    before_source = old[old.index("        reg [1:0] bypass_count;"):]
    before_source = before_source[:before_source.index("    end endgenerate")]
    before_source = "\n".join(line for line in before_source.splitlines() if "`TP_" not in line)
    before_events = old[old.index("    wire accept"):old.index("    reg [8:0] m_live")]
    after_events = new[new.index("    wire ar_fire"):new.index("    // 参考状态")]
    before_history = old[old.index("    reg [3:0] last_pending;"):old.index("    // Covers confirm")]
    before_history = "\n".join(line for line in before_history.splitlines() if "`TP_" not in line)
    after_history = new[new.index("    reg [3:0] last_pending;"):new.index("    // x &")]
    # The one-assignment if/else is now surrounded by an explicit begin/end.
    without_blocks = lambda s: re.sub(r"\b(begin|end)\b", "", s)
    calendar = lambda s: re.search(r"wire \[3:0\] calendar_count\s*=(.*?);", s, re.DOTALL)[1]
    checks = {
        "transaction_model_and_cover_history": tokens(before_model) == tokens(
            (HERE / "cmdbuf_rd_reference_model.svh").read_text(encoding="utf-8")),
        "per_xau_fifo_and_cover_history": tokens(before_source) == tokens(
            (HERE / "cmdbuf_rd_xau_order_model.svh").read_text(encoding="utf-8")),
        "public_events": tokens(before_events) == tokens(after_events),
        "pending_port_history": tokens(without_blocks(before_history)) == tokens(without_blocks(after_history)),
        "return_calendar_count": tokens(calendar(old)) == tokens(calendar(new)),
    }
    if not all(checks.values()):
        raise ValueError("History update code changed: " + repr(checks))
    return checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--tools", type=Path, required=True)
    args = parser.parse_args()
    os.environ["PATH"] = str(args.tools) + os.pathsep + os.environ.get("PATH", "")
    args.output.mkdir(parents=True, exist_ok=False)
    old_path = args.baseline / "cmdbuf_rd_port_sva.sv"
    new_path = HERE / "cmdbuf_rd_port_sva.sv"
    old, new = old_path.read_text(encoding="utf-8"), new_path.read_text(encoding="utf-8")
    legacy = json.loads((args.baseline / "property_audit.json").read_text())["properties"]
    current = properties(new)
    by_label = {p["label"]: p for p in current}
    assert set(by_label) == {p["label"] for p in legacy}
    for p in legacy:
        q = by_label[p["label"]]
        assert all(p[k] == q[k] for k in ("kind", "instances", "dependency"))
    ordered = [path for p in sorted(current, key=lambda p: p["label"])
               for path in instance_paths(p)]
    assert len(ordered) == 202

    history_audit = audit_history_updates(old, new)
    (args.output / "state_update_audit.json").write_text(json.dumps(history_audit, indent=2)+"\n")
    old_by_label = {p["label"]: p for p in legacy}
    # Compare predicates on identical arbitrary histories. No environment or
    # DUT assumption is activated: all former properties become Boolean wires.
    for p in reversed(current):
        old_expr = rename_events(old_by_label[p["label"]]["expression"])
        wires = ("wire %s_before = (%s);\nwire %s_after = (%s);" %
                 (p["label"], old_expr, p["label"], sampled_boolean(p["expression"])))
        new = new[:p["start"]] + wires + new[p["end"]:]
    includes = ("cmdbuf_rd_reference_model.svh", "cmdbuf_rd_xau_order_model.svh")
    for name in includes:
        shutil.copyfile(HERE / name, args.output / name)
    assignments = "\n".join("    assign before_values[%d] = %s_before;\n"
                              "    assign after_values[%d] = %s_after;" % (i, path, i, path)
                              for i, path in enumerate(ordered))
    footer = """
    wire [201:0] before_values, after_values;
""" + assignments + """
    // No assume: compare obligations even when arbitrary inputs violate them.
    Q_ALL_PREDICATES_EQUAL: assert property (
        @(posedge clk) disable iff (!rst_n)
        before_values == after_values
    );
endmodule
"""
    top = new.replace("module cmdbuf_rd_port_sva", "module checker_equivalence", 1)
    top = top.replace("endmodule", footer, 1)
    (args.output / "checker_equivalence.sv").write_text(top, encoding="utf-8")
    files = ["checker_equivalence.sv"] + list(includes)
    sby = """[options]
mode prove
depth 12
timeout 180

[engines]
abc pdr

[script]
read_slang --top checker_equivalence --no-implicit-memories -I . checker_equivalence.sv
prep -top checker_equivalence -flatten
async2sync
dffunmap
chformal -lower
opt -full
sim -clock clk -resetn rst_n -rstlen 1 -n 1 -w -vcd reset_initialization.vcd

[files]
""" + "\n".join(files) + "\n"
    (args.output / "run.sby").write_text(sby, encoding="utf-8")
    manifest = {"baseline_checker_sha256": sha(old_path),
                "readable_checker_sha256": sha(new_path),
                "properties": ordered,
                "files": {p: sha(args.output / p) for p in files},
                "baseline_property_audit_sha256": sha(args.baseline / "property_audit.json")}
    (args.output / "inputs.json").write_text(json.dumps(manifest, indent=2)+"\n")
    start = time.time()
    with (args.output / "console.log").open("w", encoding="utf-8") as log:
        proc = subprocess.run(["sby", "run.sby"], cwd=str(args.output),
                              stdout=log, stderr=subprocess.STDOUT)
    status_path = args.output / "run/status"
    result = dict(status=status_path.read_text().strip() if status_path.exists() else "NO_STATUS",
                  returncode=proc.returncode, elapsed_seconds=round(time.time()-start, 2),
                  compared_instances=len(ordered), assumptions=0,
                  history_updates_unchanged=all(history_audit.values()),
                  scope="Two-state sampled predicates on shared histories, with history-update token equivalence; no DUT instantiated.")
    (args.output / "result.json").write_text(json.dumps(result, indent=2)+"\n")
    print(json.dumps(result), flush=True)
    return int(not result["status"].startswith("PASS"))


if __name__ == "__main__":
    raise SystemExit(main())
