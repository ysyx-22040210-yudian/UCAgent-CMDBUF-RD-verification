#!/usr/bin/env python3
"""Exercise port-only assertions; simulation hits are explicitly NOT formal proofs."""
import argparse,hashlib,json,re,subprocess,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
def main():
    p=argparse.ArgumentParser();p.add_argument('--binary',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--case',help='Optional single mode:integer case')
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    configs=[('isolated',i) for i in range(48)]
    configs += [('occupancy',100*x+10*y+z) for x in range(8) for y in range(8) for z in range(8) if max(x,1)+max(y,1)+max(z,1)<=9]
    configs += [('busy6',0),('retry',0),('outorder',0),('hotspot',0),('idle',0),('walking',0)]
    configs += [('burst',i) for i in [1,2,4,5,6,9]]+[('backlog',i) for i in range(66)]+[('perf',i) for i in range(4)]+[('random',i) for i in range(6)]
    if a.case:
        mode,arg=a.case.split(':');configs=[(mode,int(arg))]
    results=[];hits={}
    for mode,arg in configs:
        name=mode+'_'+str(arg);trace=a.output/(name+'.inputs');log=a.output/(name+'.log');begin=time.time()
        with log.open('w') as f:r=subprocess.run([str(a.binary.resolve()),mode,str(arg),str(trace.resolve())],stdout=f,stderr=subprocess.STDOUT)
        txt=log.read_text()
        for label,t in re.findall(r'COVER_HIT (\w+) (\d+)',txt):
            cycle=(int(t)-1)//2
            hit=dict(run=name,cycle=cycle,method='verilator_simulation',trace=str(trace.name),log=log.name)
            if label not in hits or cycle<hits[label]['cycle']:hits[label]=hit
        rec=dict(run=name,returncode=r.returncode,passed=r.returncode==0 and 'RUN_PASS ' in txt,seconds=round(time.time()-begin,3),input_sha256=hashlib.sha256(trace.read_bytes()).hexdigest())
        results.append(rec)
        (a.output/'results.json').write_text(json.dumps(dict(runs=results,hits=hits,method='simulation_not_formal'),indent=2)+'\n')
        if not rec['passed']:
            print(json.dumps(rec),flush=True);print(txt[-2000:],flush=True);return 1
    print(json.dumps(dict(runs=len(results),hits=len(hits),all_passed=True)),flush=True)
if __name__=='__main__':raise SystemExit(main())
