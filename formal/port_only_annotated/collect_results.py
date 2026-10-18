#!/usr/bin/env python3
"""Merge exact SBY witness locations and simulation hits without conflating methods."""
import argparse,hashlib,json,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
def formal_hits(root):
    hits={};jobs=[]
    for log in sorted(root.glob('wave*/*/run/logfile.txt')):
        job=log.parent.parent;manifest=json.loads((job/'inputs.json').read_text())
        status=(log.parent/'status').read_text().strip() if (log.parent/'status').exists() else 'RUNNING'
        jobs.append(dict(job=str(job.relative_to(root)),status=status,mode=manifest['mode'],profile=manifest['profile'],depth=manifest['depth'],engine=manifest.get('engine'),guided=manifest.get('guided_input_witness',False),closed_input_driver=manifest.get('closed_input_driver',False),trim_unused_wrapper_exports=manifest.get('trim_unused_wrapper_exports',False),selected_assertions=manifest.get('selected_assertions'),cover_check_start=manifest.get('cover_check_start',0),inputs_sha256=hashlib.sha256((job/'inputs.json').read_bytes()).hexdigest()))
        waiting=[]
        for line in log.read_text().splitlines():
            m=re.search(r'Reached cover statement in step (\d+).*?((?:cmdbuf_rd_port_)[\w]+\.svh):(\d+)',line)
            if m:
                source=job/m[2];source_line=source.read_text(encoding='utf8').splitlines()[int(m[3])-1]
                label=re.search(r'`TP_COVER\((\w+),',source_line)
                if not label:raise ValueError('Cannot resolve source label '+line)
                record=dict(method='sby_cover_guided' if manifest.get('guided_input_witness') else 'sby_cover_unrestricted',job=str(job.relative_to(root)),step=int(m[1]),source=m[2],line=int(m[3]),job_status=status,trace=None)
                if label[1] not in hits or record['step']<hits[label[1]]['step']:hits[label[1]]=record
                waiting.append((label[1],record))
            t=re.search(r'Writing trace to VCD file: (\S+)',line)
            if t:
                for label,record in waiting:record['trace']=str((log.parent/t[1]).relative_to(root))
                waiting=[]
        # BTOR cover has no SMTBMC "Reached cover statement" line. Accept only
        # a verified single-target job; b0 in a SAT witness is then unambiguous.
        if manifest['mode']=='cover' and manifest.get('engine','').startswith('btor ') and status.split()[0]=='PASS':
            selected=[]
            for source in sorted(job.glob('cmdbuf_rd_port*')):
                if source.suffix not in ('.sv','.svh'):continue
                for number,line in enumerate(source.read_text(encoding='utf8').splitlines(),1):
                    m=re.match(r'^\s*`TP_COVER\((\w+),',line)
                    if m:selected.append((m[1],source.name,number))
            btor=(job/'run/model/design_btor.btor').read_text()
            targets=[line for line in btor.splitlines() if re.match(r'^\d+ bad ',line)]
            witness=(job/'run/engine_0/trace.wit').read_text().splitlines()
            trace=job/'run/engine_0/trace.vcd'
            assert len(selected)==len(targets)==1,(job,'BTOR collector requires exactly one cover')
            label,source,number=selected[0]
            assert '{}:{}'.format(source,number) in targets[0],(job,'BTOR target/source mismatch')
            assert witness[:2]==['sat','b0'] and trace.stat().st_size>0,(job,'Missing SAT cover witness')
            step=max(int(s[1:]) for s in witness if re.match(r'^#\d+$',s))
            method='sby_cover_closed_inputs' if manifest.get('closed_input_driver') else ('sby_cover_guided' if manifest.get('guided_input_witness') else 'sby_cover_unrestricted')
            record=dict(method=method,job=str(job.relative_to(root)),step=step,source=source,line=number,job_status=status,trace=str(trace.relative_to(root)),witness=str((job/'run/engine_0/trace.wit').relative_to(root)))
            if label not in hits or step<hits[label]['step']:hits[label]=record
    return hits,jobs
def collect(root):
    mapping=json.loads((HERE/'property_map.json').read_text(encoding='utf8'));fh,jobs=formal_hits(root)
    sh={};runs=[]
    for path in sorted(root.glob('witness*/results.json')):
        result=json.loads(path.read_text())
        for run in result['runs']:runs.append(dict(run=path.parent.name+'/'+run['run'],passed=run['passed'],input_sha256=run['input_sha256']))
        passed={r['run'] for r in result['runs'] if r['passed']}
        for label,hit in result['hits'].items():
            if hit['run'] not in passed:continue
            r={**hit,'folder':path.parent.name}
            if label not in sh or r['cycle']<sh[label]['cycle']:sh[label]=r
    rows=[]
    for row in mapping['rows']:
        bins=[]
        for b in row['cover_bins']:
            label=b['label'];bins.append(dict(label=label,predicate=b['predicate'],profile=b['profile'],formal=fh.get(label),simulation=sh.get(label),hit=label in fh or label in sh))
        rows.append(dict(testpoint=row['testpoint'],name=row['name'],assertions=row['assertions'],observable_scope=row['observable_scope'],structural_gap=row['structural_gap'],original_scope_limit=row['limitation'],total_bins=len(bins),formal_bins=sum(b['formal'] is not None for b in bins),hit_bins=sum(b['hit'] for b in bins),all_bins_hit=all(b['hit'] for b in bins),any_bin_hit=any(b['hit'] for b in bins),bins=bins))
    methods={}
    for row in rows:
        for item in row['bins']:
            if item['formal']:
                method=item['formal']['method'];methods[method]=methods.get(method,0)+1
    summary=dict(testpoints=len(rows),mapped_bins=sum(r['total_bins'] for r in rows),testpoints_any_witness=sum(r['any_bin_hit'] for r in rows),testpoints_all_bins_hit=sum(r['all_bins_hit'] for r in rows),testpoints_all_formal_bins=sum(r['formal_bins']==r['total_bins'] for r in rows),formal_bins=sum(r['formal_bins'] for r in rows),formal_witness_methods=methods,combined_hit_bins=sum(r['hit_bins'] for r in rows),structural_gap_testpoints=sum(bool(r['structural_gap']) for r in rows),original_scope_limit_testpoints=sum(bool(r['original_scope_limit']) for r in rows),simulation_runs=len(runs),simulation_runs_passed=sum(r['passed'] for r in runs),all_original_requirements_proved=False,formalmc_executed=False)
    result=dict(schema_version=1,summary=summary,jobs=jobs,runs=runs,rows=rows,scope='Covers establish bounded reachability. Guided runs fix only input ports. Simulation is reported separately. Physical storage requirements remain unobservable. Bounded PASS is not an unbounded proof.')
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    r=collect(a.root);a.output.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n',encoding='utf8');print(json.dumps(r['summary']))
