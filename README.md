# UCAgent CMDBUF RD：RTL、形式验证与 Tk GUI

本仓库保存当前已对齐的 `cmdbuf_rd` 项目：9 项 CMDBUF/OTB、3 个 XAU、最老 5 条未成功发射命令窗口、三周期前向流水、MEM 成功发射后四拍返回，以及每个 XAU 保序的 RR 响应。

项目说明统一提供 **PDF 阅读版和 Word 编辑版**。完整资料见 [完整说明手册 PDF](documents/CMDBUF_RD_完整说明手册.pdf) / [完整说明手册 Word](documents/CMDBUF_RD_完整说明手册.docx)，各主题分册见下表。原 Markdown、HTML 和历史证据作为维护及追溯来源保留。

| 说明内容 | PDF | Word |
|---|---|---|
| 项目使用、RTL 集成与服务部署 | [阅读](documents/01_project_usage.pdf) | [编辑](documents/01_project_usage.docx) |
| 详细 RTL 设计方案与架构 | [阅读](documents/02_rtl_design.pdf) | [编辑](documents/02_rtl_design.docx) |
| 13 个已对齐时序场景 | [阅读](documents/03_timing_scenarios.pdf) | [编辑](documents/03_timing_scenarios.docx) |
| 49 组注错与容量保护 | [阅读](documents/04_fault_catalog.pdf) | [编辑](documents/04_fault_catalog.docx) |
| Tk GUI 操作图示与放大视图 | [阅读](documents/05_tk_gui_guide.pdf) | [编辑](documents/05_tk_gui_guide.docx) |
| 完整 Formal 流程、177 CK 与验证结果 | [阅读](documents/06_formal_verification.pdf) | [编辑](documents/06_formal_verification.docx) |
| 仿真基线与历史阶段记录 | [阅读](documents/07_simulation_history.pdf) | [编辑](documents/07_simulation_history.docx) |
| FormalMC 2024 零初值适配与新验证记录 | [阅读](documents/08_formalmc2024_zero_init.pdf) | [编辑](documents/08_formalmc2024_zero_init.docx) |

当前芯片 RTL 使用 **Verilog-2001**，入口为 [cmdbuf_rd.v](rtl/cmdbuf_rd.v)、[cmdbuf_rd_cmd.v](rtl/cmdbuf_rd_cmd.v) 和 [cmdbuf_rd_otb.v](rtl/cmdbuf_rd_otb.v)。集成与 Bank 状态位序见 [RTL 使用说明 PDF](documents/01_project_usage.pdf)。形式验证属性与观测器继续使用验证工具支持的 SystemVerilog。

操作界面为 **Python Tkinter/ttk 原生 GUI**。在 UCAgent 已关联的 SBY 任务中点击“切换到 FormalMC”，即可进入完整项目的 FormalMC 操作页；两种后端独立保存配置和结果。HTML 文件是报告与文档。

## 目录

| 目录 | 内容 |
|---|---|
| `rtl/` | 当前三份 RTL，与封存验证包的 RTL 字节相同 |
| `formal/cmdbuf_rd_dual_backend/` | 可迁移的 SBY / FormalMC 验证包、22 个任务、177 个检查点与历史验证证据 |
| `formal/releases/` | 独立 FormalMC 2024 零初值候选 ZIP 与 SHA256 校验文件 |
| `ucagent-tool/` | 已更新的 UCAgent 桌面与服务完整源码，保留上游 Apache-2.0 许可证 |
| `gui/` | Tk 桌面 zipapp 和当前项目启动入口 |
| `docs/design/` | 详细设计方案与架构图 |
| `docs/timing/` | 已对齐时序图、5A / 6B / 10B 决策 |
| `docs/fault_catalog/` | 注错清单及容量保底场景 |
| `docs/gui/` | 15 张真实 Tk 截图和操作说明的维护来源 |
| `documents/` | 全部项目说明的 PDF / Word 完整手册与主题分册 |
| `simulation/` | 早期 RTL 仿真工程、独立参考模型与历史结果 |
| `verification/closure/` | 完整 UCAgent 流程报告与原始证据分卷 |
| `verification/gui/` | Tk GUI 回归日志、实际界面截图与验收记录 |
| `verification/verilog_20261012/` | 本次 Verilog 转换、新旧等价性与重新验证的证据 |
| `verification/formalmc_2024_20261014/` | 零初值候选的 22 个模型 SBY 结果汇总、转换来源、输入保留检查和运行器测试日志 |
| `provenance/` | GUI 变更及交付来源说明 |

## 运行 SBY / FormalMC

在有对应工具的 Linux 设备上：

```sh
cd formal/cmdbuf_rd_dual_backend
python3 run.py --list
python3 run.py --backend sby --tool /your/oss-cad-suite/bin/sby --tool-dir /your/oss-cad-suite/bin --timeout 1200 --sby-timeout 900
python3 run.py --backend formalmc --tool /your/install/bin/FormalMC
```

FormalMC 入口沿用当前 UCAgent 支持的命令接口，并先执行能力自检。当前开发设备没有真实 FormalMC，因此未宣称已完成 FormalMC 实机证明。许可证及厂商环境由执行设备提供。

针对目标设备“声明初值 1 不支持、0 支持”的反馈，独立零初值候选包通过状态反相编码保留初态和转移，并适配已识别的 typed Cover 报告。构建与验证入口为 `formal/build_formalmc_2024.py` 和 `formal/validate_formalmc_2024.py`；22 个新模型均取得 SBY 通过记录，容量作业保留首次超时与重试记录。手册核查、适配范围和实际结果见 [补充说明 PDF](documents/08_formalmc2024_zero_init.pdf)。原验证包保持封存，目标 FormalMC 2024 实测仍未完成。

候选包下载：[FormalMC 2024 零初值 ZIP](formal/releases/CMDBUF_RD_FormalMC2024_zero_init_20261014.zip) / [SHA256](formal/releases/CMDBUF_RD_FormalMC2024_zero_init_20261014.zip.sha256)。解压后使用包内 `run.py`；Tk 执行服务登记该解压目录的绝对路径。迁移前请阅读 [PDF](documents/08_formalmc2024_zero_init.pdf) / [Word](documents/08_formalmc2024_zero_init.docx)。[结果汇总](verification/formalmc_2024_20261014/validation_summary.json) 可在仓库查看，原始日志、首次运行与容量重试证据均随 ZIP 提供。

这是已验证版本的快照：形式任务使用 `jobs/` 中锁定的输入和模型。只修改顶层 `rtl/` 不会改变形式验证对象；迭代设计应重新生成任务输入并重新验证。

## 使用 Tk GUI

[详细操作图示 PDF](documents/05_tk_gui_guide.pdf) / [Word](documents/05_tk_gui_guide.docx) 覆盖启动连接、一键切换 SBY / FormalMC、保存配置、运行验证、结果判断、日志排错及阶段工作台，包含真实截图和关键操作区域的放大视图。

```sh
python3 gui/UCAgent-Desktop.pyz --server http://127.0.0.1:8814
```

执行服务需使用仓库内匹配的 UCAgent 源码，并登记 `formal/cmdbuf_rd_dual_backend` 的实际绝对路径。登记与迁移说明见 [项目使用与部署 PDF](documents/01_project_usage.pdf)。新设备可以从“**双后端验证**”入口打开登记项目；原 SBY 任务的一键导航需填入该设备的真实任务 ID。

`gui/Start-UCAgent-CMDBUF.pyw` 是本次原任务入口，默认连接本机 SSH 转发端口 18814。新设备使用上面的通用命令并填写自己的服务地址。仓库没有保存 SSH 密码、API token 或许可证。

![实际 Tk GUI](verification/gui/02_formalmc_ready.png)

## 已完成的实际验证

本次 Verilog 修订已重新完成严格 Verilog 编译、3162 项顺序等价证明、23 项仿真回归、22 项完整 SBY 任务、22 个重建模型交叉验证和 49 类注错回放。当前与历史验证说明见 [Formal 验证 PDF](documents/06_formal_verification.pdf) / [Word](documents/06_formal_verification.docx)；实际输入和日志位于 `verification/verilog_20261012/`。以下原 UCAgent 14 阶段等记录保留其历史验收范围。

- 原 UCAgent 正式流程 14/14 阶段完成；规格拆分为 15 FG → 35 FC → 177 CK。
- 107 个安全检查点获得无界证明，65 个业务覆盖获得见证；5 个环境假设单列。
- 49 个代表注错变异检出并完成原版/故障版同输入回放。
- 可迁移入口原始 SBY 22/22 任务通过；FormalMC 规范化输入由 SBY 完成 22/22 交叉验证。
- Tk 桌面测试 82/82、服务及平台入口回归 39/39；实际 Tk 界面完成原 SBY 页一键切换及 SBY 单任务运行。
- FormalMC 实际环境检查记录工具缺失，没有将其显示为完整验证通过。

来源、范围及历史失败尝试见 [Formal 验证说明](documents/06_formal_verification.pdf) 和 [GUI 验收记录](verification/gui/validation_summary.json)。[仿真历史分册](documents/07_simulation_history.pdf) 只描述当时的仿真阶段，完整形式验证结论以后续正式报告为准。

## 复核上传完整性与原始证据

```sh
python3 tools/verify_publication.py
python3 tools/assemble_evidence.py
tar -xzf verification/closure/cmdbuf_rd_evidence.tar.gz -C verification/closure
python3 verification/closure/evidence/verify_delivery_sha256.py verification/closure/evidence
```

完整原始证据包共 212,829,414 字节，因单文件大小限制分为 5 卷。重组后的 SHA256 必须为 `9cc646b2c13a659256b45d1b30a0cd82444ca6a7d8bcbe16a6cd9e9df4ccda00`。上传不重写原始签名、证明结果或封存输入。

本项目结论适用于已定义的初始复位事务域和输入输出约束；无条件最终完成、运行中 MEM 协同复位及物理时序签核不在已完成验证范围内。第三方工具运行时不随本仓库打包。
