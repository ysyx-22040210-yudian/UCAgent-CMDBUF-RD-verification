#!/usr/bin/env python3
"""Run independent VM formal jobs and preserve precise per-job status."""
import argparse,concurrent.futures,hashlib,json,os,subprocess,sys,time
from pathlib import Path
HERE=Path(__file__).resolve().parent
def main():
    p=argparse.ArgumentParser();p.add_argument('--rtl',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--tools',type=Path,required=True);p.add_argument('--config',type=Path,required=True);p.add_argument('--jobs',type=int,default=2)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    env=os.environ.copy();env['PATH']=str(a.tools)+os.pathsep+env.get('PATH','')
    configs=json.loads(a.config.read_text());results=[]
    def job(c):
        folder=a.output/c['name'];begin=time.time()
        cmd=[sys.executable,str(HERE/'build.py'),'--rtl',str(a.rtl),'--output',str(folder)]
        for flag in ['mode','profile','depth','timeout','group','engine','select_cover','witness','assertions','skip']:
            if flag in c:cmd+=['--'+flag.replace('_','-'),str(c[flag])]
        if c.get('trim_outputs'):cmd+=['--trim-outputs']
        with (a.output/(c['name']+'.log')).open('w') as log:
            r=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,env=env)
            if not r.returncode:r=subprocess.run(['sby','run.sby'],cwd=str(folder),stdout=log,stderr=subprocess.STDOUT,env=env)
        status=(folder/'run/status').read_text().strip() if (folder/'run/status').exists() else 'NO_STATUS'
        record={**c,'status':status,'returncode':r.returncode,'seconds':round(time.time()-begin,2),'input_manifest_sha256':hashlib.sha256((folder/'inputs.json').read_bytes()).hexdigest()}
        (a.output/(c['name']+'.result.json')).write_text(json.dumps(record,indent=2)+'\n')
        print(json.dumps(record),flush=True);return record
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        for r in pool.map(job,configs):
            results.append(r);(a.output/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    return int(any(not r['status'].startswith('PASS') for r in results))
if __name__=='__main__':raise SystemExit(main())
