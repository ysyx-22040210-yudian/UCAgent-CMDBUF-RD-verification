"""Compile a plain Verilog-2001 bench and replay representative archived inputs with Icarus."""

import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path('/root/cmdbuf_rd/verilog_20261012')
PACKAGE = ROOT / 'package'
sys.path.insert(0, str(PACKAGE))
sys.dont_write_bytecode = True
import replay_engine as engine


def main():
    """Validate actual four-state simulation observations against the existing independent oracle."""
    output = ROOT / 'validation/iverilog_replay'
    output.mkdir(exist_ok=True)
    text = engine.testbench()
    ports = ['clk'] + list(engine.WIDTHS) + ['arready', 'req', 'arb_addr', 'pending_cnt', 'rvalid', 'rdata', 'rid', 'r_port_id', 'raddr', 'rresp']
    text = text.replace('cmdbuf_rd dut(.*);', 'cmdbuf_rd dut(' + ','.join('.' + name + '(' + name + ')' for name in ports) + ');')
    text = text.replace('string input_path, wave_path;', 'reg [8191:0] input_path, wave_path;')
    text = re.sub(r'\$fatal\(2,"([^"]+)"\);', lambda match: 'begin $display("' + match[1] + '"); $stop; end', text)
    source = output / 'replay_tb.v'
    source.write_text(text)
    binary = output / 'replay.vvp'
    command = ['iverilog', '-g2001', '-s', 'replay_tb', '-o', str(binary), str(source)] + [str(ROOT / 'rtl' / name) for name in engine.FILES]
    compile_result = subprocess.run(command, capture_output=True, text=True)
    (output / 'compile.log').write_text(compile_result.stdout + compile_result.stderr)
    if compile_result.returncode:
        raise RuntimeError('Strict Verilog Icarus bench compilation failed.')
    report = {'language': 'Verilog-2001 for both DUT and simulation bench', 'command': command, 'cases': [], 'rtl_sha256': {name: engine.sha(ROOT / 'rtl' / name) for name in engine.FILES}}
    observations = list(engine.observations())
    for case in ('FI001', 'FI035', 'FI049'):
        inputs = PACKAGE / 'mutations' / case
        data = json.loads((inputs / 'external_inputs.json').read_text())
        result = subprocess.run(['vvp', '-N', str(binary), '+INPUT=' + str(inputs / 'external_inputs.hex'), '+WAVE=' + str(output / (case + '.vcd'))], capture_output=True, text=True)
        log = output / (case + '.log')
        log.write_text(result.stdout + result.stderr)
        rows = []
        for line in result.stdout.splitlines():
            if line.startswith('SAMPLE,'):
                fields = line.split(',')
                if len(fields) != len(observations) + 2 or int(fields[1]) != len(rows):
                    raise RuntimeError('Icarus observation sequence mismatch.')
                rows.append(dict(zip(observations, [int(value, 16) for value in fields[2:]])))
        oracle = engine.oracle(data['states'], rows)
        passed = result.returncode == 0 and len(rows) == len(data['states']) and oracle['input_contract_valid'] and oracle['checks'] > 0 and oracle['semantic_mismatch_count'] == 0
        record = {'id': case, 'passed': bool(passed), 'returncode': result.returncode, 'oracle': oracle, 'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest()}
        report['cases'].append(record)
        print('ICARUS ' + case + ': ' + ('PASSED' if passed else 'FAILED'), flush=True)
    report['all_passed'] = all(row['passed'] for row in report['cases'])
    (output / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['all_passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
