#!/usr/bin/env python3
"""Short public-input witnesses; every trace is replayed with all BASE checks."""
import argparse,hashlib,json,random,re,subprocess
from pathlib import Path
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
class Trace:
    def __init__(self):self.rows=[[0]*17];self.rng=random.Random(260618)
    def step(self,offer=0,src=0,addr=None,ident=None,port=None,err=0,pc=None,ready=7,busy=0,ga=255,gw=255):
        n=len(self.rows);r=self.rng
        self.rows.append([n,1,offer,src,r.randrange(1<<18) if addr is None else addr,r.randrange(256) if ident is None else ident,r.randrange(32) if port is None else port,err,ready,busy,ga,gw,r.randrange(2) if pc is None else pc]+[r.getrandbits(32) for _ in range(4)])
    def hold(self,n,**kw):
        for _ in range(n):self.step(**kw)
    def fill(self,counts,busy=0):
        for s,c in enumerate(counts):
            for _ in range(c):self.step(1,s,ready=0,busy=busy)
    def drain(self):self.hold(35)
def cases():
    for v in (0,1):
        t=Trace();t.step(1,0,(1<<18)-1 if v else 0,255 if v else 0,31 if v else 0,3 if v else 0,pc=v)
        t.hold(15,addr=0 if v else (1<<18)-1,ident=0 if v else 255,port=0 if v else 31)
        yield 'fields'+str(v),t
    t=Trace()
    for a in (0,3):
        for p in (0,1):
            t.step(1,0,0,err=a,pc=p,ready=0);t.step(pc=p,ready=0);t.step(pc=p,ready=0,ga=0,gw=0)
            t.hold(9,pc=p,ready=0);t.hold(3,pc=p)
    t.drain();yield 'error_history',t
    t=Trace()
    for s,i,p in [(0,9,1),(0,9,2),(1,9,3),(0,8,4)]:t.step(1,s,p,i,p,ready=0)
    t.hold(15,ready=0);t.drain();yield 'duplicate_history',t
    for pointer in range(3):
        for mask in range(8):
            t=Trace();t.fill([3,3,3]);t.hold(15,ready=0)
            if pointer:t.step(ready=1<<(pointer-1))
            t.step(ready=mask);t.drain();yield 'rr_%d_%d'%(pointer,mask),t
    for released in range(3):
        for offered in range(3):
            for heavy_release in (False,True):
                heavy=released if heavy_release else (released+1)%3;counts=[1,1,1];counts[heavy]=7
                t=Trace();t.fill(counts);t.hold(15,ready=0)
                t.step(1,offered,ident=255,port=31,ready=1<<released);t.drain()
                yield 'capacity_%d_%d_%d'%(heavy_release,released,offered),t
    for s in range(3):
        t=Trace();counts=[4,4,4];counts[s]=0;t.fill(counts,65535)
        t.step(1,s,ready=0,busy=65535);t.drain();yield 'reserved_'+str(s),t
def main():
    p=argparse.ArgumentParser();p.add_argument('--binary',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    result=dict(runs=[],hits={},method='directed_simulation_not_formal',binary_sha256=sha(a.binary))
    for name,t in cases():
        path=a.output/(name+'.inputs');copy=a.output/(name+'.replay');log=a.output/(name+'.log')
        path.write_text('\n'.join(' '.join(map(str,r)) for r in t.rows)+'\n')
        with log.open('w') as f:r=subprocess.run([str(a.binary.resolve()),'replay','0',str(copy.resolve()),str(path.resolve())],stdout=f,stderr=subprocess.STDOUT)
        text=log.read_text();passed=r.returncode==0 and sha(path)==sha(copy) and 'RUN_PASS ' in text
        result['runs'].append(dict(run=name,passed=passed,returncode=r.returncode,input_sha256=sha(path)))
        for label,clock in re.findall(r'COVER_HIT (\w+) (\d+)',text):
            hit=dict(run=name,cycle=(int(clock)-1)//2,method='verilator_simulation',trace=path.name,log=log.name)
            if label not in result['hits'] or hit['cycle']<result['hits'][label]['cycle']:result['hits'][label]=hit
        if not passed:print(text[-2000:]);break
    (a.output/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    passed=all(r['passed'] for r in result['runs']);print(json.dumps(dict(runs=len(result['runs']),hits=len(result['hits']),all_passed=passed)))
    return int(not passed)
if __name__=='__main__':raise SystemExit(main())
