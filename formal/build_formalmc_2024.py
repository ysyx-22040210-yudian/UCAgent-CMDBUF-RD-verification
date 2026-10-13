#!/usr/bin/env python3
"""Build a separate zero-init FormalMC candidate from sealed dual-backend inputs.

The target restriction is supplied by the device owner, not independently
certified by a public 2024 manual. Yosys zinit without -all preserves arbitrary
uninitialized state. This builder never changes the source package or imports a
historical proof status as acceptance of the new models.
"""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess


def sha(path):
    """Bind provenance and inputs to exact file bytes."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    """Write machine-readable build evidence outside the historic result namespace."""
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def state_summary(design, top):
    """Count FF Q bits and initial constraints without counting aliases twice."""
    module = design["modules"][top]
    init = {}
    for wire in module["netnames"].values():
        value = wire.get("attributes", {}).get("init")
        if value is None:
            continue
        if not isinstance(value, str) or len(value) != len(wire["bits"]):
            raise ValueError("Unexpected init encoding")
        for bit, digit in zip(wire["bits"], reversed(value)):
            if bit in init and init[bit] != digit:
                raise ValueError("Conflicting initial state aliases")
            init[bit] = digit
    cells = {name: cell for name, cell in module["cells"].items()
             if cell["type"] in {"$dff", "$dffe", "$adff", "$adffe", "$sdff", "$sdffe", "$sdffce",
                                "$dffsr", "$dffsre", "$dlatch", "$adlatch", "$dlatchsr", "$ff"}
             and cell["connections"].get("Q")}
    bits = {bit for cell in cells.values() for bit in cell["connections"]["Q"]}
    return {"bits": len(bits), "initial": dict(collections.Counter(init.get(bit, "x") for bit in bits)),
            "cell_types": dict(collections.Counter(cell["type"] for cell in cells.values()))}


def initial_literals(model):
    """Reject unsupported nonzero or unknown literal initialization in emitted HDL."""
    values = re.findall(r"^\s*reg\b[^;]*?\s=\s([^;]*);", model, re.MULTILINE)
    for value in values:
        if not re.fullmatch(r"\d+'[bhdo]0+", value):
            raise ValueError("Nonzero or unreviewed initializer remains: " + value)
    return len(values)


def normalize_runner(text):
    """Preserve capability state and interpret typed, recognized Cover results."""
    if text.count("reg first = 1'b1;") != 4 or text.count("first <= 1'b0;") != 4:
        raise ValueError("Unexpected capability state contract")
    text = text.replace("reg first = 1'b1;", "reg started = 1'b0;\nwire first = ~started;")
    text = text.replace("first <= 1'b0;", "started <= 1'b1;")
    previous = '''    observed = collections.defaultdict(list)
    for line in text.splitlines():
        for pattern in FORMAL_PATTERNS:
            match = pattern.search(line)
            if match:
                observed[match.group(1)].append(FORMAL_STATUSES[match.group(2).lower()])
                break
'''
    updated = '''    observed = collections.defaultdict(list)
    cover_labels = {p.get("formalmc_label", p["label"]) for p in job["properties"] if p["kind"] == "cover"}
    for line in text.splitlines():
        for format_index, pattern in enumerate(FORMAL_PATTERNS):
            match = pattern.search(line)
            if match:
                name, raw = match.group(1), match.group(2).lower()
                state = FORMAL_STATUSES[raw]
                # FormalMC uses Pass/TRUE for successful typed properties. Only
                # its known summary/P016 formats and the sealed Cover inventory
                # establish a cover witness; generic status text never does.
                if (format_index < 2 and raw in {"pass", "true", "fail", "false"} and
                        sum(match_name(name, label) for label in cover_labels) == 1):
                    state = "covered" if raw in {"pass", "true"} else "uncovered"
                observed[name].append(state)
                break
'''
    if text.count(previous) != 1:
        raise ValueError("Unexpected FormalMC parser contract")
    return text.replace(previous, updated).replace(
        "# tool's explicit covered/reachable/cover_pass status counts for covers.",
        "# explicit witness or typed FormalMC Pass/TRUE counts for covers.")


def main():
    """Regenerate all models with zero initial encoding and preserve source contracts."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path(__file__).resolve().with_name("cmdbuf_rd_dual_backend"))
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--yosys", required=True)
    args = parser.parse_args()
    source, output = args.source.resolve(strict=True), args.output.resolve()
    if output.exists() or output == source or source in output.parents:
        raise ValueError("Output must be a fresh directory outside the source package")
    release = json.loads((source / "release_hashes.json").read_text())
    for relative, expected in release.items():
        path = source / relative
        if not path.resolve().is_relative_to(source) or sha(path) != expected:
            raise ValueError("Baseline release integrity failure: " + relative)
    output.mkdir(parents=True)
    for relative in release:
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / relative, target)
    baseline = json.loads((source / "manifest.json").read_text())
    manifest = copy.deepcopy(baseline)
    library = source / "tools/build_portable.py"
    spec = importlib.util.spec_from_file_location("sealed_portable_builder", library)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    version = subprocess.check_output([args.yosys, "-V"], text=True).strip()
    report = {"profile": "formalmc2024_zero_init", "source_manifest_sha256": sha(source / "manifest.json"),
              "source_release_sha256": sha(source / "release_hashes.json"), "builder_sha256": sha(Path(__file__)),
              "source_library_sha256": sha(library), "yosys": version,
              "target_restriction_source": "user_report_nonzero_initializer_unsupported_zero_supported",
              "public_2024_manual_confirmed": False, "zinit_all_used": False,
              "real_formalmc_executed": False, "validation_status": "not_run", "jobs": []}
    for job in manifest["jobs"]:
        name = job["id"]
        directory = output / "jobs" / name
        meta = directory / "conversion"
        config = (directory / "sby/run.sby").read_text()
        opts, script, top = builder.parse_config(config)
        # Export symbolic ports and property endpoints before zinit, so changing
        # cell order cannot change their stable names or compiled property map.
        design = json.loads((meta / "normalized.json").read_text())
        il, properties, symbols, statements = builder.convert_normalized_il((meta / "normalized.il").read_text(), design, top, opts["mode"])
        if il != (meta / "portable.il").read_text():
            raise ValueError("Sealed property lowering is not reproducible: " + name)
        commands = 'read_rtlil "' + str(meta / "portable.il") + '"\n'
        commands += 'write_json "' + str(meta / "before_zero_init.json") + '"\nzinit\n'
        commands += 'write_rtlil "' + str(meta / "zero_init.il") + '"\nwrite_json "' + str(meta / "zero_init.json") + '"\n'
        commands += 'write_verilog -sv -noattr "' + str(directory / "formalmc/model.sv") + '"\n'
        builder.write(meta / "zero_init.ys", commands)
        builder.run_yosys(args.yosys, commands, directory / "sby", meta / "zero_init.log")
        before = state_summary(json.loads((meta / "before_zero_init.json").read_text()), top)
        design = json.loads((meta / "zero_init.json").read_text())
        after = state_summary(design, top)
        if (before["bits"] != after["bits"] or before["cell_types"] != after["cell_types"] or
                after["initial"].get("1", 0) != 0 or
                after["initial"].get("0", 0) != before["initial"].get("0", 0) + before["initial"].get("1", 0) or
                before["initial"].get("x", 0) != after["initial"].get("x", 0)):
            raise ValueError("Initial state domain changed unexpectedly: " + name)
        old_identity = [(p["label"], p["kind"], p["formalmc_label"]) for p in job["properties"]]
        new_identity = [(p["label"], p["kind"], p["formalmc_label"]) for p in properties]
        if old_identity != new_identity or symbols != job["symbolic_ports"]:
            raise ValueError("Property or symbolic input identity changed: " + name)
        model = directory / "formalmc/model.sv"
        text = model.read_text().replace("endmodule", statements + "endmodule")
        count = initial_literals(text)
        builder.write(model, text)
        job["formalmc"]["initialization_profile"] = "zero_only_polarity_encoding"
        report["jobs"].append({"id": name, "before": before, "after": after,
                               "zero_declarations": count, "model_sha256": sha(model)})
        print("ZERO_INIT " + name + " flipped=" + str(before["initial"].get("1", 0)), flush=True)
    runner = output / "run.py"
    text = normalize_runner(runner.read_text())
    runner.write_text(text, encoding="utf-8")
    test_fixture = Path(__file__).resolve().with_name("formalmc2024_runner_tests.py")
    if test_fixture.exists():
        shutil.copy2(test_fixture, output / "test_formalmc_2024.py")
    provenance = output / "provenance/formalmc2024_zero_init.json"
    save(provenance, report)
    manifest["formalmc_profile"] = "2024_zero_init"
    manifest["initial_status"] = "not_run"
    manifest["scope"]["target_formalmc_run_performed"] = False
    manifest["conversion"]["initialization"] = {
        "pass": "zinit", "all_option": False, "arbitrary_uninitialized_state_preserved": True,
        "source_manifest_sha256": report["source_manifest_sha256"], "target_acceptance": "not_run"}
    manifest["files"] = {p.relative_to(output).as_posix(): sha(p)
                         for base in [output / "jobs", output / "provenance"] for p in sorted(base.rglob("*")) if p.is_file()}
    save(output / "manifest.json", manifest)
    save(output / "release_hashes.json", {p.relative_to(output).as_posix(): sha(p)
                                          for p in sorted(output.rglob("*")) if p.is_file() and p.name != "release_hashes.json"})
    print(json.dumps({"models": len(report["jobs"]), "manifest_sha256": sha(output / "manifest.json"),
                      "real_formalmc_executed": False}), flush=True)


if __name__ == "__main__":
    main()
