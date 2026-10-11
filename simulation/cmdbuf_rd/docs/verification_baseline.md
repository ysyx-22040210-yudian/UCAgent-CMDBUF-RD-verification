# cmdbuf_rd 仿真验证基线报告

日期：2026-10-10。执行目录为 Linux VM 的 `/root/cmdbuf_rd`；本报告由实际 case JSON 汇总。RTL 的 Bank half 索引等价改写后已重新构建并重跑。

## 结果

Verilator 5.024、C++17、`--Wall --assert --trace`：基础 19/19 PASS，补充 4/4 PASS；各 case 的必达覆盖计数均满足要求。未关闭 lint 警告或 RTL 断言。

| 集合 | case | 功能周期 | 比较/检查 | 接收 | 成功发射 | MEM 捕获 | R 退休 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline | 19 | 6433 | 101329 | 3126 | 3126 | 3126 | 3126 |
| extended | 4 | 300 | 3658 | 52 | 52 | 52 | 52 |
| combined | 23 | 6733 | 104987 | 3178 | 3178 | 3178 | 3178 |

功能周期包含正常刺激、排空和末尾空闲检查，不包含复位拉低期间的时钟。每次检查是参考模型比较或明确断言意图的一次判定，不等价于 formal 属性覆盖数。

## 可复现命令

基础回归：

```sh
make -f /root/env_base/env/Makefile PROJECT_CONFIG=/root/env_base/projects/cmdbuf_rd.mk run-all
```

补充回归使用独立 adapter、build 和结果目录，不改变基础 harness：

```sh
make -f /root/env_base/env/Makefile \
  PROJECT_CONFIG=/root/env_base/projects/cmdbuf_rd.mk \
  HARNESS_FILES=/root/env_base/adapters/cmdbuf_rd/cmdbuf_rd_harness_extended.cpp \
  CASE_DIR=/root/env_base/cases/cmdbuf_rd/extended \
  BUILD_DIR=/root/cmdbuf_rd/build/verilator_extended \
  RESULT_DIR=/root/cmdbuf_rd/results/extended run-all
```

## 用例明细

| Case | 结果 | 周期 | 检查 | 接收/退休 |
| --- | --- | ---: | ---: | ---: |
| 01_pipeline | PASS | 51 | 793 | 24/24 |
| 02_same_xau_ooo | PASS | 43 | 514 | 6/6 |
| 03_forward_6b | PASS | 43 | 513 | 6/6 |
| 04_grants | PASS | 103 | 1333 | 24/24 |
| 05_failure_5a | PASS | 43 | 537 | 8/8 |
| 06_window_block | PASS | 48 | 563 | 6/6 |
| 07_single_pulse | PASS | 48 | 575 | 7/7 |
| 08_rr | PASS | 53 | 648 | 9/9 |
| 09_errors | PASS | 38 | 443 | 4/4 |
| 10_capacity_reuse | PASS | 53 | 669 | 11/11 |
| 11_capacity_700 | PASS | 53 | 648 | 9/9 |
| 12_capacity_440 | PASS | 53 | 647 | 9/9 |
| 13_tokens | PASS | 63 | 737 | 8/8 |
| 14_single_source_throughput | PASS | 170 | 3478 | 160/160 |
| 15_reset_clean | PASS | 96 | 1256 | 24/24 |
| 16_random_seed_1 | PASS | 1814 | 29188 | 935/935 |
| 17_random_seed_17 | PASS | 1812 | 29234 | 942/942 |
| 18_random_seed_91 | PASS | 1816 | 29172 | 931/931 |
| 19_rr_ready_masks | PASS | 33 | 381 | 3/3 |
| 20_all_bank_halves | PASS | 163 | 1839 | 16/16 |
| 21_repeated_ids | PASS | 58 | 697 | 9/9 |
| 22_status_after_selection | PASS | 28 | 331 | 3/3 |
| 23_nonmonotonic_ids | PASS | 51 | 791 | 24/24 |

## 独立参考模型与检查范围

- 参考模型按实际 AR 接收顺序维护命令列表，不照搬 RTL 年龄矩阵或物理 entry 分配。
- 每周期独立计算原队头、RR、当拍退休后的逐源 ready、成功前馈后的最老五项窗口、下一拍请求。
- 每次成功发射建立 +4 拍返回日历；MEM 数据仅在对应周期有效，无效拍驱动不同噪声数据。R 候选只读取此前已捕获的完成状态。
- 比较 req、完整 12-bit 下游地址、pending_cnt、三位 arready/rvalid 及共享 R 的全部 128-bit 数据与元数据。
- 失败用例打印 CHECK_FAILED、返回非零并保留 VCD；配置错误为 CONFIG_ERROR/退出 2，不能作为成功检出 RTL 注错。

## 定向覆盖审查

- 复位：所有用例检查初始低有效异步复位输出；15_reset_clean 额外排空后重新复位并再发送一批请求，两个批次共 24 条。未将运行中仍有未完成 MEM 返回的复位冲刷行为擅自定义为已支持。
- 所有 16 个 Bank half：20_all_bank_halves 每次只放开目标 half，其余 15 个 half 均忙，8 Bank × 2 half 全部成功发射并比对返回。
- ID：21_repeated_ids 使用同一 arid=0x5a，同时存在同源重复 ID，通过不同地址、port_id 和数据确认归属；23_nonmonotonic_ids 显式命中非单调 ID。
- 选择后 status 翻转：22_status_after_selection 中两条请求在判断拍空闲、请求拍变忙，但双 grant 有效；仍正确发射，不二次撤销。
- 单源吞吐：14_single_source_throughput 连续接收 160 条，159 次相邻拍连续接收；每条均满足最短三拍前向路径，153 次七项占用下退休/接收并行和四事件并发。
- 容量：明确覆盖 (7,0,0) ready=110、(4,4,0) ready=100、满表来源唯一项退休 ready=010、共享项退休 ready=111，以及两次满表同拍复用。
- 错误：arresp=00/11 与 pc_err=0/1 四组合均返回正确优先级；零数据且 pc_err=0 的单拍返回单独检查。

以下为基础回归累计事件计数；每个定向 case 同时有独立最小门槛，不能以其他 case 的覆盖替代：

| 覆盖事件 | 次数 |
| --- | ---: |
| three_cycle_path | 449 |
| failed_keep_next | 2117 |
| retry_success | 1280 |
| sixth_success_forward | 2 |
| outside_window_blocked | 14 |
| ar_only_grant | 918 |
| rw_only_grant | 703 |
| wrong_bank_grant | 408 |
| capture_without_ready | 404 |
| zero_data_no_error | 149 |
| capture_after_bubble | 1355 |
| same_xau_ooo_issue | 446 |
| same_xau_head_block | 1062 |
| rr_all_three | 45 |
| rr_skip | 1892 |
| capacity700_ready110 | 22 |
| capacity440_ready100 | 18 |
| rejected_unready_src | 150 |
| unique_retire_ready010 | 2 |
| shared_retire_ready111 | 6 |
| full_reuse | 1442 |
| single_source_turnover | 181 |
| four_events | 745 |
| error_combo_00 | 2476 |
| error_combo_01 | 370 |
| error_combo_10 | 244 |
| error_combo_11 | 36 |
| drained_reset | 1 |

补充回归的明确覆盖：

| 覆盖事件 | 次数 |
| --- | ---: |
| duplicate_live_id | 6 |
| issued_half_0_bank_0 | 7 |
| issued_half_0_bank_1 | 1 |
| issued_half_0_bank_2 | 6 |
| issued_half_0_bank_3 | 1 |
| issued_half_0_bank_4 | 5 |
| issued_half_0_bank_5 | 1 |
| issued_half_0_bank_6 | 5 |
| issued_half_0_bank_7 | 1 |
| issued_half_1_bank_0 | 1 |
| issued_half_1_bank_1 | 6 |
| issued_half_1_bank_2 | 1 |
| issued_half_1_bank_3 | 5 |
| issued_half_1_bank_4 | 1 |
| issued_half_1_bank_5 | 5 |
| issued_half_1_bank_6 | 1 |
| issued_half_1_bank_7 | 5 |
| nonmonotonic_live_id | 21 |
| request_busy_but_granted | 2 |

注：上表 half 总数为四个补充 case 合计；20_all_bank_halves 自身对每个 half 都设置且通过至少一次的门槛。

## 产物

- `/root/env_base/adapters/cmdbuf_rd/cmdbuf_rd_harness.cpp`：基础参考模型。
- `/root/env_base/adapters/cmdbuf_rd/cmdbuf_rd_harness_extended.cpp`：补充定向刺激与覆盖版本，原模型算法保持一致。
- `/root/env_base/cases/cmdbuf_rd/*.case`：基础 19 用例。
- `/root/env_base/cases/cmdbuf_rd/extended/*.case`：补充 4 用例。
- `/root/cmdbuf_rd/results/baseline/` 与 `/root/cmdbuf_rd/results/extended/`：逐 case JSON、日志、runner summary。
- `/root/cmdbuf_rd/results/baseline/05_failure_5a.vcd`、`10_capacity_reuse.vcd`、`19_rr_ready_masks.vcd`：指定保留波形。
- `/root/cmdbuf_rd/results/extended/22_status_after_selection.vcd`：选择后 Bank 状态翻转波形。
- `/root/cmdbuf_rd/docs/verification_summary.json`：本报告同源的结构化汇总。

这是固定参数配置的动态仿真基线，不是全输入空间形式证明、CDC 证明、综合面积或 STA 频率结论。随机种子固定为 1、17、91；每次请求的最终接收公平性仍依赖上游调度协议。注错运行结果由独立 mutation 报告记录，不混入本报告 PASS 统计。

## 最终输入约束与源码版本

最后一次回归已采用修正后的输入门控：每拍先令 arvalid=0，驱动其他输入并求值；按实际 DUT arready 是否全零决定是否送出 valid，再求值。若异常实现因 valid 改变再次使 ready 全零，也会在采样前撤销 valid。参考模型的 expected_ready 仍独立计算并比较，绝不使用实际 ready 替代正确性判据。因此即使注错把实际 ready 错误压低，输入仍满足 ready=000 时 valid=0 的约束，且 ready 差异会被检出。

修正后重新构建、运行基础 19 例和补充 4 例，均 PASS，上述总数与必达覆盖不变。

主线程另外执行 Icarus 的 -g2012 -DSYNTHESIS 编译/展开检查并通过；它输出 always_* sensitivity 保守扩展提示。该检查不包含 Icarus 行为仿真，也不是综合面积、综合时序或功能正确性的证明。

| Harness | SHA256 |
| --- | --- |
| cmdbuf_rd_harness.cpp | 639bc3d0ebd6dee75e7b3c0060aee39fc50efb75029b8d0dfd7e4528bcbd2e65 |
| cmdbuf_rd_harness_extended.cpp | 9d38710a535afc536162e92fe9d6c1a460ff1a102385ea47ed84e5be397d3149 |

## 每例覆盖数据索引

下列 JSON 各自包含 checks、coverage、status 和 failure，覆盖门槛定义保存在对应 .case。

| Case | 完整检查和覆盖计数 |
| --- | --- |
| 01_pipeline | [JSON](../results/baseline/01_pipeline.json) |
| 02_same_xau_ooo | [JSON](../results/baseline/02_same_xau_ooo.json) |
| 03_forward_6b | [JSON](../results/baseline/03_forward_6b.json) |
| 04_grants | [JSON](../results/baseline/04_grants.json) |
| 05_failure_5a | [JSON](../results/baseline/05_failure_5a.json) |
| 06_window_block | [JSON](../results/baseline/06_window_block.json) |
| 07_single_pulse | [JSON](../results/baseline/07_single_pulse.json) |
| 08_rr | [JSON](../results/baseline/08_rr.json) |
| 09_errors | [JSON](../results/baseline/09_errors.json) |
| 10_capacity_reuse | [JSON](../results/baseline/10_capacity_reuse.json) |
| 11_capacity_700 | [JSON](../results/baseline/11_capacity_700.json) |
| 12_capacity_440 | [JSON](../results/baseline/12_capacity_440.json) |
| 13_tokens | [JSON](../results/baseline/13_tokens.json) |
| 14_single_source_throughput | [JSON](../results/baseline/14_single_source_throughput.json) |
| 15_reset_clean | [JSON](../results/baseline/15_reset_clean.json) |
| 16_random_seed_1 | [JSON](../results/baseline/16_random_seed_1.json) |
| 17_random_seed_17 | [JSON](../results/baseline/17_random_seed_17.json) |
| 18_random_seed_91 | [JSON](../results/baseline/18_random_seed_91.json) |
| 19_rr_ready_masks | [JSON](../results/baseline/19_rr_ready_masks.json) |
| 20_all_bank_halves | [JSON](../results/extended/20_all_bank_halves.json) |
| 21_repeated_ids | [JSON](../results/extended/21_repeated_ids.json) |
| 22_status_after_selection | [JSON](../results/extended/22_status_after_selection.json) |
| 23_nonmonotonic_ids | [JSON](../results/extended/23_nonmonotonic_ids.json) |

源码与 case 的完整校验值保存在 [verification_sources.json](verification_sources.json)。
