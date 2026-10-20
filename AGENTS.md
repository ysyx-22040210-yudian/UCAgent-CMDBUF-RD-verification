# 项目交付约定

- 用户要求说明文档使用 PDF 或 Word。新增、修订的项目说明交付到 `documents/`，优先同时提供可编辑 `.docx` 与对应 `.pdf`；仓库首页的说明入口链接这些成品。
- 说明覆盖设计、时序、注错、Tk GUI 操作、验证流程、结果与设备迁移。Word 正文和表格可编辑；图示保留清晰度，真实 GUI 截图不得伪造状态。导出后检查页面排版、内容完整性和链接。
- Markdown、HTML 可以作为内容源、历史记录或仓库导航保留。RTL、脚本、断言、机器可读结果和签名证据保持工程格式。不要为文档转换改写封存输入、历史签名或运行结论。
- 用户于 2026-10-21 确认 RTL 允许使用 SystemVerilog；新增实现可以使用 `.sv`，并保留 `bit [1:0] rd_mem_status [7:0]` 的逐 Bank 二维端口。原 Verilog `.v` 及封存输入保持其历史含义。验证环境可以使用 `.sv` 和 `.svh`。历史 SBY 证据、当前重新验证结果和目标设备的真实 FormalMC 执行必须分别说明。
- 当前修正规格以 `docs/timing/protocol_corrections_20261021.json` 和 `documents/15_cmdbuf_rd_protocol_corrections_20261021.pdf` / `.docx` 为准。用户已确认窗口内非队头成功后保留其他待发项并同拍补入下一项（6B）；失败命令可以同拍重选；pending_cnt 包含本拍 AR 接收和成功发射。此前冲突的说明及旧验证结果不能作为新规格的验收结论。
- 用户指定通过 GitHub Desktop 上传；发布后的文件和远端提交需复核。
- 当前 RTL 集成入口为 `rtl/files.f`，选入三份 `.sv`；同目录 `.v` 及旧双后端包只保留历史语义。新规格验证使用 `formal/protocol_20261021/` 和 `simulation/env_base/projects/cmdbuf_rd_sv.mk`，结果在 `verification/protocol_20261021/`，不要把新旧结论混用。
- 用户已明确当前 SVA 不使用 `started`、`active` 或复位序列 assume；原生属性统一为 `@(posedge clk) disable iff (!rst_n)`，不专门检查复位行为。RR 从 XAU0 开始，按 0→1→2 扫描，实际响应后移到胜者下一通道，否则保持。无效 `arb_addr` / R 负载不检查。此轮 SVA 独立结果在 `verification/sva_alignment_20261021/`，以第 17 份说明为准；工具建立初态的方法必须单列说明，不能把 `disable iff` 当作初始化。
- 单 XAU 响应顺序必须由独立接收 FIFO 显式检查：AR 握手入队，仅该源 R 握手出队；逐项比较队头的 raddr、rid、port_id、数据和错误状态。命令 3 先发射和先返回 MEM 时，仍须等待命令 1、2 完成 R 响应。当前新增属性为 `A_XAU_R_*`，证据在 `verification/xau_order_20261021/`，第 18 份说明记录补强；此前快照保持不变。
- 用户要求 SVA 便于人工分析。当前主文件直接写原生 `assume/assert/cover property`，同拍条件义务优先用 `|->`，每条写中文意图及模型依赖分类。参考状态移到 `cmdbuf_rd_reference_model.svh` 和 `cmdbuf_rd_xau_order_model.svh`。保持属性标签便于追溯；SBY 对执行副本的布尔适配必须有源文件和转换清单，不能回写可读源码或默默降低多拍性质。当前回归证据在 `verification/sva_readability_20261021/`，第 19 份说明记录阅读入口和语义核验范围。
