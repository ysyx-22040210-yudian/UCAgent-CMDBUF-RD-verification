# cmdbuf_rd 测试敏感性检查与结果

本检查把单个错误植入真实 RTL 副本，再运行与无注错基线完全相同的独立 scoreboard。它是所选关键行为的测试敏感性检查，不代表历史注错目录全部用例已实施。

## 隔离与可复现

- 基线源码位于 `/root/cmdbuf_rd/rtl`，运行器只读。每次注错前后核对全部 SystemVerilog 文件的 SHA-256。
- 每个变异复制至 `/root/cmdbuf_rd/mutations/Mxx/rtl`，只替换一个且仅出现一次的精确片段。片段缺失、重复或未改变文本均拒绝运行。
- `RTL_ROOT` 指向该变异的项目根目录；`BUILD_DIR`、`RESULT_DIR` 使用变异 ID 和本次运行编号隔离。
- 每批冻结 harness、所选 case 和项目配置，构建显式传入快照的 `HARNESS_FILES`、`CASE_DIR`、`PROJECT_CONFIG`。逐项校验快照及通用环境文件哈希，避免构建期间跨版本。
- 先独立构建无注错副本并跑完选定用例；基线失败立即停止，不计算变异结果。
- 所有命令均通过 `/root/env_base/env/Makefile` 及 `projects/cmdbuf_rd.mk`，复用相同 case 文件和检查器。
- 编译与仿真分别保存日志；基线及每个变异保存结果 JSON，完整汇总位于 `mutations/campaigns/<run-id>/summary.json`。

## 结果口径

| 结果 | 含义 |
| --- | --- |
| `killed` | 构建成功；scoreboard 明确报告失败，或日志明确出现 RTL `Assertion failed in`，运行返回失败且其余用例没有基础设施错误。 |
| `survived` | 构建成功；全部所选用例明确通过，当前测试未发现该变异。 |
| `compile_error` | 编译失败或编译超时，不计为检测成功。 |
| `runtime_error` | 仿真超时、崩溃、缺少结果文件、配置错误或不一致的退出状态，不计为检测成功。 |
| `mutation_error` | 精确替换条件不满足或无法创建隔离副本，未有效运行变异。 |

只有 `killed` 才表示验证确实发现设计错误。`detection_kind=scoreboard` 与 `rtl_assertion` 分开记录；RTL 断言直接终止时可能来不及生成 harness JSON，此时保留具体断言日志作为证据，普通崩溃不算检测成功。检查器失败报告及相应波形保留在变异结果目录。固定接口/容量约束下的长期合法等待不能仅因等待而算作错误。

## 计划覆盖

已根据真实 RTL 绑定以下 12 个唯一片段，均保留精确变更文本和前后 SHA-256：

| ID | 故意植入的错误 |
| --- | --- |
| M01 | 五项窗口扩大为九项，允许越窗。 |
| M02 | 双 grant 的 AND 改为 OR。 |
| M03 | 关闭 6B 成功当拍窗口前馈。 |
| M04 | OTB 按 `req` 而非成功握手产生返回 token。 |
| M05 | 捕获许可额外使用提前一拍的 tap，造成早采样或重复采样。 |
| M06 | 共享额度从六项放宽到九项，破坏每来源保底。 |
| M07 | R 候选忽略当前 `rready`。 |
| M08 | 仅在已完成项中找来源队头，跳过未完成的老命令。 |
| M09 | 令奇偶异常覆盖地址越界异常。 |
| M10 | 当前请求失败时丢弃同拍预选结果，违反 5A。 |
| M11 | 准入不扣当拍退休占用，关闭 10B。 |
| M12 | 选择时反转奇偶 Bank 状态索引。 |

它们覆盖独立敏感点，不等价于目录全部 49 组注错。M05 是提前 tap 污染，不是完整 MEM→R 同拍旁路实现的变异。

## 使用

```sh
python3 /root/cmdbuf_rd/scripts/run_mutations.py --list
python3 /root/cmdbuf_rd/scripts/run_mutations.py
python3 /root/cmdbuf_rd/scripts/run_mutations.py --only M01,M03
python3 /root/cmdbuf_rd/scripts/run_mutations.py --only M01 --case 06_window_block.case
```

`--manifest` 可提供 JSON 列表（或含 `mutations` 列表的对象）。每项包含 `id`、`file`、`before`、`after`，可选 `purpose`；文件必须是 `rtl/` 下的相对路径，ID 为 `M01` 形式。仅有构建失败与未发现错误等非理想结果时也原样留存，不隐藏失败实验。

## 最终结果：campaign_03

最终完整批次为 `campaign_03`，无注错快照先通过 **19/19** 用例；随后 **12/12 变异被检测**，`survived=0`、`compile_error=0`、`runtime_error=0`、`mutation_error=0`。每个变异均运行同一组 19 个用例。全部 12 项都有独立 scoreboard 的失败证据，M04、M05 还在其他用例中触发 RTL 断言。

完整证据见 [最终汇总 JSON](../mutations/campaigns/campaign_03/summary.json)。各变异的精确替换、原文与变更后 SHA-256、编译日志、用例 JSON、失败波形及结果分类均在 `mutations/Mxx/results/campaign_03/` 及汇总中保留。

下表列出按用例执行顺序出现的首个 **scoreboard** 失败。`cycle` 是 harness 从 0 开始的测试周期编号，不直接等同于设计图中的 C1 编号；数值均为十六进制。

| 变异 | 首个 scoreboard 报错用例 | cycle | 首个不一致：实际 / 预期 | 检测来源 |
| --- | --- | ---: | --- | --- |
| M01 | `03_forward_6b.case` | 7 | `req=0x4 / 0x0` | scoreboard |
| M02 | `04_grants.case` | 3 | `pending_cnt=0x2 / 0x3` | scoreboard |
| M03 | `03_forward_6b.case` | 10 | `req=0x0 / 0x4` | scoreboard |
| M04 | `05_failure_5a.case` | 7 | `rvalid=0x1 / 0x0` | scoreboard、RTL assertion |
| M05 | `01_pipeline.case` | 6 | `rvalid=0x1 / 0x0` | scoreboard、RTL assertion |
| M06 | `07_single_pulse.case` | 7 | `arready=0x7 / 0x6` | scoreboard |
| M07 | `07_single_pulse.case` | 7 | `rvalid=0x1 / 0x0` | scoreboard |
| M08 | `02_same_xau_ooo.case` | 8 | `rvalid=0x1 / 0x0` | scoreboard |
| M09 | `09_errors.case` | 10 | `rresp=0x1 / 0x3` | scoreboard |
| M10 | `04_grants.case` | 3 | `req=0x0 / 0x2` | scoreboard |
| M11 | `01_pipeline.case` | 7 | `arready=0x6 / 0x7` | scoreboard |
| M12 | `16_random_seed_1.case` | 5 | `req=0x4 / 0x0` | scoreboard |

M04 按完整执行顺序的首个失败实际来自更早执行的 `04_grants.case`，RTL 报告 `capture ownership mismatch`。该断言中止没有 C++ 周期 JSON，不推测其周期；原始日志保留在 [M04 断言日志](../mutations/M04/results/campaign_03/04_grants.log)。上表额外提供首个 scoreboard 用例的明确周期与实际/预期值。M04 有 3 个 scoreboard 检出用例、3 个断言检出用例；M05 分别为 11 个、8 个。

## 固定版本与工具

本批使用 VM 现有工具：`/usr/local/bin/verilator`，Verilator **5.024**；通过 `/opt/rh/devtoolset-11/enable` 选择 GCC **11.2.1**；运行器 Python **3.6.8**。构建通过现有 `/root/env_base/env/Makefile`，启用 `--Wall --assert`，未关闭警告以让变异构建通过。

最终源码 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| `rtl/cmdbuf_rd.sv` | `06e57c016cc74fff564c4d7c2e6e5fc8c9df317f9b172a6f3c7a6df7d74db7e8` |
| `rtl/cmdbuf_rd_cmd.sv` | `4de7a4022db5d69f3090691d59b3fe42ca673e77020a478ac7584d0378496339` |
| `rtl/cmdbuf_rd_otb.sv` | `bbca166e8facd72ec22aeb7f1b666df1da9e08fb2efe76f94fa49a25c0ed0068` |
| 冻结的 `cmdbuf_rd_harness.cpp` | `639bc3d0ebd6dee75e7b3c0060aee39fc50efb75029b8d0dfd7e4528bcbd2e65` |
| 冻结的 `cmdbuf_rd.mk` | `89224072b813eaef06d5e81a0b090f2336c54125cf64c5ea777d0f0e830cc4c5` |

快照位于 `mutations/campaigns/campaign_03/verification/`。十九个 case 的逐文件哈希以及通用 Makefile、run_cases.py 的哈希均写入最终汇总；结束时 `baseline_source_unchanged=true`、`verification_inputs_unchanged=true`。

最终驱动先令 `arvalid=0` 稳定其他当拍输入，再依据 DUT 实际 `arready` 门控发送意图；采样前保证实际 `arready=000` 时 `arvalid=0`。期望 ready 仍由独立模型计算并比较，因此错误地拉低 ready 会被检查为接收机会损失，不靠违反输入约束检出。

## 中途批次与检查边界

- `campaign_01` 保留为 `interrupted`：RTL 为兼容 Icarus 做了等价 packed 索引改写，批次停止。该批 M04 原始连接替换造成未用信号编译失败，已单列 `compile_error`；后续修正变异表达式以保留信号使用。M05 当时的日志识别仅认识 `%Error`，未识别 `%Fatal` 断言前缀，保守记为 `runtime_error`；后续修正精确识别，未把普通 abort 归为检测成功。
- `campaign_02` 保留为 `interrupted`：独立审查发现驱动器应按实际 DUT ready 门控 valid，故停止并修正 harness；该批部分结果不作为最终结论。
- 最终结论只采用重新完整运行且源码、验证输入固定的 `campaign_03`。前两批日志和状态保留，未混入最终计数。
- 本次独立静态核对覆盖窗口与当前请求排除、5A/6B、四拍返回标记、MEM 捕获后下一拍 R、来源保序、容量计数、10B 同槽复用及错误优先级；没有提出尚未修复的 RTL 功能问题。上述输入驱动约束问题已由验证适配器修复并重跑。
- 12 项检出证明这组测试对这些具体错误敏感；不等同于全设计证明、全部 49 组历史注错完成或所有边界行为已定义。扩展 harness 的额外 4 个用例未用于本批变异结论。
