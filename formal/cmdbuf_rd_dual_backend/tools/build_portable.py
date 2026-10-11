#!/usr/bin/env python3
"""Build a relocatable, result-free SBY/FormalMC input bundle from audited evidence.

Run with Python >=3.9 and the same Yosys generation as the source campaign.
Yosys is a build-time dependency; FormalMC destination machines do not need it.
No historical PASS is imported into the portable result namespace.
"""
from __future__ import annotations
import argparse, hashlib, json, re, shlex, subprocess, tarfile
from pathlib import Path
import xml.etree.ElementTree as ET

ARCHIVE_SHA = '9cc646b2c13a659256b45d1b30a0cd82444ca6a7d8bcbe16a6cd9e9df4ccda00'
RUN_NAMES = {
 'bece67a18aa24e32a29dcbed6105bf0a':'wiring',
 'd1b24d76e50246b68984850bd65e972a':'local_transition',
 '06c3fcda800c4a8dbbeac8bbcaf4c9cd':'data_transition',
 '6b25c32cc4d64e4d83e743c701528ade':'calendar',
 '339d5e96ea7a492387752769b6cd080a':'data_origin',
 '6f1285ed84d047b9ba505a522bf71969':'aggregate',
 '1a259298993d49919ccc6332642b12e9':'structural',
 'e2b5b98c9ce24c82ac3ed80cc77611a7':'age_projection',
 '7af94773755d4ab0be53772682e87162':'policy_order',
 '710c43c596af4eea8898f0c750b4537d':'pipeline',
 '30aafb11117a4815a2ae49e811cdfc01':'aggregate_split',
 '9f128a2b818b4e24b92fdf19a4badd65':'source_net_math',
 'f0e59eb1c92d413aa7868ab341df8bcc':'quota_math',
 '23dfb1fbd1374613b5377a93dacf1f03':'capacity',
 'd3abbb66bc0a4911a09e05d86571302d':'lifecycle_r2',
 '88efe3bbd1a44059bf2cd59e4609b7b3':'lifecycle',
 '4126ae65ec774b3eb5dee97e117dfd51':'cover_pipeline',
 '4fad3bf036e74783a432f308ad4f5a89':'cover_data_identity',
 '5a0bc47ec6dc42479e2c826cce8b6a88':'cover_banks',
 '70ed659d569f48608f2c0ecb96219add':'cover_window_response',
}

def sha(data): return hashlib.sha256(data).hexdigest()
def dump(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())
def recursive_runs(obj):
    result=set()
    if isinstance(obj,dict):
        for k,v in obj.items():
            if k in ('run_id','supplier_run_id') and isinstance(v,str) and re.fullmatch('[a-f0-9]{32}',v): result.add(v)
            else: result |= recursive_runs(v)
    elif isinstance(obj,list):
        for v in obj: result |= recursive_runs(v)
    return result
def stripped_contract(obj):
    if isinstance(obj,dict):
        return {k:stripped_contract(v) for k,v in obj.items() if k not in {'property','status','review_status','started_at'}}
    if isinstance(obj,list): return [stripped_contract(v) for v in obj]
    return obj
def run_yosys(exe, script, cwd, log):
    result=subprocess.run([exe,'-Q','-T','-p',script],cwd=cwd,capture_output=True,text=True)
    write(log,result.stdout+result.stderr)
    if result.returncode: raise RuntimeError('Yosys failed: '+str(log))

def parse_config(config):
    sections={}; section=None
    for line in config.splitlines():
        m=re.fullmatch(r'\[(\w+)\]',line.strip())
        if m: section=m[1];sections[section]=[]
        elif section: sections[section].append(line)
    opts=dict(line.split(None,1) for line in sections['options'] if line.strip() and not line.startswith('#'))
    script='\n'.join(sections['script']).strip()
    if not re.search(r'\bprep -top (\w+)',script):raise ValueError('missing explicit prep top')
    if opts.get('multiclock','off')!='off':raise ValueError('only audited single-clock jobs supported')
    return opts,script,re.search(r'\bprep -top (\w+)',script)[1]

def convert_normalized_il(il_text, design, top, mode):
    """Expose exact A/EN endpoints and symbolic ports in one flattened RTLIL module.

    This is deliberately a narrow parser of Yosys's own emitted RTLIL, not an SV
    source-to-source rewrite. Unknown formal cells are rejected. All procedural
    $past and loop semantics have already been lowered by the actual frontend.
    """
    if set(design['modules'])!={top}:raise ValueError('normalization must flatten to one module')
    module=design['modules'][top]
    props=[];symbols=[];extra=[];stmts=[]
    port_id=max([0]+[int(m) for m in re.findall(r'\b(?:input|output|inout) (\d+)',il_text)])
    formal_types={'$assert','$assume','$cover'}
    allowed_special={'$anyseq','$anyconst','$scopeinfo'}
    if any(c['type'] in {'$check','$anyinit','$ff','$initstate','$allconst','$allseq','$live','$fair'} for c in module['cells'].values()):
        raise ValueError('unsupported residual formal primitive')
    blocks=list(re.finditer(r'(?:^  attribute[^\n]*\n)*^  cell (\S+) (\S+)\n(?:(?!^  end$).)*^  end\n',il_text,re.M|re.S))
    edits=[]
    for m in blocks:
        typ,raw_name=m[1],m[2];name=raw_name[1:] if raw_name.startswith('\\') else raw_name
        cell=module['cells'].get(name)
        if cell is None:raise ValueError('RTLIL/JSON name mismatch '+name)
        if typ not in formal_types|allowed_special:continue
        connections=dict(re.findall(r'^    connect \\(\w+) (.+)$',m[0],re.M))
        if typ=='$scopeinfo':edits.append((m.start(),m.end(),''));continue
        if typ in formal_types:
            if set(connections)!={'A','EN'}:raise ValueError('unknown formal cell ports')
            kind=typ[1:]
            # Match the backend's prove/cover selection, without changing assumptions.
            if (mode=='prove' and kind=='cover') or (mode=='cover' and kind=='assert'):
                edits.append((m.start(),m.end(),''));continue
            label='P_'+kind.upper()+'_'+str(len(props)).zfill(4)
            a_wire='portable_endpoint_condition_'+str(len(props)).zfill(4)
            en_wire='portable_endpoint_enabled_'+str(len(props)).zfill(4)
            extra += ['  wire \\'+a_wire,'  wire \\'+en_wire,
                      '  connect \\'+a_wire+' '+connections['A'],
                      '  connect \\'+en_wire+' '+connections['EN']]
            # A and EN already represent the exact global-step check. No extra clock delay.
            stmts.append('  always_comb if ('+en_wire+') '+label+': '+kind+' ('+a_wire+');')
            src=cell.get('attributes',{}).get('src','')
            props.append({'label':name,'sby_label':name.split('.')[-1], 'formalmc_label':label,
                          'kind':kind,'source_location':src,'a_connection':connections['A'],
                          'enable_connection':connections['EN']})
        else:
            if set(connections)!={'Y'}:raise ValueError('unknown symbolic cell ports')
            width=int(cell['parameters']['WIDTH'],2)
            label='portable_symbol_'+str(len(symbols)).zfill(4);port_id+=1
            extra += [f'  wire width {width} input {port_id} \\{label}',f'  connect {connections["Y"]} \\{label}']
            symbols.append({'port':label,'kind':typ[1:],'width':width,'original_cell':name,
                            'source_location':cell.get('attributes',{}).get('src','')})
            if typ=='$anyconst':
                stmts += [f'  reg [{width-1}:0] {label}_previous;',
                          f"  reg {label}_valid = 1'b0;",
                          f"  always @(posedge clk) begin {label}_previous <= {label}; {label}_valid <= 1'b1; end",
                          f'  always_comb if ({label}_valid) M_STABLE_{label}: assume ({label} == {label}_previous);']
        edits.append((m.start(),m.end(),''))
    for start,end,replacement in reversed(edits):il_text=il_text[:start]+replacement+il_text[end:]
    end=il_text.rfind('\nend')
    il_text=il_text[:end]+'\n'+'\n'.join(extra)+il_text[end:]
    return il_text,props,symbols,'\n'.join(stmts)+'\n'

def normalize_job(yosys, jobdir, cfg):
    opts,script,top=parse_config(cfg)
    dst=jobdir/'formalmc';meta=jobdir/'conversion';dst.mkdir(parents=True,exist_ok=True);meta.mkdir(exist_ok=True)
    il=meta/'normalized.il';js=meta/'normalized.json'
    # Same frontend and explicit initial state, then clock-preserving lowering.
    commands=script+'\nrename -witness\nflatten\nmemory_map\nasync2sync\nchformal -lower\nchformal -assume -early\nsetundef -undriven -anyseq\n'
    commands+=f'write_rtlil "{il.as_posix()}"\nwrite_json "{js.as_posix()}"\n'
    write(meta/'normalize.ys',commands)
    run_yosys(yosys,commands,jobdir/'sby',meta/'normalize.log')
    original_il=il.read_text();design=json.loads(js.read_text())
    converted,props,symbols,stmts=convert_normalized_il(original_il,design,top,opts['mode'])
    stripped=meta/'portable.il';write(stripped,converted)
    model=dst/'model.sv'
    run_yosys(yosys,f'read_rtlil "{stripped.as_posix()}"; write_verilog -sv -noattr "{model.as_posix()}"',jobdir/'sby',meta/'emit.log')
    sv=model.read_text();sv=sv.replace('endmodule',stmts+'endmodule')
    # Nonstandard primitives or sampled functions must not leak to the target.
    if re.search(r'\\\$(?:\w+)|\$(?:past|global_clock|initstate|anyseq|anyconst|anyinit|allseq|allconst)\b',sv):
        raise ValueError('untranslated formal primitive in '+str(model))
    write(model,sv)
    dump(meta/'property_map.json',props);dump(meta/'symbols.json',symbols)
    tcl=f'''# Generated portable FormalMC input. No reset abstraction: reset is in the model.
set here [file dirname [file normalize [info script]]]
read_design -top {top} -sysv -mfcu [list [file join $here model.sv]]
def_clk clk
if {{[info exists ::env(CMDBUF_FORMALMC_TIME)]}} {{
    set_opt -time $::env(CMDBUF_FORMALMC_TIME)
}} else {{
    set_opt -time 100000
}}
prove
show_prop -summary
fanin -cover -list -dump
exit
'''
    write(dst/'formal.tcl',tcl)
    # Fresh cross-backend validation entry, no target result carried forward.
    cross=f'''[options]
mode {opts['mode']}
depth {opts.get('depth','24')}
timeout {opts.get('timeout','600')}
multiclock off

[engines]
smtbmc yices

[script]
read_verilog -formal -sv model.sv
prep -top {top}

[files]
model.sv
'''
    write(dst/'validate.sby',cross)
    return opts,top,props,symbols

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--archive',required=True,type=Path);ap.add_argument('--output',required=True,type=Path);ap.add_argument('--yosys',required=True)
    args=ap.parse_args();archive=args.archive;out=args.output.resolve()
    h=hashlib.sha256()
    with archive.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    if h.hexdigest()!=ARCHIVE_SHA:raise ValueError('source archive SHA mismatch')
    names=['evidence/task/native_bindings.json','evidence/task/native_run_reviews.json','evidence/session/workspace/formal_out/tests/sby_inputs.json','evidence/session/workspace/formal_out/tests/sby_evidence.json']
    metadata={}
    with tarfile.open(archive,'r|gz') as tf:
        for m in tf:
            if m.name in names:metadata[m.name]=json.load(tf.extractfile(m))
    if set(metadata)!=set(names):raise ValueError('required source metadata missing')
    bindings=metadata[names[0]];reviews=metadata[names[1]];inputs=metadata[names[2]];guided_evidence=metadata[names[3]]
    runs=set(v['run_id'] for v in bindings.values())
    for rid in list(runs):runs |= recursive_runs(reviews.get(rid,{}))
    if not runs<=set(RUN_NAMES):raise ValueError('new run requires explicit reviewed naming')
    guided={mode:'evidence/session/workspace/'+p.rsplit('/',1)[0]+'/' for mode,p in guided_evidence['manifests'].items()}
    selected={};provenance={};manifests={};manifest_hashes={};configs={};xmls={}
    with tarfile.open(archive,'r|gz') as tf:
        for member in tf:
            if not member.isfile():continue
            name=member.name;job=None;tail=None
            match=re.search(r'^evidence/native/[^/]+/[^/]+/project/\.ucagent/platform-runs/([a-f0-9]{32})/formal/(.*)$',name)
            if match and match[1] in runs:job=RUN_NAMES[match[1]];tail=match[2]
            else:
                for mode,prefix in guided.items():
                    if name.startswith(prefix):job='guided_'+mode;tail=name[len(prefix):];break
            if not job:continue
            if tail=='manifest.json':
                raw=tf.extractfile(member).read();manifests[job]=json.loads(raw);manifest_hashes[job]=sha(raw)
            elif tail in ('proof/config.sby','run.sby'):configs[job]=tf.extractfile(member).read().decode()
            elif tail=='proof/run.xml':xmls[job]=tf.extractfile(member).read()
            elif tail.startswith('inputs/'):
                data=tf.extractfile(member).read();selected[(job,tail)]=data;provenance[(job,tail)]={'archive_member':name,'sha256':sha(data)}
    expect=set(RUN_NAMES[r] for r in runs)|{'guided_prove','guided_cover'}
    if set(configs)!=expect or set(manifests)!=expect:raise ValueError('incomplete source jobs '+str(expect-set(configs)))
    for (job,tail),data in selected.items():write(out/'jobs'/job/'sby'/tail,data)
    jobs=[];run_jobs={r:RUN_NAMES[r] for r in runs};maps={}
    for job in sorted(expect):
        jobdir=out/'jobs'/job;cfg=configs[job];write(jobdir/'sby/run.sby',cfg)
        manifest=manifests[job]
        # Every source byte is checked against the original signed run's input table.
        expected_hashes={}
        expected_hashes.update(manifest.get('input_hashes',{}));expected_hashes.update(manifest.get('prepared_input_hashes',{}))
        for (j,tail),data in selected.items():
            if j!=job:continue
            path=tail[len('inputs/'):]
            expected=expected_hashes.get(path)
            if expected is None:
                # Guided manifests bind sources via their session copy path.
                matches={v for k,v in expected_hashes.items() if k.endswith('/'+path) or k==path}
                if len(matches)==1:expected=matches.pop()
            if expected!=sha(data):raise ValueError('source binding mismatch '+job+'/'+path)
        print('normalize',job,flush=True)
        opts,top,props,symbols=normalize_job(args.yosys,jobdir,cfg);maps[job]=props
        rid=next((r for r,j in run_jobs.items() if j==job),None)
        deps=set()
        if rid:
            deps={run_jobs[r] for r in recursive_runs(reviews.get(rid,{})) if r!=rid}
            # CK supporting relations describe final end-to-end review, not
            # assumptions imported into each solver job. Only explicit theorem
            # supplier contracts schedule solver execution; mixing the two
            # creates false cycles between otherwise independent proof groups.
        jobs.append({'id':job,'depends_on':sorted(deps),'top':top,'mode':opts['mode'],
          'sby':{'config':f'jobs/{job}/sby/run.sby','sources':[f'jobs/{job}/sby/'+p for j,p in selected if j==job]},
          'formalmc':{'tcl':f'jobs/{job}/formalmc/formal.tcl','sources':[f'jobs/{job}/formalmc/model.sv'],
                      'validation_config':f'jobs/{job}/formalmc/validate.sby'},
          'properties':props,'ck_ids':[], 'source_run_id':rid or manifest['run_id'],
          'source_manifest_sha256':manifest_hashes[job],
          'source_inputs':[provenance[(j,p)]|{'path':p} for j,p in selected if j==job],
          'symbolic_ports':symbols})
    checks=[]
    for fg in inputs['spec']['function_groups']:
      for fc in fg['functions']:
       for ck in fc['check_points']:
        cid=ck['id'];kind=ck['kind'];binding=bindings.get(cid)
        if binding:job=run_jobs[binding['run_id']];label=binding['property_id'];support=binding.get('supporting_ck_ids',[])
        else:
            job='guided_cover' if kind=='cover' else 'guided_prove'
            prefix={'environment':'M_','safety':'A_','cover':'C_'}[kind]
            label=prefix+cid.replace('-','_');support=[]
        candidates=[p for p in maps[job] if p['label']==label or p['label'].endswith('.'+label)]
        if len(candidates)!=1:raise ValueError('missing/nonunique CK property '+cid+' '+job+' '+label)
        p=candidates[0]
        checks.append({'ck_id':cid,'kind':{'safety':'assert','environment':'assume','cover':'cover'}[kind],'job_id':job,'label':p['label'],'formalmc_label':p['formalmc_label'],
                       'supporting_ck_ids':support,'requirements':ck.get('requirements',[]),'description':ck.get('description','')})
        next(j for j in jobs if j['id']==job)['ck_ids'].append(cid)
    if len(checks)!=177:raise ValueError('expected 177 CK')
    guards=[{'job_id':'guided_cover','label':p['label'],'formalmc_label':p['formalmc_label']} for p in maps['guided_cover'] if p['label'].split('.')[-1].startswith('G_A_')]
    if len(guards)!=7:raise ValueError('expected 7 guard witnesses')
    dump(out/'provenance/contracts.json',{rid:stripped_contract(reviews[rid]) for rid in runs if rid in reviews})
    dump(out/'provenance/source_archive.json',{'sha256':ARCHIVE_SHA,'file':archive.name,'historical_results_imported':False})
    # The independently maintained runner/replay/readme are sealed by the final
    # release manifest; this builder owns only generated jobs and provenance.
    files={p.relative_to(out).as_posix():sha(p.read_bytes()) for root in (out/'jobs',out/'provenance') for p in root.rglob('*') if p.is_file()}
    dump(out/'manifest.json',{'schema_version':1,'project':'cmdbuf_rd','source_archive':{'sha256':ARCHIVE_SHA},
        'initial_status':'not_run','jobs':jobs,'checks':checks,'extra_guard_witnesses':guards,'files':files,
        'expected_counts':{'checks':177,'assert':107,'cover':65,'assume':5},
        'scope':{'initial_reset_only':True,'unconditional_liveness':False,'target_formalmc_run_performed':False},
        'conversion':{'method':'Yosys clock-preserving frontend lowering; exact A/EN endpoints; symbolic input lifting',
                      'yosys_version':subprocess.check_output([args.yosys,'-V'],text=True).strip(),
                      'no_extra_property_clock':True,'reset_not_abstracted':True}})
    print(json.dumps({'jobs':len(jobs),'checks':len(checks),'extra_guards':len(guards),'output':str(out)}))

if __name__=='__main__':main()
