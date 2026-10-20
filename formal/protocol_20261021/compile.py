#!/usr/bin/env python3
"""Record reproducible RTL lint, unpacked-port compile and native SVA compile."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    commands = {
        "rtl_lint": ["verilator", "--lint-only", "--Wall", "--assert",
                     "--language", "1800-2017", "--top-module", "cmdbuf_rd", "-f", "rtl/files.f"],
        "interface_compile": ["iverilog", "-g2012", "-s", "cmdbuf_rd",
                              "-o", str(args.output / "interface.vvp"), "-f", "rtl/files.f"],
        "native_sva_compile": ["verilator", "--lint-only", "--assert", "-Wno-WIDTHEXPAND",
                               "-Wno-WIDTHTRUNC", "--top-module", "cmdbuf_rd_formal",
                               "-f", "formal/protocol_20261021/native.f"],
    }
    results = {}
    for name, cmd in commands.items():
        with (args.output / (name + ".log")).open("w", encoding="utf-8") as log:
            run = subprocess.run(cmd, cwd=str(ROOT), stdout=log, stderr=subprocess.STDOUT)
        results[name] = {"command": cmd, "returncode": run.returncode,
                         "status": "PASS" if run.returncode == 0 else "FAIL"}
    for tool, option in (("verilator", "--version"), ("iverilog", "-V")):
        run = subprocess.run([tool, option], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             universal_newlines=True)
        results[tool + "_version"] = run.stdout.splitlines()[0]
    (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results), flush=True)
    return int(any(results[n]["returncode"] for n in commands))


if __name__ == "__main__":
    raise SystemExit(main())
