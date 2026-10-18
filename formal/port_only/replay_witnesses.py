#!/usr/bin/env python3
"""Re-run every saved input witness against one final, hashed simulation binary."""
import argparse,hashlib,json,re,subprocess
from pathlib import Path
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--binary',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    result=dict(binary_sha256=sha(a.binary),method='strict_input_replay_simulation_not_formal',runs=[],hits={})
    for report in sorted(a.root.glob('witness*/results.json')):
        old=json.loads(report.read_text())
        for run in old['runs']:
            name=report.parent.name+'_'+run['run'];original=report.parent/(run['run']+'.inputs')
            assert sha(original)==run['input_sha256']
            output=a.output/(name+'.inputs');log=a.output/(name+'.log')
            with log.open('w') as f:r=subprocess.run([str(a.binary.resolve()),'replay','0',str(output.resolve()),str(original.resolve())],stdout=f,stderr=subprocess.STDOUT)
            txt=log.read_text();same=sha(original)==sha(output)
            rec=dict(run=name,passed=r.returncode==0 and same and 'RUN_PASS ' in txt,returncode=r.returncode,input_sha256=sha(original),exact_input_replay=same,cycles=len(original.read_text().splitlines()))
            result['runs'].append(rec)
            for label,t in re.findall(r'COVER_HIT (\w+) (\d+)',txt):
                result['hits'].setdefault(label,dict(run=name,cycle=(int(t)-1)//2,log=log.name))
            if not rec['passed']:print(json.dumps(rec));print(txt[-1500:]);break
    result['all_passed']=all(x['passed'] for x in result['runs']);result['total_cycles']=sum(x['cycles'] for x in result['runs'])
    (a.output/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(dict(runs=len(result['runs']),all_passed=result['all_passed'],hits=len(result['hits']),cycles=result['total_cycles'])))
    return int(not result['all_passed'])
if __name__=='__main__':raise SystemExit(main())
