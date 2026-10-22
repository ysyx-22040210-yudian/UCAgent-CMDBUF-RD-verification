#!/usr/bin/env python3
"""Run the independent relaxed checker; retain native source and SBY lowering evidence."""
import argparse, concurrent.futures, hashlib, json, os, shutil, subprocess, time
from pathlib import Path
from property_catalog import properties, lower_overlapping_implications

HERE=Path(__file__).resolve().parent
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def source():
    return (HERE/'cmdbuf_rd_relaxed_sva.sv').read_text(encoding='utf-8').replace(
        '`include "cmdbuf_rd_relaxed_model.svh"',
        (HERE/'cmdbuf_rd_relaxed_model.svh').read_text(encoding='utf-8'))
def catalog(text):
    multiplicity={p['label']:p['instances'] for p in json.loads((HERE/'property_scope.json').read_text(encoding='utf-8'))['properties']}
    result=properties(text)
    for p in result:p['instances']=multiplicity[p['label']]
    return result
def select(text,assertions,covers):
    for p in reversed(catalog(text)):
        keep=assertions if p['kind']=='assert' else covers if p['kind']=='cover' else None
        if keep is not None and p['label'] not in keep:
            text=text[:p['start']]+'\n'.join('// Unselected: '+line for line in text[p['start']:p['end']].split('\n'))+text[p['end']:]
    return text
def job(cfg,out):
    folder=out/cfg['name'];folder.mkdir(parents=True,exist_ok=False)
    native=source();selected=select(native,cfg.get('assertions'),cfg.get('covers'))
    executed,changes=lower_overlapping_implications(selected)
    (folder/'native_checker.sv').write_text(native,encoding='utf-8')
    (folder/'cmdbuf_rd_relaxed_sva.sv').write_text(executed,encoding='utf-8')
    files=['cmdbuf_rd.sv','cmdbuf_rd_cmd.sv','cmdbuf_rd_otb.sv','cmdbuf_rd_value_bag.sv','cmdbuf_rd_relaxed_sva.sv','formal_top.sv']
    inputs={}
    for name in files:
        if name=='cmdbuf_rd_relaxed_sva.sv':continue
        path=HERE/('rtl/'+name if name.startswith('cmdbuf_rd') and name not in ('cmdbuf_rd_value_bag.sv',) else name)
        shutil.copyfile(path,folder/name);inputs[str(path.relative_to(HERE))]=sha(path)
    for name in ('cmdbuf_rd_relaxed_sva.sv','cmdbuf_rd_relaxed_model.svh','property_scope.json','run.py','property_catalog.py'):
        inputs[name]=sha(HERE/name)
    inputs.update(native_sha256=sha(folder/'native_checker.sv'),executed_sha256=sha(folder/'cmdbuf_rd_relaxed_sva.sv'),
        initialization='One real reset cycle in Yosys sim; rst_n is unconstrained afterwards. No reset-sequence assume and no -zinit.')
    (folder/'inputs.json').write_text(json.dumps(inputs,indent=2)+'\n',encoding='utf-8')
    (folder/'lowering.json').write_text(json.dumps(changes,indent=2)+'\n',encoding='utf-8')
    props=catalog(selected)
    (folder/'selected_properties.json').write_text(json.dumps(props,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    sby='[options]\nmode {mode}\ndepth {depth}\ntimeout {timeout}\n\n[engines]\n{engine}\n\n'.format(**cfg)
    sby+='[script]\nread_slang --top cmdbuf_rd_formal --no-implicit-memories -D SYNTHESIS '+ ' '.join(files)+'\n'
    sby+='prep -top cmdbuf_rd_formal\nasync2sync\ndffunmap\nchformal -lower\n'
    sby+='sim -clock clk -resetn rst_n -rstlen 1 -n 1 -w -vcd reset_initialization.vcd\n\n[files]\n'+'\n'.join(files)+'\n'
    (folder/'run.sby').write_text(sby,encoding='utf-8')
    start=time.time()
    with (folder/'console.log').open('w',encoding='utf-8') as f:
        p=subprocess.run(['sby','run.sby'],cwd=str(folder),stdout=f,stderr=subprocess.STDOUT)
    statuspath=folder/'run/status';status=statuspath.read_text().strip() if statuspath.exists() else 'NO_STATUS'
    result=dict(cfg,status=status,returncode=p.returncode,seconds=round(time.time()-start,2),
        counts={k:sum(q['instances'] for q in props if q['kind']==k) for k in ('assert','assume','cover')})
    (folder/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result),flush=True)
    return result
def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True);ap.add_argument('--tools',type=Path)
    ap.add_argument('--group',action='append',choices=['prove','admission_prove','bmc','cover'])
    ap.add_argument('--jobs',type=int,default=2);ap.add_argument('--timeout',type=int,default=240)
    ap.add_argument('--bmc-depth',type=int,default=10);ap.add_argument('--cover-depth',type=int,default=32)
    ap.add_argument('--bmc-engine',choices=['smtbmc yices','abc bmc3'],default='smtbmc yices')
    args=ap.parse_args()
    if args.tools:os.environ['PATH']=str(args.tools)+os.pathsep+os.environ.get('PATH','')
    props=catalog(source());assert {p['label'] for p in props if p['kind']=='assume'}=={'E03_SRC','E04_ARRESP','E05_ZERO_READY','E06_SUCCESS_BUSY'}
    args.output.mkdir(parents=True,exist_ok=False)
    (args.output/'inventory.json').write_text(json.dumps(props,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    configs=[]
    for group in args.group or ['prove','bmc','cover']:
        cfg=dict(name=group,timeout=args.timeout)
        if group=='prove':cfg.update(mode='prove',depth=16,engine='abc pdr',assertions=['A_L_REQ_ONEHOT','A_L_R_ONEHOT','A_L_R_READY','A_L_RRESP_CODE'],covers=[])
        elif group=='admission_prove':cfg.update(mode='prove',depth=16,engine='abc pdr',assertions=['A_L_PENDING','A_L_PENDING_RANGE','A_L_READY','A_L_TOTAL','A_L_RESERVATION','A_L_SOURCE_LIMIT','A_L_SOURCE_NONEMPTY'],covers=[])
        elif group=='bmc':cfg.update(mode='bmc',depth=args.bmc_depth,engine=args.bmc_engine,assertions=None,covers=[])
        else:cfg.update(mode='cover',depth=args.cover_depth,engine='smtbmc yices',assertions=None,covers=None)
        configs.append(cfg)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:results=list(pool.map(lambda cfg:job(cfg,args.output),configs))
    (args.output/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
    return int(any(not r['status'].startswith('PASS') for r in results))
if __name__=='__main__':raise SystemExit(main())
