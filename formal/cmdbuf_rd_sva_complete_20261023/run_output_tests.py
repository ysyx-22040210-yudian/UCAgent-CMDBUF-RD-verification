#!/usr/bin/env python3
"""Validate ten exact output assertions with native SVA and deliberate output faults.

The real DUT receives legal input traffic. Only the checker-facing copy of one
output is corrupted; DUT state and its input traffic are not modified by faults.
This is directed assertion sensitivity testing, not a universal formal proof.
"""
import argparse, hashlib, json, os, re, subprocess
from pathlib import Path
from run import expand, select, all_properties

HERE = Path(__file__).resolve().parent

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def testbench(source, outputs):
    # 从实际检查器接口生成连线，禁止增加观察参数或引用 DUT 内部层次。
    ports=[]; declarations=[]; widths={}
    for line in source.splitlines():
        m=re.match(r'\s*input wire\s+(\[\d+:\d+\]\s+)?(\w+)(\s+\[7:0\])?',line)
        if not m:continue
        shape,name,array=m.groups();ports.append(name)
        widths[name]=int(shape.split(':')[0][1:])+1 if shape else 1
        declaration=(shape or '')+name+(array or '')+';'
        declarations.append(('wire ' if name in outputs else 'reg ')+declaration)
        if name in outputs:declarations.append('wire '+(shape or '')+'raw_'+name+';')
    assert len(ports)==24
    mutations={
        'arready': "(case_id==1 && cycle==4) ? raw_arready ^ 3'b001 : raw_arready",
        'pending_cnt': "(case_id==2 && cycle==4) ? raw_pending_cnt ^ 4'b0001 : raw_pending_cnt",
        'req': "(case_id==3 && cycle==2) ? raw_req ^ 8'b00000010 : raw_req",
        # 改行地址而保留 bit0 奇偶选择，使成功拍半区忙的环境契约继续成立。
        'arb_addr': "((case_id==4 && cycle==2) || (case_id==11 && raw_req==0)) ? raw_arb_addr ^ 12'hFFE : raw_arb_addr",
        'rvalid': "(case_id==5 && cycle==7) ? raw_rvalid ^ 3'b011 : raw_rvalid",
        'rid': "((case_id==6 && cycle==7) || (case_id==11 && raw_rvalid==0)) ? raw_rid ^ 8'h80 : raw_rid",
        'r_port_id': "((case_id==7 && cycle==7) || (case_id==11 && raw_rvalid==0)) ? raw_r_port_id ^ 5'h10 : raw_r_port_id",
        'raddr': "((case_id==8 && cycle==7) || (case_id==11 && raw_rvalid==0)) ? raw_raddr ^ 3'h4 : raw_raddr",
        'rresp': "((case_id==9 && cycle==7) || (case_id==11 && raw_rvalid==0)) ? raw_rresp ^ 2'b10 : raw_rresp",
        'rdata': "((case_id==10 && cycle==7) || (case_id==11 && raw_rvalid==0)) ? raw_rdata ^ 128'h80000000000000000000000000000000 : raw_rdata",
    }
    tb='module output_test_tb;\n'+'\n'.join(declarations)+'\n'
    tb+='integer case_id; integer cycle; integer responses; integer requests;\n'
    tb+='cmdbuf_rd dut ('+', '.join('.'+n+'('+('raw_' if n in outputs else '')+n+')' for n in ports)+');\n'
    tb+='cmdbuf_rd_port_sva checks (.*);\n'
    for name in outputs:tb+='assign '+name+' = '+mutations[name]+';\n'
    tb+='initial begin\nif (!$value$plusargs("CASE=%d",case_id)) $fatal(1,"CASE missing");\n'
    tb+='cycle=-1; responses=0; requests=0; clk=0; rst_n=0;\n'
    for n,w in widths.items():
        if n in outputs or n in ('clk','rst_n'):continue
        tb+='for (integer b=0;b<8;b=b+1) rd_mem_status[b]=0;\n' if n=='rd_mem_status' else n+'=0;\n'
    tb+='''#5; clk=1; #5; clk=0; rst_n=1;
// 公开端口合法输入：同一 XAU 连续接收两条不同地址/ID/port 的命令。
// 请求在 t=2、3 成功；MEM 在 t=6、7 返回；R 最快 t=7、8 返回。
for (cycle=0; cycle<13; cycle=cycle+1) begin
    arvalid=(cycle==0 || cycle==1);
    src=0; rready=7;
    araddr=(cycle==1) ? 18'h10A : 18'h81;
    arid=(cycle==1) ? 8'h22 : 8'h11;
    ar_port_id=(cycle==1) ? 5'h5 : 5'h3;
    arresp=(cycle==0) ? 2'b11 : 2'b00;
    mem_rdata=(cycle==6) ? 128'h123456789ABCDEF00000000000000101 :
              (cycle==7) ? 128'hFEDCBA98765432100000000000000202 : 128'b0;
    pc_err=(cycle==6 || cycle==7);
    ar_rd_gnt=0; rw_rd_gnt=0;
    for (integer b=0;b<8;b=b+1) rd_mem_status[b]=0;
    #1;
    // grant/status 只依据真实 DUT 的请求，故注错不会影响 RTL 的状态演进。
    ar_rd_gnt=raw_req; rw_rd_gnt=raw_req;
    for (integer b=0;b<8;b=b+1)
        if (raw_req[b]) rd_mem_status[b][raw_arb_addr[0]]=1;
    #3;
    if (raw_req!=0) requests=requests+1;
    if (raw_rvalid!=0) responses=responses+1;
    if (cycle==2 && raw_req!=8'h01) $fatal(1,"Baseline first request absent");
    if (cycle==7 && raw_rvalid!=3'b001) $fatal(1,"Baseline first response absent");
    if ((case_id==1 || case_id==2) && cycle==4)
        $display("INJECT cycle=%0d case=%0d",cycle,case_id);
    if ((case_id==3 || case_id==4) && cycle==2)
        $display("INJECT cycle=%0d case=%0d",cycle,case_id);
    if (case_id>=5 && case_id<=10 && cycle==7)
        $display("INJECT cycle=%0d case=%0d",cycle,case_id);
    #1; clk=1; #5; clk=0;
end
if (requests!=2 || responses!=2) $fatal(1,"Baseline lifecycle incomplete");
$display("OUTPUT_TEST_PASS requests=%0d responses=%0d",requests,responses);
$finish;
end
endmodule
'''
    return tb

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--tools',type=Path)
    ap.add_argument('--compiler-bin',type=Path)
    ap.add_argument('--atomic-library',type=Path)
    ap.add_argument('--output',type=Path,default=HERE/'build/output_tests')
    args=ap.parse_args();args.output=args.output.resolve()
    if args.tools:os.environ['PATH']=str(args.tools)+os.pathsep+os.environ.get('PATH','')
    if args.compiler_bin:os.environ['PATH']=str(args.compiler_bin)+os.pathsep+os.environ.get('PATH','')
    if os.name=='posix':
        import resource
        resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    args.output.mkdir(parents=True,exist_ok=False)
    mapping=json.loads((HERE/'output_assertions.json').read_text(encoding='utf-8'))['outputs']
    original=(HERE/'cmdbuf_rd_port_sva.sv').read_text(encoding='utf-8')
    tb=testbench(original,[x['output'] for x in mapping])
    (args.output/'output_test_tb.sv').write_text(tb,encoding='utf-8')
    expanded=expand(HERE/'cmdbuf_rd_port_sva.sv')
    results=[]
    # full：原生完整断言正常业务；outputs：只选十条，逐一验证其自身可检出性。
    for profile in ('full','outputs'):
        folder=args.output/profile;folder.mkdir()
        selection=None if profile=='full' else [x['label'] for x in mapping]
        native=select(expanded,covers=[],assertions=selection)
        checker=folder/'cmdbuf_rd_port_sva.sv';checker.write_text(native,encoding='utf-8')
        props=all_properties(native)
        save(folder/'selected_properties.json',props)
        save(folder/'inputs.json',dict(source_sha256={
            p.relative_to(HERE).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
            for p in [HERE/'cmdbuf_rd_port_sva.sv',HERE/'cmdbuf_rd_reference_model.svh',HERE/'cmdbuf_rd_xau_order_model.svh']+list(HERE.glob('cmdbuf_rd_corner_*.svh'))+list((HERE/'rtl').glob('*.sv'))},
            checker_sha256=hashlib.sha256(native.encode('utf-8')).hexdigest(),
            tb_sha256=hashlib.sha256(tb.encode('utf-8')).hexdigest(),
            selected_assertions=selection,assumptions_unchanged=True,
            implication_lowering=False,initial_state='One real reset before traffic; no reset-sequence assumption.'))
        command=['verilator','--binary','--timing','--assert','-Wno-WIDTHEXPAND','-Wno-WIDTHTRUNC',
            '-DCMDBUF_CORNER_SUITE','--top-module','output_test_tb','--Mdir',str(folder/'obj'),
            str(HERE/'rtl/cmdbuf_rd.sv'),str(HERE/'rtl/cmdbuf_rd_cmd.sv'),str(HERE/'rtl/cmdbuf_rd_otb.sv'),
            str(checker),str(args.output/'output_test_tb.sv')]
        if args.atomic_library:
            lib=args.atomic_library.resolve();assert lib.is_file()
            (folder/'linker').mkdir();(folder/'linker/libatomic.so').symlink_to(lib)
            command+=['-LDFLAGS','-L'+str(folder/'linker')]
        save(folder/'compile_command.json',command)
        with (folder/'build.log').open('w',encoding='utf-8') as out:
            p=subprocess.run(command,stdout=out,stderr=subprocess.STDOUT)
        if p.returncode:raise RuntimeError('Compile failed: '+str(folder/'build.log'))
        cases=[dict(case=0,name='two_commands_exact',expected=None),
               dict(case=11,name='invalid_payloads_ignored',expected=None)]
        if profile=='outputs':
            for i,item in enumerate(mapping,1):
                cases.append(dict(case=i,name='corrupt_'+item['output'],expected=item['label']))
        for case in cases:
            p=subprocess.run([str(folder/'obj/Voutput_test_tb'),'+CASE='+str(case['case'])],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
            log=p.stdout.decode('utf-8',errors='replace')
            (folder/(case['name']+'.log')).write_text(log,encoding='utf-8')
            failures=re.findall(r'Assertion failed[^\n]*\b(A_COMPARE_[A-Z_]+)',log)
            if case['expected']:
                ok=p.returncode!=0 and case['expected'] in failures and 'INJECT cycle=' in log
            else:ok=p.returncode==0 and 'OUTPUT_TEST_PASS' in log
            result=dict(case,profile=profile,status='PASS' if ok else 'FAIL',returncode=p.returncode,failed_assertions=failures)
            results.append(result);print(json.dumps(result),flush=True)
    save(args.output/'results.json',dict(scope='Native full-checker baseline plus ten isolated output assertion sensitivity tests; not a universal proof.',cases=results))
    return int(any(r['status']!='PASS' for r in results))

if __name__=='__main__':raise SystemExit(main())
