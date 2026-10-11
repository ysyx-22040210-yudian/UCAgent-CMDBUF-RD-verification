# cmdbuf_rd：SBY / FormalMC 可迁移验证包

此包把当前 `cmdbuf_rd` 的验证输入、检查点映射和证明依赖放在同一目录，使用相对路径运行。新设备不需要原虚拟机、原平台数据库或历史会话。RTL 的接口及功能没有为迁移而修改。

## 在有 FormalMC 的 Linux 设备上运行

要求：Python 3.9 或更新版本、可启动且许可证有效的 FormalMC。沿用当前 UCAgent 的 FormalMC 命令接口；不锁定未经核实的小版本。不需要在 FormalMC 设备安装 SBY、Yosys、Python 第三方库或 UCAgent 服务。

```sh
tar -xzf cmdbuf_rd_dual_backend.tar.gz
cd cmdbuf_rd_dual_backend
python3 run.py --backend formalmc --tool /your/install/bin/FormalMC
```

工具已在 PATH 时，可以省略 `--tool`。许可证和厂商启动环境继续由目标设备配置；包不携带许可证或登录凭据。运行器会自动先做能力自检，再执行完整证明依赖图。结果进入新建的 `results/` 子目录。

可先单独检查环境及工具能力：

```sh
python3 run.py --backend formalmc --tool /your/install/bin/FormalMC --preflight
python3 run.py --backend formalmc --tool /your/install/bin/FormalMC --self-test
```

`--preflight` 只检查文件与工具启动；`--self-test` 检查初始值、符号输入、可达覆盖和故意失败的性质。两者都不表示 DUT 已通过。完整运行自动执行同一自检，无需手动先做。

## 保留 SBY 入口

```sh
python3 run.py --backend sby --tool /your/oss-cad-suite/bin/sby --tool-dir /your/oss-cad-suite/bin --timeout 1200 --sby-timeout 900
```

SBY 后端使用原来的 RTL / 监视器输入和证明任务，设备需提供 SBY、Yosys、SMTBMC 及配置所需的 Yices / Z3。此包不会安装或覆盖设备上的 EDA 工具，也不会改写旧项目和已完成的 UCAgent 会话。

`python3 run.py --list` 查看任务。`--job JOB_ID` 自动加入真实证明供应者及相关检查点所需任务；部分运行不会标成完整套件通过。`--timeout 3600` 设置每项任务的外部等待上限；`--sby-timeout 3000` 设置 SBY 自身预算，只调整本次新建副本并记录变更，不改源码、证明深度或性质。

## 检查点、模型与结果

- 总计 177 个检查点：107 个安全性质、65 个业务覆盖、5 个环境假设。5 个假设不计为证明通过。辅助性质和额外 guard witnesses 随任务一起保留。
- `manifest.json` 是任务依赖、检查点到性质的映射及输入哈希清单。供应者未通过时，依赖它的任务不能作为已证明结果使用。
- `spec_catalog.md` / `spec_catalog.json` 保留需求拆分。`provenance/` 保留迁移输入来源与转换记录。
- FormalMC 使用随包提供的规范化模型。模型在开发机上由与 SBY 相同的前端语义展开，显式保留初始状态、历史寄存器、约束、符号变量及性质，避免目标设备依赖 Yosys 私有语法。原始可读 RTL 和监视器仍随包提供。
- 这是当前已验证设计的快照包。顶层 `rtl/` 用于阅读及注错回放；形式任务读取 `jobs/` 中各自锁定的原始输入或转换模型。仅修改顶层 `rtl/` 不会更新形式任务。设计迭代必须重新生成任务输入和模型，并完成新的验证。
- 每次运行创建新的结果目录，记录工具探测、命令、返回码、日志、逐性质结果和逐检查点结果。超时、缺失结果、未识别状态、编译/许可证错误均不能算通过。旧 SBY PASS 不会被用作新 FormalMC PASS。
- 独立运行器的结果不冒充 UCAgent 的签名阶段验收。原 14 阶段验收是历史 SBY 证据；在新设备执行本包会产生新的独立求解记录。

## 49 个注错场景的回放

包内保留 FI001～FI049 的注错定义、选定变异 RTL、已归档的外部输入和独立参考模型。目标机装有 Verilator 5.x、C++ 编译器与 make 时可运行：

```sh
python3 replay.py
python3 replay.py --case FI001 --case FI035 --case FI049
```

每条输入会重新驱动原版与变异版 RTL，要求原版无语义差异、变异版实际出现差异。该入口复用历史 SBY 反例的外部输入，属于新的仿真回放；它不宣称重新生成了 FormalMC 反例，也不替代完整形式证明。

## 验证边界

本包采用已对齐的初始复位协议，不覆盖尚未定义的运行中 MEM 复位协调。永久 Bank 阻塞、上游缺少公平性等情况不被擅自改成无条件活性保证。严格五条待发窗口及其他已对齐规则继续保留。

交付时实际执行过的测试及结果见 `validation/validation_summary.json`。当前开发设备未安装真实 FormalMC；FormalMC 的完整实机编译、求解和版本兼容性以目标设备的新运行结果为准。启动自检发现不支持的命令或结果格式时会保留日志并停止，不能把此情况解释成 RTL 已通过。

迁移验证包括：新入口的原始 SBY 全套回归、标准 SV 模型的 SBY 交叉验证、Verilator 语法检查和运行器测试。模型中并行选择条件的二态结构互斥检查另存于 `validation/audit_pmux_v2.tar.gz`；此检查不是 FormalMC 实测，也不是四态等价证明。超时、早期转换错误及后续修复后的实际运行记录分别保留。

本包的完整性可由外部 `.sha256` 校验；目录内 `release_hashes.json` 覆盖交付文件，形式验证输入另由 `manifest.json` 校验。修改性质或 RTL 后，需要重新生成输入清单和转换模型，再重新验证；不要只改哈希并沿用旧结果。
