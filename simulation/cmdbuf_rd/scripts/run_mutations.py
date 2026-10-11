#!/usr/bin/env python3
"""Isolated, exact-fragment RTL mutations; compatible with Python 3.6."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time


# Each anchor was reviewed against the actual RTL; --manifest may override.
DEFAULT_MUTATIONS = [
    {"id": "M01", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "rank_count[i] < 5", "after": "rank_count[i] < 9",
     "purpose": "错误扩大最老五条窗口，允许第六条绕过阻塞窗口"},
    {"id": "M02", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "assign issue_success = |(req & ar_rd_gnt & rw_rd_gnt);",
     "after": "assign issue_success = |(req & (ar_rd_gnt | rw_rd_gnt));",
     "purpose": "将双 grant 同时命中错误放宽为任一 grant 命中"},
    {"id": "M03", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "success_mask = issue_success ? current_issue_mask : 9'b0;",
     "after": "success_mask = (issue_success && !issue_valid_q) ? current_issue_mask : 9'b0;",
     "purpose": "关闭 6B 成功当拍窗口前馈"},
    {"id": "M04", "file": "rtl/cmdbuf_rd.sv",
     "before": ".retire_entry, .issue_success, .issue_entry, .capture_valid,",
     "after": ".retire_entry, .issue_success(issue_success || (|req)), .issue_entry, .capture_valid,",
     "purpose": "仅发 req 即启动 OTB 返回 token，失败请求也被计入"},
    {"id": "M05", "file": "rtl/cmdbuf_rd_otb.sv",
     "before": "assign capture_valid = rst_n && ret_valid_q[3];",
     "after": "assign capture_valid = rst_n && (ret_valid_q[3] || ret_valid_q[2]);",
     "purpose": "固定四拍捕获错误多使用提前一拍的 tap，导致早采样或重复捕获"},
    {"id": "M06", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "((occ_after[x] == 0) || (shared_after < 6));",
     "after": "((occ_after[x] == 0) || (shared_after < 9));",
     "purpose": "放宽共享额度，破坏每来源一项容量保底"},
    {"id": "M07", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "r_candidate[x] = done_q[head_entry[x]] && rready[x];",
     "after": "r_candidate[x] = done_q[head_entry[x]];",
     "purpose": "响应候选忽略当拍 rready"},
    {"id": "M08", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "((older_q[i] & src_mask[x]) == 9'b0);",
     "after": "((older_q[i] & src_mask[x] & done_q) == 9'b0) && done_q[i];",
     "purpose": "仅在完成项中找来源队头，跳过同来源更老的未完成命令"},
    {"id": "M09", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "if (arresp_q[rsp_entry] == 2'b11)\n                rresp = 2'b11;\n            else if (rsp_pc_err)\n                rresp = 2'b01;",
     "after": "if (rsp_pc_err)\n                rresp = 2'b01;\n            else if (arresp_q[rsp_entry] == 2'b11)\n                rresp = 2'b11;",
     "purpose": "错误地让奇偶异常覆盖地址越界异常"},
    {"id": "M10", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "issue_valid_q <= select_valid;",
     "after": "issue_valid_q <= select_valid && !(issue_valid_q && !issue_success);",
     "purpose": "违反 5A，在当前请求失败时丢弃同拍预选的下一命令"},
    {"id": "M11", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "if (retire_fire && (winner == 2'(x))) occ_after[x] = occ_after[x] - 1;",
     "after": "if (retire_fire && (winner == 2'(x))) occ_after[x] = occ_after[x];",
     "purpose": "关闭 10B 准入的退休前馈，满表时多停一拍"},
    {"id": "M12", "file": "rtl/cmdbuf_rd_cmd.sv",
     "before": "!(addr_q[i][6] ? rd_mem_status[1][addr_q[i][5:3]] : rd_mem_status[0][addr_q[i][5:3]]);",
     "after": "!(addr_q[i][6] ? rd_mem_status[0][addr_q[i][5:3]] : rd_mem_status[1][addr_q[i][5:3]]);",
     "purpose": "反转命令选择时的奇偶 Bank 状态索引"},
]


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def execute(command, log, timeout):
    started = time.monotonic()
    timed_out = False
    with log.open("w", encoding="utf-8") as stream:
        stream.write("COMMAND " + json.dumps(command) + "\n")
        stream.flush()
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT,
                                   universal_newlines=True, start_new_session=True)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            # Terminate the whole make/compiler/simulator process group.
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            code = process.returncode
    return {"command": command, "returncode": code, "timeout": timed_out,
            "seconds": round(time.monotonic() - started, 3), "log": str(log)}


def inspect_cases(result_dir, case_files):
    records = []
    for case in case_files:
        path = result_dir / (case.stem + ".json")
        record = {"case": case.name, "result": str(path)}
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            record.update({"status": data.get("status"),
                           "checks_failed": data.get("checks_failed", 0),
                           "failure": data.get("failure", "")})
            if record["status"] == "fail" and int(record["checks_failed"]) > 0:
                record["checker_failure"] = True
                record["detection_kind"] = "scoreboard"
            elif record["status"] != "pass":
                record["infrastructure_error"] = True
        except (OSError, ValueError, TypeError) as exc:
            # Verilator $fatal exits before the C++ harness can write JSON.
            # Accept only an explicit source-level assertion message, not abort alone.
            log_path = result_dir / (case.stem + ".log")
            if not log_path.is_file() and len(case_files) == 1:
                log_path = result_dir / "run.log"
            log = log_path.read_text(encoding="utf-8", errors="replace") if log_path.is_file() else ""
            assertion = re.search(r"%(?:Error|Fatal):[^\n]*\.sv:\d+:[^\n]*Assertion failed in[^\n]*", log)
            if assertion:
                record.update({"status": "fail", "checker_failure": True,
                               "detection_kind": "rtl_assertion", "failure": assertion.group(0),
                               "evidence_log": str(log_path)})
            else:
                record.update({"infrastructure_error": True, "error": str(exc)})
        records.append(record)
    return records


def check_tree_unchanged(root, expected):
    observed = {str(p.relative_to(root)): sha256(p) for p in sorted(root.rglob("*.sv"))}
    if observed != expected:
        raise RuntimeError("Baseline RTL changed during the mutation campaign; results are not comparable")


def check_files_unchanged(expected):
    for name, digest in expected.items():
        if sha256(Path(name)) != digest:
            raise RuntimeError("Verification input changed during the mutation campaign: " + name)


def snapshot(source, destination, allowed_parent):
    # Only this campaign's known .../<id>/rtl snapshot may be replaced.
    if destination.name != "rtl" or destination.parent.resolve() != allowed_parent.resolve():
        raise ValueError("Unsafe snapshot target")
    if destination.is_symlink() or allowed_parent.is_symlink():
        raise ValueError("Refusing symlink snapshot target")
    if destination.exists():
        shutil.rmtree(str(destination))
    shutil.copytree(str(source), str(destination))


def make_command(args, root, build, results, target):
    command = ["make", "-f", str(args.env / "env/Makefile"),
               "PROJECT_CONFIG=" + str(args.project), "RTL_ROOT=" + str(root),
               "BUILD_DIR=" + str(build), "RESULT_DIR=" + str(results),
               "CASE_DIR=" + str(args.cases), "HARNESS_FILES=" + str(args.harness),
               "JOBS=" + str(args.jobs)]
    if args.case:
        command.append("CASE=" + str(args.cases / args.case))
    return command + [target]


def run_one(args, root, name, case_files):
    build = root / "build" / args.run_id
    results = root / "results" / args.run_id
    results.mkdir(parents=True, exist_ok=False)
    record = {"id": name, "rtl_root": str(root), "result_dir": str(results)}
    record["build"] = execute(make_command(args, root, build, results, "build"),
                              results / "build.log", args.build_timeout)
    if record["build"]["returncode"] != 0 or record["build"]["timeout"]:
        record["status"] = "compile_error"
    else:
        target = "run-case" if args.case else "run-all"
        record["run"] = execute(make_command(args, root, build, results, target),
                                results / "run.log", args.run_timeout)
        record["cases"] = inspect_cases(results, case_files)
        record["detecting_cases"] = [c["case"] for c in record["cases"] if c.get("checker_failure")]
        record["detection_kinds"] = sorted(set(c["detection_kind"] for c in record["cases"]
                                                if c.get("checker_failure")))
        record["first_detection"] = next((c for c in record["cases"] if c.get("checker_failure")), None)
        errors = any(c.get("infrastructure_error") for c in record["cases"])
        if record["run"]["timeout"] or errors:
            record["status"] = "runtime_error"
        elif record["detecting_cases"] and record["run"]["returncode"] != 0:
            record["status"] = "killed"
        elif record["run"]["returncode"] == 0 and all(c["status"] == "pass" for c in record["cases"]):
            record["status"] = "survived"
        else:
            record["status"] = "runtime_error"
    write_json(results / "mutation_result.json", record)
    print(name + ": " + record["status"], flush=True)
    return record


def apply_mutation(root, mutation):
    relative = Path(mutation["file"])
    if relative.is_absolute() or ".." in relative.parts or relative.parts[0] != "rtl":
        raise ValueError("Mutation file must be a relative path beneath rtl/")
    path = root / relative
    before, after = mutation["before"], mutation["after"]
    if not before or before == after:
        raise ValueError("Mutation must change a nonempty exact fragment")
    content = path.read_text(encoding="utf-8")
    count = content.count(before)
    if count != 1:
        raise ValueError("Expected one exact fragment in %s, observed %d" % (relative, count))
    old_hash = sha256(path)
    path.write_text(content.replace(before, after, 1), encoding="utf-8")
    return {"file": str(relative), "before": before, "after": after,
            "baseline_sha256": old_hash, "mutant_sha256": sha256(path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=Path, default=Path("/root/cmdbuf_rd"))
    parser.add_argument("--env", type=Path, default=Path("/root/env_base"))
    parser.add_argument("--project", type=Path, default=Path("/root/env_base/projects/cmdbuf_rd.mk"))
    parser.add_argument("--harness", type=Path, default=Path("/root/env_base/adapters/cmdbuf_rd/cmdbuf_rd_harness.cpp"))
    parser.add_argument("--cases", type=Path, default=Path("/root/env_base/cases/cmdbuf_rd"))
    parser.add_argument("--case", help="Run one named .case file instead of the complete regression")
    parser.add_argument("--manifest", type=Path, help="JSON list, or object with a mutations list")
    parser.add_argument("--only", help="Comma-separated mutation IDs")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--build-timeout", type=int, default=300)
    parser.add_argument("--run-timeout", type=int, default=300)
    parser.add_argument("--run-id", default=datetime.datetime.utcnow().strftime("%Y%m%dT%H%M%S%fZ"))
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    for name in ("workspace", "env", "project", "cases", "harness"):
        setattr(args, name, getattr(args, name).resolve())
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.run_id):
        parser.error("run-id must contain only letters, digits, underscore or hyphen")
    mutations = DEFAULT_MUTATIONS
    if args.manifest:
        mutations = json.loads(args.manifest.read_text(encoding="utf-8"))
        if isinstance(mutations, dict):
            mutations = mutations["mutations"]
    ids = [m["id"] for m in mutations]
    if len(set(ids)) != len(ids) or any(not re.fullmatch(r"M[0-9]{2,3}", x) for x in ids):
        parser.error("Mutation IDs must be distinct M01-style names")
    if args.only:
        selected = set(args.only.split(","))
        if selected - set(ids):
            parser.error("Unknown mutation IDs: " + ",".join(sorted(selected - set(ids))))
        mutations = [m for m in mutations if m["id"] in selected]
    if args.list:
        print(json.dumps(mutations, ensure_ascii=True, indent=2))
        return 0
    if not mutations:
        parser.error("No exact-fragment mutations configured")
    if args.case and (Path(args.case).name != args.case or not args.case.endswith(".case")):
        parser.error("--case must be a plain .case filename")
    case_files = [args.cases / args.case] if args.case else sorted(args.cases.glob("*.case"))
    if not case_files or any(not p.is_file() for p in case_files):
        parser.error("No selected case files found")
    source = args.workspace / "rtl"
    expected = {str(p.relative_to(source)): sha256(p) for p in sorted(source.rglob("*.sv"))}
    if not expected:
        parser.error("Baseline RTL is missing")
    campaign = args.workspace / "mutations"
    summary_path = campaign / "campaigns" / args.run_id / "summary.json"
    verification = summary_path.parent / "verification"
    verification.mkdir(parents=True, exist_ok=False)
    frozen_cases = verification / "cases"
    frozen_cases.mkdir()
    snapshots = []
    for original in [args.project, args.harness] + case_files:
        destination = (frozen_cases / original.name) if original in case_files else (verification / original.name)
        shutil.copy2(str(original), str(destination))
        snapshots.append({"original": str(original), "snapshot": str(destination), "sha256": sha256(destination)})
    args.project = verification / args.project.name
    args.harness = verification / args.harness.name
    args.cases = frozen_cases
    case_files = [frozen_cases / p.name for p in case_files]
    verification_hashes = {item["snapshot"]: item["sha256"] for item in snapshots}
    environment_hashes = {str(p): sha256(p) for p in
                          (args.env / "env/Makefile", args.env / "scripts/run_cases.py")}
    summary = {"run_id": args.run_id, "status": "running", "baseline_hashes": expected,
               "verification_snapshots": snapshots, "environment_hashes": environment_hashes,
               "scope": "Selected exact-fragment mutations; not the complete fault catalogue",
               "selected_cases": [p.name for p in case_files], "mutations": []}
    baseline_root = campaign / "BASELINE"
    baseline_root.mkdir(parents=True, exist_ok=True)
    snapshot(source, baseline_root / "rtl", baseline_root)
    baseline = run_one(args, baseline_root, "BASELINE", case_files)
    baseline["raw_status"] = baseline["status"]
    baseline["status"] = "passed" if baseline["status"] == "survived" else "failed"
    write_json(Path(baseline["result_dir"]) / "mutation_result.json", baseline)
    summary["baseline"] = baseline
    write_json(summary_path, summary)
    if baseline["status"] != "passed":
        summary["status"] = "baseline_failed"
        write_json(summary_path, summary)
        print("Baseline did not pass; no mutants executed. Summary: " + str(summary_path))
        return 1
    for mutation in mutations:
        check_tree_unchanged(source, expected)
        check_files_unchanged(verification_hashes)
        check_files_unchanged(environment_hashes)
        root = campaign / mutation["id"]
        root.mkdir(parents=True, exist_ok=True)
        try:
            snapshot(source, root / "rtl", root)
            applied = apply_mutation(root, mutation)
            record = run_one(args, root, mutation["id"], case_files)
            record["change"] = applied
            record["purpose"] = mutation.get("purpose", "")
            write_json(Path(record["result_dir"]) / "mutation_result.json", record)
        except (OSError, ValueError) as exc:
            record = {"id": mutation["id"], "status": "mutation_error", "error": str(exc)}
            print(mutation["id"] + ": mutation_error: " + str(exc), flush=True)
        summary["mutations"].append(record)
        summary["counts"] = {s: sum(r["status"] == s for r in summary["mutations"])
                             for s in ("killed", "survived", "compile_error", "runtime_error", "mutation_error")}
        write_json(summary_path, summary)
    check_tree_unchanged(source, expected)
    check_files_unchanged(verification_hashes)
    check_files_unchanged(environment_hashes)
    summary["status"] = "complete"
    summary["baseline_source_unchanged"] = True
    summary["verification_inputs_unchanged"] = True
    write_json(summary_path, summary)
    print("Summary: " + str(summary_path), flush=True)
    counts = summary["counts"]
    if counts["compile_error"] or counts["runtime_error"] or counts["mutation_error"]:
        return 1
    return 2 if counts["survived"] else 0


if __name__ == "__main__":
    sys.exit(main())
