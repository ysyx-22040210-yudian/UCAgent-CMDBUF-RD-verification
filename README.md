# UCAgent CMDBUF RD：RTL、形式验证与 Tk GUI

本仓库保存 `cmdbuf_rd` 项目的 RTL、验证环境与历史证据：9 项 CMDBUF/OTB、3 个 XAU、最老 5 条未成功发射命令窗口、三周期前向流水、MEM 成功发射后四拍返回，以及每个 XAU 保序的 RR 响应。

**2026-10-21 规格修正：** 用户已确认逐 Bank 二维 `rd_mem_status`、成功拍对应状态为忙、失败命令同拍重选、`pending_cnt` 同拍加 AR 接收并减成功发射、每源最多七项并保留其他来源首项容量，以及窗口内非队头成功后同拍补入下一项（6B）。RTL 允许使用 SystemVerilog。最新定义见 [修订说明 PDF](documents/15_cmdbuf_rd_protocol_corrections_20261021.pdf) / [Word](documents/15_cmdbuf_rd_protocol_corrections_20261021.docx) 和 [规格记录](docs/timing/protocol_corrections_20261021.json)。新版 RTL/SVA 已实现这些修正，当前入口为 [rtl/files.f](rtl/files.f)，只编译三份 `.sv`。实现与本轮 VM 结果见 [修复验证说明 PDF](documents/16_cmdbuf_rd_rtl_revision_20261021.pdf) / [Word](documents/16_cmdbuf_rd_rtl_revision_20261021.docx) 及 [本轮结果](verification/protocol_20261021/summary.json)。下文此前验证结果仅适用于各自的原始规格和封存输入。

项目说明统一提供 **PDF 阅读版和 Word 编辑版**。完整资料见 [完整说明手册 PDF](documents/CMDBUF_RD_完整说明手册.pdf) / [完整说明手册 Word](documents/CMDBUF_RD_完整说明手册.docx)，各主题分册见下表。原 Markdown、HTML 和历史证据作为维护及追溯来源保留。

**SVA 对齐基线：** 用户已确认去掉 `started` / `active` 和复位序列约束，所有原生属性统一在 `!rst_n` 时禁用；RR 从 XAU0 开始、仅实际响应后推进；无效请求地址和无效 R 负载不检查。第 17 份说明记录该轮的 11 个 assume、16 个 DUT 断言和 99 个模型自检实例，以及 10 步 BMC、三项接口性质无界证明、31 个 cover 和 27 个仿真用例。见 [SVA 对齐 PDF](documents/17_cmdbuf_rd_sva_alignment_20261021.pdf) / [Word](documents/17_cmdbuf_rd_sva_alignment_20261021.docx) 与 [该轮结果](verification/sva_alignment_20261021/summary.json)。第 16 份说明及此前运行保留原始范围，其中复位和空闲清零属性不再是当前检查规则。

**当前单 XAU 保序检查：** 新增每源独立 AR 接收 FIFO，仅实际 R 握手弹出队头；通过 `A_XAU_R_*` 逐项检查地址、ID、port_id、数据及错误状态。命令 3 即使先发射、先返回 MEM，也须等命令 1、2 完成 R 后再响应。当前共有 40 个 DUT 断言、105 个模型自检，原 11 个 assume 不变；145 个实例通过 SBY ABC 的 10 步 BMC，46 个 cover 命中，33 个原生 SVA 仿真用例通过，7 类保序及字段注错全部检出。首次 Yices 超时也已保留。详见 [单 XAU 保序 PDF](documents/18_cmdbuf_rd_xau_response_order_20261021.pdf) / [Word](documents/18_cmdbuf_rd_xau_response_order_20261021.docx)、[测试点与注错映射](docs/testpoints/xau_order_20261021.json) 和 [本轮证据](verification/xau_order_20261021/summary.json)。

**SVA 阅读入口已优化：** [主文件](formal/protocol_20261021/cmdbuf_rd_port_sva.sv) 直接展示完整的 `assume/assert/cover property`，有条件的同拍义务使用 `|->`，每条附中文意图和依赖标注；参考状态分别放在事务模型和单 XAU FIFO 文件中。61 个标签与 202 个展开实例保持不变。改写后的回归及采样表达式等价检查通过，见 [阅读说明 PDF](documents/19_cmdbuf_rd_sva_readability_20261021.pdf) / [Word](documents/19_cmdbuf_rd_sva_readability_20261021.docx) 和 [最新证据](verification/sva_readability_20261021/summary.json)。VM 的 SBY 前端不支持 `|->`，运行脚本只对执行副本作同拍布尔转换，保留原生输入与逐条转换记录；原生 Verilator 仿真直接编译主文件。

三个 SVA 源文件已进一步补充详细中文注释，覆盖各端口含义、61 个属性的前提与分析提示，以及窗口推进、四拍捕获、FIFO 同拍出入和覆盖监视器。当前行号与逐条说明见 [属性索引](verification/sva_comments_20261021/property_audit.json)，[注释修改核验](verification/sva_comments_20261021/comment_audit.json) 记录注释前后的代码 token 一致性；原验证证据保留原始输入。

| 说明内容 | PDF | Word |
|---|---|---|
| 项目使用、RTL 集成与服务部署 | [阅读](documents/01_project_usage.pdf) | [编辑](documents/01_project_usage.docx) |
| 详细 RTL 设计方案与架构 | [阅读](documents/02_rtl_design.pdf) | [编辑](documents/02_rtl_design.docx) |
| 历史 13 个时序场景，冲突部分以最新修订为准 | [阅读](documents/03_timing_scenarios.pdf) | [编辑](documents/03_timing_scenarios.docx) |
| 49 组注错与容量保护 | [阅读](documents/04_fault_catalog.pdf) | [编辑](documents/04_fault_catalog.docx) |
| Tk GUI 操作图示与放大视图 | [阅读](documents/05_tk_gui_guide.pdf) | [编辑](documents/05_tk_gui_guide.docx) |
| 完整 Formal 流程、177 CK 与验证结果 | [阅读](documents/06_formal_verification.pdf) | [编辑](documents/06_formal_verification.docx) |
| 仿真基线与历史阶段记录 | [阅读](documents/07_simulation_history.pdf) | [编辑](documents/07_simulation_history.docx) |
| FormalMC 2024 零初值适配与新验证记录 | [阅读](documents/08_formalmc2024_zero_init.pdf) | [编辑](documents/08_formalmc2024_zero_init.docx) |
| 按端口、功能特性、业务场景分解的 200 项测试计划 | [阅读](documents/09_cmdbuf_rd_testpoints.pdf) | [编辑](documents/09_cmdbuf_rd_testpoints.docx) |
| 200 项测试点的 assert assume cover 分类与证明边界 | [阅读](documents/10_cmdbuf_rd_formal_testpoint_mapping.pdf) | [编辑](documents/10_cmdbuf_rd_formal_testpoint_mapping.docx) |
| 200 项测试点的 SVA 实现与接入说明 | [阅读](documents/11_cmdbuf_rd_sva_guide.pdf) | [编辑](documents/11_cmdbuf_rd_sva_guide.docx) |
| 仅顶层端口的 SVA 实现、VM 覆盖结果与 200 项逐点索引 | [阅读](documents/12_cmdbuf_rd_port_only_verification.pdf) | [编辑](documents/12_cmdbuf_rd_port_only_verification.docx) |
| SVA 无需参考模型部分的逐条标注与依赖说明 | [阅读](documents/13_cmdbuf_rd_sva_model_dependency.pdf) | [编辑](documents/13_cmdbuf_rd_sva_model_dependency.docx) |
| 2026-10-20 对既有 RTL 行为与待定边界的核对 | [阅读](documents/14_cmdbuf_rd_protocol_alignment_20261020.pdf) | [编辑](documents/14_cmdbuf_rd_protocol_alignment_20261020.docx) |
| 2026-10-21 用户确认的协议修正与 SV 实现许可 | [阅读](documents/15_cmdbuf_rd_protocol_corrections_20261021.pdf) | [编辑](documents/15_cmdbuf_rd_protocol_corrections_20261021.docx) |
| 2026-10-21 新版 RTL 修复、集成入口与本轮 VM 验证 | [阅读](documents/16_cmdbuf_rd_rtl_revision_20261021.pdf) | [编辑](documents/16_cmdbuf_rd_rtl_revision_20261021.docx) |
| 2026-10-21 最新 assume assert 对齐、RR 规则与有效负载检查 | [阅读](documents/17_cmdbuf_rd_sva_alignment_20261021.pdf) | [编辑](documents/17_cmdbuf_rd_sva_alignment_20261021.docx) |
| 单 XAU 保序独立断言、命令 3 先完成场景与注错结果 | [阅读](documents/18_cmdbuf_rd_xau_response_order_20261021.pdf) | [编辑](documents/18_cmdbuf_rd_xau_response_order_20261021.docx) |
| SVA 阅读顺序、显式蕴含、参考模型分离及改写核验 | [阅读](documents/19_cmdbuf_rd_sva_readability_20261021.pdf) | [编辑](documents/19_cmdbuf_rd_sva_readability_20261021.docx) |

新增测试计划包含端口 39 项、功能特性 126 项、业务场景 35 项，每项给出激励、预期结果、建议验证方式和依据类型，并在测试组层级关联已有 CK/FI。[机器可读清单](docs/testpoints/cmdbuf_rd_testpoints.json) 可用于后续用例落实；这 200 项尚未全部验证闭环，本次新增 SVA 的实现与执行范围如下。

形式属性分类逐项给出 assert 检查、cover 见证目标及 assume 边界，区分基础环境、条件吞吐/排空、非法输入监测和空闲复位扩展。[分类数据](docs/testpoints/formal_classification.json) 可供后续绑定具体属性；该分类文档记录分析阶段；后续 SVA 实现与新运行记录单独保存。

新增 [SVA 源码](formal/testpoints_sva/cmdbuf_rd_sva.sv) 为 200 个测试点提供断言、5 项基础环境假设及 [属性映射](formal/testpoints_sva/property_map.json)，含 1415 个映射 cover bin。原生 SVA/bind 的 8 个环境配置编译通过；虚拟机上最终代码通过 9 个采样步的 SBY BMC，选定 13 个 cover 目标命中，6 类代表故障全部被断言检出。条件吞吐任务完成 20 步 BMC；整体无界证明和排空任务仍有超时，尚未完成全部新性质闭环，也未在真实 FormalMC 2024 上执行。各任务使用的源码快照、结果和反例见 [本次执行记录](verification/sva_20261018/validation_results.json)，不沿用历史结论。

后续新增的 [顶层端口验证器](formal/port_only/cmdbuf_rd_port_sva.sv) 只连接原始 24 个端口，无内部层级访问、无额外观察端口，RTL 字节不变。在 VM 上，**200 个测试点映射的 1415 个功能 cover bin 全部取得 SBY 见证**；其中 1299 个使用各属性环境的常规搜索，115 个使用公开输入引导，1 个使用固定输入长流。全部 BASE 断言通过 10 步 BMC，五项协议性质完成新无界证明，单源和三源轮流吞吐各通过 20 步 BMC；8 类代表故障全部检出。最终完整检查器回放 388 组保存输入、386500 个周期，全部通过；9 种原生 SVA 配置编译通过。详见 [逐点覆盖结果](verification/port_only_20261018/coverage_final.json) 和 [验证汇总](verification/port_only_20261018/validation_summary.json)。

此处的全部命中指**已映射的功能场景**：28 个测试点包含仅凭端口无法直接证明的物理结构要求，报告逐项保留缺口，另保留 6 项原始范围限制。整体无界证明、一般排空界和真实 FormalMC 2024 执行仍未完成。输入、证明范围、未通过的尝试、波形和故障反例随 [VM 证据包](verification/port_only_20261018/vm_evidence.tar.gz) 保存；运行 `python3 formal/port_only/verify_evidence.py` 可校验全部封存成员。此次结果独立于历史 UCAgent 完整流程，不替换其验收范围。

顶层端口 SVA 已逐条标出无需事务参考模型的部分：`NO_REF_MODEL_PORTS` 表示只需端口及通用采样门控，`NO_REF_MODEL_HISTORY` 表示还需端口历史或计数器，`NO_REF_MODEL_ENV` 表示还需独立环境阶段控制。BASE 有 6 项无需事务模型的断言；PERF 和 NEGATIVE 配置另有 3 项。1415 个映射 cover bin 中有 703 个无需事务模型，但这不等于其所属测试点的全部检查均无需模型。其余属性明确保留 `REF_MODEL` 或 `MODEL_SELF_CHECK` 标签。完整分类与依赖链见 [逐属性清单](formal/port_only/model_dependency_map.json)，逐点映射见 [属性映射](formal/port_only/property_map.json)。本次仅新增注释和元数据，表达式、辅助逻辑及源码行号未变；9 种原生 SVA 配置编译通过，VM 源码逻辑核对通过，未新增求解器证明。检查记录位于 [标注审计](verification/port_only_annotations_20261018/annotation_audit.json)。

**查看本次标注版请打开 [带行首标签的主文件](formal/port_only_annotated/cmdbuf_rd_port_sva.sv) 与 [配置文件](formal/port_only_annotated/cmdbuf_rd_port_profiles.svh)。** `formal/port_only_annotated/` 是完整可构建源码副本，无需模型的标签同时放在属性行开头和行末。旧主文件路径曾反复回退为未标注内容，具体写入来源未定位；新副本使用独立编辑器路径，并在生成前检查标签完整性。表达式与原行号不变，9 种原生配置编译通过，记录见 [本次检查](verification/port_only_visible_20261018/lint/source_validation.json)。

当前芯片 RTL 使用 **SystemVerilog**：[cmdbuf_rd.sv](rtl/cmdbuf_rd.sv)、[cmdbuf_rd_cmd.sv](rtl/cmdbuf_rd_cmd.sv)、[cmdbuf_rd_otb.sv](rtl/cmdbuf_rd_otb.sv)。使用 [rtl/files.f](rtl/files.f) 显式选择当前版本；逐 Bank 状态口为 `input bit [1:0] rd_mem_status [7:0]`。同目录 `.v` 是历史实现，禁止把 `.v` 和 `.sv` 同时加入一个编译任务。旧 GUI 验证包、历史 SVA 和证据仍对应旧规格；本次修订的独立验证入口为 [formal/protocol_20261021/run.py](formal/protocol_20261021/run.py)。

操作界面为 **Python Tkinter/ttk 原生 GUI**。在 UCAgent 已关联的 SBY 任务中点击“切换到 FormalMC”，即可进入完整项目的 FormalMC 操作页；两种后端独立保存配置和结果。HTML 文件是报告与文档。

## 目录

| 目录 | 内容 |
|---|---|
| `rtl/` | 当前三份 `.sv`、显式文件清单及保留的历史 `.v` |
| `formal/protocol_20261021/` | 新规格端口 SVA、同拍 busy 约束、SBY/read_slang 运行入口与原生 SVA 文件清单 |
| `verification/protocol_20261021/` | 新版 RTL 本轮 VM 仿真、注错、SBY 范围及独立证据包 |
| `verification/sva_alignment_20261021/` | 最新复位禁用与有效负载规则的原生 SVA 验证、属性清单、初态记录及证据 |
| `verification/xau_order_20261021/` | 独立单源接收 FIFO 保序检查、六个定向序列、十五个新增 cover 与七类注错证据 |
| `verification/sva_readability_20261021/` | 可读版 SVA 的逐属性索引、语义比较、SBY 适配记录、原生仿真与注错回归 |
| `formal/cmdbuf_rd_dual_backend/` | 可迁移的 SBY / FormalMC 验证包、22 个任务、177 个检查点与历史验证证据 |
| `formal/testpoints_sva/` | 本次 200 项测试点的 SVA、场景监测器、bind、生成器和属性映射 |
| `formal/port_only/` | 只连 24 个顶层端口的独立参考模型、SVA、覆盖映射、SBY 生成器及证据校验器 |
| `formal/port_only_annotated/` | 本次可查看、可构建的完整标注版；NO_REF_MODEL 标签位于属性行开头与行末 |
| `formal/releases/` | 独立 FormalMC 2024 零初值候选 ZIP 与 SHA256 校验文件 |
| `ucagent-tool/` | 已更新的 UCAgent 桌面与服务完整源码，保留上游 Apache-2.0 许可证 |
| `gui/` | Tk 桌面 zipapp 和当前项目启动入口 |
| `docs/design/` | 详细设计方案与架构图 |
| `docs/timing/` | 历史时序图、原 5A / 6B / 10B 决策与 2026-10-21 最新修正规格 |
| `docs/fault_catalog/` | 注错清单及容量保底场景 |
| `docs/testpoints/` | 200 项测试点、既有 CK/FI 语义关联及文档完整性检查记录 |
| `docs/gui/` | 15 张真实 Tk 截图和操作说明的维护来源 |
| `documents/` | 全部项目说明的 PDF / Word 完整手册与主题分册 |
| `simulation/` | 早期 RTL 仿真工程、独立参考模型与历史结果 |
| `verification/closure/` | 完整 UCAgent 流程报告与原始证据分卷 |
| `verification/sva_20261018/` | 本次 SVA 编译、SBY 有界/覆盖/超时结果及 6 类故障反例 |
| `verification/port_only_20261018/` | 端口验证的 1415 个功能覆盖见证、有限证明范围、8 类注错、388 组回放及逐点报告 |
| `verification/port_only_annotations_20261018/` | 无参考模型标签的依赖核对、逻辑不变检查、9 种原生编译及 VM 同步记录 |
| `verification/port_only_visible_20261018/` | 行首标签版本的源码副本审计、9 种编译和 VM 核对 |
| `verification/gui/` | Tk GUI 回归日志、实际界面截图与验收记录 |
| `verification/verilog_20261012/` | 本次 Verilog 转换、新旧等价性与重新验证的证据 |
| `verification/formalmc_2024_20261014/` | 零初值候选的 22 个模型 SBY 结果汇总、转换来源、输入保留检查和运行器测试日志 |
| `provenance/` | GUI 变更及交付来源说明 |

## 当前修订版入口

在仓库根目录编译 `rtl/files.f`。VM 回归与 SBY（要求 Yosys 的 `read_slang` 前端）入口为：

```sh
make -f simulation/env_base/env/Makefile PROJECT_CONFIG=simulation/env_base/projects/cmdbuf_rd_sv.mk lint run-all
python3 formal/protocol_20261021/run.py --output build/formal_new --tools /your/oss-cad-suite/bin
```

原生 SVA 接入清单为 [native.f](formal/protocol_20261021/native.f)。目标 FormalMC 2024 和加密 RTL 等价检查尚未在本轮执行。详细结果及明确的证明范围见本轮 PDF / Word 说明。

最新 SVA 回归使用 `PROJECT_CONFIG=simulation/env_base/projects/cmdbuf_rd_sva.mk`，在检查器输入端对无效负载及复位期间信号加入干扰。VM 上已验证的原生 SVA 仿真工具为 Verilator 5.051；5.024 的二维端口采样存在 C++ 代码生成失败，记录在证据中。SBY 初态通过真实复位逻辑的模拟结果建立，之后不限制复位序列；这属于工具设置，不是新增 SVA assume。当前结果收集使用 [collect_readability_results.py](formal/protocol_20261021/collect_readability_results.py)。`collect_xau_order_results.py`、`collect_alignment_results.py`、`collect_results.py` 分别对应第 18、17、16 份说明的封存输入与运行。

人阅读和原生 SVA 工具使用 `cmdbuf_rd_port_sva.sv` 及其两个 `.svh` 引用文件，不需要属性宏。SBY 的每个运行目录同时保存 `native_checker.sv`、实际执行的布尔适配副本和 `sby_lowering.json`；适配器只接受本拍蕴含，遇到延迟或多拍性质会报错。cover 保持真实事件条件，不用蕴含获取空真命中。

## 历史双后端包入口

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
