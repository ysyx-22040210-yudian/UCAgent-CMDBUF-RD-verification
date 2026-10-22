#!/usr/bin/env python3
"""运行只有原始顶层接口的直接比较检查器；支持按输出组选择属性。

未选中的 assert 仅在执行副本中移除，绝不转成 assume。
可读源码、同拍蕴含适配、RTL 和实际命令分别保存在每个作业目录。
"""
import argparse,concurrent.futures,hashlib,json,os,shutil,subprocess,time
from pathlib import Path
from property_catalog import properties,lower_overlapping_implications
HERE=Path(__file__).resolve().parent
DEFAULT_GROUPS=['ports','admission','pending','request','response','id','port','address','status','data','cover']
RTL_FILES=['cmdbuf_rd.sv','cmdbuf_rd_cmd.sv','cmdbuf_rd_otb.sv']

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def source():
    return (HERE/'cmdbuf_rd_compact_sva.sv').read_text(encoding='utf-8').replace('`include "cmdbuf_rd_compact_model.svh"',(HERE/'cmdbuf_rd_compact_model.svh').read_text(encoding='utf-8'))

def catalog(text):
    scope={p['label']:p for p in json.loads((HERE/'scope.json').read_text(encoding='utf-8'))['properties']}
    result=properties(text)
    for p in result:p.update(instances=scope[p['label']]['instances'],group=scope[p['label']]['group'])
    return result

def selected(text,group,mode):
    for p in reversed(catalog(text)):
        keep=p['kind']=='assume' or (p['kind']=='assert' and (group in ('all','cover') or p['group']==group)) or (p['kind']=='cover' and mode=='cover')
        if not keep:text=text[:p['start']]+'\n'.join('// Unselected: '+x for x in text[p['start']:p['end']].split('\n'))+text[p['end']:]
    return text

def job(cfg,out):
    dest=out/cfg['group'];dest.mkdir(parents=True,exist_ok=False)
    native=source();sel=selected(native,cfg['group'],cfg['mode']);exe,lowering=lower_overlapping_implications(sel)
    (dest/'native_checker.sv').write_text(native,encoding='utf-8')
    (dest/'cmdbuf_rd_compact_sva.sv').write_text(exe,encoding='utf-8')
    files=RTL_FILES+['cmdbuf_rd_field_set.sv','cmdbuf_rd_compact_sva.sv','formal_top.sv'];hashes={}
    for name in files:
        if name=='cmdbuf_rd_compact_sva.sv':continue
        path=HERE/'rtl'/name if name in RTL_FILES else HERE/name
        shutil.copyfile(path,dest/name);hashes[str(path.relative_to(HERE))]=sha(path)
    snap=dest/'source_snapshot';snap.mkdir()
    for name in ('cmdbuf_rd_compact_sva.sv','cmdbuf_rd_compact_model.svh','scope.json','run.py','property_catalog.py'):
        hashes[name]=sha(HERE/name);shutil.copyfile(HERE/name,snap/name)
    hashes.update(executed_sha256=sha(dest/'cmdbuf_rd_compact_sva.sv'),native_sha256=sha(dest/'native_checker.sv'),
        initialization='Real reset simulation once, rst_n unconstrained afterwards. No reset-sequence assume or extra checker inputs.')
    (dest/'inputs.json').write_text(json.dumps(hashes,indent=2)+'\n',encoding='utf-8')
    (dest/'lowering.json').write_text(json.dumps(lowering,indent=2)+'\n',encoding='utf-8')
    props=catalog(sel)
    (dest/'selected_properties.json').write_text(json.dumps(props,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    sby='[options]\nmode {mode}\ndepth {depth}\ntimeout {timeout}\n\n[engines]\n{engine}\n\n'.format(**cfg)
    sby+='[script]\nread_slang --top cmdbuf_rd_formal --no-implicit-memories -D SYNTHESIS '+' '.join(files)+'\n'
    sby+='prep -top cmdbuf_rd_formal\nasync2sync\ndffunmap\nchformal -lower\n'
    sby+='sim -clock clk -resetn rst_n -rstlen 1 -n 1 -w -vcd reset_initialization.vcd\n'
    sby+='stat -width\nwrite_json initialized.json\n\n[files]\n'+'\n'.join(files)+'\n'
    (dest/'run.sby').write_text(sby,encoding='utf-8');start=time.time()
    with (dest/'console.log').open('w') as f:p=subprocess.run(['sby','run.sby'],cwd=str(dest),stdout=f,stderr=subprocess.STDOUT)
    st=dest/'run/status';status=st.read_text().strip() if st.exists() else 'NO_STATUS'
    result=dict(cfg,status=status,returncode=p.returncode,seconds=round(time.time()-start,2),
        counts={k:sum(x['instances'] for x in props if x['kind']==k) for k in ('assert','assume','cover')})
    (dest/'result.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(result),flush=True);return result

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--tools',type=Path)
    ap.add_argument('--group',action='append',choices=DEFAULT_GROUPS+['all'])
    ap.add_argument('--depth',type=int,default=10);ap.add_argument('--cover-depth',type=int,default=32)
    ap.add_argument('--timeout',type=int,default=180);ap.add_argument('--jobs',type=int,default=3)
    ap.add_argument('--prove-groups',action='store_true')
    ap.add_argument('--engine',choices=['smtbmc yices','abc bmc3'],default='smtbmc yices');a=ap.parse_args()
    if a.tools:os.environ['PATH']=str(a.tools)+os.pathsep+os.environ.get('PATH','')
    assert {x['label'] for x in catalog(source()) if x['kind']=='assume'}=={'E03_SRC','E04_ARRESP','E05_ZERO_READY','E06_SUCCESS_BUSY'}
    a.output.mkdir(parents=True,exist_ok=False);jobs=[]
    for g in a.group or DEFAULT_GROUPS:
        mode='cover' if g=='cover' else 'prove' if g=='ports' or a.prove_groups else 'bmc'
        jobs.append(dict(group=g,mode=mode,depth=a.cover_depth if mode=='cover' else a.depth,timeout=a.timeout,
            engine='abc pdr' if mode=='prove' else 'smtbmc yices' if mode=='cover' else a.engine))
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:results=list(pool.map(lambda c:job(c,a.output),jobs))
    (a.output/'results.json').write_text(json.dumps(results,indent=2)+'\n',encoding='utf-8')
    return int(any(not x['status'].startswith('PASS') for x in results))
if __name__=='__main__':raise SystemExit(main())
