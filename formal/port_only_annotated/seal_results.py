#!/usr/bin/env python3
"""Audit and archive this port-only VM campaign, preserving non-PASS attempts.

This packages actual records; it does not run a solver or turn coverage into proof.
The complete heavy solver work directories remain on the originating VM.
"""
import argparse, collections, hashlib, json, re, subprocess, tarfile
from pathlib import Path
from collect_results import collect

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(1048576),b''):h.update(block)
    return h.hexdigest()

def save(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf8')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',required=True,type=Path)
    p.add_argument('--output',required=True,type=Path)
    a=p.parse_args();root=a.root.resolve();out=a.output.resolve()
    out.mkdir(parents=True,exist_ok=False)
    coverage=collect(root)
    assert coverage['summary']['formal_bins']==1415
    assert coverage['summary']['testpoints_all_formal_bins']==200
    traces={b['formal']['trace'] for r in coverage['rows'] for b in r['bins']}
    assert None not in traces
    for name in traces:assert (root/name).is_file() and (root/name).stat().st_size>0,name

    # Every recorded job is checked against the exact source/config snapshot.
    input_audits=[]
    for manifest in sorted(root.glob('**/inputs.json')):
        if out in manifest.parents:continue
        record=json.loads(manifest.read_text())
        for name,expected in record['files'].items():
            assert sha(manifest.parent/name)==expected,(manifest,name,'changed input')
        input_audits.append(dict(path=str(manifest.relative_to(root)),sha256=sha(manifest),files=len(record['files'])))

    mutations={};attempts=[]
    for file in sorted(root.glob('mutations*/results.json')):
        for row in json.loads(file.read_text())['mutations']:
            row=dict(row,evidence=str(file.relative_to(root)));attempts.append(row)
            if row['assertion_failure_observed']:mutations[row['mutation']]=row
    assert len(mutations)==8
    replay=json.loads((root/'replay_final/results.json').read_text())
    assert replay['all_passed'] and len(replay['runs'])==388 and replay['total_cycles']==386500
    input_hashes={sha(f) for f in root.glob('witness*/*.inputs')}
    for row in replay['runs']:
        assert row['passed'] and row['exact_input_replay'] and row['input_sha256'] in input_hashes,row
    assert sha(root/'sim_final/obj_dir/Vcmdbuf_rd_formal')==replay['binary_sha256']

    tool_versions={}
    for name,args in [('sby',['sby','--version']),('yosys',['yosys','-V']),('verilator',['/usr/local/bin/verilator','--version']),('yices',['yices-smt2','--version']),('btormc',['btormc','--version'])]:
        run=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,universal_newlines=True)
        tool_versions[name]=dict(returncode=run.returncode,output=run.stdout.strip())
    native=json.loads((root/'source_validation_final.json').read_text())
    port_audit=json.loads((root/'port_audit_final.json').read_text())
    assert len(native['native_lint'])==9 and all(x['passed'] for x in native['native_lint'])
    assert port_audit['passed']
    jobs={j['job']:j for j in coverage['jobs']}
    proof=jobs['wave02/protocol_prove']
    assert proof['status'].startswith('PASS')
    expected_proof='A_RESET_OUTPUTS,A_REQ_ONEHOT,A_R_ONEHOT,A_R_READY,A_R_IDLE_ZERO'
    assert proof['selected_assertions']==expected_proof
    bounded=[jobs[n] for n in ['wave11/base_bmc10','wave11/perf0_bmc20','wave11/perf_rr_bmc20','wave_alt/highest_free_slot']]
    assert all(j['status'].startswith('PASS') for j in bounded)
    profiles=collections.Counter(jobs[b['formal']['job']]['profile'] for r in coverage['rows'] for b in r['bins'])
    summary=dict(schema_version=1,campaign='cmdbuf_rd_port_only_20261018',verification_host='Linux VM 192.168.31.116',
        coverage=coverage['summary'],cover_profiles=dict(profiles),distinct_formal_trace_files=len(traces),
        port_audit=port_audit,native_compile=native,unbounded_proof=proof,bounded_checks=bounded,
        full_unbounded_proof_complete=False,general_drain_bound_proved=False,
        mutation_detected=len(mutations),mutation_total=8,mutations=list(mutations.values()),mutation_attempts=attempts,
        simulation_replay=dict(runs=len(replay['runs']),cycles=replay['total_cycles'],all_passed=True,exact_input_replay=True,binary_sha256=replay['binary_sha256']),
        tool_versions=tool_versions,formalmc_executed=False,
        scope_notes=[
            'All 200 mapped points have witnesses for all 1415 mapped functional bins, not a proof of all original requirements.',
            '28 points include physical implementation requirements unobservable at public ports; only their stated functional proxies are checked.',
            'Six original scenario/sampling limitations remain listed per testpoint.',
            'Unrestricted cover means no saved-input guidance; each profile retains its own declared input assumptions.',
            'Guided covers constrain public input ports only. The longflow driver also fixes only inputs and starts its counter at zero.',
            'Selected-property and skip settings remain in every job record. Skipped cover prefixes are not assertion proofs.',
            'Only the five named protocol properties have new unbounded PASS evidence; the whole checker has BASE BMC depth 10.',
            'All failed, unknown, timed-out and cancelled search attempts are preserved; previously emitted valid cover traces retain their reachability meaning.',
            'Native compilation is Slang on Windows. Formal runs and final assertion-enabled simulation replay are on the Linux VM.',
            'These are new port-only checker results, not a rerun of the historic UCAgent 14-stage closure or 49-mutation campaign.'
        ])
    save(out/'coverage_final.json',coverage);save(out/'validation_summary.json',summary)
    save(out/'input_audit.json',dict(passed=True,manifests=input_audits))
    save(out/'source_manifest.json',{str(f.relative_to(root)):sha(f) for f in sorted(root.iterdir()) if f.is_file() and f.suffix in ['.py','.sv','.svh','.cpp','.json']})

    members=set()
    def add(file):
        if file.is_file() and out not in file.parents:members.add(file)
    # Source, job matrices, logs and status records from every attempt.
    for file in root.iterdir():
        if file.is_file() and file.suffix in ['.py','.sv','.svh','.cpp','.json','.log']:add(file)
    for file in (root/'rtl').glob('*.v'):add(file)
    for manifest in root.glob('**/inputs.json'):
        if out in manifest.parents:continue
        add(manifest)
        for name in json.loads(manifest.read_text())['files']:add(manifest.parent/name)
    for folder in list(root.glob('wave*'))+list(root.glob('mutations*')):
        if not folder.is_dir():continue
        for file in folder.rglob('*'):
            if file.name in ['status','PASS','FAIL','UNKNOWN','ERROR','TIMEOUT'] or file.suffix=='.log' or (file.name=='results.json'):add(file)
    # Exactly the formal traces selected by the per-point report, with replay aids.
    for name in traces:
        file=root/name;add(file)
        for suffix in ['.yw','.wit','.tb.v','.smtc']:add(file.with_suffix(suffix))
    # Preserve counterexamples and induction diagnostics even on non-PASS tasks.
    for folder in list(root.glob('mutations*'))+[root/'wave01/base_prove']:
        for file in folder.glob('**/engine_*/*'):
            if file.suffix in ['.vcd','.yw','.wit','.v','.smtc']:add(file)
    for file in (root/'wave12/long4096_btor/run/model').glob('*.btor*'):add(file)
    for folder in root.glob('witness*'):
        if folder.is_dir():
            for file in folder.iterdir():
                if file.suffix in ['.inputs','.json','.log']:add(file)
    for file in (root/'replay_final').iterdir():
        if file.suffix in ['.json','.log']:add(file)
    add(root/'replay_final.log');add(root/'sim_final_compile.log')
    file_map={str(f.relative_to(root)):dict(bytes=f.stat().st_size,sha256=sha(f)) for f in sorted(members)}
    save(out/'evidence_manifest.json',dict(files=file_map,exclusions='Unselected duplicate cover traces, compiled binaries and heavy generated SMT/Yosys intermediates; full VM work directories retained.'))
    archive=out/'vm_evidence.tar.gz'
    with tarfile.open(str(archive),'w:gz',compresslevel=6) as tar:
        for file in sorted(members):tar.add(str(file),arcname=str(file.relative_to(root)),recursive=False)
    save(out/'archive.json',dict(file=archive.name,bytes=archive.stat().st_size,sha256=sha(archive),members=len(members)))
    print(json.dumps(dict(summary=summary['coverage'],archive_bytes=archive.stat().st_size,members=len(members),input_manifests=len(input_audits))))

if __name__=='__main__':main()
