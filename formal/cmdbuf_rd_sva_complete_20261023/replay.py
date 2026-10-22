#!/usr/bin/env python3
"""Extract only public inputs/outputs from SMTBMC VCD and validate native replay.

Only complete samples (all port values published by SMTBMC) are consumed.
An incomplete terminal clock marker is not an extra stimulus cycle.
"""
import argparse,json,re,subprocess
from pathlib import Path
FIELDS=['rst_n','arvalid','araddr','src','arid','ar_port_id','arresp','rready','ar_rd_gnt','rw_rd_gnt','rd_mem_status','mem_rdata','pc_err',
        'arready','req','arb_addr','pending_cnt','rvalid','rdata','rid','r_port_id','raddr','rresp']
def extract(vcd):
    scopes=[];signals={};values={};changed=set();time=0;samples=[];body=False
    def finish():
        if time%10==0 and all(k in changed for k in FIELDS):
            row=[]
            for k in FIELDS:
                val=values[k]
                if any(c in val.lower() for c in 'xz'):raise ValueError('Non-binary trace value '+k)
                n=int(val,2)
                row.extend((n>>(32*b))&0xffffffff for b in range(4)) if k in ('mem_rdata','rdata') else row.append(n)
            row.append(time//10);samples.append(row)
    for line in vcd.read_text(encoding='utf-8').splitlines():
        if not body:
            words=line.split()
            if line.startswith('$scope'):scopes.append(words[2])
            elif line.startswith('$upscope'):scopes.pop()
            elif line.startswith('$var') and scopes==['cmdbuf_rd_formal'] and words[4] in FIELDS:signals[words[3]]=words[4]
            elif line.startswith('$enddefinitions'):
                assert set(signals.values())==set(FIELDS),(vcd,set(FIELDS)-set(signals.values()))
                body=True
        elif line.startswith('#'):
            finish();time=int(line[1:]);changed=set()
        elif line.startswith('b'):
            value,token=line[1:].split()
            if token in signals:values[signals[token]]=value;changed.add(signals[token])
        elif line and line[0] in '01xz':
            if line[1:] in signals:values[signals[line[1:]]]=line[0];changed.add(signals[line[1:]])
    finish();assert samples,vcd
    return samples

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--formal',type=Path,action='append',required=True);ap.add_argument('--sim',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--group',action='append',help='Optional completed job directory name, e.g. ar')
    a=ap.parse_args();a.output.mkdir(parents=True,exist_ok=False);results=[]
    for root in a.formal:
        for vcd in sorted(root.glob('*/run/engine_0/trace*.vcd')):
            if a.group and vcd.parents[2].name not in a.group:continue
            # Exclude negative and mutant jobs explicitly by choosing positive roots only.
            name=root.name+'_'+vcd.parents[2].name+'_'+vcd.stem
            rows=extract(vcd);csv=a.output/(name+'.txt');cov=a.output/(name+'.dat');log=a.output/(name+'.log')
            csv.write_text('\n'.join(' '.join(format(x,'x') for x in r) for r in rows)+'\n',encoding='utf-8')
            with log.open('w',encoding='utf-8') as f:proc=subprocess.run([str(a.sim.resolve()),str(csv.resolve()),str(cov.resolve())],stdout=f,stderr=subprocess.STDOUT)
            record=dict(trace=str(vcd),name=name,cycles=len(rows),returncode=proc.returncode)
            results.append(record)
            if proc.returncode:print(json.dumps(record),flush=True)
    # Keep native user-cover hit names. All files contain cumulative counts for one trace.
    hit=set()
    for path in a.output.glob('*.dat'):
        for line in path.read_text(encoding='utf-8',errors='replace').splitlines():
            if not line.startswith('C '):continue
            try:count=int(line.rsplit(' ',1)[1])
            except ValueError:continue
            if count:
                hit.update(re.findall(r'\b(?:C_CC_[A-Z0-9_]+|C_XAU_[A-Z0-9_]+|C_SUCCESS_BUSY_TARGET)\b',line))
    report=dict(traces=len(results),cycles=sum(r['cycles'] for r in results),failed=[r for r in results if r['returncode']],native_cover_labels=sorted(hit),results=results)
    (a.output/'summary.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='results'}),flush=True)
    return int(bool(report['failed']))

if __name__=='__main__':raise SystemExit(main())
