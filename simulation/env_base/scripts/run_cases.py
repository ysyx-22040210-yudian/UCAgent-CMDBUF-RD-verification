#!/usr/bin/env python3
import argparse
import json
import pathlib
import subprocess
import sys
p = argparse.ArgumentParser()
p.add_argument('--sim', required=True)
p.add_argument('--cases', required=True)
p.add_argument('--results', required=True)
a = p.parse_args()
out = pathlib.Path(a.results)
out.mkdir(parents=True, exist_ok=True)
cases = sorted(pathlib.Path(a.cases).glob('*.case'))
if not cases:
    raise SystemExit('No case files found')
records = []
for case in cases:
    run = subprocess.run([a.sim, '--case', str(case), '--result-dir', str(out)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    (out / (case.stem + '.log')).write_text(run.stdout)
    print(run.stdout.strip(), flush=True)
    records.append({'case_file': str(case), 'exit_code': run.returncode})
(out / 'regression.json').write_text(json.dumps({'passed': sum(x['exit_code'] == 0 for x in records), 'total': len(records), 'cases': records}, indent=2))
sys.exit(0 if all(x['exit_code'] == 0 for x in records) else 1)
