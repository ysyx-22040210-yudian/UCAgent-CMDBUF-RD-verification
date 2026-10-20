# cmdbuf_rd 当前 RTL 入口

当前实现采用 SystemVerilog，规格确认日期为 2026-10-21。

- [files.f](files.f)：从仓库根目录使用的当前 RTL 文件清单。
- [cmdbuf_rd.sv](cmdbuf_rd.sv)：顶层，保留 `input bit [1:0] rd_mem_status [7:0]`。
- [cmdbuf_rd_cmd.sv](cmdbuf_rd_cmd.sv)：待发窗口、失败重选、组合计数、容量管理及响应 RR。
- [cmdbuf_rd_otb.sv](cmdbuf_rd_otb.sv)：四拍 MEM 捕获、128 位数据及 pc_err 保存。
- [本轮修复和验证说明 PDF](../documents/16_cmdbuf_rd_rtl_revision_20261021.pdf) / [Word](../documents/16_cmdbuf_rd_rtl_revision_20261021.docx)。
- [修正规格](../docs/timing/protocol_corrections_20261021.json) / [本轮结果](../verification/protocol_20261021/summary.json)。

同目录 `.v` 保留其历史语义，不是当前集成入口。不要同时编译 `.v` 与 `.sv`；原平铺状态口、失败排除和寄存计数不能用于新规格。历史验证结果只适用于其封存输入。
