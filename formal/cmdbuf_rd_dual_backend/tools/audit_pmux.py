"""Conservative two-state structural onehot0 certificate for generated pmuxes.

This is not a DUT property proof. It proves that parallel/priority case selection
agrees for each exported mux without relying on reset, contracts or reachability.
Every pair of simultaneously-high select bits must impose contradictory bit
assignments. Unknown cells retain only the select bit constraint (never guessed).
"""
from pathlib import Path
import hashlib
import itertools
import json
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parameter(cell, name):
    return int(cell['parameters'][name], 2)


def constraints(module, select, drivers):
    result = {}
    impossible = []
    rules = []

    def require(bit, value):
        if isinstance(bit, int):
            if bit in result and result[bit] != value:
                impossible.append(f'bit {bit} required both 0 and 1')
            result[bit] = value
        elif bit in ('0', '1'):
            if int(bit) != value:
                impossible.append(f'constant {bit} required {value}')
        else:
            # Unknown/x/z is not usable as a certificate constraint.
            pass

    require(select, 1)
    if select not in drivers:
        return result, impossible, rules
    name, cell, output_index = drivers[select]
    con = cell['connections']
    typ = cell['type']
    if typ == '$logic_not':
        assert output_index == 0
        for bit in con['A']:
            require(bit, 0)
        rules.append({'cell': name, 'rule': 'logic_not_true_requires_all_input_bits_zero'})
    elif typ == '$not':
        bits = con['A']
        if output_index < len(bits):
            require(bits[output_index], 0)
            rules.append({'cell': name, 'rule': 'bitwise_not_true_requires_input_bit_zero'})
    elif typ == '$eq':
        assert output_index == 0
        a, b = con['A'], con['B']
        # This certificate deliberately supports only equal-signedness operands.
        # Unusual/invalid widths and mixed-signed cells retain the raw S=1
        # requirement, but contribute no inferred operand constraints.
        a_signed = parameter(cell, 'A_SIGNED')
        b_signed = parameter(cell, 'B_SIGNED')
        if not a or not b or a_signed != b_signed:
            return result, impossible, rules
        width = max(len(a), len(b))
        signed = a_signed
        a = a + [a[-1] if signed else '0'] * (width - len(a))
        b = b + [b[-1] if signed else '0'] * (width - len(b))
        if all(bit in ('0', '1') for bit in a):
            a, b = b, a
        if all(bit in ('0', '1') for bit in b):
            for bit, value in zip(a, b):
                require(bit, int(value))
            rules.append({'cell': name, 'rule': 'eq_constant_true_requires_matching_operand_bits', 'signed_extension': bool(signed)})
    return result, impossible, rules


def inspect(job):
    path = job / 'conversion/normalized.json'
    design = json.loads(path.read_text())
    assert len(design['modules']) == 1, 'Only flattened single-module models are supported'
    module = next(iter(design['modules'].values()))
    drivers = {}
    for name, cell in module['cells'].items():
        for port, bits in cell['connections'].items():
            if cell['port_directions'].get(port) == 'output':
                for index, bit in enumerate(bits):
                    if isinstance(bit, int):
                        assert bit not in drivers, f'Multiple drivers at {bit}'
                        drivers[bit] = (name, cell, index)
    muxes = []
    for name, cell in module['cells'].items():
        if cell['type'] != '$pmux':
            continue
        selectors = cell['connections']['S']
        requirements = [constraints(module, bit, drivers) for bit in selectors]
        pairs = []
        for i, j in itertools.combinations(range(len(selectors)), 2):
            ai, impossible_i, _ = requirements[i]
            aj, impossible_j, _ = requirements[j]
            contradictory = sorted(bit for bit in ai.keys() & aj.keys() if ai[bit] != aj[bit])
            passed = bool(impossible_i or impossible_j or contradictory)
            pairs.append({'selectors': [i, j], 'contradictory_bits': contradictory,
                          'constant_contradiction': impossible_i + impossible_j, 'passed': passed})
        muxes.append({'name': name, 'S': selectors,
                      'select_constraints': [{'bit': bit, 'requires': req, 'impossible': imp, 'rules': rules}
                                             for bit, (req, imp, rules) in zip(selectors, requirements)],
                      'pairs': pairs, 'passed': all(pair['passed'] for pair in pairs)})
    return {'job': job.name, 'normalized_json_sha256': sha(path),
            'model_sv_sha256': sha(job/'formalmc/model.sv'), 'pmuxes': muxes,
            'passed': all(mux['passed'] for mux in muxes)}


def main():
    package = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('output/cmdbuf_rd_formal/portable_20261012/cmdbuf_rd_dual_backend')
    output = Path(sys.argv[2]) if len(sys.argv) > 2 else Path('artifacts/cmdbuf_rd_portable_20261012/audit_pmux_result.json')
    jobs = [inspect(job) for job in sorted((package/'jobs').iterdir()) if job.is_dir()]
    pmuxes = [mux for job in jobs for mux in job['pmuxes']]
    result = {'scope': 'Two-state structural select mutual-exclusion certificate; no solver, temporal assumptions or reachability assumptions used. Does not establish four-state simulation equivalence.',
              'manifest_sha256': sha(package/'manifest.json'), 'jobs': jobs, 'job_count': len(jobs),
              'pmux_count': len(pmuxes), 'pair_count': sum(len(mux['pairs']) for mux in pmuxes),
              'passed': all(job['passed'] for job in jobs)}
    output.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='jobs'}))
    for job in jobs:
        failed = [mux['name'] for mux in job['pmuxes'] if not mux['passed']]
        if failed:
            print(json.dumps({'job': job['job'], 'unproven': failed}))
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
