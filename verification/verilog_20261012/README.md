# Verilog-2001 转换与实际重新验证

本次将芯片 RTL 转换为 IEEE 1364-2001 Verilog。当前集成文件为 `rtl/cmdbuf_rd.v`、`rtl/cmdbuf_rd_cmd.v`、`rtl/cmdbuf_rd_otb.v`，详细接口见 [RTL 说明](../../rtl/README.md)。开发和验证在已授权虚拟机 `192.168.31.116` 完成，工作目录为 `/root/cmdbuf_rd/verilog_20261012`。

`rd_mem_status` 的实际端口为 `[15:0]`，保留原 `[1:0][7:0]` 的位序：低 8 位偶 Bank、高 8 位奇 Bank。其余功能、接口位宽、时序、五条窗口和容量保底规则保持一致。

## 当前实际结果

| 检查 | 结果 |
|---|---|
| Icarus 严格 Verilog-2001 编译 | 仿真诊断启用和 `SYNTHESIS` 两种模式通过，使用 `-g2001` |
| Verilator 严格 Verilog lint | 通过，`--Wall --language 1364-2001`，0 告警 |
| 新旧实现顺序等价性 | 3162 个等价检查项全部证明，0 未证明 |
| 既有独立参考模型回归 | 基础 19/19、补充 4/4 通过 |
| 纯 Verilog DUT 与测试台的 Icarus 功能回放 | FI001、FI035、FI049 三组原版输入全部通过 |
| 当前 `.v` DUT 的完整 SBY 运行 | 22/22 任务通过，107 项安全无界证明、65 项覆盖、5 项环境假设单列 |
| 重建 FormalMC 模型的 SBY 交叉验证 | 22/22 模型通过，实际模型哈希与当前输入逐项核对 |
| 导出模型选择条件审计 | 22 任务、271 个 pmux、8492 对选择条件满足二态互斥证书 |
| 当前 Verilog 原版与变异版的历史输入回放 | FI001～FI049 全部检出，原版无语义差异，故障版产生真实差异 |
| 既有精确片段注错运行器回归 | M01～M12 全部检出，基线和验证输入前后哈希一致 |

[机器可读汇总](validation_summary.json)记录了输入哈希、范围与方法。原始 SBY 结果见 [sby_result.json](sby_result.json)，模型交叉结果见 [normalized_result.json](normalized_result.json)，49 类回放见 [fault_replay_result.json](fault_replay_result.json)。

本次等价检查使用 Yosys `equiv_simple`、`equiv_induct -seq 5` 和 `equiv_status -assert`。它证明时钟可观测的二态合成语义，包含 `async2sync` 前端归一化；不声称四态全等价或物理时序签核。Icarus 回放另行实际执行，不能替代上述范围说明。

## 验证输入与观测器

形式任务中的 DUT 文件已同步为 `.v`。原先内嵌的形式观测器放入 `inputs/formal_hooks/*.svh`，通过 `FORMAL` 条件 include 接入；正式芯片集成使用顶层 `rtl/` 三份文件。

观测器和验证模型保留 SystemVerilog 属性语法。22 个 FormalMC 模型从转换后的当前任务输入重新生成。177 个 CK 的 ID、需求、性质种类和证明供应关系保留；自动生成的性质名称重新对应到当前源位置。对应关系见 [转换记录](conversion.json)和包内 `provenance/verilog_property_correspondence.json`。

历史 UCAgent 的 14 阶段验收、原始签名和先前失败尝试保留原时间与输入。本次是新的编译、仿真和求解记录，不把旧 PASS 写成新结果。

虚拟机默认 `/root/cmdbuf_rd/rtl` 已切换到当前三份 `.v`；原文件另行保留。GUI 的同名 `cmdbuf_rd` 项目已关联到新封存包，SBY / FormalMC 配置保持原值，原阶段投影逐项核对未变。新服务由 `cmdbuf-rd-ucagent.service` 管理，支持 `systemctl start cmdbuf-rd-ucagent` 恢复。详见 [部署记录](deployment_receipt.json)。GUI 实际执行的 [环境检查记录](gui_preflight_receipt.json)对应当前输入哈希，它不替代上述已完成的完整求解。

## 已处理的执行环境问题

首次 49 类回放调用了 OSS-CAD 内的 Verilator 5.051 与系统旧 GCC，编译器拒绝相关参数，运行器记录为构建失败。这一轮没有计为检出。使用已验证的 GCC 11 / Verilator 5.024 环境重新执行后，49/49 通过；首次记录与修正后的记录均保留在原始证据归档中。

当前设备仍没有真实 FormalMC。交叉验证和选择条件审计不能替代商业工具的实际执行；目标设备使用包内入口先做能力自检，再运行其完整套件。

## 证据与复现

- [execution_evidence.tar.gz](execution_evidence.tar.gz)：原始日志、XML、状态、运行输入、见证和回放波形，包含已处理的首次编译失败记录。
- [evidence_inventory.json](evidence_inventory.json)：归档内每个载荷的字节数与 SHA256。
- [equivalence.ys](equivalence.ys)、[equivalence.log](equivalence.log)：新旧实现等价流程与真实工具输出。
- [legacy_mutation_result.json](legacy_mutation_result.json)：12 类精确片段注错运行器的新回归结果。
- [pmux_audit.json](pmux_audit.json)：当前导出模型的互斥检查证书。

在有对应工具的设备上重新运行当前包：

```sh
python3 formal/cmdbuf_rd_dual_backend/run.py --backend sby --tool /your/oss-cad-suite/bin/sby --tool-dir /your/oss-cad-suite/bin --timeout 1200 --sby-timeout 900
python3 formal/cmdbuf_rd_dual_backend/replay.py
```

本目录的开发取证脚本记录了实际虚拟机路径；跨设备入口使用验证包的 `run.py` / `replay.py`。复现顺序等价需要 Git 提交 `3c21c39` 中的旧三份 `.sv` 作为 `baseline/`，以及当前三份 `.v` 作为 `rtl/`。
