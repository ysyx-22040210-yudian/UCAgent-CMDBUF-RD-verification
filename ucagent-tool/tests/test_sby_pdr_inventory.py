"""ABC PDR aggregate PASS must identify real active compiler assertions."""

import json
import os
from pathlib import Path

import pytest

from ucagent.eda.sby_results import parse_sby_results
from ucagent.eda.adapters.sby import SbyAdapter
from ucagent.eda import JobRunner, ToolchainProfile, verify_manifest


def inventory(tmp_path):
    proof = tmp_path / 'proof'
    (proof / 'model').mkdir(parents=True)
    (proof / 'status').write_text('PASS 0 0.5')
    (proof / 'run.xml').write_text('<testsuites><testsuite><properties><property name="status" value="PASS"/></properties><testcase name="default"/></testsuite></testsuites>')
    data = {'version': '0.0.1', 'modules': [
        {'name': 'Top', 'attributes': {'top': '01'}, 'cell_sorts': [
            {'type': 'Child', 'cells': [{'name': 'u0'}, {'name': 'u1'}]},
            {'type': '$check', 'cells': [{'name': 'top_check', 'attributes': {'src': 'inputs/h.sv:20.1-20.8'}, 'parameters': {'FLAVOR': 'assert'}},
                                        {'name': 'disabled_cover', 'parameters': {'FLAVOR': 'cover'}}]}]},
        {'name': 'Child', 'cell_sorts': [{'type': '$check', 'cells': [
            {'name': 'same_name', 'attributes': {'src': 'inputs/h.sv:10.1-10.8', 'hdlname': 'g A_child'}, 'parameters': {'FLAVOR': 'assert'}}]}]},
    ]}
    (proof / 'model/design.json').write_text(json.dumps(data))
    (proof / 'model/design_aiger.ywa').write_text(json.dumps({'version': 'Yosys Witness Aiger map', 'asserts': [
        ['\\u0', '\\g', '\\A_child'], ['\\u1', '\\g', '\\A_child'], ['\\top_check']]}))
    return proof


def test_pdr_active_compiled_inventory(tmp_path):
    inventory(tmp_path)
    result = parse_sby_results(tmp_path, mode='prove', depth=2, return_code=0, engine='sby/abc/pdr')
    assert result.execution_status == 'completed'
    assert result.verification_status == 'passed'
    assert len(result.properties) == 3
    assert len({prop.name for prop in result.properties}) == 3
    assert all(prop.details['proof_basis'] == 'aggregate_abc_pdr_pass' for prop in result.properties)
    assert all(prop.details['location'].startswith('inputs/h.sv:') for prop in result.properties)


@pytest.mark.parametrize('damage', ['missing_design', 'missing_aiger', 'empty_aiger', 'wrong_identity', 'duplicate', 'wrong_source', 'bad_top', 'recursive', 'junit_failure', 'wrong_engine', 'bmc', 'unknown', 'fail'])
def test_pdr_aggregate_never_invents_proofs(tmp_path, damage):
    proof = inventory(tmp_path)
    engine, mode, code = 'sby/abc/pdr', 'prove', 0
    model = proof / 'model/design.json'
    aig = proof / 'model/design_aiger.ywa'
    if damage == 'missing_design':
        model.unlink()
    elif damage == 'missing_aiger':
        aig.unlink()
    elif damage in {'empty_aiger', 'wrong_identity', 'duplicate'}:
        data = json.loads(aig.read_text())
        data['asserts'] = [] if damage == 'empty_aiger' else [['\\uncompiled']] if damage == 'wrong_identity' else [['\\top_check'], ['\\top_check']]
        aig.write_text(json.dumps(data))
    elif damage in {'wrong_source', 'bad_top', 'recursive'}:
        data = json.loads(model.read_text())
        if damage == 'wrong_source':
            data['modules'][1]['cell_sorts'][0]['cells'][0]['attributes']['src'] = ''
        elif damage == 'bad_top':
            data['modules'][0]['attributes'] = {}
        else:
            data['modules'][1]['cell_sorts'].append({'type': 'Top', 'cells': [{'name': 'cycle'}]})
        model.write_text(json.dumps(data))
    elif damage == 'junit_failure':
        f = proof / 'run.xml'
        f.write_text(f.read_text().replace('<testcase name="default"/>', '<testcase name="default"><failure/></testcase>'))
    elif damage == 'wrong_engine':
        engine = 'sby/smtbmc/z3'
    elif damage == 'bmc':
        mode = 'bmc'
    else:
        status, code = ('UNKNOWN', 4) if damage == 'unknown' else ('FAIL', 2)
        (proof / 'status').write_text(f'{status} {code} 0.5')
        f = proof / 'run.xml'
        f.write_text(f.read_text().replace('PASS', status))
    result = parse_sby_results(tmp_path, mode=mode, depth=2, return_code=code, engine=engine)
    assert result.execution_status == 'error'
    assert result.properties == []


def test_pdr_explicit_unknowns_remain_unconstrained(tmp_path):
    (tmp_path / 'top.sv').write_text("module top; wire x = 1'bx; always @* assert(x || !x); endmodule")
    pdr = SbyAdapter().prepare(workspace=tmp_path, top='top', sources=[Path('top.sv')], engine='abc pdr')
    smt = SbyAdapter().prepare(workspace=tmp_path, top='top', sources=[Path('top.sv')])
    assert 'prep -top top\nsetundef -undriven -anyseq' in pdr.content
    assert 'setundef' not in smt.content


def test_real_pdr_multiple_assertions_and_signed_identity(tmp_path):
    tool_root = os.environ.get('UCAGENT_TEST_SBY_BIN')
    if not tool_root:
        pytest.skip('Set UCAGENT_TEST_SBY_BIN to run real PDR acceptance')
    (tmp_path / 'top.sv').write_text('''module top(input wire clk, arbitrary);
      reg past_valid = 0;
      reg value, inverse;
      always @(posedge clk) begin
        past_valid <= 1;
        value <= arbitrary;
        inverse <= !arbitrary;
        if (past_valid) begin
          A_VALUE: assert(value == $past(arbitrary));
          A_COMPLEMENT: assert(value != inverse);
        end
      end
    endmodule
    ''')
    adapter = SbyAdapter()
    plan = adapter.prepare(workspace=tmp_path, top='top', sources=[Path('top.sv')], engine='abc pdr', timeout_seconds=30)
    (tmp_path / 'run.sby').write_text(plan.content)
    request = adapter.build_formal_request(workspace=tmp_path, output_dir=Path('run'), config_path=Path('run.sby'), plan=plan, mode='prove', depth=40, timeout_seconds=30, run_id='real-pdr-unknowns')
    profile = ToolchainProfile(id='isolated-pdr-real-test', tools={name: str(Path(tool_root) / name) for name in adapter.required_tools}, environment={'PATH': tool_root + os.pathsep + os.environ.get('PATH', '')}, minimum_free_bytes=0)
    key = b'isolated-test-key-not-for-production'
    result = JobRunner(key).run(request, profile)
    assert result.execution_status == 'completed', result.diagnostics
    assert result.verification_status == 'passed', result.diagnostics
    manifest = verify_manifest(result.manifest_path, key, workspace=tmp_path)
    assert {prop['details']['property_id'] for prop in manifest['properties']} == {'A_VALUE', 'A_COMPLEMENT'}
    assert all(prop['details']['proof_basis'] == 'aggregate_abc_pdr_pass' for prop in manifest['properties'])
    assert manifest['metadata']['engine'] == 'sby/abc/pdr'


def test_real_pdr_literal_x_is_not_assumed_zero(tmp_path):
    tool_root = os.environ.get('UCAGENT_TEST_SBY_BIN')
    if not tool_root:
        pytest.skip('Set UCAGENT_TEST_SBY_BIN to run real PDR acceptance')
    (tmp_path / 'top.sv').write_text("module top(input wire clk); wire arbitrary = 1'bx; always @(posedge clk) A_X: assert(arbitrary == 0); endmodule")
    adapter = SbyAdapter()
    plan = adapter.prepare(workspace=tmp_path, top='top', sources=[Path('top.sv')], engine='abc pdr', timeout_seconds=30)
    (tmp_path / 'run.sby').write_text(plan.content)
    request = adapter.build_formal_request(workspace=tmp_path, output_dir=Path('run'), config_path=Path('run.sby'), plan=plan, mode='prove', depth=40, timeout_seconds=30, run_id='real-pdr-x-free')
    profile = ToolchainProfile(id='isolated-pdr-x-test', tools={name: str(Path(tool_root) / name) for name in adapter.required_tools}, environment={'PATH': tool_root + os.pathsep + os.environ.get('PATH', '')}, minimum_free_bytes=0)
    result = JobRunner(b'isolated-test-key-not-for-production').run(request, profile)
    assert result.verification_status != 'passed'
    assert (tmp_path / 'run/proof/status').read_text().startswith('FAIL ')
    assert not any(prop.status == 'proven' for prop in result.properties)
