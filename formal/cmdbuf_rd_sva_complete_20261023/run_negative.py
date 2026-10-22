#!/usr/bin/env python3
"""Isolated environment-contract experiments; NEVER a normal DUT proof profile.

For each case remove only its contract assume, assert that contract as a monitor,
and cover its violation. Expected: cover PASS and monitor BMC FAIL, same label.
MEM-14 has no observable valid/tag/oracle and is intentionally not fabricated.
"""
import argparse,concurrent.futures,json,os,shutil,subprocess,sys,time
from pathlib import Path
# 本目录包含全部输入，负向作业也不借用原仓库路径。
HERE=Path(__file__).resolve().parent;ROOT=HERE;BASE=HERE
sys.path.insert(0,str(BASE))
from property_catalog import lower_overlapping_implications

CONTRACTS={
 'AR_09':('E05_ZERO_READY','(arready==0) |-> (!arvalid)','arready==0 && arvalid','全不 ready 时环境仍发送有效请求'),
 'AR_10':('E03_SRC','arvalid |-> (src<3)','arvalid && src==3','有效请求使用不存在的第四个来源'),
 'ARB_12':('E06_SUCCESS_BUSY','!bad_busy','bad_busy','req 同位双 grant 成功但对应半区仍空闲'),
 'ERR_05':('E04_ARRESP','arvalid |-> (arresp==0 || arresp==3)','arvalid && (arresp==1 || arresp==2)','有效请求携带未定义的 arresp'),
}

def native(case):
    header=(BASE/'cmdbuf_rd_port_sva.sv').read_text(encoding='utf-8').split('    // 公开端口事件')[0]
    text=header+'\n// 独立负向环境检查：没有正常事务模型；本文件不能用于宣称 DUT 正常证明。\n'
    text+='wire bad_busy;\nwire [7:0] bad_bits;\ngenvar nb;\ngenerate for(nb=0;nb<8;nb=nb+1) begin: busy_contract\n'
    text+='assign bad_bits[nb]=req[nb]&&ar_rd_gnt[nb]&&rw_rd_gnt[nb]&&!rd_mem_status[nb][arb_addr[0]];\nend endgenerate\nassign bad_busy=|bad_bits;\n'
    for key,(label,expr,bad,comment) in CONTRACTS.items():
        kind='assert' if key==case else 'assume';name='V_'+key if key==case else label
        text+='// [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] '+comment+'；'+('本项改为监测断言，预期检出。' if key==case else '保留其他环境约束。')+'\n'
        text+=name+': '+kind+' property (\n    @(posedge clk) disable iff (!rst_n)\n    '+expr+'\n);\n'
    text+='// [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 真正违规条件共现；不是蕴含空真。\n'
    text+='N_'+case+': cover property (\n    @(posedge clk) disable iff (!rst_n)\n    '+CONTRACTS[case][2]+'\n);\nendmodule\n`default_nettype wire\n'
    return text

def run_one(case,mode,out,timeout):
    folder=out/(case.lower()+'_'+mode);folder.mkdir(parents=True,exist_ok=False)
    text=native(case);(folder/'native_checker.sv').write_text(text,encoding='utf-8')
    lowered,changes=lower_overlapping_implications(text)
    (folder/'cmdbuf_rd_port_sva.sv').write_text(lowered,encoding='utf-8')
    (folder/'lowering.json').write_text(json.dumps(changes,indent=2)+'\n',encoding='utf-8')
    files=[]
    for p in [ROOT/'rtl'/n for n in ('cmdbuf_rd.sv','cmdbuf_rd_cmd.sv','cmdbuf_rd_otb.sv')]+[BASE/'formal_top.sv']:
        shutil.copyfile(str(p),str(folder/p.name));files.append(p.name)
    files.append('cmdbuf_rd_port_sva.sv')
    sby='[options]\nmode '+mode+'\ndepth 16\ntimeout '+str(timeout)+'\n\n[engines]\n'+('smtbmc yices' if mode=='cover' else 'abc bmc3')+'\n\n[script]\n'
    sby+='read_slang --top cmdbuf_rd_formal --no-implicit-memories -D SYNTHESIS '+' '.join(files)+'\n'
    sby+='prep -top cmdbuf_rd_formal\nasync2sync\ndffunmap\nchformal -lower\nsim -clock clk -resetn rst_n -rstlen 1 -n 1 -w\n\n[files]\n'+'\n'.join(files)+'\n'
    (folder/'run.sby').write_text(sby,encoding='utf-8')
    start=time.time()
    with (folder/'console.log').open('w',encoding='utf-8') as f:proc=subprocess.run(['sby','run.sby'],cwd=str(folder),stdout=f,stderr=subprocess.STDOUT)
    sf=folder/'run/status';status=sf.read_text(encoding='utf-8').strip() if sf.exists() else 'NO_STATUS'
    log=(folder/'console.log').read_text(encoding='utf-8',errors='replace')
    # Cover does not prove the monitor; BMC must name the intended failed assertion.
    ok=status.startswith('PASS') if mode=='cover' else status.startswith('FAIL') and ('V_'+case) in log
    record=dict(case=case.replace('_','-'),mode=mode,status=status,expected='PASS' if mode=='cover' else 'FAIL V_'+case,
                experiment_pass=ok,returncode=proc.returncode,seconds=round(time.time()-start,2))
    (folder/'result.json').write_text(json.dumps(record,indent=2)+'\n',encoding='utf-8');print(json.dumps(record),flush=True)
    return record

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--tools',type=Path);ap.add_argument('--jobs',type=int,default=2);ap.add_argument('--timeout',type=int,default=180)
    a=ap.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    if a.tools:os.environ['PATH']=str(a.tools)+os.pathsep+os.environ.get('PATH','')
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
        rr=list(pool.map(lambda cm:run_one(cm[0],cm[1],a.output,a.timeout),[(c,m) for c in CONTRACTS for m in ('cover','bmc')]))
    (a.output/'results.json').write_text(json.dumps(rr,indent=2)+'\n',encoding='utf-8')
    return int(not all(r['experiment_pass'] for r in rr))

if __name__=='__main__': raise SystemExit(main())
