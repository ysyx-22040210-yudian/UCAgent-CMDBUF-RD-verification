"""Portable replay engine; oracle/functions copied verbatim from the audited campaign."""
import hashlib, json, os, subprocess, time
from pathlib import Path
ROOT = Path(__file__).resolve().parent
ORIGINAL = ROOT / 'rtl'
FILES = ['cmdbuf_rd.sv', 'cmdbuf_rd_cmd.sv', 'cmdbuf_rd_otb.sv']
WIDTHS = {'rst_n':1,'arvalid':1,'araddr':18,'src':2,'arid':8,'ar_port_id':5,'arresp':2,'rready':3,'ar_rd_gnt':8,'rd_mem_status':16,'mem_rdata':128,'pc_err':1,'rw_rd_gnt':8}
ENV = os.environ.copy()
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def cmd(args,cwd,log,timeout=120):
    t=time.monotonic()
    try:
        p=subprocess.run(args,cwd=str(cwd),env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True,timeout=timeout)
        code=p.returncode;s=p.stdout;status='finished'
    except subprocess.TimeoutExpired as e:
        code=None;s=e.stdout or '';s=s.decode('utf-8','replace') if isinstance(s,bytes) else s;status='timeout'
    Path(log).write_text(s,encoding='utf-8')
    return dict(command=args,exit_code=code,status=status,seconds=time.monotonic()-t,log=str(log),log_sha256=sha(log))

def observations():
    out={x:x for x in ['arready','req','arb_addr','pending_cnt','rvalid','rdata','rid','r_port_id','raddr','rresp']}
    out.update({x:'dut.'+x for x in ['alloc_fire','alloc_entry','retire_fire','retire_entry','issue_success','issue_entry','capture_valid','capture_entry','rsp_entry']})
    for key,sig in [('cmd_valid','valid_q'),('cmd_issued','issued_q'),('cmd_done','done_q'),('rr','rr_ptr_q'),('select_valid','select_valid'),('select_entry','select_entry'),('window','window_mask'),('candidate','candidate_mask')]:out[key]='dut.u_cmd.'+sig
    for x in ['reserved_q','done_q','pc_err_q','ret_valid_q']:out['otb_'+x]='dut.u_otb.'+x
    out['otb_alloc_entry']='dut.u_otb.alloc_entry'
    for i in range(9):
        for x in ['addr_q','src_q','id_q','port_q','arresp_q','older_q']:out['cmd_'+x+'_'+str(i)]='dut.u_cmd.'+x+'['+str(i)+']'
        out['data_'+str(i)]='dut.u_otb.data_q['+str(i)+']'
    for i in range(3):out['occ_'+str(i)]='dut.u_cmd.occ_q['+str(i)+']'
    for i in range(4):out['token_'+str(i)]='dut.u_otb.ret_entry_q['+str(i)+']'
    return out

def testbench():
    declarations=[]
    for n,w in WIDTHS.items():declarations.append('reg '+('' if w==1 else '[%d:0] '%(w-1))+n+';')
    outs={'arready':3,'req':8,'arb_addr':12,'pending_cnt':4,'rvalid':3,'rdata':128,'rid':8,'r_port_id':5,'raddr':3,'rresp':2}
    for n,w in outs.items():declarations.append('wire [%d:0] %s;'%(w-1,n))
    obs=observations(); names=list(WIDTHS)
    return '''`timescale 1ns/1ps
module replay_tb;
reg clk=0;
'''+ '\n'.join(declarations)+'''
cmdbuf_rd dut(.*);
integer fin, fields, state=0;
string input_path, wave_path;
initial begin
 if(!$value$plusargs("INPUT=%s", input_path)) $fatal(2,"INPUT required");
 if(!$value$plusargs("WAVE=%s", wave_path)) $fatal(2,"WAVE required");
 fin=$fopen(input_path,"r"); if(!fin) $fatal(2,"input open failed");
 $dumpfile(wave_path); $dumpvars(0,replay_tb);
 while(!$feof(fin)) begin
  clk=0;
  fields=$fscanf(fin,"'''+ ' '.join(['%h']*len(names))+'''\\n",'''+','.join(names)+''');
  if(fields=='''+str(len(names))+''') begin
   #4;
   $write("SAMPLE,%0d",state);
'''+ '\n'.join('   $write(",%h",'+sig+');' for sig in obs.values())+'''
   $write("\\n");
   #1;clk=1;#5;state=state+1;
  end else if(fields!=-1) $fatal(2,"incomplete input row");
 end
 clk=0;$fclose(fin);$display("SAMPLES=%0d",state);$finish;
end
endmodule
'''

def simulate(source,work,inputs):
    work.mkdir(parents=True,exist_ok=True)
    tb=work/'replay_tb.sv';text=testbench()
    if tb.exists():assert tb.read_text(encoding='utf-8')==text,'immutable replay wrapper changed'
    else:tb.write_text(text,encoding='utf-8')
    sources=[str(source/f) for f in FILES]
    fingerprints={f:sha(source/f) for f in FILES};fingerprints['replay_tb.sv']=sha(tb)
    manifest=work/'build_sources.json';binary=work/'obj/replay_sim'
    if manifest.exists() and binary.exists():
        assert json.loads(manifest.read_text(encoding='utf-8'))==fingerprints,'stale build source'
        build=json.loads((work/'build.json').read_text(encoding='utf-8'))
    else:
        build=cmd(['verilator','--binary','--timing','--trace','-Wno-fatal','-DSYNTHESIS','--top-module','replay_tb','--Mdir',str(work/'obj'),'-o','replay_sim','-j','2',str(tb)]+sources,work,work/'compile.log',180)
        (work/'build.json').write_text(json.dumps(build,indent=2),encoding='utf-8')
        if build['exit_code']!=0:return {'status':'compile_error','build':build}
        manifest.write_text(json.dumps(fingerprints,indent=2),encoding='utf-8')
    # A shared original executable may replay many traces; each trace owns its log.
    output=inputs.parent/('original_sim' if source==ORIGINAL else 'mutant_sim');output.mkdir(exist_ok=True)
    run=cmd([str(binary),'+INPUT='+str(inputs),'+WAVE='+str(output/'replay.vcd')],output,output/'run.log',30)
    rows=[];keys=list(observations())
    for l in (output/'run.log').read_text(encoding='utf-8').splitlines():
        if l.startswith('SAMPLE,'):
            fields=l.split(',');assert len(fields)==len(keys)+2
            assert int(fields[1])==len(rows)
            rows.append(dict(zip(keys,[int(x,16) for x in fields[2:]])))
    return dict(status='simulated' if run['exit_code']==0 else 'simulation_error',source_sha256=fingerprints,build=build,run=run,rows=rows,wave=str(output/'replay.vcd'))

def oracle(states,rows):
    live=[];slots={};serial=0;attempt=None;rr=0;pipe=[None]*4
    data=[0]*9;pc=[0]*9;violations=[];failures=[];checks=0
    def eq(i,name,actual,expected):
        nonlocal checks
        checks+=1
        if actual!=expected:failures.append(dict(state=i,check=name,actual=hex(actual),expected=hex(expected)))
    # Validate the entire recorded trace even if a semantic mismatch later
    # prevents the oracle from assigning a legal physical identity.
    for i,(s,o) in enumerate(zip(states,rows)):
        if o['arready']==0 and s['arvalid']:violations.append(dict(state=i,kind='ready000_requires_valid0'))
        if s['arvalid'] and (s['src']>=3 or s['arresp'] not in (0,3)):violations.append(dict(state=i,kind='illegal_valid_metadata'))
        if not s['rst_n'] and i!=0:violations.append(dict(state=i,kind='runtime_reset_outside_formal_scope'))
        if s['rst_n'] and i==0:violations.append(dict(state=0,kind='missing_initial_reset'))
    for i,(s,o) in enumerate(zip(states,rows)):
        if not s['rst_n']:
            live=[];slots={};serial=0;attempt=None;rr=0;pipe=[None]*4;data=[0]*9;pc=[0]*9
            for name in ['arready','req','pending_cnt','rvalid']:eq(i,name,o[name],0)
            continue
        byseq={c['seq']:c for c in live}
        occ=[sum(c['src']==x for c in live) for x in range(3)]
        heads=[next((c for c in live if c['src']==x),None) for x in range(3)]
        winner=next((x for x in [(rr+k)%3 for k in range(3)] if heads[x] is not None and heads[x]['done'] and s['rready']&(1<<x)),None)
        retiring=heads[winner] if winner is not None else None
        after=[n-int(winner==x) for x,n in enumerate(occ)];shared=sum(max(n-1,0) for n in after)
        ready=sum((1<<x) for x,n in enumerate(after) if sum(after)<9 and (n==0 or shared<6))
        accept=bool(s['arvalid'] and s['src']<3 and ready&(1<<s['src']))
        ac=byseq.get(attempt);req=(1<<((ac['addr']>>3)&7)) if ac else 0
        success=bool(req&s['ar_rd_gnt']&s['rw_rd_gnt'])
        pending=[c for c in live if not c['issued']]
        pool=[c for c in pending if not(success and c['seq']==attempt)]
        window=pool[:5]
        candidates=[c for c in window if c['seq']!=attempt and not(s['rd_mem_status']&(1<<(8*((c['addr']>>6)&1)+((c['addr']>>3)&7))))]
        selected=candidates[0] if candidates else None
        due=byseq.get(pipe[3]);rvalid=0 if winner is None else 1<<winner
        eq(i,'arready',o['arready'],ready);eq(i,'req',o['req'],req)
        eq(i,'arb_addr',o['arb_addr'],ac['addr']>>6 if ac else 0)
        eq(i,'pending_cnt',o['pending_cnt'],len(pending));eq(i,'rvalid',o['rvalid'],rvalid)
        for n,v in [('alloc_fire',accept),('issue_success',success),('capture_valid',due is not None),('retire_fire',retiring is not None)]:eq(i,n,o[n],int(v))
        if ac:eq(i,'issue_entry',o['issue_entry'],ac['slot'])
        if due:eq(i,'capture_entry',o['capture_entry'],due['slot'])
        if retiring:
            slot=retiring['slot'];eq(i,'retire_entry',o['retire_entry'],slot);eq(i,'rsp_entry',o['rsp_entry'],slot)
        for n,v in [('rid',retiring['id'] if retiring else 0),('r_port_id',retiring['port'] if retiring else 0),('raddr',retiring['addr']&7 if retiring else 0),('rdata',data[retiring['slot']] if retiring else 0),('rresp',(3 if retiring['resp']==3 else int(pc[retiring['slot']])) if retiring else 0)]:eq(i,n,o[n],v)
        mask=lambda cs:sum(1<<c['slot'] for c in cs)
        eq(i,'cmd_valid',o['cmd_valid'],mask(live));eq(i,'cmd_issued',o['cmd_issued'],mask([c for c in live if c['issued']]))
        eq(i,'cmd_done',o['cmd_done'],mask([c for c in live if c['done']]))
        eq(i,'otb_reserved',o['otb_reserved_q'],mask(live));eq(i,'otb_done',o['otb_done_q'],mask([c for c in live if c['done']]))
        eq(i,'window',o['window'],mask(window));eq(i,'candidate',o['candidate'],mask(candidates));eq(i,'select_valid',o['select_valid'],int(selected is not None))
        if selected:eq(i,'select_entry',o['select_entry'],selected['slot'])
        eq(i,'rr',o['rr'],rr);eq(i,'otb_pc',o['otb_pc_err_q'],sum(pc[k]<<k for k in range(9)))
        eq(i,'token_valid',o['otb_ret_valid_q'],sum((1<<k) for k in range(4) if pipe[k] is not None))
        for k in range(4):eq(i,'token_'+str(k),o['token_'+str(k)],byseq[pipe[k]]['slot'] if pipe[k] is not None else 0)
        for x in range(3):eq(i,'occ_'+str(x),o['occ_'+str(x)],occ[x])
        for k in range(9):
            c=next((c for c in live if c['slot']==k),None)
            eq(i,'data_'+str(k),o['data_'+str(k)],data[k])
            for reg,key in [('addr_q','addr'),('src_q','src'),('id_q','id'),('port_q','port'),('arresp_q','resp')]:eq(i,reg+'_'+str(k),o['cmd_'+reg+'_'+str(k)],c[key] if c else 0)
            eq(i,'age_'+str(k),o['cmd_older_q_'+str(k)],mask([a for a in live if c and a['seq']<c['seq']]))
        newslot=o['alloc_entry'] if accept else None
        if accept:
            eq(i,'otb_alloc_entry',o['otb_alloc_entry'],newslot)
            legal=bool(newslot<9 and (newslot not in slots or (retiring is not None and retiring['slot']==newslot)))
            eq(i,'alloc_unique_free',int(legal),1)
            if not legal:break
        # Commit expected events after all pre-edge comparisons. Physical ID is
        # observed only at a legal allocation; it never chooses expected events.
        if success:ac['issued']=True
        if due:due['done']=True;data[due['slot']]=s['mem_rdata'];pc[due['slot']]=s['pc_err']
        if retiring:
            slot=retiring['slot'];live.remove(retiring);slots.pop(slot);data[slot]=0;pc[slot]=0;rr=(winner+1)%3
        if accept:
            q=dict(seq=serial,slot=newslot,addr=s['araddr'],src=s['src'],id=s['arid'],port=s['ar_port_id'],resp=s['arresp'],issued=False,done=False)
            serial+=1;live.append(q);slots[newslot]=q;data[newslot]=0;pc[newslot]=0
        pipe=[attempt if success else None]+pipe[:3];attempt=selected['seq'] if selected else None
    return dict(checks=checks,protocol_violations=violations,semantic_mismatch_count=len(failures),first_failure=failures[0] if failures else None,failures=failures,recorded_samples=len(rows),expected_samples=len(states),input_contract_valid=not violations)
