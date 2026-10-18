#!/usr/bin/env python3
"""Audit the public-port boundary, initializer policy and generated RTL bytes."""
import argparse,hashlib,json,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def ports(text,module):
    header=text.split('module '+module+' (',1)[1].split('\n);',1)[0]
    header=re.sub(r'//[^\n]*','',header)
    out=[]
    for m in re.finditer(r'\b(input|output)\s+wire\s*(\[[^\]]+\])?\s*([^\n]+)',header):
        width=m[2] or 'scalar'
        for token in m[3].split(','):
            token=token.strip()
            if token:out.append((token,width))
    return dict(out)
def main():
    p=argparse.ArgumentParser();p.add_argument('--rtl',type=Path,required=True);p.add_argument('--job',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    rtl=ports((a.rtl/'cmdbuf_rd.v').read_text(encoding='utf8'),'cmdbuf_rd')
    checker=ports((HERE/'cmdbuf_rd_port_sva.sv').read_text(encoding='utf8'),'cmdbuf_rd_port_sva')
    assert rtl==checker,(rtl,checker)
    assert len(rtl)==24
    for f in HERE.glob('cmdbuf_rd_port*.sv*'):
        text=f.read_text(encoding='utf8');text=re.sub(r'//[^\n]*|/\*.*?\*/','',text,flags=re.S)
        assert not re.search(r'\bo_\w+|\$root\b|\$unit\b|\b(?:dut|u_cmd|u_otb)\s*\.',text),f
        code=re.sub(r'"(?:\\.|[^"\\])*"','',text)
        assert not re.search(r'\b[A-Za-z_]\w*\s*\.\s*[A-Za-z_]\w*',code),('hierarchical reference',f)
        for value in re.findall(r'\breg\s+(?:\[[^\]]+\]\s*)?\w+\s*=\s*([^;]+);',text):assert value.strip() in ("1'b0",'0'),(f,value)
    original={p.name:sha(p) for p in a.rtl.glob('*.v')}
    copies={n:sha(a.job/n) for n in original};assert original==copies
    bind=(a.job/'cmdbuf_rd_port_bind.sv').read_text()
    connections=re.findall(r'\.(\w+)\((\w+)\)',bind)
    assert set(connections)=={(n,n) for n in rtl} and len(connections)==24
    r=dict(passed=True,public_port_count=24,ports=rtl,rtl_byte_identical=True,rtl_sha256=original,no_internal_observation=True,only_zero_declaration_initializers=True,checker_sha256=sha(HERE/'cmdbuf_rd_port_sva.sv'))
    a.output.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r))
if __name__=='__main__':raise SystemExit(main())
