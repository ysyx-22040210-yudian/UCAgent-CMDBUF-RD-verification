#!/usr/bin/env python3
"""Validate source labels, 200-point traceability and native SVA elaboration.

Requires pyslang for --lint. This checks language and wiring, not proof status.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE=Path(__file__).resolve().parent
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rtl',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    p.add_argument('--lint',action='store_true');a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    mapping=json.loads((HERE/'property_map.json').read_text(encoding='utf8'))
    assert len(mapping['rows'])==200
    assert len({r['testpoint'] for r in mapping['rows']})==200
    source='\n'.join(f.read_text(encoding='utf8') for f in HERE.glob('cmdbuf_rd_sva*') if f.suffix in ['.sv','.svh'])
    assertions=set(re.findall(r'`TP_ASSERT\((\w+),',source))
    covers=re.findall(r'`TP_COVER\((\w+),',source)
    assert len(covers)==len(set(covers)),'Duplicate cover label'
    for row in mapping['rows']:
        for ap in row['assertions']:assert ap.split('.')[-1] in assertions,(row['testpoint'],ap)
        for cp in row['cover_bins']:assert cp['label'] in covers,(row['testpoint'],cp['label'])
    assert len([b for r in mapping['rows'] if r['testpoint']=='F-CAP-12' for b in r['cover_bins'] if b['label'].split('_')[-1].startswith('O')])==190
    # Do not accidentally reintroduce the target's unsupported declaration =1.
    for initializer in re.findall(r'\breg\s+\w+\s*=\s*([^;]+);',source):
        assert initializer.strip() in ["1'b0",'0'],initializer
    result={'testpoints':200,'source_assert_labels':len(assertions),'source_cover_labels':len(covers),'mapped_cover_bins':mapping['cover_bins'],'base_environment_labels':['E01_RESET_FIRST','E02_RESET_RELEASE','E03_SRC','E04_ARRESP','E05_ZERO_READY'],'native_lint':[],'proof_executed':False}
    if a.lint:
        code="from pyslang.driver import Driver; d=Driver(); d.addStandardArgs(); assert d.parseCommandLine('slang -f native.f --top cmdbuf_rd_native_formal'); assert d.processOptions(); assert d.parseAllSources(); c=d.createCompilation(); d.reportCompilation(c,False); ok=d.reportDiagnostics(False); raise SystemExit(0 if ok else 1)"
        for profile in ['base','negative','idle_reset','drain','perf_rr','perf0','perf1','perf2']:
            target=a.output/profile
            subprocess.check_call([sys.executable,str(HERE/'build.py'),'--rtl',str(a.rtl),'--output',str(target),'--profile',profile,'--mode','cover'])
            run=subprocess.run([sys.executable,'-c',code],cwd=str(target),stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True)
            (a.output/(profile+'.log')).write_text(run.stdout,encoding='utf8')
            result['native_lint'].append({'profile':profile,'returncode':run.returncode,'passed':run.returncode==0,'input_manifest_sha256':hashlib.sha256((target/'inputs.json').read_bytes()).hexdigest()})
    (a.output/'source_validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf8')
    print(json.dumps(result,indent=2))
    return 0 if all(r['passed'] for r in result['native_lint']) else 1
if __name__=='__main__':raise SystemExit(main())
