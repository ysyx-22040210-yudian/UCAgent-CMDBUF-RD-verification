#!/usr/bin/env python3
"""Test the checker itself with intentional relaxed passes and rejected corruptions.

This driver supplies public interface traces directly; it is not DUT simulation
or a proof. Negative tests expect a named native assertion to fail.
"""
import argparse, json, os, re, subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
def cmd(src=0,bank=0,low=1,ident=17,port=3,data=257,pc=0,oob=0,row=1):
    return dict(src=src,addr=(row<<7)|(bank<<3)|low,id=ident,port=port,data=data,pc=pc,oob=oob)
def rsp(c,**changes):
    r=dict(src=c['src'],id=c['id'],port=c['port'],low=c['addr']&7,data=c['data'],resp=3 if c['oob'] else c['pc'])
    r.update(changes);return r
def frames(accept,issue,respond,failed=None,length=None):
    failed=failed or {};occ=[0,0,0];wait=0;mem={};result=[]
    n=length or max(list(accept)+list(issue)+list(respond)+list(failed)+[0])+3
    for t in range(n):
        r=respond.get(t);a=accept.get(t);q=issue.get(t) or failed.get(t)
        after=[occ[i]-int(r is not None and r['src']==i) for i in range(3)]
        shared=sum(max(x-1,0) for x in after)
        ready=sum(int(sum(after)<9 and (after[i]==0 or shared<6))<<i for i in range(3))
        if a:assert ready&(1<<a['src']),('test construction AR not ready',t)
        success=t in issue
        if success:mem[t+4]=issue[t]
        m=mem.get(t);status=[0]*8
        if success:status[(q['addr']>>3)&7]=1<<((q['addr']>>6)&1)
        f=dict(arvalid=int(a is not None),arready=ready,araddr=a['addr'] if a else 0,
            src=a['src'] if a else 0,arid=a['id'] if a else 0,ar_port_id=a['port'] if a else 0,
            arresp=3 if a and a['oob'] else 0,rvalid=(1<<r['src']) if r else 0,rready=7,
            rdata=r['data'] if r else 0,rid=r['id'] if r else 0,r_port_id=r['port'] if r else 0,
            raddr=r['low'] if r else 0,rresp=r['resp'] if r else 0,
            req=(1<<((q['addr']>>3)&7)) if q else 0,arb_addr=(q['addr']>>6) if q else 0,
            pending_cnt=wait+int(a is not None)-int(success),
            ar_rd_gnt=(1<<((q['addr']>>3)&7)) if success else 0,
            rw_rd_gnt=(1<<((q['addr']>>3)&7)) if success else 0,
            mem_rdata=m['data'] if m else 0,pc_err=m['pc'] if m else 0,rd_mem_status=status)
        result.append(f)
        occ=[after[i]+int(a is not None and a['src']==i) for i in range(3)]
        wait=f['pending_cnt']
    return result
def cases():
    a=cmd();b=cmd(bank=1,low=2,ident=34,port=5,data=514,row=2)
    ac={0:a,1:b};iss={2:a,3:b};out=[]
    def add(name,trace,expected=None):out.append(dict(name=name,frames=trace,expected_assert=expected))
    add('normal_lifecycle',frames(ac,iss,{8:rsp(a),9:rsp(b)}))
    add('relaxed_same_source_reverse_order',frames(ac,iss,{8:rsp(b),9:rsp(a)}))
    add('relaxed_rdata_swapped_between_commands',frames(ac,iss,{8:rsp(a,data=b['data']),9:rsp(b,data=a['data'])}))
    add('relaxed_metadata_from_different_entries',frames(ac,iss,{8:rsp(a,port=b['port'],low=b['addr']&7),9:rsp(b,port=a['port'],low=a['addr']&7)}))
    add('reject_unknown_rdata',frames(ac,iss,{8:rsp(a,data=999)}),'A_L_RDATA_ANY')
    add('reject_unknown_id',frames(ac,iss,{8:rsp(a,id=254)}),'A_L_RID_ANY')
    add('reject_consumed_data_reuse',frames(ac,iss,{8:rsp(a),9:rsp(b,data=a['data'])}),'A_L_RDATA_ANY')
    add('reject_consumed_id_reuse',frames(ac,iss,{8:rsp(a),9:rsp(b,id=a['id'])}),'A_L_RID_ANY')
    # 当前没有任何旧数据；提前 R 同时违反数量与数据匹配义务，仿真器可先报告其中任一条。
    add('reject_same_cycle_MEM_to_R',frames({0:a},{2:a},{6:rsp(a)}),['A_L_R_AFTER_CAPTURE','A_L_RDATA_ANY'])
    add('retry_without_bubble',frames({0:a},{3:a},{8:rsp(a)},failed={2:a}))
    dup=cmd(bank=1,row=2) # 同源重复 ID/port/低地址/数据，仍是两次独立消费。
    add('duplicate_values_consumed_once_each',frames({0:a,1:dup},{2:a,3:dup},{8:rsp(a),9:rsp(dup)}))
    same=cmd() # 完全相同地址，第二次成功与前一次之间保留空闲采样拍。
    add('duplicate_full_command',frames({0:a,1:same},{2:a,4:same},{8:rsp(a),9:rsp(same)}))
    for pc in (0,1):
        oa=cmd(oob=1,pc=pc);nb=cmd(bank=1,row=2,pc=1-pc)
        add('oob_masks_pc_duplicate_data_'+str(pc),frames({0:oa,1:nb},{2:oa,3:nb},{8:rsp(oa),9:rsp(nb)}))
    xs=cmd(src=2,bank=1,row=2,ident=34,port=5,data=514)
    add('relaxed_wrong_RR_winner',frames({0:a,1:xs},{2:a,3:xs},{8:rsp(xs),9:rsp(a)}))
    add('relaxed_cross_source_data_swap',frames({0:a,1:xs},{2:a,3:xs},{8:rsp(a,data=514),9:rsp(xs,data=257)}))
    sixth=[cmd(bank=i,ident=10+i,port=i,row=i+1) for i in range(6)]
    add('relaxed_sixth_pending_command_issued',frames(dict(enumerate(sixth)),{7:sixth[5]},{}))
    add('reject_unknown_command',frames({0:a},{2:b},{}),'A_L_COMMAND_ANY')
    add('reject_request_one_cycle_after_AR',frames({0:a},{1:a},{}),'A_L_COMMAND_ANY')
    add('reject_unavailable_pc_flag',frames(ac,iss,{8:rsp(a,resp=1)}),'A_L_PC_BAD_POSSIBLE')
    add('reject_unavailable_address_error',frames(ac,iss,{8:rsp(a,resp=3)}),'A_L_ADDR_ERROR_ANY')
    ac={0:a};iss={2:a};rs={}
    for i in range(12):
        t=8+i*9;c=cmd(src=1,bank=1,low=i%8,ident=50+i,port=i,data=1000+i,row=20+i)
        ac[t]=c;iss[t+2]=c;rs[t+7]=rsp(c)
    rs[126]=rsp(a)
    add('old_entry_survives_more_than_nine_new_commands',frames(ac,iss,rs))
    # 满九项时 R 与 AR 同拍，三个字段集合均复用旧槽；数据捕获与另一个 R 也可同拍。
    full=[cmd(src=i//3,bank=i%8,low=i%8,ident=80+i,port=i,data=2000+i,row=40+i) for i in range(9)]
    ac=dict(enumerate(full));iss={i+2:c for i,c in enumerate(full)}
    new=cmd(src=0,bank=3,low=7,ident=99,port=20,data=3000,row=60)
    ac[16]=new;iss[18]=new;rs={16+i:rsp(c) for i,c in enumerate(full)};rs[25]=rsp(new)
    add('full_nine_same_cycle_reuse',frames(ac,iss,rs))
    return out

base_cases=cases

def cases():
    cs=base_cases()
    labels={
        'A_L_RDATA_ANY':['A_COMPARE_RDATA'],
        'A_L_RID_ANY':['A_COMPARE_RID'],
        'A_L_R_AFTER_CAPTURE':['A_COMPARE_RVALID'],
        'A_L_COMMAND_ANY':['A_COMPARE_REQ','A_COMPARE_ARB_ADDR'],
        'A_L_PC_BAD_POSSIBLE':['A_COMPARE_RRESP'],
        'A_L_ADDR_ERROR_ANY':['A_COMPARE_RRESP']}
    for c in cs:
        if c['expected_assert']:
            old=c['expected_assert'] if isinstance(c['expected_assert'],list) else [c['expected_assert']]
            c['expected_assert']=[v for n in old for v in labels[n]]
    a=cmd();b=cmd(bank=1,low=2,ident=34,port=5,data=514,row=2)
    def add(name,trace,expected=None):cs.append(dict(name=name,frames=trace,expected_assert=expected))
    def normal():return frames({0:a,1:b},{2:a,3:b},{8:rsp(a),9:rsp(b)})
    f=normal();f[4]['arready']=0;add('reject_arready_wrong',f,['A_COMPARE_ARREADY'])
    f=normal();f[4]['pending_cnt']=1;add('reject_pending_wrong',f,['A_COMPARE_PENDING_CNT'])
    f=normal();f[2]['req']=3;add('reject_req_multihot',f,['A_COMPARE_REQ','A_L_REQ_ONEHOT'])
    f=normal();f[2]['req']=4;f[2]['ar_rd_gnt']=4;f[2]['rw_rd_gnt']=4;f[2]['rd_mem_status']=[0,0,1,0,0,0,0,0]
    add('reject_req_wrong_bank',f,['A_COMPARE_REQ'])
    f=normal();f[2]['arb_addr']=100;add('reject_arb_addr_wrong',f,['A_COMPARE_ARB_ADDR'])
    f=normal();f[8]['rready']=6;add('reject_rvalid_when_not_ready',f,['A_COMPARE_RVALID','A_L_R_READY'])
    f=normal();f[8]['r_port_id']=31;add('reject_rport_wrong',f,['A_COMPARE_R_PORT_ID'])
    f=normal();f[8]['raddr']=7;add('reject_raddr_wrong',f,['A_COMPARE_RADDR'])
    f=normal();f[8]['rresp']=2;add('reject_rresp_encoding',f,['A_COMPARE_RRESP','A_L_RRESP_CODE'])
    f=normal();f[8]['rdata']=(1<<127)|257;add('reject_rdata_high_bit_corruption',f,['A_COMPARE_RDATA'])
    h=cmd(data=(1<<127)|257)
    add('complete_128_bit_high_value',frames({0:h},{2:h},{7:rsp(h)}))
    f=normal();f[4].update(rid=255,r_port_id=31,raddr=7,rresp=2,rdata=(1<<128)-1,arb_addr=4095)
    add('invalid_output_payloads_ignored',f)
    return cs

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--tools',type=Path);ap.add_argument('--compiler-bin',type=Path,help='Directory containing a C++20/coroutine-capable g++ for Verilator --timing');ap.add_argument('--atomic-library',type=Path,help='Optional installed libatomic.so.1; create only a build-local linker symlink');ap.add_argument('--output',type=Path,default=HERE/'build/monitor');ap.add_argument('--reuse-build',action='store_true',help='Reuse only if regenerated TB and checker source hash match the saved build');a=ap.parse_args()
    if a.tools:os.environ['PATH']=str(a.tools)+os.pathsep+os.environ.get('PATH','')
    if a.compiler_bin:os.environ['PATH']=str(a.compiler_bin)+os.pathsep+os.environ.get('PATH','')
    a.output.mkdir(parents=True,exist_ok=a.reuse_build);cs=cases()
    if os.name=='posix':
        import resource
        resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    source=(HERE/'cmdbuf_rd_compact_sva.sv').read_text(encoding='utf-8')
    declarations=[];widths={}
    for line in source.splitlines():
        match=re.match(r'\s*input wire\s+(\[\d+:\d+\]\s+)?(\w+)(\s+\[7:0\])?',line)
        if match:
            w,n,arr=match.groups();declarations.append('reg '+(w or '')+n+(arr or '')+';')
            widths[n]=int(w.split(':')[0][1:])+1 if w else 1
    tb='module monitor_tb;\n'+'\n'.join(declarations)+'\ncmdbuf_rd_compact_sva checks (.*);\ninteger case_id;\ninitial begin\n'
    tb+='if (!$value$plusargs("CASE=%d",case_id)) $fatal(1,"CASE missing");\nclk=0;rst_n=0;\n'
    for n,w in widths.items():
        if n in ('clk','rst_n'):continue
        if n=='rd_mem_status':tb+='for (integer i=0;i<8;i=i+1) rd_mem_status[i]=0;\n'
        else:tb+=n+'=0;\n'
    tb+='#5;clk=1;#5;clk=0;rst_n=1;\ncase(case_id)\n'
    for i,c in enumerate(cs):
        tb+=str(i)+': begin\n'
        for t,f in enumerate(c['frames']):
            tb+='// '+c['name']+' cycle '+str(t)+'\n'
            for n,v in f.items():
                if n=='rd_mem_status':tb+=''.join('rd_mem_status[%d]=2\'h%x;'%(b,x) for b,x in enumerate(v))+'\n'
                else:tb+=n+'='+str(widths[n])+"'h"+format(v,'x')+';\n'
            tb+='#5;clk=1;#5;clk=0;\n'
        tb+='end\n'
    tb+='endcase\n$display("MONITOR_PASS");$finish;end\nendmodule\n'
    import hashlib
    signature=hashlib.sha256((tb+source+(HERE/'cmdbuf_rd_compact_model.svh').read_text(encoding='utf-8')+(HERE/'cmdbuf_rd_field_set.sv').read_text(encoding='utf-8')).encode('utf-8')).hexdigest()
    if a.reuse_build:
        assert (a.output/'monitor_tb.sv').read_text(encoding='utf-8')==tb,'Changed testbench requires rebuild'
        if (a.output/'build_signature.txt').exists():assert (a.output/'build_signature.txt').read_text().strip()==signature,'Changed checker requires rebuild'
        else:raise RuntimeError('No recorded build signature; rebuild required')
    else:(a.output/'monitor_tb.sv').write_text(tb,encoding='utf-8')
    args=['verilator','--binary','--timing','--assert','-Wno-WIDTHEXPAND','-Wno-WIDTHTRUNC','--top-module','monitor_tb','--Mdir',str(a.output/'obj'),'-I'+str(HERE),str(HERE/'cmdbuf_rd_field_set.sv'),str(HERE/'cmdbuf_rd_compact_sva.sv'),str(a.output/'monitor_tb.sv')]
    if a.atomic_library and not a.reuse_build:
        lib=a.atomic_library.resolve();assert lib.is_file(),str(lib)
        (a.output/'linker').mkdir();(a.output/'linker/libatomic.so').symlink_to(lib)
        args.extend(['-LDFLAGS','-L'+str((a.output/'linker').resolve())])
    if not a.reuse_build:
        with (a.output/'build.log').open('w') as f:p=subprocess.run(args,stdout=f,stderr=subprocess.STDOUT)
        if p.returncode:raise RuntimeError('compile failed; see build.log')
        (a.output/'build_signature.txt').write_text(signature+'\n')
    results=[]
    for i,c in enumerate(cs):
        p=subprocess.run([str(a.output/'obj/Vmonitor_tb'),'+CASE='+str(i)],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        log=p.stdout.decode('utf-8',errors='replace');(a.output/(c['name']+'.log')).write_text(log,encoding='utf-8')
        expected=c['expected_assert'] if isinstance(c['expected_assert'],list) else [c['expected_assert']]
        ok=(p.returncode!=0 and any(name in log for name in expected)) if c['expected_assert'] else (p.returncode==0 and 'MONITOR_PASS' in log)
        results.append(dict(name=c['name'],status='PASS' if ok else 'FAIL',expected_assert=c['expected_assert'],returncode=p.returncode,cycles=len(c['frames'])))
        print(json.dumps(results[-1]),flush=True)
    (a.output/'results.json').write_text(json.dumps(dict(scope='Native direct-comparison checker-only traces using original public ports; not DUT simulation or a universal proof.',cases=results),indent=2)+'\n',encoding='utf-8')
    return int(any(r['status']!='PASS' for r in results))
if __name__=='__main__':raise SystemExit(main())
