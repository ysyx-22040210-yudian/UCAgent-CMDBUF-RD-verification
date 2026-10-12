"""Regenerate portable proof models from the new Verilog inputs and rebind the same CK inventory."""

from collections import defaultdict
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys

ROOT = Path('/root/cmdbuf_rd/verilog_20261012')
PACKAGE = ROOT / 'package'
YOSYS = '/home/ucagent-lab/portable-distributions/UCAgent-Studio-0.3.1-linux-x86_64/oss-cad-suite/bin/yosys'


def digest(path):
    """Hash bytes rather than trusting old source or backend records."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def location_revision(location, job_id, conversion):
    """Relocate original in-module observer coordinates to their external include files."""
    for row in conversion['rows']:
        old = row['original'].removeprefix('formal/cmdbuf_rd_dual_backend/')
        job_prefix = 'jobs/' + job_id + '/sby/'
        if not old.startswith(job_prefix):
            continue
        old_path = old.removeprefix(job_prefix)
        pattern = re.escape(old_path) + r':(\d+)\.(\d+)-(\d+)\.(\d+)'

        def relocate(match):
            line, column, end_line, end_column = map(int, match.groups())
            for hook in row['formal_hooks']:
                first, last = hook['original_monitor_start_line'], hook['original_monitor_end_line']
                if first <= line <= last and first <= end_line <= last:
                    path = hook['path'].removeprefix(job_prefix)
                    return f'{path}:{line-first+1}.{column}-{end_line-first+1}.{end_column}'
            return old_path.removesuffix('.sv') + f'.v:{line}.{column}-{end_line}.{end_column}'

        location = re.sub(pattern, relocate, location)
    return location


def instance_prefix(label):
    """Keep properties from separate DUT instances distinct while compiler IDs change."""
    return label.split('._witness_.', 1)[0] if '._witness_.' in label else ''


def compiler_order(prop):
    """Order repeated unnamed properties by their original compiler generation index."""
    found = re.search(r'_(\d+)$', prop['label'])
    return int(found[1]) if found else prop['label']


def main():
    """Generate every model, require one-to-one property correspondence, then seal new input hashes."""
    sys.dont_write_bytecode = True
    conversion = json.loads((ROOT / 'conversion.json').read_text())
    manifest = json.loads((ROOT / 'baseline_manifest.json').read_text())
    source_manifest = copy.deepcopy(manifest)
    builder_path = PACKAGE / 'tools/build_portable.py'
    spec = importlib.util.spec_from_file_location('audited_normalized_builder', builder_path)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)
    report = {'rtl_language': 'Verilog-2001', 'old_manifest_sha256': digest(ROOT / 'baseline_manifest.json'),
              'models_generated_from_current_inputs': True, 'old_results_used_for_current_verdict': False, 'jobs': []}
    correspondence = {}
    for job in manifest['jobs']:
        job_id = job['id']
        directory = PACKAGE / 'jobs' / job_id
        print('NORMALIZE ' + job_id, flush=True)
        before = copy.deepcopy(job['properties'])
        cfg = (directory / 'sby/run.sby').read_text()
        opts, top, properties, symbols = builder.normalize_job(YOSYS, directory, cfg)
        if len(before) != len(properties) or sorted(p['kind'] for p in before) != sorted(p['kind'] for p in properties):
            raise RuntimeError('Formal property inventory changed: ' + job_id)
        available = {(p['kind'], p['label']): p for p in properties}
        mapping, unmatched = {}, []
        for old in before:
            candidate = available.pop((old['kind'], old['label']), None)
            if candidate:
                mapping[old['label']] = candidate
            else:
                unmatched.append(old)
        grouped_old, grouped_new = defaultdict(list), defaultdict(list)
        for old in unmatched:
            key = (old['kind'], location_revision(old['source_location'], job_id, conversion), instance_prefix(old['label']))
            grouped_old[key].append(old)
        for new in available.values():
            grouped_new[(new['kind'], new['source_location'], instance_prefix(new['label']))].append(new)
        if grouped_old.keys() != grouped_new.keys():
            missing = list(grouped_old.keys() - grouped_new.keys())
            unexpected = list(grouped_new.keys() - grouped_old.keys())
            raise RuntimeError(json.dumps({'job': job_id, 'missing_property_locations': missing[:8], 'unexpected_property_locations': unexpected[:8]}))
        repeated = []
        for key, old_group in grouped_old.items():
            new_group = grouped_new[key]
            if len(old_group) != len(new_group):
                raise RuntimeError('Replicated property count changed: ' + repr(key))
            if len(old_group) > 1:
                repeated.append({'kind': key[0], 'source_location': key[1], 'count': len(old_group)})
            for old, new in zip(sorted(old_group, key=compiler_order), sorted(new_group, key=compiler_order)):
                mapping[old['label']] = new
        if len(mapping) != len(before) or len({p['label'] for p in mapping.values()}) != len(properties):
            raise RuntimeError('Property migration is not one-to-one: ' + job_id)
        correspondence[job_id] = mapping
        renamed = []
        for check in manifest['checks']:
            if check['job_id'] != job_id:
                continue
            old_label = check['label']
            new = mapping[old_label]
            if check['kind'] != new['kind']:
                raise RuntimeError('CK kind changed: ' + check['ck_id'])
            if old_label != new['label']:
                check['baseline_label'] = old_label
                renamed.append(check['ck_id'])
            check['label'], check['formalmc_label'] = new['label'], new['formalmc_label']
        for guard in manifest['extra_guard_witnesses']:
            if guard['job_id'] == job_id:
                new = mapping[guard['label']]
                guard['label'], guard['formalmc_label'] = new['label'], new['formalmc_label']
        current_sources = []
        for value in job['sby']['sources']:
            for name in ('cmdbuf_rd', 'cmdbuf_rd_cmd', 'cmdbuf_rd_otb'):
                value = value.replace(name + '.sv', name + '.v')
            current_sources.append(value)
        current_sources += [p.relative_to(PACKAGE).as_posix() for p in sorted((directory / 'sby/inputs/formal_hooks').glob('*.svh'))]
        job['sby']['sources'] = current_sources
        job['properties'], job['symbolic_ports'] = properties, symbols
        job['input_revision'] = 'verilog2001_20261012'
        job['revision_source_hashes'] = {value: digest(PACKAGE / value) for value in current_sources}
        report['jobs'].append({'id': job_id, 'properties_before': len(before), 'properties_after': len(properties),
                              'checkpoints_rebound': renamed, 'replicated_properties_preserved': repeated,
                              'model_sha256': digest(directory / 'formalmc/model.sv')})
        print('MAPPED ' + job_id + ' properties=' + str(len(properties)) + ' CK-renamed=' + str(len(renamed)), flush=True)
    provenance = PACKAGE / 'provenance'
    (provenance / 'systemverilog_baseline_manifest.json').write_bytes((ROOT / 'baseline_manifest.json').read_bytes())
    (provenance / 'verilog_2001_conversion.json').write_bytes((ROOT / 'conversion.json').read_bytes())
    (provenance / 'verilog_property_correspondence.json').write_text(json.dumps({job: {old: new['label'] for old, new in mapping.items()} for job, mapping in correspondence.items()}, indent=2) + '\n')
    (provenance / 'verilog_normalization_report.json').write_text(json.dumps(report, indent=2) + '\n')
    manifest['rtl_language'] = 'Verilog-2001 (IEEE 1364-2001)'
    manifest['input_revision'] = 'verilog2001_20261012'
    manifest['scope']['target_formalmc_run_performed'] = False
    manifest['conversion']['verilog_revision'] = {'source_manifest_sha256': report['old_manifest_sha256'],
        'models_regenerated': True, 'ck_ids_and_requirements_preserved': True, 'all_property_kinds_preserved': True,
        'proof_dependencies_preserved': True, 'bank_status_mapping': {'even': '[7:0]', 'odd': '[15:8]'}}
    for old, new in zip(source_manifest['jobs'], manifest['jobs']):
        if old['depends_on'] != new['depends_on']:
            raise RuntimeError('Proof dependency changed.')
    if [(c['ck_id'], c['kind'], c['job_id'], c['supporting_ck_ids'], c['requirements']) for c in source_manifest['checks']] != [(c['ck_id'], c['kind'], c['job_id'], c['supporting_ck_ids'], c['requirements']) for c in manifest['checks']]:
        raise RuntimeError('Checkpoint contract changed.')
    manifest['files'] = {p.relative_to(PACKAGE).as_posix(): digest(p) for base in (PACKAGE / 'jobs', provenance) for p in sorted(base.rglob('*')) if p.is_file()}
    (PACKAGE / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    # Replay results are fresh; old edit fragments remain provenance, not an executable generator.
    catalog_path = PACKAGE / 'mutation_replay_catalog.json'
    catalog = json.loads(catalog_path.read_text())
    for case in catalog['cases']:
        case['baseline_edits'] = case.pop('edits')
        case['rtl_language'] = 'Verilog-2001'
        case['current_rtl_sha256'] = {p.name: digest(p) for p in sorted((PACKAGE / 'mutations' / case['id'] / 'rtl').glob('*.v'))}
    catalog['oracle_source_sha256'] = digest(PACKAGE / 'replay_engine.py')
    catalog['input_revision'] = 'verilog2001_20261012'
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    release = {p.relative_to(PACKAGE).as_posix(): digest(p) for p in sorted(PACKAGE.rglob('*')) if p.is_file() and '__pycache__' not in p.parts and p.name != 'release_hashes.json'}
    (PACKAGE / 'release_hashes.json').write_text(json.dumps(release, ensure_ascii=False, indent=2) + '\n')
    report['new_manifest_sha256'] = digest(PACKAGE / 'manifest.json')
    report['models_generated'] = len(manifest['jobs'])
    (ROOT / 'normalization_report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'models_generated': len(manifest['jobs']), 'checks': len(manifest['checks']), 'manifest_sha256': report['new_manifest_sha256']}), flush=True)


if __name__ == '__main__':
    main()
