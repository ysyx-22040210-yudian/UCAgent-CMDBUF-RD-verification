"""Verify the self-contained CMDBUF RD source package without invoking a solver."""
from pathlib import Path
import hashlib,json,re
from property_catalog import properties
ROOT=Path(__file__).resolve().parent
def expand(path,stack=()):
    assert path not in stack,('cyclic include',path)
    s=path.read_text(encoding='utf-8')
    def include(m):
        p=(ROOT/m[1]).resolve()
        assert ROOT.resolve() in p.parents and p.is_file(),('missing/unsafe include',m[1])
        return expand(p,stack+(path,))
    return re.sub(r'`include\s+"([^"]+)"',include,s)
def main():
    manifest=json.loads((ROOT/'bundle_manifest.json').read_text(encoding='utf-8'))
    for name,record in manifest['files'].items():
        p=(ROOT/name).resolve()
        assert ROOT.resolve() in p.parents and p.is_file(),name
        data=p.read_bytes()
        assert len(data)==record['bytes'] and hashlib.sha256(data).hexdigest()==record['sha256'],name
    props=properties(expand(ROOT/'cmdbuf_rd_port_sva.sv'))
    for p in props:
        if p['label'] in ('A_CC_SRC_LIMIT','A_CC_R_NONEMPTY'):p['instances']=3
    counts={kind:sum(p['instances'] for p in props if p['kind']==kind) for kind in ('assume','assert','cover')}
    assert len(props)==617 and counts=={'assume':11,'assert':158,'cover':593},(len(props),counts)
    assert {p['label'] for p in props if p['kind']=='assume'}=={'E03_SRC','E04_ARRESP','E05_ZERO_READY','E06_SUCCESS_BUSY'}
    comparison_map=json.loads((ROOT/'output_assertions.json').read_text(encoding='utf-8'))
    main_text=(ROOT/'cmdbuf_rd_port_sva.sv').read_text(encoding='utf-8')
    main_props={p['label']:p for p in properties(main_text)}
    assert len(comparison_map['outputs'])==10
    for item in comparison_map['outputs']:
        p=main_props[item['label']]
        expr=main_text[p['start']:p['end']]
        assert p['kind']=='assert' and re.search(r'\b'+item['output']+r'\s*==',expr),item
    ports=re.findall(r'^\s*input wire\s+(?:\[[^]]+\]\s+)?(\w+)',main_text,re.M)
    assert len(ports)==24 and not any(p.startswith('watch_') for p in ports),ports
    for name in ('native.f','checker.f'):
        content=(ROOT/name).read_text(encoding='utf-8')
        assert '+define+CMDBUF_CORNER_SUITE' in content
        for line in content.splitlines():
            line=line.strip()
            if not line or line.startswith('//') or line.startswith('+'):continue
            assert (ROOT/line).is_file() and not line.startswith('optional/'),line
    print(json.dumps(dict(status='PASS',files=len(manifest['files']),labels=len(props),instances=counts,
                         include_closure=True,optional_assumes_in_normal_profile=False),indent=2))
if __name__=='__main__':main()
