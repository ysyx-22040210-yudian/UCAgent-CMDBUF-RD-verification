#!/usr/bin/env python3
"""Run isolated current-source checks; never treats an old PASS as a new result."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

HERE=Path(__file__).resolve().parent

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rtl',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--tools',type=Path,required=True)
    p.add_argument('--jobs',type=int,default=2)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    env=os.environ.copy();env['PATH']=str(a.tools)+os.pathsep+env.get('PATH','')
    versions={}
    for cmd in [['yosys','-V'],['sby','--version'],['yices-smt2','--version']]:
        r=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True)
        versions[cmd[0]]=r.stdout.strip()
    (a.output/'versions.json').write_text(json.dumps(versions,indent=2)+'\n')
    configs=[
        ('base_bmc','base','bmc',12,None,240),
        ('base_prove','base','prove',12,None,240),
        ('cover_lifecycle','base','cover',24,'C_B_FLOW_01_S0T00,C_F_CON_16_MAIN,C_F_REU_01_MAIN,C_F_ERR_04_MAIN',180),
        ('cover_schedule','base','cover',40,'C_B_BLOCK_04_MAIN,C_B_BLOCK_03_MAIN,C_F_WIN_05_MAIN,C_F_CAP_04_EMPTY2,C_F_RR_05_PTR0E7',240),
        ('negative','negative','cover',6,None,60),
        ('idle_reset','idle_reset','cover',36,None,180),
        ('perf_rr','perf_rr','bmc',20,None,180),
        ('perf0','perf0','bmc',20,None,180),
        ('drain','drain','bmc',35,None,240),
    ]
    results=[]
    def job(config):
        name,profile,mode,depth,covers,limit=config
        folder=a.output/name
        command=[sys.executable,str(HERE/'build.py'),'--rtl',str(a.rtl),'--output',str(folder),'--profile',profile,'--mode',mode,'--depth',str(depth),'--timeout',str(limit),'--solver','yices']
        if covers:command+=['--select-cover',covers]
        if profile in ['negative','idle_reset']:command+=['--group','NONE']
        begin=time.time()
        with (a.output/(name+'.log')).open('w') as log:
            made=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,env=env)
            if made.returncode: return {'job':name,'status':'BUILD_ERROR','returncode':made.returncode}
            proc=subprocess.run(['sby','run.sby'],cwd=str(folder),stdout=log,stderr=subprocess.STDOUT,env=env)
        status=(folder/'run/status').read_text().strip() if (folder/'run/status').exists() else 'NO_STATUS'
        record={'job':name,'profile':profile,'mode':mode,'depth':depth,'status':status,'returncode':proc.returncode,'seconds':round(time.time()-begin,2),'input_manifest_sha256':hashlib.sha256((folder/'inputs.json').read_bytes()).hexdigest()}
        print(json.dumps(record),flush=True)
        return record
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        for result in pool.map(job,configs):
            results.append(result)
            (a.output/'results.json').write_text(json.dumps({'versions':versions,'jobs':results,'target_formalmc_executed':False,'suite_complete':len(results)==len(configs)},indent=2)+'\n')
    print('CURRENT_SOURCE_VALIDATION_FINISHED',flush=True)
    return 0 if all(r['status'].startswith('PASS') for r in results) else 1
if __name__=='__main__':raise SystemExit(main())
