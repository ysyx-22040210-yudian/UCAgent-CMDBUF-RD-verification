#!/usr/bin/env python3
"""Collect fresh evidence without rewriting any historical source or status."""
import hashlib
import json
from pathlib import Path
import re
import tarfile

HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    base=HERE/'runs_01'
    report=json.loads((base/'results.json').read_text())
    report['mutations']=json.loads((HERE/'mutations_01/results.json').read_text())['mutations']
    report['additional_jobs']=[]
    for name in ['release_bmc','prove_strengthened']:
        f=HERE/name
        if not (f/'run/status').exists():raise RuntimeError('Still running: '+name)
        report['additional_jobs'].append({'job':name,'status':(f/'run/status').read_text().strip(),
          'mode':'bmc' if name=='release_bmc' else 'prove','depth':9 if name=='release_bmc' else 5,
          'input_manifest_sha256':sha(f/'inputs.json')})
    report['final_sources']={p.name:sha(p) for p in HERE.glob('cmdbuf_rd_sva*') if p.suffix in ['.sv','.svh']}
    report['all_new_assertions_unbounded_proven']=False
    report['all_1415_mapped_covers_executed']=False
    report['formalMC_executed']=False
    report['current_RTL_modified']=False
    report['executed_cover_labels']={
      'cover_lifecycle':['C_B_FLOW_01_S0T00','C_F_CON_16_MAIN','C_F_REU_01_MAIN','C_F_ERR_04_MAIN'],
      'cover_schedule':['C_B_BLOCK_04_MAIN','C_B_BLOCK_03_MAIN','C_F_WIN_05_MAIN','C_F_CAP_04_EMPTY2','C_F_RR_05_PTR0E7'],
      'negative':['C_P_AR_11_SRC','C_P_AR_11_RESP01','C_P_AR_11_RESP10'],
      'idle_reset':['C_B_FLOW_10_RESET']}
    report['source_revisions_note']='Each inputs.json binds the actual source snapshot. Early runs precede final declaration-placement fix and the extra induction invariants. release_bmc uses final checker sources. Native SVA final profiles are separately compiled on Windows.'
    (HERE/'validation_results.json').write_text(json.dumps(report,indent=2)+'\n')
    roots=[HERE/'runs_01',HERE/'mutations_01',HERE/'release_bmc',HERE/'prove_strengthened']
    files=[]
    for root in roots:
        for p in root.rglob('*'):
            if not p.is_file():continue
            rel=p.relative_to(root).parts
            # Preserve input snapshots, raw logs/status and executable witnesses;
            # omit reproducible solver intermediates and duplicated src trees.
            if any(s in ['src','model'] for s in rel):continue
            if p.suffix in ['.sv','.svh','.v','.sby','.tcl','.f','.json','.log','.txt','.vcd','.yw','.smtc'] or p.name=='status':files.append(p)
    files += [HERE/'validation_results.json',HERE/'validation_driver.log',HERE/'mutation_driver.log',HERE/'release_bmc.log',HERE/'prove_strengthened.log']
    archive=HERE/'sva_validation_evidence.tar.gz'
    with tarfile.open(str(archive),'w:gz') as tar:
        for p in sorted(set(files)):tar.add(str(p),arcname=p.relative_to(HERE).as_posix())
    result={'archive':archive.name,'sha256':sha(archive),'bytes':archive.stat().st_size,'files':len(set(files)),
            'results_sha256':sha(HERE/'validation_results.json')}
    (HERE/'evidence_manifest.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result))
if __name__=='__main__':main()
