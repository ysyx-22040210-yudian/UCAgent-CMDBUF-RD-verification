#!/usr/bin/env python3
import pathlib
import sys
root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[1])
required = ['env/Makefile', 'projects', 'adapters', 'cases', 'scripts/run_cases.py']
missing = [item for item in required if not (root / item).exists()]
if missing:
    raise SystemExit('Missing: ' + ', '.join(missing))
print('PASS reusable environment layout: ' + str(root))
