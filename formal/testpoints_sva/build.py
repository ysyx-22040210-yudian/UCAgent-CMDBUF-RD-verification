#!/usr/bin/env python3
"""Build a fresh, isolated SVA/SBY job without modifying synthesizable RTL.

Native SVA: use native.f (bind) or native_instrumented.f (read-only ports).
Yosys: run `sby -f run.sby` in the output folder. The expressions are identical
and macros select the supported property syntax. Results are not imported from
the historical release. All generated inputs are hashed in inputs.json.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

HERE=Path(__file__).resolve().parent

def pack(name,n):return '{'+', '.join(f'{name}[{i}]' for i in reversed(range(n)))+'}'
TOP={
 'o_alloc':(1,'alloc_fire'),'o_retire':(1,'retire_fire'),
 'o_issue':(1,'issue_success'),'o_capture':(1,'capture_valid'),
 'o_alloc_e':(4,'alloc_entry'),'o_retire_e':(4,'retire_entry'),
 'o_issue_e':(4,'issue_entry'),'o_capture_e':(4,'capture_entry'), 'o_rsp_e':(4,'rsp_entry')}
CMD={
 'o_valid':(9,'valid_q'),'o_issued':(9,'issued_q'),'o_done':(9,'done_q'),
 'o_addr':(162,pack('addr_q',9)), 'o_src':(18,pack('src_q',9)),
 'o_arresp':(18,pack('arresp_q',9)), 'o_id':(72,pack('id_q',9)),
 'o_port':(45,pack('port_q',9)), 'o_older':(81,pack('older_q',9)),
 'o_occ':(12,pack('occ_q',3)), 'o_rr':(2,'rr_ptr_q'),
 'o_attempt':(1,'issue_valid_q'),'o_select':(1,'select_valid'),
 'o_select_e':(4,'select_entry'),'o_pending':(9,'pending_mask'),
 'o_pool':(9,'rank_pool'),'o_window':(9,'window_mask'),
 'o_idle':(9,'bank_idle_mask'),'o_candidate':(9,'candidate_mask'),
 'o_selected':(9,'select_onehot')}
OTB={
 'o_data':(1152,pack('data_q',9)), 'o_pc':(9,'pc_err_q'),
 'o_reserved':(9,'reserved_q'),'o_otb_done':(9,'done_q'),
 'o_ret_valid':(4,'ret_valid_q'),'o_ret_entry':(16,pack('ret_entry_q',4))}
OBS={**TOP,**CMD,**OTB}

def decl(name,width,kind='wire'):
    return f'{kind} '+(f'[{width-1}:0] ' if width!=1 else '')+name

def instrument(text,ports,assigns):
    p=text.index('\n);')
    text=text[:p]+',\n'+',\n'.join('    '+decl(n,w,'output wire') for n,(w,_) in ports.items())+text[p:]
    additions='\n// Read-only formal observation ports. No driver of DUT state.\n'
    additions+=''.join(f'assign {n} = {expr};\n' for n,(_,expr) in assigns.items())
    return text.replace('endmodule',additions+'endmodule')

def connect_instance(text,instance,ports):
    pos=text.index(' '+instance+' (')
    end=text.index('\n    );',pos)
    return text[:end]+',\n'+',\n'.join(f'        .{n}({n})' for n in ports)+text[end:]

def build(args):
    out=args.output.resolve()
    if out.exists():raise ValueError('Use a fresh output directory; existing evidence is never overwritten.')
    rtl=args.rtl.resolve(strict=True)
    out.mkdir(parents=True)
    raw={p.name:p.read_text(encoding='utf8') for p in rtl.glob('*.v')}
    if set(raw)!={'cmdbuf_rd.v','cmdbuf_rd_cmd.v','cmdbuf_rd_otb.v'}:
        raise ValueError('Unexpected RTL module inventory')
    for name,text in raw.items():(out/name).write_text(text,encoding='utf8')
    (out/'cmdbuf_rd_cmd_observed.v').write_text(instrument(raw['cmdbuf_rd_cmd.v'],CMD,CMD).replace('module cmdbuf_rd_cmd (','module cmdbuf_rd_cmd_observed ('),encoding='utf8')
    (out/'cmdbuf_rd_otb_observed.v').write_text(instrument(raw['cmdbuf_rd_otb.v'],OTB,OTB).replace('module cmdbuf_rd_otb (','module cmdbuf_rd_otb_observed ('),encoding='utf8')
    top=instrument(raw['cmdbuf_rd.v'],OBS,TOP)
    top=connect_instance(top,'u_cmd',CMD);top=connect_instance(top,'u_otb',OTB)
    top=top.replace('module cmdbuf_rd (','module cmdbuf_rd_observed (').replace('cmdbuf_rd_cmd u_cmd','cmdbuf_rd_cmd_observed u_cmd').replace('cmdbuf_rd_otb u_otb','cmdbuf_rd_otb_observed u_otb')
    (out/'cmdbuf_rd_observed.v').write_text(top,encoding='utf8')
    header=raw['cmdbuf_rd.v'].split('module cmdbuf_rd (',1)[1].split('\n);',1)[0]
    public=re.findall(r'\b(?:input|output)\s+wire\s+(?:\[[^\]]+\]\s*)?(\w+)',header)
    assert len(public)==24,len(public)
    wires='\n'.join(decl(n,w)+';' for n,(w,_) in OBS.items())
    ports=',\n'.join(f'    .{n}({n})' for n in public+list(OBS))
    wrapper='`default_nettype none\nmodule cmdbuf_rd_formal ('+header+'\n);\n'+wires+'\ncmdbuf_rd_observed dut (\n'+ports+'\n);\ncmdbuf_rd_sva tp_check (\n'+ports+'\n);\nendmodule\n`default_nettype wire\n'
    (out/'formal_top.sv').write_text(wrapper,encoding='utf8')
    native='`default_nettype none\nmodule cmdbuf_rd_native_formal ('+header+'\n);\ncmdbuf_rd dut ('+', '.join(f'.{p}({p})' for p in public)+');\nendmodule\n`default_nettype wire\n'
    (out/'native_top.sv').write_text(native,encoding='utf8')
    def path_expr(expr,instance):
        return re.sub(r'\b([A-Za-z_]\w*)(?=\[|\b)',lambda m:instance+'.'+m.group(1),expr)
    bindings={n:n for n in public}
    bindings.update({n:e for n,(_,e) in TOP.items()})
    bindings.update({n:path_expr(e,'u_cmd') for n,(_,e) in CMD.items()})
    bindings.update({n:path_expr(e,'u_otb') for n,(_,e) in OTB.items()})
    bind='bind cmdbuf_rd cmdbuf_rd_sva tp_check (\n'+',\n'.join(f'    .{n}({e})' for n,e in bindings.items())+'\n);\n'
    (out/'cmdbuf_rd_bind.sv').write_text(bind,encoding='utf8')
    for p in HERE.glob('cmdbuf_rd_sva*'):
        if p.suffix in ['.sv','.svh']:shutil.copy2(p,out/p.name)
    defs=['SYNTHESIS']
    profile=args.profile
    if profile=='negative':defs+=['TP_NEGATIVE']
    elif profile=='idle_reset':defs+=['TP_IDLE_RESET']
    elif profile=='drain':defs+=['TP_DRAIN']
    elif profile.startswith('perf'):
        defs+=['TP_PERF']
        if profile!='perf_rr':defs+=['TP_PERF_SINGLE='+profile[-1]]
    if args.mode=='cover':
        mapping=json.loads((HERE/'property_map.json').read_text(encoding='utf8'))
        groups=sorted({r['testpoint'].rsplit('-',1)[0] for r in mapping['rows']}) if args.group=='all' else args.group.split(',')
        defs+=['TP_COVER_'+g.replace('-','_') for g in groups]
    if args.select_cover:
        names=set(args.select_cover.split(','))
        coverpath=out/'cmdbuf_rd_sva_covers.svh'
        content=coverpath.read_text(encoding='utf8').splitlines()
        found=set()
        for n,line in enumerate(content):
            m=re.match(r'`TP_COVER\((\w+),',line)
            if m:
                if m[1] in names:found.add(m[1])
                else:content[n]='// Disabled by --select-cover: '+m[1]
        if found!=names:raise ValueError('Unknown cover labels: '+str(names-found))
        coverpath.write_text('\n'.join(content)+'\n',encoding='utf8')
    sources=['cmdbuf_rd_cmd_observed.v','cmdbuf_rd_otb_observed.v','cmdbuf_rd_observed.v','cmdbuf_rd_sva.sv','formal_top.sv']
    script='read_verilog -formal -sv -I. '+' '.join('-D'+d for d in defs)+' '+' '.join(sources)+'\nprep -top cmdbuf_rd_formal\n'
    options=f'mode {args.mode}\ndepth {args.depth}\ntimeout {args.timeout}\n'
    if args.mode=='cover':options+='cover_assert on\n'
    sby='[options]\n'+options+'\n[engines]\nsmtbmc '+args.solver+'\n\n[script]\n'+script+'\n[files]\n'+'\n'.join(sources+['cmdbuf_rd_sva_macros.svh','cmdbuf_rd_sva_covers.svh','cmdbuf_rd_sva_profiles.svh','cmdbuf_rd_sva_scenarios.svh'])+'\n'
    (out/'run.sby').write_text(sby,encoding='utf8')
    (out/'prepare.ys').write_text(script+'flatten\nasync2sync\ndffunmap\nopt_clean\nwrite_smt2 -wires model.smt2\nwrite_json compiled.json\n',encoding='utf8')
    (out/'native.f').write_text('+incdir+.\n+define+CMDBUF_NATIVE_SVA\n'+''.join('+define+'+d+'\n' for d in defs)+'\n'.join(['cmdbuf_rd_cmd.v','cmdbuf_rd_otb.v','cmdbuf_rd.v','cmdbuf_rd_sva.sv','cmdbuf_rd_bind.sv','native_top.sv'])+'\n',encoding='utf8')
    (out/'native_instrumented.f').write_text('+incdir+.\n+define+CMDBUF_NATIVE_SVA\n'+''.join('+define+'+d+'\n' for d in defs)+'\n'.join(sources)+'\n',encoding='utf8')
    single_unit='`define CMDBUF_NATIVE_SVA\n'+''.join('`define '+d.replace('=',' ',1)+'\n' for d in defs)
    single_unit+='\n'.join((out/f).read_text(encoding='utf8') for f in sources)
    (out/'native_input.sv').write_text(single_unit,encoding='utf8')
    (out/'formal.tcl').write_text('# Native SVA candidate; real FormalMC 2024 execution is not certified.\nset here [file dirname [file normalize [info script]]]\ncd $here\nread_design -top cmdbuf_rd_formal -sysv -mfcu [list [file join $here native_input.sv]]\ndef_clk clk\nprove\nshow_prop -summary\nexit\n',encoding='utf8')
    record={'schema_version':1,'profile':profile,'mode':args.mode,'depth':args.depth,
            'defines':defs,'native_sva_executed':False,'formalmc_executed':False,
            'rtl':{n:hashlib.sha256((rtl/n).read_bytes()).hexdigest() for n in raw},
            'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()}}
    (out/'inputs.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf8')
    print(json.dumps({'output':str(out),'profile':profile,'mode':args.mode,'files':len(record['files'])}))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rtl',type=Path,default=HERE.parents[1]/'rtl')
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--profile',choices=['base','negative','idle_reset','drain','perf_rr','perf0','perf1','perf2'],default='base')
    p.add_argument('--mode',choices=['prove','bmc','cover'],default='prove')
    p.add_argument('--depth',type=int,default=20)
    p.add_argument('--timeout',type=int,default=600)
    p.add_argument('--solver',default='yices')
    p.add_argument('--group',default='all',help='Comma-separated cover groups, e.g. F-CON,F-WIN')
    p.add_argument('--select-cover',help='Optional exact labels for focused nonvacuity runs')
    build(p.parse_args())
