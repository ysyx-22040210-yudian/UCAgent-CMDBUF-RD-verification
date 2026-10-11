# cmdbuf_rd 开发与验证交付

实际开发与验证主机：`192.168.31.116`。工程：`/root/cmdbuf_rd`。日期：2026-10-10。

三个 SystemVerilog 模块已完成：顶层连接、CMDBUF 命令控制、OTB 数据与固定延迟返回。实现了当前已对齐的 9 项、窗口 5、三周期前向流水、5A/6B/10B、四拍 MEM 返回、下一拍才可返回 R、单 XAU 保序、ready 内 RR、错误优先级与来源容量保留。

## 实际结果

| 项目 | 结果 |
| --- | --- |
| Verilator 静态检查 | PASS，启用 --Wall，无警告 |
| 公共验证环境结构检查 | PASS |
| 独立模型基础回归 | 19/19 PASS |
| 补充定向回归 | 4/4 PASS |
| 合计功能周期 / 检查次数 | 6,733 / 104,987 |
| 完整接收→发射→捕获→返回 | 3,178 条，四阶段计数一致 |
| Icarus 编译与展开 | PASS；有工具本身的 always_* 敏感列表扩展提示，未运行 Icarus 功能仿真 |
| 最终 RTL 注错 | 12/12 检出；漏检 0，构建失败 0，运行错误 0，注入错误 0 |

注错最终批次为 `campaign_03`，使用固定源码及验证环境快照，RTL 前后 SHA256 一致。旧的两个批次中断记录保留在 VM，它们不纳入上述最终统计。注错同时统计独立参考模型和内部 RTL 断言的检测，具体类型见下表；编译失败和环境异常不计为检出。

## 本次运行的注错

| 编号 | 目的 | 结果 | 检测途径 |
| --- | --- | --- | --- |
| M01 | 错误扩大最老五条窗口，允许第六条绕过阻塞窗口 | killed | scoreboard |
| M02 | 将双 grant 同时命中错误放宽为任一 grant 命中 | killed | scoreboard |
| M03 | 关闭 6B 成功当拍窗口前馈 | killed | scoreboard |
| M04 | 仅发 req 即启动 OTB 返回 token，失败请求也被计入 | killed | rtl_assertion, scoreboard |
| M05 | 固定四拍捕获错误多使用提前一拍的 tap，导致早采样或重复捕获 | killed | rtl_assertion, scoreboard |
| M06 | 放宽共享额度，破坏每来源一项容量保底 | killed | scoreboard |
| M07 | 响应候选忽略当拍 rready | killed | scoreboard |
| M08 | 仅在完成项中找来源队头，跳过同来源更老的未完成命令 | killed | scoreboard |
| M09 | 错误地让奇偶异常覆盖地址越界异常 | killed | scoreboard |
| M10 | 违反 5A，在当前请求失败时丢弃同拍预选的下一命令 | killed | scoreboard |
| M11 | 关闭 10B 准入的退休前馈，满表时多停一拍 | killed | scoreboard |
| M12 | 反转命令选择时的奇偶 Bank 状态索引 | killed | scoreboard |

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
