#!/usr/bin/env python3
"""核查直接比较版的原始接口、十组输出断言、模型结构与交付签名。"""
import hashlib,json,re
from pathlib import Path
import run
HERE=Path(__file__).resolve().parent

def check_interval():
    # rresp=11 隐藏 pc_err 时允许消费正常或异常标记；上下界必须覆盖且仅覆盖可行数量。
    cases=0
    for total in range(10):
        for lo in range(total+1):
            for hi in range(lo,total+1):
                for response in (None,0,1,3):
                    if response is not None and not total:continue
                    possible=set()
                    for bad in range(lo,hi+1):
                        if response is None:possible.add(bad)
                        elif response==0 and bad<total:possible.add(bad)
                        elif response==1 and bad>0:possible.add(bad-1)
                        elif response==3:
                            if bad>0:possible.add(bad-1)
                            if bad<total:possible.add(bad)
                    permitted=response is None or response==3 or (response==0 and lo<total) or (response==1 and hi>0)
                    assert bool(possible)==permitted
                    if not possible:continue
                    after=total-int(response is not None)
                    l=lo-1 if response is not None and response!=0 and lo>0 else lo
                    h=hi if response is None else max(hi-1,0) if response==1 else min(hi,after)
                    for incoming in (0,1):
                        expected={x+incoming for x in possible}
                        assert expected==set(range(l+incoming,h+incoming+1))
                        cases+=1
    return cases


def main():
    scope=json.loads((HERE/'scope.json').read_text(encoding='utf-8'))
    props=run.catalog(run.source());by_label={p['label']:p for p in props}
    counts={k:sum(p['instances'] for p in props if p['kind']==k) for k in ('assert','assume','cover')}
    assert counts==scope['counts']
    expected_ports={'clk','rst_n','arvalid','arready','araddr','src','arid','ar_port_id','arresp','rvalid','rready','rdata','rid','r_port_id','raddr','rresp','req','arb_addr','pending_cnt','ar_rd_gnt','rw_rd_gnt','rd_mem_status','mem_rdata','pc_err'}
    source=(HERE/'cmdbuf_rd_compact_sva.sv').read_text(encoding='utf-8')
    port_names=re.findall(r'input wire\s+(?:\[[^\]]+\]\s+)?(\w+)',source)
    assert len(port_names)==24 and set(port_names)==expected_ports,port_names
    assert len(scope['outputs'])==10
    for output,item in scope['outputs'].items():
        prop=by_label[item['assertion']]
        assert prop['kind']=='assert' and re.search(r'\b'+output+r'(?:\s*}|)\s*==',prop['expression']),output
    for p in scope['properties']:assert by_label[p['label']]['expression']==p['expression'],p['label']
    assert {p['label'] for p in props if p['kind']=='assume'}=={'E03_SRC','E04_ARRESP','E05_ZERO_READY','E06_SUCCESS_BUSY'}
    assignments=0
    for name in ('cmdbuf_rd_compact_sva.sv','cmdbuf_rd_compact_model.svh','cmdbuf_rd_field_set.sv','formal_top.sv'):
        text=(HERE/name).read_text(encoding='utf-8');code=re.sub(r'//[^\n]*','',text)
        assert not re.search(r'\bwatch_\w*|\banyconst\b|\banyseq\b',code),name
        assert not re.search(r'\balways_comb\b|always\s*@\s*\(?\s*\*',code),name
        assert not re.search(r'\b(started|active|bit)\b',code),name
        assert not re.search(r'\b(dut|u_cmd|u_otb)\s*\.',code),name
        lines=text.splitlines()
        for i,line in enumerate(lines):
            if re.match(r'\s*assign\s+',line):
                assert i and re.match(r'\s*//',lines[i-1]) and re.search('[\u4e00-\u9fff]',lines[i-1]),(name,i+1)
                assignments+=1
    checked=0
    if (HERE/'bundle_manifest.json').exists():
        manifest=json.loads((HERE/'bundle_manifest.json').read_text(encoding='utf-8'))
        if manifest.get('revision')=='direct_top_ports_20261023':
            for name,meta in manifest['files'].items():
                assert hashlib.sha256((HERE/name).read_bytes()).hexdigest()==meta['sha256'],name
                checked+=1
    print(json.dumps(dict(status='PASS',counts=counts,original_ports=len(port_names),explicit_output_assertions=len(scope['outputs']),commented_assign_statements=assignments,pc_interval_transitions=check_interval(),source_files_checked=checked),ensure_ascii=False))
if __name__=='__main__':main()
