#!/usr/bin/env python3
"""Run Corner native SVA on unchanged SV RTL, with explicit source/execution hashes.

Cover jobs select labels, never add assumptions to force stimulus or DUT output.
Initialization simulates real reset once; this is tool setup, not a reset testcase.
read_slang's same-sample |-> adapter operates only on a saved execution copy.
"""
import argparse, concurrent.futures, hashlib, json, os, re, shutil, subprocess, sys, time
from pathlib import Path
HERE=Path(__file__).resolve().parent
# 本交付目录即工程根；所有源文件均从这里寻找，不引用原仓库的其他目录。
ROOT=HERE
BASE=HERE
sys.path.insert(0,str(BASE))
from property_catalog import properties, lower_overlapping_implications

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def expand(path):
    content=path.read_text(encoding='utf-8')
    def repl(match):
        name=match.group(1)
        for folder in (HERE,BASE):
            target=folder/name
            if target.exists(): return '// BEGIN '+name+'\n'+expand(target)+'\n// END '+name
        raise FileNotFoundError(name)
    return re.sub(r'`include\s+"([^"]+)"',repl,content)

def all_properties(text):
    result=properties(text)
    for p in result:
        if p['label'] in ('A_CC_SRC_LIMIT','A_CC_R_NONEMPTY'): p['instances']=3
        if p['label']=='W_LONG_STATUS':p['instances']=8
    return result

def select(text,covers=None,assertions=None):
    for p in reversed(all_properties(text)):
        excluded=(p['kind']=='cover' and covers is not None and p['label'] not in covers) or \
                 (p['kind']=='assert' and assertions is not None and p['label'] not in assertions)
        if excluded:
            text=text[:p['start']]+'\n'.join('// Unselected: '+line for line in text[p['start']:p['end']].split('\n'))+text[p['end']:]
    return text

def job(cfg,out):
    folder=out/cfg['name'];folder.mkdir(parents=True,exist_ok=False)
    text=expand(BASE/'cmdbuf_rd_port_sva.sv')
    native=folder/'native_checker.sv';native.write_text(text,encoding='utf-8')
    selected=select(text,cfg.get('covers'),cfg.get('assertions'))
    executed,changes=lower_overlapping_implications(selected)
    checker=folder/'cmdbuf_rd_port_sva.sv';checker.write_text(executed,encoding='utf-8')
    files=[];manifest={}
    originals=[BASE/'cmdbuf_rd_port_sva.sv',BASE/'cmdbuf_rd_reference_model.svh',BASE/'cmdbuf_rd_xau_order_model.svh']+sorted(HERE.glob('*.svh'))+sorted((HERE/'optional').glob('*.svh'))
    for p in originals: manifest[str(p.relative_to(ROOT))]=sha(p)
    for p in [ROOT/'rtl'/n for n in ('cmdbuf_rd.sv','cmdbuf_rd_cmd.sv','cmdbuf_rd_otb.sv')]+[BASE/'formal_top.sv']:
        shutil.copyfile(str(p),str(folder/p.name));files.append(p.name);manifest[str(p.relative_to(ROOT))]=sha(p)
    files.append(checker.name)
    (folder/'lowering.json').write_text(json.dumps(changes,indent=2)+'\n',encoding='utf-8')
    selected_props=all_properties(selected)
    (folder/'selected_properties.json').write_text(json.dumps(selected_props,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    manifest.update(native_sha256=sha(native),executed_sha256=sha(checker),initial_state='One cycle of real RTL/checker reset simulation; no -zinit, no reset-sequence assume. rst_n unconstrained afterwards; properties disabled when low.')
    (folder/'inputs.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    sby='[options]\nmode {mode}\ndepth {depth}\ntimeout {timeout}\n\n[engines]\n{engine}\n\n'.format(**cfg)
    sby+='[script]\nread_slang --top cmdbuf_rd_formal --no-implicit-memories -D SYNTHESIS -D CMDBUF_CORNER_SUITE '+ ' '.join(files)+'\n'
    sby+='prep -top cmdbuf_rd_formal\nasync2sync\ndffunmap\nchformal -lower\n'
    sby+='sim -clock clk -resetn rst_n -rstlen 1 -n 1 -w -vcd reset_initialization.vcd\n\n[files]\n'+'\n'.join(files)+'\n'
    (folder/'run.sby').write_text(sby,encoding='utf-8')
    start=time.time()
    with (folder/'console.log').open('w',encoding='utf-8') as handle:
        proc=subprocess.run(['sby','run.sby'],cwd=str(folder),stdout=handle,stderr=subprocess.STDOUT)
    status_file=folder/'run/status'
    status=status_file.read_text(encoding='utf-8').strip() if status_file.exists() else 'NO_STATUS'
    log=(folder/'console.log').read_text(encoding='utf-8',errors='replace')
    reached=[]
    for line in log.splitlines():
        if 'Reached cover statement' in line: reached.append(line)
    result=dict(cfg,status=status,returncode=proc.returncode,elapsed_seconds=round(time.time()-start,2),
                counts={k:sum(p['instances'] for p in selected_props if p['kind']==k) for k in ('assert','assume','cover')},
                reached_lines=reached,inputs_sha256=sha(folder/'inputs.json'))
    (folder/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('covers','reached_lines')}),flush=True)
    return result

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--output',type=Path,required=True);ap.add_argument('--tools',type=Path)
    ap.add_argument('--group',action='append',help='AR/CAP/ENT/WIN/ARB/CNT/MEM/RSP/ERR/CON/BIZ/ENV, or base/prove/admission_prove/bmc')
    ap.add_argument('--jobs',type=int,default=2);ap.add_argument('--timeout',type=int,default=360)
    ap.add_argument('--depth',type=int,default=48)
    ap.add_argument('--bmc-depth',type=int,default=10,help='Bound, not an induction proof; recorded in results')
    args=ap.parse_args()
    if args.tools:os.environ['PATH']=str(args.tools)+os.pathsep+os.environ.get('PATH','')
    text=expand(BASE/'cmdbuf_rd_port_sva.sv');props=all_properties(text)
    assumes=[p['label'] for p in props if p['kind']=='assume']
    assert set(assumes)=={'E03_SRC','E04_ARRESP','E05_ZERO_READY','E06_SUCCESS_BUSY'},assumes
    assert not re.search(r'\b(started|active)\b\s*[;=]',text)
    args.output.mkdir(parents=True,exist_ok=False)
    (args.output/'property_inventory.json').write_text(json.dumps(props,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    jobs=[]
    groups=args.group or ['prove','bmc','base','AR','CAP','ENT','WIN','ARB','CNT','MEM','RSP','ERR','CON','BIZ','ENV']
    for g in groups:
        cfg=dict(name=g.lower(),timeout=args.timeout)
        if g=='prove':cfg.update(mode='prove',depth=12,engine='abc pdr',assertions=['A_REQ_ONEHOT','A_R_ONEHOT','A_R_READY'],covers=[])
        elif g=='bmc':cfg.update(mode='bmc',depth=args.bmc_depth,engine='abc bmc3',assertions=None,covers=[])
        elif g=='admission_prove':cfg.update(mode='prove',depth=12,engine='abc pdr',assertions=['A_CC_TOTAL','A_CC_BUDGET','A_CC_READY','A_CC_SRC_LIMIT','A_CC_R_NONEMPTY'],covers=[])
        else:
            labels=[p['label'] for p in props if p['kind']=='cover' and (not p['label'].startswith('C_CC_') if g=='base' else p['label'].startswith('C_CC_'+g+'_'))]
            assert labels,g
            cfg.update(mode='cover',depth=args.depth,engine='smtbmc yices',assertions=None,covers=labels)
        jobs.append(cfg)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results=list(pool.map(lambda c:job(c,args.output),jobs))
    (args.output/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
    return int(any(not r['status'].startswith('PASS') for r in results))

if __name__=='__main__': raise SystemExit(main())
