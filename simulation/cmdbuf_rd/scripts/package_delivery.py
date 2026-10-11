#!/usr/bin/env python3
"""Validate completed reports and package the VM's source/evidence without build binaries."""
import datetime
import hashlib
import json
from pathlib import Path
import tarfile

ROOT = Path('/root/cmdbuf_rd')
ENV = Path('/root/env_base')

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    reports = []
    for path in (ROOT/'mutations/campaigns').glob('*/summary.json'):
        summary = read_json(path)
        if summary.get('status') == 'complete':
            reports.append((path, summary))
    if not reports:
        raise RuntimeError('No completed mutation campaign; packaging is premature')
    campaign_path, mutation = sorted(reports, key=lambda item: item[0].parent.name)[-1]
    if mutation.get('baseline', {}).get('status') != 'passed':
        raise RuntimeError('Mutation baseline did not pass')
    if not mutation.get('verification_inputs_unchanged'):
        raise RuntimeError('Verification inputs were not confirmed unchanged')
    for rel, expected in mutation['baseline_hashes'].items():
        if digest(ROOT/'rtl'/rel) != expected:
            raise RuntimeError('RTL changed after verification: '+rel)
    for name in ('baseline', 'extended'):
        regression = read_json(ROOT/'results'/name/'regression.json')
        if regression['total'] != regression['passed']:
            raise RuntimeError(name+' has nonpassing cases')
        for path in (ROOT/'results'/name).glob('*.json'):
            if path.name != 'regression.json' and read_json(path).get('status') != 'pass':
                raise RuntimeError('Nonpassing result '+str(path))

    stats = read_json(ROOT/'docs/verification_summary.json')
    counts = mutation['counts']
    tools = {
        'host': '192.168.31.116',
        'verilator': '5.024', 'gcc': '11.2.1 (devtoolset-11)',
        'iverilog': '12.0 development',
        'verilator_lint': {'exit_code':0,'warnings':0,'flags':'--lint-only --Wall --assert'},
        'env_layout_validation': {'exit_code':0},
        'iverilog_elaboration': {'exit_code':0,'flags':'-g2012 -DSYNTHESIS -s cmdbuf_rd',
            'note':'Icarus emits sensitivity-list expansion notices for always_* constant selects; no Icarus functional simulation was run.'},
        'formal_proof': 'not_run', 'synthesis_sta': 'not_run'
    }
    (ROOT/'results/tool_checks.json').write_text(json.dumps(tools,indent=2)+'\n',encoding='utf-8')
    report = '''# cmdbuf_rd 开发与验证交付

实际开发与验证主机：`192.168.31.116`。工程：`/root/cmdbuf_rd`。日期：2026-10-10。

三个 SystemVerilog 模块已完成：顶层连接、CMDBUF 命令控制、OTB 数据与固定延迟返回。实现了当前已对齐的 9 项、窗口 5、三周期前向流水、5A/6B/10B、四拍 MEM 返回、下一拍才可返回 R、单 XAU 保序、ready 内 RR、错误优先级与来源容量保留。

## 实际结果

| 项目 | 结果 |
| --- | --- |
| Verilator 静态检查 | PASS，启用 --Wall，无警告 |
| 公共验证环境结构检查 | PASS |
| 独立模型基础回归 | {base_cases}/{base_cases} PASS |
| 补充定向回归 | {ext_cases}/{ext_cases} PASS |
| 合计功能周期 / 检查次数 | {cycles:,} / {checks:,} |
| 完整接收→发射→捕获→返回 | {accepted:,} 条，四阶段计数一致 |
| Icarus 编译与展开 | PASS；有工具本身的 always_* 敏感列表扩展提示，未运行 Icarus 功能仿真 |
| 最终 RTL 注错 | {killed}/{total} 检出；漏检 {survived}，构建失败 {compile_error}，运行错误 {runtime_error}，注入错误 {mutation_error} |

注错最终批次为 `{campaign}`，使用固定源码及验证环境快照，RTL 前后 SHA256 一致。旧的两个批次中断记录保留在 VM，它们不纳入上述最终统计。注错同时统计独立参考模型和内部 RTL 断言的检测，具体类型见下表；编译失败和环境异常不计为检出。

## 本次运行的注错

| 编号 | 目的 | 结果 | 检测途径 |
| --- | --- | --- | --- |
'''.format(base_cases=stats['baseline']['cases'],ext_cases=stats['extended']['cases'],
           campaign=mutation['run_id'],total=len(mutation['mutations']),
           cycles=stats['combined']['cycles'],checks=stats['combined']['checks'],
           accepted=stats['combined']['accepted'],**counts)
    for rec in mutation['mutations']:
        report += '| {id} | {purpose} | {status} | {detection} |\n'.format(
            id=rec['id'],purpose=rec.get('purpose','').replace('|','/'),status=rec['status'],
            detection=', '.join(rec.get('detection_kinds',[])))
    report += '''
本次实际运行的是上述 12 个具体 RTL 变异；此前 49 组注错清单仍作为完整规格覆盖来源，并未将清单条目数当作实际注错运行数量。

## 覆盖与实现选择

定向验证包括窗口内全阻塞而第六条空闲、失败后保持下一条、成功当拍推进窗口、双 grant、固定四拍与单拍 MEM 数据、无同拍 MEM→R 旁路、同源乱序发射但有序返回、ready 内 RR、满表同拍复用、每来源保底容量、四种错误组合、全部 16 个 Bank half、重复与非单调 ID、选中后状态翻转、初始复位及排空后复位。

参考模型按接收序号及队列建立预期，不依赖 RTL 年龄矩阵。驱动器按实际 arready 门控 arvalid，保证在注错情况下也遵守 arready=000 时 arvalid=0 的输入约束；ready 的正确值仍由独立模型检查。

容量实现采用每 XAU 1 项逻辑保底 + 6 项共享，物理 entry 不分区。尚未由系统冻结的细节采用 README 中明确记录的实现选择：异步低有效复位、RR 初始从 0 开始、错误数据透传、请求级不随状态变化撤销等。

## 文件和复现

- `rtl/`：3 个 RTL 文件。
- `README.md`：接口行为、实现选择和基础运行命令。
- `docs/verification_baseline.md`：每例结果、覆盖计数、基础与扩展回归命令。
- `docs/verification_summary.json`：仿真结构化汇总。
- `docs/mutation_plan.md` 与 `scripts/run_mutations.py`：注错定义和可复现 runner。
- `results/baseline/`、`results/extended/`：逐例日志、JSON 与选定波形。
- `source_manifest.json`：实际交付源码、环境和 case 的 SHA256。
- 随包的 `env_base/`：只包含本项目 adapter/cases/config 和所需公共 runner，未包含其他项目。

在原虚拟机运行：

```sh
cd /root/cmdbuf_rd
make lint validate
make test
```

扩展回归和注错重跑命令见上述报告，注错重跑请使用新的 run-id。压缩包以 `/root` 为目录基准保存 `cmdbuf_rd/` 和 `env_base/`，可在独立位置解包检查；原 VM 已有完整可运行工程。

## 验证边界

本次交付为固定配置 RTL 与动态功能验证，不是完整形式证明；未运行综合、STA 或 CDC 验证，不能据此承诺频率和面积。运行中复位涉及未完成 MEM 事务的协同协议仍需系统定义；上游调度公平性未定，不声明无条件最终接收保证。
'''
    (ROOT/'docs/verification_report.md').write_text(report,encoding='utf-8')
    (ROOT/'docs/mutation_summary.json').write_text(json.dumps(mutation,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    source_files = []
    for folder in ('rtl','scripts'):
        source_files.extend(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    source_files.extend([ROOT/'Makefile',ROOT/'README.md',ENV/'projects/cmdbuf_rd.mk'])
    for folder in ('adapters/cmdbuf_rd','cases/cmdbuf_rd','env','scripts'):
        source_files.extend(p for p in (ENV/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    source_files = sorted(set(source_files))
    manifest = {'created_utc':datetime.datetime.utcnow().isoformat()+'Z',
                'mutation_campaign':mutation['run_id'],
                'files':{str(p.relative_to('/root')):digest(p) for p in source_files}}
    (ROOT/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    selected = set(source_files + [ROOT/'source_manifest.json',ROOT/'.gitignore'])
    for folder in ('docs','results'):
        selected.update(p for p in (ROOT/folder).rglob('*') if p.is_file() and '__pycache__' not in p.parts)
    selected.update(p for p in campaign_path.parent.rglob('*') if p.is_file())
    for rec in [mutation['baseline']] + mutation['mutations']:
        selected.update((Path(rec['rtl_root'])/'rtl').glob('*.sv'))
        selected.update(p for p in Path(rec['result_dir']).rglob('*') if p.is_file() and not p.name.startswith('core'))
    delivery = ROOT/'delivery'
    delivery.mkdir(exist_ok=True)
    archive = delivery/'cmdbuf_rd_20261010.tar.gz'
    with tarfile.open(str(archive),'w:gz') as tar:
        for path in sorted(selected):
            tar.add(str(path),arcname=str(path.relative_to('/root')),recursive=False)
    archive_hash = digest(archive)
    (delivery/(archive.name+'.sha256')).write_text(archive_hash+'  '+archive.name+'\n',encoding='ascii')
    print(json.dumps({'archive':str(archive),'bytes':archive.stat().st_size,'files':len(selected),'sha256':archive_hash,'cases':stats['combined']['cases'],'mutations':counts}))

if __name__ == '__main__':
    main()
