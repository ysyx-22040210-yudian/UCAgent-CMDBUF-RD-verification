#!/usr/bin/env python3
"""Confirm ENT-12 with a declared legal-input schedule; not an unrestricted proof."""
import argparse,json,os
from pathlib import Path
import run

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--tools',type=Path)
    args=ap.parse_args()
    if args.tools:os.environ['PATH']=str(args.tools)+os.pathsep+os.environ.get('PATH','')
    original_expand=run.expand
    # Expand the normal checker first. Only the top-level result receives witness assumptions.
    def with_witness(path):
        text=original_expand(path)
        if path.name=='cmdbuf_rd_port_sva.sv':
            assert text.count('\nendmodule')==1
            text=text.replace('\nendmodule','\n'+(run.HERE/'cmdbuf_rd_long_witness.svh').read_text(encoding='utf-8')+'\nendmodule')
        return text
    run.expand=with_witness
    args.output.mkdir(parents=True,exist_ok=False)
    cfg=dict(name='ent_long_guided',mode='cover',engine='smtbmc yices',depth=48,timeout=180,
             assertions=None,covers=['C_CC_ENT_12_MAIN'])
    result=run.job(cfg,args.output)
    result['scope']='Guided legal-input witness only; W_LONG_* assumptions are not the design environment and not used for unrestricted proofs.'
    (args.output/'results.json').write_text(json.dumps([result],indent=2)+'\n',encoding='utf-8')
    return int(not result['status'].startswith('PASS'))

if __name__=='__main__':raise SystemExit(main())
