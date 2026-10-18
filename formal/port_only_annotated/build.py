#!/usr/bin/env python3
"""Build a port-only harness. RTL is copied byte-for-byte, never instrumented."""
import argparse, hashlib, json, re, shutil
from pathlib import Path
HERE=Path(__file__).resolve().parent

def build(a):
    # Reject missing/stale dependency comments before producing a runnable copy.
    from annotate_model_dependencies import annotate
    annotate(HERE, check=True)
    out=a.output.resolve()
    out.mkdir(parents=True,exist_ok=False)
    rtl=a.rtl.resolve(strict=True)
    names=['cmdbuf_rd_cmd.v','cmdbuf_rd_otb.v','cmdbuf_rd.v']
    for n in names: shutil.copyfile(rtl/n,out/n)
    header=(rtl/'cmdbuf_rd.v').read_text().split('module cmdbuf_rd (',1)[1].split('\n);',1)[0]
    ports=re.findall(r'\b(?:input|output)\s+wire\s+(?:\[[^\]]+\]\s*)?(\w+)',header)
    assert len(ports)==24
    connections=',\n'.join(f'    .{p}({p})' for p in ports)
    wrapper='`default_nettype none\nmodule cmdbuf_rd_formal ('+header+'\n);\ncmdbuf_rd dut (\n'+connections+'\n);\ncmdbuf_rd_port_sva check_ports (\n'+connections+'\n);\nendmodule\n`default_nettype wire\n'
    if a.profile=='longflow':
        assert not a.sim and not a.witness
        decls=re.sub(r'\b(?:input|output)\s+wire', 'wire', header)
        decls=re.sub(r',\s*(?=\n)', ';', decls).strip().rstrip(',')+';\n'
        driver="""reg [12:0] input_cycle = 13'd0;
reg [1:0] input_source = 2'd0;
always @(posedge clk) begin
    if (input_cycle!=8191) input_cycle<=input_cycle+1'b1;
    if (input_cycle==0 || input_source==2) input_source<=0;
    else input_source<=input_source+1'b1;
end
assign rst_n=(input_cycle!=0);
assign arvalid=(input_cycle!=0 && input_cycle<=4100 && (|arready));
assign src=input_source;
assign araddr=18'd0;
assign arid=input_cycle[7:0];
assign ar_port_id=input_cycle[4:0];
assign arresp=2'b00;
assign rready=3'b111;
assign rd_mem_status=16'd0;
assign ar_rd_gnt=8'hff;
assign rw_rd_gnt=8'hff;
assign mem_rdata=128'd0;
assign pc_err=1'b0;
"""
        decls=re.sub(r'\bwire\s+clk\s*;','',decls)
        wrapper='`default_nettype none\nmodule cmdbuf_rd_formal(input wire clk);\n'+decls+driver+'\ncmdbuf_rd dut (\n'+connections+'\n);\ncmdbuf_rd_port_sva check_ports (\n'+connections+'\n);\nendmodule\n`default_nettype wire\n'
    (out/'formal_top.sv').write_text(wrapper)
    (out/'cmdbuf_rd_port_bind.sv').write_text('bind cmdbuf_rd cmdbuf_rd_port_sva check_ports (\n'+connections+'\n);\n')
    for p in HERE.glob('cmdbuf_rd_port*'):
        if p.suffix in ('.sv','.svh'):shutil.copyfile(p,out/p.name)
    defs=['SYNTHESIS']
    if a.profile=='negative':defs+=['TP_NEGATIVE']
    elif a.profile=='idle_reset':defs+=['TP_IDLE_RESET']
    elif a.profile=='drain':defs+=['TP_DRAIN']
    elif a.profile.startswith('perf'):
        defs+=['TP_PERF']
        if a.profile!='perf_rr':defs+=['TP_PERF_SINGLE='+a.profile[-1]]
    mapping=json.loads((HERE/'property_map.json').read_text(encoding='utf8'))
    if a.mode=='cover' or a.sim:
        groups=sorted({r['testpoint'].rsplit('-',1)[0] for r in mapping['rows']}) if a.group=='all' else a.group.split(',')
        defs+=['TP_COVER_'+g.replace('-','_') for g in groups]
    if a.select_cover:
        selected=set(a.select_cover.split(','));found=set()
        for p in out.glob('cmdbuf_rd_port*.svh'):
            if p.name.endswith('macros.svh'):continue
            lines=p.read_text(encoding='utf8').splitlines()
            for i,line in enumerate(lines):
                m=re.search(r'`TP_COVER\((\w+),',line)
                if m:
                    if m[1] in selected:found.add(m[1])
                    else:lines[i]='// Unselected cover '+m[1]
            p.write_text('\n'.join(lines)+'\n',encoding='utf8')
        assert found==selected,selected-found
    if a.sim:
        defs+=['TP_SIM']
        shutil.copyfile(HERE/'port_witness.cpp',out/'port_witness.cpp')
    if a.assertions:
        keep=set(a.assertions.split(','));found=set()
        for p in out.glob('cmdbuf_rd_port*'):
            if p.suffix not in ('.sv','.svh') or p.name.endswith('macros.svh'):continue
            lines=p.read_text(encoding='utf8').splitlines()
            for i,line in enumerate(lines):
                m=re.search(r'`TP_ASSERT\((\w+),',line)
                if m:
                    if m[1] in keep:found.add(m[1])
                    else:lines[i]='// Unselected assertion '+m[1]
            p.write_text('\n'.join(lines)+'\n',encoding='utf8')
        assert found==keep,keep-found
    sources=names+['cmdbuf_rd_port_sva.sv','formal_top.sv']
    includes=sorted(p.name for p in out.glob('*.svh'))
    script='read_verilog -formal -sv -I. '+' '.join('-D'+d for d in defs)+' '+' '.join(sources)+'\nprep -top cmdbuf_rd_formal\n'
    if a.trim_outputs:
        assert not a.sim
        # Remove only wrapper export flags, then ordinary dead-cone optimization.
        # Every signal used by a selected assertion/cover remains in the cone.
        # No DUT source, transition, input constraint or property is rewritten.
        script+='flatten\nselect -module cmdbuf_rd_formal\ndelete -output w:*\nopt_clean\nselect -clear\n'
    options=f'mode {a.mode}\ndepth {a.depth}\ntimeout {a.timeout}\n'
    if a.skip:
        assert a.mode=='cover' and (a.witness or a.profile=='longflow'), 'Skipping is only supported for guided reachability, never general proof.'
        assert 0<=a.skip<a.depth
        options+='skip '+str(a.skip)+'\n'
    if a.mode=='cover':options+='cover_assert on\n'
    if a.witness:
        # Only public input ports are fixed; no DUT output/internal assumptions.
        fields=[('rst_n',1),('arvalid',1),('src',2),('araddr',18),('arid',8),('ar_port_id',5),('arresp',2),('rready',3),('rd_mem_status',16),('ar_rd_gnt',8),('rw_rd_gnt',8),('pc_err',1)]
        constraints=[]
        for line in a.witness.read_text().splitlines()[:a.depth]:
            values=list(map(int,line.split()));step=values[0]
            assert len(values)==17
            constraints+=['state '+str(step)]
            for (n,w),v in zip(fields,values[1:13]):
                assert 0<=v<2**w
                literal=('true' if v else 'false') if w==1 else '#b'+format(v,'0'+str(w)+'b')
                constraints+=['assume (= ['+n+'] '+literal+')']
            data=sum(values[13+i]<<(32*i) for i in range(4))
            constraints+=['assume (= [mem_rdata] #b'+format(data,'0128b')+')']
        (out/'input_witness.smtc').write_text('\n'.join(constraints)+'\n')
        shutil.copyfile(a.witness,out/'input_witness.inputs')
        options+='smtc input_witness.smtc\n';includes+=['input_witness.smtc']
    (out/'run.sby').write_text('[options]\n'+options+'\n[engines]\n'+a.engine+'\n\n[script]\n'+script+'\n[files]\n'+'\n'.join(sources+includes)+'\n')
    (out/'prepare.ys').write_text(script+'flatten\nasync2sync\ndffunmap\nopt_clean\nwrite_smt2 -wires model.smt2\nwrite_json compiled.json\n')
    (out/'native.f').write_text('+incdir+.\n+define+CMDBUF_NATIVE_SVA\n'+''.join('+define+'+d+'\n' for d in defs)+'\n'.join(sources)+'\n')
    (out/'sim.f').write_text('+incdir+.\n'+''.join('+define+'+d+'\n' for d in defs)+'\n'.join(sources)+'\n')
    unit='`define CMDBUF_NATIVE_SVA\n'+''.join('`define '+d.replace('=',' ',1)+'\n' for d in defs)+'\n'.join((out/n).read_text(encoding='utf8') for n in sources)
    (out/'native_input.sv').write_text(unit,encoding='utf8')
    (out/'formal.tcl').write_text('# Candidate for target FormalMC; not a certification of an unexecuted version.\nset here [file dirname [file normalize [info script]]]\ncd $here\nread_design -top cmdbuf_rd_formal -sysv -mfcu [list [file join $here native_input.sv]]\ndef_clk clk\nprove\nshow_prop -summary\nexit\n')
    (out/'ports.json').write_text(json.dumps(ports,indent=2)+'\n')
    record=dict(schema_version=1,profile=a.profile,mode=a.mode,depth=a.depth,port_only=True,rtl_unmodified=True,
                defines=defs,engine=a.engine,formalmc_executed=False,guided_input_witness=bool(a.witness),selected_assertions=a.assertions,cover_check_start=a.skip,trim_unused_wrapper_exports=a.trim_outputs,closed_input_driver=(a.profile=='longflow'),
                rtl={n:hashlib.sha256((rtl/n).read_bytes()).hexdigest() for n in names},
                files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()})
    (out/'inputs.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(dict(output=str(out),profile=a.profile,mode=a.mode,port_only=True)))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rtl',type=Path,default=HERE.parents[1]/'rtl');p.add_argument('--output',type=Path,required=True)
    p.add_argument('--profile',choices=['base','negative','idle_reset','drain','perf_rr','perf0','perf1','perf2','longflow'],default='base')
    p.add_argument('--mode',choices=['prove','bmc','cover'],default='prove');p.add_argument('--depth',type=int,default=20)
    p.add_argument('--timeout',type=int,default=300);p.add_argument('--engine',default='smtbmc yices')
    p.add_argument('--group',default='all');p.add_argument('--select-cover');p.add_argument('--sim',action='store_true')
    p.add_argument('--witness',type=Path,help='Optional port input trace for reachability replay, never a general proof.')
    p.add_argument('--assertions',help='Optional comma separated property labels for cone partitioning.')
    p.add_argument('--skip',type=int,default=0,help='Guided cover only: first checked step; does not prove assertions in the skipped prefix.')
    p.add_argument('--trim-outputs',action='store_true',help='Let Yosys remove wrapper outputs not used by selected properties; DUT source remains intact.')
    build(p.parse_args())
