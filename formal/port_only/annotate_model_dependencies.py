#!/usr/bin/env python3
"""Mark properties which do not need the transaction reference model.

Classification follows a reviewed dependency registry, not a signal-name rule.
The helper-defining source logic is pinned: review the registry again if it changes.
Unknown dependencies are conservatively classified as REF_MODEL.
Only comments and metadata are changed; no property or assumption is rewritten.
"""
import argparse,collections,hashlib,json,re
from pathlib import Path
from audit_ports import ports

HERE=Path(__file__).resolve().parent
APPROVED_LOGIC={
    'cmdbuf_rd_port_sva.sv':'d1441a6515544d27d23c53db9bdd09863137dcefa3257f1c4610c5787ef59e76',
    'cmdbuf_rd_port_scenarios.svh':'1e7274d2c6329be025635735910153760334aa6771c009c801743aa9e70768bd',
    'cmdbuf_rd_port_profiles.svh':'ae7b93cb8e167906073b1c981b0e8d890a045dbeac563b1efc968d07817fb2b2',
}
def logic_text(text):
    text=re.sub(r'//[^\n]*|/\*[\s\S]*?\*/','',text)
    return '\n'.join(line.rstrip() for line in text.splitlines())+'\n'
def logic_sha(text):return hashlib.sha256(logic_text(text).encode('utf8')).hexdigest()

# Dependencies include both RHS values and control conditions of each helper.
# A common initial-sample guard is allowed in NO_REF_MODEL_PORTS; it predicts no
# transaction behavior. Actual temporal predicates use NO_REF_MODEL_HISTORY.
REGISTRY={
    'started':('GUARD',[], 'Zero-initialized first-clock flag; 1 thereafter.'),
    'active':('ALIAS',['started','rst_n'],'Common sample guard.'),
    'accept':('ALIAS',['arvalid','src','arready'],'Actual AR handshake.'),
    'success':('ALIAS',['req','ar_rd_gnt','rw_rd_gnt'],'Actual same-bank dual grant.'),
    'retire':('ALIAS',['rvalid','rready'],'Actual R handshake.'),
    'bad_src':('ALIAS',['arvalid','src'],'Illegal source input monitor.'),
    'bad_arresp':('ALIAS',['arvalid','arresp'],'Illegal response-code input monitor.'),
    'attempt_ar':('ALIAS',['req','ar_rd_gnt'],'Current request intersects AR grant.'),
    'attempt_rw':('ALIAS',['req','rw_rd_gnt'],'Current request intersects RW read grant.'),
    'wrong_grant':('ALIAS',['ar_rd_gnt','rw_rd_gnt','success'],'Unmatched public grants.'),
    'previous_reset':('HISTORY',['rst_n'],'One-cycle reset history.'),
    'history':('HISTORY',['rst_n'],'Four-bit post-reset sample-valid history.'),
    'm_due':('HISTORY',['rst_n','success'],'Four-cycle issue-valid shift only; no entry identity.'),
    'due':('ALIAS',['m_due'],'Expected arrival-valid time, not observed DUT capture.'),
    'aimr':('ALIAS',['accept','success','due','retire'],'Public events plus expected arrival-valid.'),
    'accepted_total':('HISTORY',['rst_n','accept'],'Saturating accepted-transaction count.'),
    'retired_total':('HISTORY',['rst_n','retire'],'Saturating response count.'),
    'success_pattern':('HISTORY',['rst_n','success'],'Eight sampled issue-success bits.'),
    'pc_pattern':('HISTORY',['rst_n','due','pc_err'],'Error history sampled at expected arrival.'),
    'last_status':('HISTORY',['rst_n','rd_mem_status'],'Previous public Bank state.'),
    'prev_status':('HISTORY',['rst_n','rd_mem_status'],'Previous public Bank state in scenarios.'),
    'issue_streak':('HISTORY',['rst_n','success'],'Consecutive successful issue count.'),
    'response_streak':('HISTORY',['rst_n','retire'],'Consecutive response count.'),
    'fullrate_streak':('HISTORY',['rst_n','aimr'],'Consecutive A/I/expected-M/R count.'),
    'seen_accept_src':('HISTORY',['rst_n','accept','src'],'Accepted source bitmap.'),
    'pc_run':('HISTORY',['rst_n','due'],'Consecutive expected-arrival count.'),
    'pc_contiguous':('HISTORY',['rst_n','due','pc_err'],'Expected-arrival error pattern.'),
    'pc_run_done':('HISTORY',['rst_n','due','pc_run','pc_contiguous','pc_err'],'Recognizes the input error pattern; no response-data association.'),
    'success_bubble_seen':('HISTORY',['rst_n','success_pattern'],'Recognizes a public success pattern.'),
    'perf_cycles':('HISTORY',['rst_n'],'Saturating PERF elapsed-clock count.'),
    'offer_src':('HISTORY',['rst_n'],'Deterministic PERF source phase.'),
    'TP_PERF_SINGLE':('CONSTANT',[],'Selected PERF source macro.'),
    'reset_seen':('HISTORY',['started','rst_n'],'Additional reset seen.'),
    'resumed':('HISTORY',['reset_seen','rst_n'],'Released after additional reset.'),
    'drain_start':('ENV_CONTROL',[],'Independent anyseq harness marker, not a DUT port.'),
    'draining':('ALIAS',['rst_n','drain_start'],'Latched environment drain phase.'),
    'drain_cycles':('ALIAS',['rst_n','draining'],'Environment drain phase elapsed time.'),
}
DESCRIPTIONS={
    'NO_REF_MODEL_PORTS':'No transaction reference model: public ports / aliases / common sample guards only.',
    'NO_REF_MODEL_HISTORY':'No transaction reference model: retain the listed public-port histories or counters.',
    'NO_REF_MODEL_ENV':'No transaction reference model: requires an independent environment phase marker.',
    'REF_MODEL':'Depends on transaction identity, occupancy, scheduling, stored expected data or derived reference state.',
    'MODEL_SELF_CHECK':'Consistency of the reference model itself; not a DUT storage proof.',
}
PROPERTY_RE=re.compile(r'^\s*`TP_(ASSERT|ASSUME|COVER)\((\w+),\s*(.+)\)\s*$')
def identifiers(expr):
    expr=re.sub(r"\b\d*'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+|\b\d+|\$\w+",' ',expr)
    return sorted(set(re.findall(r'\b[A-Za-z_]\w*',expr)))

def classify(kind,label,expr,public):
    names=identifiers(expr);hist=set();env=set();unknown=set();helpers=set()
    def visit(name):
        if name in public:return
        if name in helpers:return
        if name not in REGISTRY:unknown.add(name);return
        helpers.add(name);category,parents,_=REGISTRY[name]
        if category=='HISTORY':hist.add(name)
        if category=='ENV_CONTROL':env.add(name)
        for parent in parents:visit(parent)
    for name in names:visit(name)
    temporal=bool(re.search(r'\$(?:past|rose|fell|stable)\b',expr))
    if kind=='ASSERT' and label.startswith('M_'):category='MODEL_SELF_CHECK'
    elif unknown:category='REF_MODEL'
    elif env:category='NO_REF_MODEL_ENV'
    elif hist or temporal or label in ['E01_RESET_FIRST','E02_RESET_RELEASE']:category='NO_REF_MODEL_HISTORY'
    else:category='NO_REF_MODEL_PORTS'
    return dict(category=category,no_transaction_reference_model=category.startswith('NO_REF_MODEL'),
                direct_identifiers=names,required_helpers=sorted(helpers),history_helpers=sorted(hist),
                environment_helpers=sorted(env),reference_or_unclassified_dependencies=sorted(unknown),uses_temporal_operator=temporal)

def annotate(directory=HERE,check=False):
    directory=Path(directory)
    for name,expected in APPROVED_LOGIC.items():
        assert logic_sha((directory/name).read_text(encoding='utf8'))==expected,('Helper logic changed; review dependency registry before annotation',name)
    public=set(ports((directory/'cmdbuf_rd_port_sva.sv').read_text(encoding='utf8'),'cmdbuf_rd_port_sva'))
    records=[];sources={};updates={}
    for name in ['cmdbuf_rd_port_sva.sv','cmdbuf_rd_port_covers.svh','cmdbuf_rd_port_profiles.svh']:
        file=directory/name;text=file.read_bytes().decode('utf8');lines=text.splitlines(keepends=True);conditions=[]
        for n,line in enumerate(lines):
            # The leading block tag is visible without horizontal scrolling.
            # Strip only our own tag before parsing; keep the property unchanged.
            code=re.sub(r'/\* \[NO_REF_MODEL_(?:PORTS|HISTORY|ENV)\] \*/', '', line.split('//',1)[0]).rstrip();m=PROPERTY_RE.match(code)
            directive=re.match(r'^\s*`(ifdef|ifndef)\s+(\w+)',code)
            if directive:conditions.append(('!' if directive[1]=='ifndef' else '')+directive[2])
            elif re.match(r'^\s*`else\b',code):conditions[-1]=conditions[-1][1:] if conditions[-1].startswith('!') else '!'+conditions[-1]
            elif re.match(r'^\s*`endif\b',code):conditions.pop()
            if not m:continue
            kind,label,expr=m.groups();dependency=classify(kind,label,expr,public)
            item=dict(label=label,kind=kind,source=name,line=n+1,compile_conditions=list(conditions),expression=expr,**dependency)
            records.append(item)
            ending='\r\n' if line.endswith('\r\n') else '\n'
            indent=code[:len(code)-len(code.lstrip())]
            leading=('/* ['+dependency['category']+'] */') if dependency['no_transaction_reference_model'] else ''
            lines[n]=indent+leading+code[len(indent):]+' // ['+dependency['category']+']'+ending
        annotated=''.join(lines)
        assert logic_text(text)==logic_text(annotated),(name,'Non-comment change')
        assert len(text.splitlines())==len(annotated.splitlines()),(name,'Line numbers changed')
        sources[name]=dict(logic_sha256=logic_sha(annotated),line_count=len(lines))
        updates[file]=annotated.encode('utf8')
    counts={kind:dict(collections.Counter(r['category'] for r in records if r['kind']==kind)) for kind in ['ASSERT','ASSUME','COVER']}
    standalone_asserts={r['label'] for r in records if r['kind']=='ASSERT' and r['no_transaction_reference_model']}
    assert standalone_asserts=={'A_RESET_OUTPUTS','A_RESET_EMPTY','A_REQ_ONEHOT','A_R_ONEHOT','A_R_READY','A_R_IDLE_ZERO','A_PERF_STEADY','A_NEG_SRC_MONITOR','A_NEG_RESP_MONITOR'},standalone_asserts
    mapping_file=directory/'property_map.json';mapping=json.loads(mapping_file.read_text(encoding='utf8'))
    by_label=collections.defaultdict(list)
    for row in records:by_label[row['label']].append(row)
    rows=[]
    for row in mapping['rows']:
        for name in row['assertions']:assert by_label[name.split('.')[-1]],('Missing assertion',name)
        for item in row['cover_bins']:assert by_label[item['label']],('Missing cover',item['label'])
        independent=[a for a in row['assertions'] if all(r['no_transaction_reference_model'] for r in by_label[a.split('.')[-1]])]
        dependent=[a for a in row['assertions'] if a not in independent]
        independent_covers=[b['label'] for b in row['cover_bins'] if all(r['no_transaction_reference_model'] for r in by_label[b['label']])]
        data=dict(no_ref_assertions=independent,reference_model_assertions=dependent,no_ref_cover_bin_count=len(independent_covers),total_cover_bins=len(row['cover_bins']),no_ref_cover_labels=independent_covers)
        row['model_dependency']=data
        rows.append(dict(testpoint=row['testpoint'],name=row['name'],**data))
    result=dict(schema_version=1,scope='Property dependency annotation only, not a new verification result.',
        definitions=DESCRIPTIONS,counts_by_occurrence=counts,sources=sources,
        helper_registry={key:dict(kind=value[0],parents=value[1],meaning=value[2]) for key,value in REGISTRY.items()},
        properties=records,testpoints=rows,
        caveats=[
            'A NO_REF_MODEL tag describes that expression and its helpers, not the entire testpoint or every assumption in its profile.',
            'started/active common sampling guards are permitted in NO_REF_MODEL_PORTS; HISTORY still needs finite auxiliary state.',
            'm_due/due is only a four-cycle history of actual public issue success, not an observation of internal MEM capture; m_due_e is model-dependent.',
            'A_RR_BOUND uses model-derived eligible and therefore remains REF_MODEL even though it contains a counter.',
            'NEGATIVE assertions validate input-violation monitors, not DUT recovery. PERF and DRAIN require their separate environment contracts.',
            'TP_IDLE_RESET contains model-dependent E02_RESET_IDLE_ONLY; individual independent properties do not remove this profile dependency.',
            'Unknown dependencies are conservatively REF_MODEL. The reviewed helper source logic is pinned to prevent silent classification drift.'
        ])
    updates[mapping_file]=(json.dumps(mapping,ensure_ascii=False,indent=2)+'\n').encode('utf8')
    updates[directory/'model_dependency_map.json']=(json.dumps(result,ensure_ascii=False,indent=2)+'\n').encode('utf8')
    for file,content in updates.items():
        if check:assert file.read_bytes()==content,('Stale or missing dependency annotation',file)
        else:file.write_bytes(content)
    return result

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');a=p.parse_args()
    result=annotate(check=a.check)
    print(json.dumps(result['counts_by_occurrence'],indent=2))
