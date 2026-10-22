#!/usr/bin/env python3
"""Check source structure, published checksums and the pc_err interval abstraction."""
import hashlib,json,re
from pathlib import Path
import run
HERE=Path(__file__).resolve().parent

def check_interval():
    # Enumerate concrete pc=1 counts, then compare their min/max with the two-register model.
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
                    permitted=(response is None or response==3 or (response==0 and lo<total) or (response==1 and hi>0))
                    assert bool(possible)==permitted,(total,lo,hi,response)
                    if not possible:continue
                    after=total-int(response is not None)
                    l=lo-1 if response is not None and response!=0 and lo>0 else lo
                    h=hi if response is None else (max(hi-1,0) if response==1 else min(hi,after))
                    for incoming in (0,1):
                        expected={x+incoming for x in possible}
                        assert (l+incoming,h+incoming)==(min(expected),max(expected))
                        assert expected==set(range(min(expected),max(expected)+1))
                        cases+=1
    return cases

def main():
    props=run.catalog(run.source());scope=json.loads((HERE/'property_scope.json').read_text(encoding='utf-8'))
    counts={k:sum(p['instances'] for p in props if p['kind']==k) for k in ('assert','assume','cover')}
    assert counts==scope['counts'],(counts,scope['counts'])
    expect={p['label']:p for p in scope['properties']}
    for p in props:assert p['expression']==expect[p['label']]['expression'],p['label']
    assert {p['label'] for p in props if p['kind']=='assume'}=={'E03_SRC','E04_ARRESP','E05_ZERO_READY','E06_SUCCESS_BUSY'}
    assignments=0
    for name in ('cmdbuf_rd_relaxed_sva.sv','cmdbuf_rd_relaxed_model.svh','cmdbuf_rd_value_bag.sv'):
        text=(HERE/name).read_text(encoding='utf-8')
        code=re.sub(r'//[^\n]*','',text)
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
        for name,meta in json.loads((HERE/'bundle_manifest.json').read_text(encoding='utf-8'))['files'].items():
            p=HERE/name;assert p.is_file(),name
            assert hashlib.sha256(p.read_bytes()).hexdigest()==meta['sha256'],name
            checked+=1
    print(json.dumps(dict(status='PASS',counts=counts,commented_assign_statements=assignments,
        interval_transitions=check_interval(),files_checked=checked),ensure_ascii=False))
if __name__=='__main__':main()
