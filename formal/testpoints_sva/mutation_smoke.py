#!/usr/bin/env python3
"""Confirm that selected bugs produce assertion failures, in isolated RTL copies."""
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
MUTATIONS=[
 ('M01_SINGLE_GRANT','cmdbuf_rd_cmd.v', [('assign issue_success = |(req & ar_rd_gnt & rw_rd_gnt);','assign issue_success = |(req & (ar_rd_gnt | rw_rd_gnt));')]),
 ('M02_SIXTH_BYPASS','cmdbuf_rd_cmd.v',[('(rank_count[i] < 5)','(rank_count[i] < 6)')]),
 ('M03_RETURN_EARLY','cmdbuf_rd_otb.v',[('assign capture_valid = rst_n && ret_valid_q[3];','assign capture_valid = rst_n && ret_valid_q[2];'),('assign capture_entry = ret_entry_q[3];','assign capture_entry = ret_entry_q[2];')]),
 ('M04_DATA_HIGH_BIT','cmdbuf_rd.v',[("assign rdata = (|rvalid) ? rsp_data : 128'b0;","assign rdata = (|rvalid) ? (rsp_data ^ (128'b1 << 127)) : 128'b0;")]),
 ('M05_RESERVATION_STOLEN','cmdbuf_rd_cmd.v',[('(shared_after < 6)','(shared_after < 7)')]),
 ('M06_OLD_CLEAR_WINS','cmdbuf_rd_otb.v',[("if (alloc_fire && (alloc_entry == i[3:0])) begin","if (alloc_fire && (alloc_entry == i[3:0]) && !(retire_fire && retire_entry == i[3:0])) begin")]),
]

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rtl',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
    p.add_argument('--tools',required=True,type=Path);p.add_argument('--jobs',default=2,type=int)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    env=os.environ.copy();env['PATH']=str(a.tools)+os.pathsep+env.get('PATH','')
    def run(m):
        name,file,replacements=m;folder=a.output/name;rtl=folder/'rtl';rtl.mkdir(parents=True)
        for f in a.rtl.glob('*.v'):
            text=f.read_text(encoding='utf8')
            if f.name==file:
                for old,new in replacements:
                    if text.count(old)!=1:raise ValueError('Mutation anchor must occur once: '+name)
                    text=text.replace(old,new)
            (rtl/f.name).write_text(text,encoding='utf8')
        cmd=[sys.executable,str(HERE/'build.py'),'--rtl',str(rtl),'--output',str(folder/'job'),'--mode','bmc','--depth','14','--timeout','180']
        start=time.time()
        with (folder/'driver.log').open('w') as log:
            subprocess.check_call(cmd,stdout=log,stderr=subprocess.STDOUT,env=env)
            proc=subprocess.run(['sby','run.sby'],cwd=str(folder/'job'),stdout=log,stderr=subprocess.STDOUT,env=env)
        status=(folder/'job/run/status').read_text().strip() if (folder/'job/run/status').exists() else 'NO_STATUS'
        log=(folder/'driver.log').read_text(errors='replace')
        failures=[line for line in log.splitlines() if 'Assert failed' in line]
        result={'mutation':name,'status':status,'assertion_failure_observed':status.startswith('FAIL') and bool(failures),'failure_lines':failures,'returncode':proc.returncode,'seconds':round(time.time()-start,2),'mutated_file':file,'mutated_sha256':hashlib.sha256((rtl/file).read_bytes()).hexdigest()}
        print(json.dumps(result),flush=True);return result
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(run,MUTATIONS))
    (a.output/'results.json').write_text(json.dumps({'mutations':results,'note':'Representative checker validation only; not the historic 49-mutation closure.'},indent=2)+'\n')
    return 0 if all(r['assertion_failure_observed'] for r in results) else 1
if __name__=='__main__':raise SystemExit(main())
