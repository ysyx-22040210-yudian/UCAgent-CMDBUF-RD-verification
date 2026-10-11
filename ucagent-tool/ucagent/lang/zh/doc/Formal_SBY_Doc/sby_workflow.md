
# SBY：沿用原始形式化操作流程

## 1. 不变的操作

仍通过 CurrentTips 查看任务、文本工具维护 `{OUT}/.formal_records.yaml`、Check 检查、Complete 推进，并在推进前记录 SetCurrentStageJournal。技能可选；没有 `.ucagent/skills` 时同样可完成。RTL 和规格保持只读，生成的 SV、.sby、JSON、Markdown 不直接编辑。

| 阶段 | 事实源 / 操作 | SBY 的实际检查 |
|---|---|---|
| 需求分析与规划 | planning | 范围、策略、交付物、风险 |
| DUT 功能理解 | basic_info | 完整端口、功能、显式时钟复位 |
| 功能规格分析 | spec，仍有 FG / FC / CK 三个子阶段 | 原始标签、Assume / Comb / Seq / Cover |
| 属性生成 | sva_body / sby_guard / sby_trigger，或 native_binding | 表达式与可追踪原生性质绑定 |
| 脚本生成 | extra_config.sby | 自动 .sby，真实 prove 或 bmc，再运行 cover |
| 环境调试 | analysis / extra_config.sby.review | 当前签名结果、约束依据、输入版本审查 |
| 覆盖分析 | spec / review | 业务 Cover 与 guard witness，缺口分类 |
| 反例测试 | tests/test_{DUT}_counterexample.py | 复用原始真实 DUT 回放门禁 |
| Bug 报告 | bugs | 复用原始 Bug 结构与一致性检查 |
| 静态 Bug 关联 | 静态报告 | 原始条件分支，未决不能判误报 |
| 总结与审查 | summary | 当前签名结论及能力边界 |

反例和静态关联分支仍由原配置中的 CEX_CHECK / IGNORE_STATIC_CHECK 条件控制，禁用时仍应在目录中可见。CEX_CHECK=false 表示启用原始反例阶段，不是关闭。

## 2. 属性和环境规则

`sva_body` 在 SBY 下是表达式，不带末尾分号。不能直接照搬 FormalMC 的 property/endproperty、default clocking、disable iff、|->、|=>、## 或 s_eventually。用户切换引擎时需审查属性语义；系统不偷偷转换或替换求解器。

- Comb：`always @*` 中的即时 assert；Seq：声明时钟边沿上的即时 assert。
- Assume / Cover：有时钟时按声明边沿采样，否则组合求值。
- `sby_guard`：明确的检查使能，默认 `1'b1`。不会隐式排除复位周期。
- `sby_trigger`：明确的可达性探针，默认 `1'b1`。每条断言另生成 `G_A_CK_*` guard witness，检查 guard 与 trigger 能否同时成立；这不是完整的前件或空洞性证明。
- `$past/$stable/$rose/$fell` 仅用于采样检查。`uc_past_valid` 只说明已有一次采样；若使用更深历史，必须自行建立充分的历史有效条件，不能用一个周期代替多个周期。
- 所有输入都在 wrapper 顶层显式暴露为符号输入，DUT 输出连接 checker。实际展开后逐项核对 DUT 的端口集合、方向和位宽，阻止漏连或错宽。
- 当前自动生成路径支持组合或单时钟、整数参数、明确展开的整数位宽。不支持自动白盒导出、多时钟生成、接口数组等复杂类型；这些工程可使用现有“原生 SBY / 已有 harness”运行入口，不冒充自动支持。
- 每个 CK 保留 `requirements`。复杂队列、影子模型和白盒性质可设 `verification_route: native`，通过 `native_binding` 纳入同一阶段门禁；不要填恒真 `sva_body` 或仅在计划中列出义务。
- `extra_config.sby.engine` 只能是 `smtbmc z3`（默认）、`smtbmc yices` 或 `abc pdr`。PDR 仅用于 prove；guided 流程的 Cover 明确使用 `smtbmc z3`。工具缺失会报错，不自动替换求解器。
- `reset_policy: none` 只适用于无复位端口；`initial` 必须同时声明 `reset_active`（0/1）与 `reset_cycles`；`unconstrained` 保留自由复位，仍需明确极性、在属性中按规格编写约束。信号名不决定极性。

## 3. 完整记录示例：属性生成阶段完成态

以下是 4 位使能计数器完成规划、接口和属性后的整个 YAML，可作为输入模板。此时尚未运行 EDA，故不含伪造 run_results、证明签名或通过结论。先把 Counter/Counter.sv 放在工作区；其行为是低有效同步复位时 y=0，否则 en=1 时加一并按 4 位回绕。

```yaml
dut: Counter
planning:
  project_overview: 4 位使能计数器
  verification_scope:
    included: [同步复位, 使能累加, 四位回绕]
  strategy: [安全属性证明, 业务可达性检查]
  deliverables: [属性, 签名证据, Bug 报告, 总结]
  risks: [有界覆盖不能证明不可达, 不含多时钟检查]
basic_info:
  module_type: 计数器
  ports:
    inputs:
      - {name: clk, width: 1, signal_type: clock, desc: 上升沿时钟}
      - {name: rst_n, width: 1, signal_type: reset, desc: 低有效同步复位}
      - {name: en, width: 1, signal_type: data, desc: 使能}
    outputs:
      - {name: y, width: 4, signal_type: data, desc: 计数值}
  clock_reset:
    clock_signal: clk
    clock_count: 1
    clock_edge: posedge
    reset_signal: rst_n
  core_functions: [使能时加一]
  correctness_requirements: [复位后为零, 加法按四位回绕]
spec:
  function_groups:
    - id: FG-API
      name: 环境
      functions:
        - id: FC-API
          check_points:
            - id: CK-API
              style: Assume
              description: 二值使能不限制输入行为
              sva_body: en == 0 || en == 1
    - id: FG-COUNT
      name: 计数与复位
      functions:
        - id: FC-COUNT
          check_points:
            - id: CK-COUNT
              style: Seq
              description: 使能后加一
              sva_body: "y == (($past(y) + 4'd1) & 4'hf)"
              sby_guard: uc_past_valid && rst_n && $past(rst_n) && $past(en)
              sby_trigger: en
            - id: CK-RESET
              style: Seq
              description: 前一采样周期复位则当前值为零
              sva_body: y == 0
              sby_guard: uc_past_valid && !$past(rst_n)
    - id: FG-COVERAGE
      name: 可达性
      functions:
        - id: FC-REACH
          check_points:
            - id: CK-REACH
              style: Cover
              description: 能到达计数三
              sva_body: rst_n && y == 3
analysis:
  tt_entries: []
  fa_entries: []
bugs: []
extra_config:
  sby:
    sources: [Counter/Counter.sv]
    filelists: []
    include_dirs: []
    defines: []
    mode: prove
    engine: smtbmc z3
    depth: 12
    timeout_seconds: 30
    reset_policy: initial
    reset_active: 0
    reset_cycles: 1
summary: {}
```

## 4. 执行、审查、恢复

在脚本阶段调用 Check 后：

1. 检查生成和编译。工具错误、缺依赖、超时、取消与磁盘不足不属于 RTL 缺陷。
2. 查看 `{OUT}/tests/sby_coverage.json`。其中每个结果保留 FG / FC / CK、工具属性 ID、模式、结论、manifest 和反例路径。反例路径相对于对应 manifest 所在目录。
3. `sby_evidence.json` 只是索引；Check 实际校验签名 manifest 及所有输入/产物哈希。不接受 LLM 手填的 run_results 作为证据。
4. 环境阶段维护 `extra_config.sby.review.assumptions`：以每个 `M_CK_*` 为键写规格依据；有初始复位时还必须审查 `M_ENV_RESET`。`review.limitations` 必须是一个非空字符串（不是 YAML 列表），在同一段文本中明确说明 `COI: unsupported`、`vacuity: not_established` 和 `liveness: not_established`，以及当前运行的其他范围限制。
5. 完成当前版本审查后，把报告中的 `input_sha256` 原样写入 `review.input_sha256`。输入改变后必须重新审查，不复用旧版本判断。
6. 对自动列出的 `analysis.fa_entries` 填写 `analysis` 和 `resolution`。仍 falsified 的断言只能保留为已确认 RTL_BUG，或修正实际环境错误后重跑。未决证明和 Cover/guard witness 缺口填 INCONCLUSIVE，不填 RTL_BUG。
7. 再次 Check：输入未变时验证并复用证据，不重复求解；输入改变后在脚本/环境/覆盖阶段重新执行。后续只读证据阶段遇到陈旧证据会阻止推进并提示回到执行阶段。

“阶段完成”允许表示所有未决项已如实分析；不表示覆盖已收敛或 DUT 已通过。运行目录按唯一 ID 保存，不覆盖既有波形和证明证据。

## 5. 反例、Bug 与最终总结

Bug 仍使用原 `bugs` 字段：id、property、fg_id、fc_id、ck_id、rtl_file、rtl_line、description、root_cause、trigger、expected、actual、fix、severity、confidence。property 必须对应当前已审查的 RTL_BUG。

若启用反例阶段，为 A_CK_COUNT 编写 `test_cex_ck_count(dut)` 等对应函数：从签名 VCD 获取输入映射，实际赋值 DUT 输入、Step/RefreshComb、比较 expected/actual，并确保 Finish；真实运行且失败症状一致才算复现。仅有函数或 VCD 不算。无 Bug 时测试文件保留明确无需回放的注释。静态报告沿用 `<BG-STATIC-*>`、`<LINK-BUG-[BG-...]>`；无形式反例不能直接判定静态线索为误报。

最后填写 `summary.core_function`、`summary.overall_result`、`summary.acceptance_conclusion`。overall_result 必须严格等于当前报告的 passed / failed / inconclusive。不得用 stats_override 改写实际数据。

- proven：在所写模型与假设下完成所选安全属性证明。
- falsified：有形式反例，先审查环境再决定是否 RTL_BUG。
- covered：所写探针可达；不是功能正确性的证明。
- uncovered / inconclusive：尚无足够证据；有界未命中不表示不可达。
- bmc 无反例：仍为 inconclusive，不升级为无界 proven。
- COI：不支持；vacuity / liveness：未建立。不要用 Cover 命中率替代 FormalMC 的 COI 门禁。

上述计数器示例只验证所列属性，不包含未使能保持等未列出的规格点，不能据此声称“整个模块已完全验证”。

## 6. 复杂原生性质的正式 CK 绑定

保留上述完整记录和可执行 guided 基础检查，将需要独立 harness 的 CK 放入同一个 `spec.function_groups[].functions[].check_points`。`style` 仍为 Seq/Comb/Cover；环境 Assume 继续由 guided 记录声明。以下是一个完整 native CK 的字段示例，其中运行标识、工具性质标识和 hash 必须替换为实际签名结果，不代表该示例已运行：

```yaml
id: CK-DATA-E2E
style: Seq
description: 已接收命令在返回时保留完整数据及归属
requirements: [R02, R15]
kind: safety
expected_behavior: 返回数据与该事务实际捕获的数据一致
formal_obligation: 任意合法输入与任意背压下，独立追踪事务的数据、源和ID直到退休
verification_route: native
sva_body: null
native_binding:
  run_id: actual-platform-run-id
  property_id: A_DATA_E2E
  source: formal/harness.sv
  source_sha256: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  mode: prove
  expected_kind: assert
  scope: end_to_end
  input_map:
    rtl/dut.sv: Counter/Counter.sv
  alias_of: null
  alias_justification: ''
```

`property_id` 必须逐字匹配工具结果中的 `details.property_id`，并且编译来源必须位于指定 `source`。`input_map` 从 native 项目相对路径指向本会话相对路径，必须覆盖全部 `extra_config.sby.sources`；源文件 hash 必须一致。Check 只读取管理员配置的受信平台，核验实际注册的 run、Job、attempt、HMAC manifest、全部输入与产物 hash，不能用手工 JSON 代替。

已审查的 cmdbuf 观测代码允许唯一固定转换：将 `input_map` 值写为 `{session_source: cmdbuf_rd/rtl/cmdbuf_rd.sv, transform: strip_cmdbuf_monitor}`。原生完整文件仍须通过签名验证。转换只删除严格成对、完整独占一行的 `// BEGIN CMDBUF NATIVE FORMAL MONITOR` 与 `// END CMDBUF NATIVE FORMAL MONITOR`，或相同格式的 `CLOSURE` 标记；最多16块、禁止嵌套，剥离后逐字 hash 必须与本会话源相同。它只核验原 RTL 来源，不替代对新增观测代码、假设、驱动和证明范围的审查。

同一合取性质确实覆盖多个原子 CK 时，主 CK 不填 `alias_of`，其他 CK 填主 CK 的 ID 与至少20字符的 `alias_justification`，其余 binding 字段必须完全一致。报告保留每个 CK 的映射，但唯一性质计数与覆盖分母去重。`scope` 必须明确为 `end_to_end`、`local_invariant` 或 `reachability`；选择局部不变量不能自动获得端到端结论。

组合论证可在 `native_binding.supporting_ck_ids` 列出所依赖的安全 CK。必须指向已列出的安全性质，禁止缺失引用和循环。支持项未 proven 时，即便该原生单项性质 proven，依赖 CK 的闭合状态仍为 inconclusive，并保留原工具状态；不会把支持性质直接当作环境 Assume。

完整 `.formal_records.yaml` 的受控保存上限为 2 MiB；普通文档和测试源仍为 200000 字节。`existing_evidence_keys`、`spec_basis`、`evidence_gap` 及 FC 的 `name` 均保留，不静默丢弃未知 CK 字段。

环境与后续审查阶段，在 `extra_config.sby.review.native_runs` 中按精确 run ID 写入 `manifest_sha256`、`assumptions` 和 `scope`。后两项各至少20字符，解释实际 harness 假设的规格依据、归纳辅助是否为断言以及结论边界。manifest hash 必须与本次 Check 已核验值完全相同。未绑定、失效签名、错误模式、来源变化、无唯一编译性质或未经审查都会阻止门禁通过；BMC 无反例仍为 inconclusive，工具错误或超时不能当作完成的证明。

`existing_evidence`、`implementation_status` 和 `proof_status` 仅为作者描述；最终状态只来自当前核验后的性质结果。`run_results` 始终由 Check 生成。原生绑定不会跳过规划、FG/FC/CK、环境、覆盖、反例、静态关联或总结阶段。

`abc pdr` 的 SBY JUnit 若仅返回整组 PASS，工具交叉核对本次 `proof/model/design.json` 编译层次与 `design_aiger.ywa` 实际断言输出，只有两者明确对应的性质获得 proven，并记录 `proof_basis: aggregate_abc_pdr_pass`。不从 RTL 文本猜测性质，不把整组 FAIL 批量标为各项 falsified。PDR 前端使用 `setundef -undriven -anyseq` 将不能编码的 X/Z 转为不受约束的符号值，绝不默认置零；该命令也进入签名控制文件。


## 导出到 FormalMC

保持本任务的规格、属性和 RTL 一致，完成真实 SBY prove/bmc、cover 编译与执行后，保存全部草稿并点击“迁移到 FormalMC”。工具内部创建并打开关联的固定版本工程，使用现有 FormalMC 运行入口验证。输入已变时先重新 Check；源审批与通过状态不迁移。具体使用见 Guide_Doc/formalmc_migration.md。
