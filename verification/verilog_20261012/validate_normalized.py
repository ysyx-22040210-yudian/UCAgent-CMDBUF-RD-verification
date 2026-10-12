#!/usr/bin/env python3
"""Fresh sequential SBY cross-runs of the exact generated FormalMC model files."""
import datetime,hashlib,json,os,shutil,subprocess,time,argparse,re
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT=Path('/root/cmdbuf_rd/verilog_20261012')
PACKAGE=ROOT/'package'
TOOLS=Path('/home/ucagent-lab/portable-distributions/UCAgent-Studio-0.3.1-linux-x86_64/oss-cad-suite/bin')
SBY='/home/ucagent-lab/development/cmdbuf_rd_closure_20261011/tooling/sby-late-anyseq-v1/bin/sby'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--start-at',default=None);parser.add_argument('--job');parser.add_argument('--timeout',type=int);parser.add_argument('--solver',choices=['yices','z3']);args=parser.parse_args()
    manifest=json.loads((PACKAGE/'manifest.json').read_text());stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    out=ROOT/'normalized_validation'/stamp;out.mkdir(parents=True)
    shutil.copyfile(PACKAGE/'manifest.json',out/'manifest_snapshot.json')
    receipt={'schema_version':1,'suite':'normalized_formalmc_models_via_sby','created_at':stamp,'manifest_sha256':sha(PACKAGE/'manifest.json'),'formalmc_executed':False,'runs':[]}
    env=os.environ.copy();env['PATH']=str(TOOLS)+':'+env.get('PATH','')
    order=['wiring','quota_math','structural','age_projection','pipeline','policy_order','calendar','data_transition','local_transition','source_net_math','aggregate_split','aggregate','data_origin','capacity','lifecycle','lifecycle_r2','guided_prove','guided_cover','cover_banks','cover_pipeline','cover_data_identity','cover_window_response']
    if args.start_at:order=order[order.index(args.start_at):]
    if args.job:order=[args.job]
    def save():
        (out/'results.json').write_text(json.dumps(receipt,indent=2)+'\n')
        (ROOT/'normalized_validation/latest.json').write_text(json.dumps({'result_path':str(out/'results.json'),'completed':len(receipt['runs'])==22,'counts':{s:sum(x['status']==s for x in receipt['runs']) for s in ['passed','failed','inconclusive','error']}},indent=2)+'\n')
    for jid in order:
        j=next(x for x in manifest['jobs'] if x['id']==jid);dest=out/jid;inputs=dest/'inputs';shutil.copytree(PACKAGE/'jobs'/jid/'formalmc',inputs)
        if args.timeout:
            config=inputs/'validate.sby';config.write_text(re.sub(r'^timeout \d+$','timeout '+str(args.timeout),config.read_text(),flags=re.M))
        if args.solver:
            config=inputs/'validate.sby';config.write_text(re.sub(r'^smtbmc (yices|z3)$','smtbmc '+args.solver,config.read_text(),flags=re.M))
        command=[SBY,'-d',str(dest/'work'),str(inputs/'validate.sby')]
        row={'job_id':jid,'mode':j['mode'],'command':command,'cwd':str(inputs),'sources':{p.name:sha(p) for p in inputs.iterdir() if p.is_file()},'started_at':time.time()}
        print('START',jid,flush=True)
        with (dest/'console.log').open('w') as log:
            try:
                cp=subprocess.run(command,cwd=inputs,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=1900);row['exit_code']=cp.returncode
            except subprocess.TimeoutExpired:row['exit_code']=124
        sf=dest/'work/status';row['backend_status_raw']=sf.read_text().strip() if sf.exists() else 'missing';row['backend_status']=row['backend_status_raw'].split()[0]
        xp=dest/'work/validate.xml';props=[]
        if xp.exists():
            for tc in ET.parse(xp).findall('.//testcase'):
                if tc.get('type','').upper() not in ('ASSERT','COVER'):continue
                props.append({'label':tc.get('id'), 'kind':tc.get('type').lower(),'failed':tc.find('failure') is not None,'skipped':tc.find('skipped') is not None})
        kind='assert' if j['mode']=='prove' else 'cover';wanted={p['formalmc_label'] for p in j['properties'] if p['kind']==kind}
        found={p['label'] for p in props if p['kind']==kind and not p['failed'] and not p['skipped']}
        row.update({'expected_property_count':len(wanted),'actual_property_count':len(found),'missing_labels':sorted(wanted-found),'properties':props,'finished_at':time.time()})
        row['status']='passed' if row['exit_code']==0 and row['backend_status']=='PASS' and wanted<=found else ('failed' if row['backend_status']=='FAIL' else 'inconclusive' if row['backend_status'] in ('UNKNOWN','TIMEOUT') else 'error')
        receipt['runs'].append(row);save();print('DONE',jid,row['status'],row['backend_status'],len(found),'/',len(wanted),flush=True)
        if row['status']=='error':
            print('STOP: frontend/tool error requires inspection before continuing',flush=True)
            break
    receipt['all_passed']=all(x['status']=='passed' for x in receipt['runs']);save()
if __name__=='__main__':main()
