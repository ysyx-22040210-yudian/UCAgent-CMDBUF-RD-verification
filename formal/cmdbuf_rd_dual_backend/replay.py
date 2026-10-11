"""Re-simulate all archived mutation stimuli on original and mutant RTL."""
import argparse
import datetime
import hashlib
import json
import shutil
import sys
import uuid
from pathlib import Path

def main():
    """Produce fresh simulation receipts; never copy a historic pass result."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case', action='append', help='FI001..FI049; repeat to select, default all')
    parser.add_argument('--output', type=Path, default=Path('results'))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    # Reuse the release integrity check independently of the formal backend.
    checksums = json.loads((root / 'release_hashes.json').read_text(encoding='utf-8'))
    for relative, digest in checksums.items():
        path = (root / relative).resolve()
        if not path.is_relative_to(root) or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError('Release integrity mismatch: ' + relative)
    import replay_engine as engine
    from run import execute

    def replay_command(argv, cwd, logfile, timeout=120):
        """Keep replay receipt fields while killing subprocess trees on timeout."""
        result = execute(argv, cwd, logfile, timeout, engine.ENV)
        return {'command': argv, 'exit_code': result['returncode'],
                'status': result['execution_status'], 'seconds': result['elapsed_seconds'],
                'log': str(logfile), 'log_sha256': result['log_sha256']}

    engine.cmd = replay_command
    if shutil.which('verilator') is None:
        raise RuntimeError('Verilator is required for trace replay; add its bin directory to PATH')
    catalog = json.loads((root / 'mutation_replay_catalog.json').read_text(encoding='utf-8'))
    if len(catalog['cases']) != 49 or {c['id'] for c in catalog['cases']} != {'FI%03d' % i for i in range(1, 50)}:
        raise ValueError('Incomplete mutation case inventory')
    selected = set(args.case or [c['id'] for c in catalog['cases']])
    if selected - {c['id'] for c in catalog['cases']}:
        raise ValueError('Unknown fault case')
    result_root = args.output.resolve() / ('replay-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex[:8])
    result_root.mkdir(parents=True, exist_ok=False)
    engine.ORIGINAL = root / 'rtl'
    results = []
    for case in catalog['cases']:
        if case['id'] not in selected:
            continue
        source = root / 'mutations' / case['id']
        work = result_root / case['id']
        work.mkdir()
        inputs = json.loads((source / 'external_inputs.json').read_text(encoding='utf-8'))
        if inputs['widths'] != engine.WIDTHS:
            raise ValueError('Stimulus width mismatch: ' + case['id'])
        expected = ''.join(' '.join(format(s[k], 'x') for k in engine.WIDTHS) + '\n' for s in inputs['states'])
        if (source / 'external_inputs.hex').read_bytes() != expected.encode('ascii'):
            raise ValueError('Stimulus data mismatch: ' + case['id'])
        shutil.copy2(source / 'external_inputs.hex', work / 'external_inputs.hex')
        row = {'case': case['id'], 'historical_sby_trace': case['source_sby_run'], 'variants': {}}
        for variant, rtl, build in [('original', engine.ORIGINAL, result_root / 'build/original'),
                                    ('mutant', source / 'rtl', result_root / 'build' / case['id'])]:
            simulation = engine.simulate(rtl, build, work / 'external_inputs.hex')
            if simulation['status'] == 'simulated':
                simulation['oracle'] = engine.oracle(inputs['states'], simulation.pop('rows'))
            row['variants'][variant] = simulation
        original, mutant = row['variants']['original'], row['variants']['mutant']
        valid = all(v.get('oracle', {}).get('input_contract_valid') and
                    v['oracle']['recorded_samples'] == len(inputs['states']) and
                    v['oracle']['checks'] > 0 and v['status'] == 'simulated'
                    for v in (original, mutant))
        row['passed'] = bool(valid and original['oracle']['semantic_mismatch_count'] == 0 and
                             mutant['oracle']['semantic_mismatch_count'] > 0)
        (work / 'result.json').write_text(json.dumps(row, indent=2) + '\n', encoding='utf-8')
        results.append({'case': case['id'], 'passed': row['passed'], 'report': str(work / 'result.json')})
        print(case['id'] + ': ' + ('reproduced' if row['passed'] else 'FAILED'), flush=True)
    report = {'scope': catalog['scope'], 'new_formalmc_counterexamples': False,
              'selected': len(results), 'passed': sum(r['passed'] for r in results), 'cases': results}
    (result_root / 'summary.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(str(result_root / 'summary.json'), flush=True)
    return 0 if all(r['passed'] for r in results) else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(2)
