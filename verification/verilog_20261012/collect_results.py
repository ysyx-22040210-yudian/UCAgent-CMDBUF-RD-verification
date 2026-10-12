"""Validate fresh Verilog proof receipts and retain both successful evidence and infrastructure retry history."""

import hashlib
import json
from pathlib import Path
import re
import shutil
import tarfile

ROOT = Path('/root/cmdbuf_rd/verilog_20261012')
PACKAGE = ROOT / 'package'


def sha(path):
    """Hash the evidence bytes actually produced by the running tools."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def one(parent, pattern):
    """A non-unique or missing result is an error, never silently the latest PASS."""
    matches = list(parent.glob(pattern))
    if len(matches) != 1:
        raise RuntimeError('Expected one result: ' + str(parent / pattern))
    return matches[0]


def main():
    """Check full-suite semantics and source hashes before assembling a new revision report."""
    source = ROOT / 'validation'
    out = ROOT / 'delivery'
    out.mkdir(exist_ok=True)
    primary_path = one(source / 'sby', '*/result.json')
    normalized_path = one(ROOT / 'normalized_validation', '*/results.json')
    replay_path = one(source / 'replay_toolchain_fixed', '*/summary.json')
    primary, normalized, replay = [json.loads(p.read_text()) for p in (primary_path, normalized_path, replay_path)]
    basic = json.loads((source / 'simulation/regression.json').read_text())
    extended = json.loads((source / 'extended/regression.json').read_text())
    icarus = json.loads((source / 'iverilog_replay/summary.json').read_text())
    if primary['status'] != 'passed' or primary['full_suite_passed'] is not True or primary['counts'] != {'proven': 107, 'covered': 65, 'assumption': 5}:
        raise RuntimeError('Verilog DUT full-suite proof is incomplete.')
    if primary['manifest_sha256'] != sha(PACKAGE / 'manifest.json'):
        raise RuntimeError('Current input manifest differs from freshly executed proof.')
    if len(normalized['runs']) != 22 or not all(r['status'] == 'passed' and r['exit_code'] == 0 and not r['missing_labels'] for r in normalized['runs']):
        raise RuntimeError('Normalized-model cross-check is incomplete.')
    if normalized['manifest_sha256'] != sha(PACKAGE / 'manifest.json'):
        raise RuntimeError('Cross-checked manifest differs.')
    if replay['selected'] != 49 or replay['passed'] != 49:
        raise RuntimeError('Fresh replay did not reproduce every fault.')
    for data, count in [(basic, 19), (extended, 4)]:
        if data['total'] != count or data['passed'] != count:
            raise RuntimeError('Simulation regression is incomplete.')
    if not icarus['all_passed'] or len(icarus['cases']) != 3:
        raise RuntimeError('Strict Verilog functional replay is incomplete.')
    equivalence = (source / 'equivalence.log').read_text()
    if 'Of those cells 3162 are proven and 0 are unproven.' not in equivalence or 'Equivalence successfully proven!' not in equivalence:
        raise RuntimeError('No successful sequential equivalence receipt.')
    lint = (source / 'lint.log').read_text()
    if re.search(r'%Warning|%Error', lint):
        raise RuntimeError('Lint emitted warnings or errors.')
    # Rebind all reported model files to the present generated models.
    for run in normalized['runs']:
        if run['sources']['model.sv'] != sha(PACKAGE / 'jobs' / run['job_id'] / 'formalmc/model.sv'):
            raise RuntimeError('Cross-checked model drift: ' + run['job_id'])
    rtl_hashes = {p.name: sha(p) for p in sorted((ROOT / 'rtl').glob('*.v'))}
    for name, digest in rtl_hashes.items():
        if sha(PACKAGE / 'rtl' / name) != digest:
            raise RuntimeError('DUT integration RTL differs from proof/replay release.')
    for name, path in [('sby_result.json', primary_path), ('normalized_result.json', normalized_path), ('fault_replay_result.json', replay_path), ('simulation_result.json', source / 'simulation/regression.json'), ('extended_result.json', source / 'extended/regression.json'), ('icarus_result.json', source / 'iverilog_replay/summary.json'), ('equivalence.log', source / 'equivalence.log'), ('lint.log', source / 'lint.log'), ('iverilog.log', source / 'iverilog.log'), ('iverilog_synthesis.log', source / 'iverilog_synthesis.log'), ('input_manifest.json', PACKAGE / 'manifest.json'), ('normalization_report.json', ROOT / 'normalization_report.json')]:
        shutil.copy2(path, out / name)
    selected = []
    for base in (source, ROOT / 'normalized_validation'):
        for path in sorted(base.rglob('*')):
            if not path.is_file() or 'build' in path.relative_to(base).parts or 'obj' in path.relative_to(base).parts:
                continue
            if path.suffix in ('.json', '.log', '.vcd', '.xml', '.sby', '.ys', '.v') or path.name in ('status', 'logfile.txt'):
                label = ('validation/' if base == source else 'normalized_validation/') + path.relative_to(base).as_posix()
                selected.append((path, label))
    archive = out / 'execution_evidence.tar.gz'
    inventory = {name: {'sha256': sha(path), 'bytes': path.stat().st_size} for path, name in selected}
    with tarfile.open(archive, 'w:gz') as handle:
        for path, name in selected:
            handle.add(path, arcname=name, recursive=False)
    summary = {'revision': 'verilog2001_20261012', 'rtl_language': 'IEEE 1364-2001', 'rtl_sha256': rtl_hashes,
               'strict_iverilog_compile': {'simulation_diagnostics_enabled': True, 'synthesis_mode_checked': True, 'language_flag': '-g2001'},
               'verilator_lint': {'language_flag': '--language 1364-2001', 'warnings': 0},
               'sequential_equivalence': {'proven': 3162, 'unproven': 0, 'method': 'Yosys equiv_simple + equiv_induct -seq 5', 'scope': 'Clock-observable two-state synthesis semantics with async2sync; not a four-state or physical timing equivalence claim'},
               'simulation': {'basic': {'passed': 19, 'total': 19}, 'extended': {'passed': 4, 'total': 4}},
               'icarus_functional_replay': {'passed': 3, 'total': 3, 'dut_and_bench_verilog2001': True},
               'fresh_sby': {'jobs': 22, 'full_suite_passed': True, 'counts': primary['counts'], 'manifest_sha256': primary['manifest_sha256']},
               'fresh_normalized_models': {'passed': 22, 'total': 22, 'model_hashes_checked': True},
               'fault_replay': {'passed': 49, 'total': 49, 'scope': 'Fresh simulation of archived SBY stimuli on current original and converted mutant RTL; no new formal counterexamples claimed'},
               'resolved_infrastructure_attempt': {'first_replay_failed': True, 'reason': 'OSS-CAD bundled Verilator 5.051 selected with incompatible system GCC; compiler rejected flags',
                  'retry_environment': 'devtoolset-11 GCC and /usr/local/bin Verilator 5.024', 'first_attempt_retained': True, 'counted_as_detected_fault': False},
               'actual_formalmc_execution': False, 'historical_ucagent_14_stage_receipt_rewritten': False,
               'evidence_archive': {'file': archive.name, 'sha256': sha(archive), 'bytes': archive.stat().st_size, 'files': len(inventory)}}
    (out / 'evidence_inventory.json').write_text(json.dumps(inventory, indent=2) + '\n')
    (out / 'validation_summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == '__main__':
    main()
