# cmdbuf_rd · Verilog-2001 实现

当前可综合 RTL 使用 IEEE 1364-2001 Verilog，文件为：

- [cmdbuf_rd.v](cmdbuf_rd.v)：顶层端口与 CMDBUF / OTB 连接。
- [cmdbuf_rd_cmd.v](cmdbuf_rd_cmd.v)：9 项命令、年龄矩阵、最老 5 条待发窗口、发射流水、容量保底、每来源保序和响应 RR。
- [cmdbuf_rd_otb.v](cmdbuf_rd_otb.v)：9 项 128 位数据、pc_err、四拍返回标记与捕获。

RTL 使用 `wire` / `reg`、`always @*`、时钟沿 `always` 和显式端口连接。每个过程独立声明循环变量；截断、零扩展和复位常量都写出位宽。

## Bank 状态接口的 Verilog 表达

Verilog-2001 用一维端口保存原来 `[1:0][7:0]` 的 16 位状态：

```verilog
input wire [15:0] rd_mem_status;
```

| 原逻辑位 | 当前 Verilog 位 | 含义 |
|---|---|---|
| `rd_mem_status[0][b]` | `rd_mem_status[b]` | Bank b 的偶半区状态 |
| `rd_mem_status[1][b]` | `rd_mem_status[8+b]` | Bank b 的奇半区状态 |

0 表示空闲，1 表示忙。命令选择直接读取 `rd_mem_status[addr_q[i][6:3]]`：`addr[6]` 选择奇偶，`addr[5:3]` 选择 Bank 0～7。连接原二维状态源时，传入 `{odd_status[7:0], even_status[7:0]}`。

其他端口名称、位宽和协议继续使用当前设计：18 位 AR 地址、12 位下游地址 `[17:6]`、128 位读数据、8 位 ID、5 位 port_id、ready 内 RR，MEM 返回与 R 响应之间至少一拍。

## 严格语法检查

```sh
iverilog -g2001 -s cmdbuf_rd -o cmdbuf_rd.vvp rtl/cmdbuf_rd.v rtl/cmdbuf_rd_cmd.v rtl/cmdbuf_rd_otb.v
verilator --lint-only --Wall --assert --language 1364-2001 --top-module cmdbuf_rd rtl/cmdbuf_rd.v rtl/cmdbuf_rd_cmd.v rtl/cmdbuf_rd_otb.v
```

仿真诊断也使用 Verilog 函数、任务和 `$stop`，合成时定义 `SYNTHESIS` 将其排除。Icarus 运行使用 `vvp -N`，使实际诊断停止返回失败状态。

形式验证中的属性、观测器和 FormalMC 模型属于验证环境，保留 `.sv` / `.svh`；它们不作为芯片 RTL 集成文件。验证任务中 `.v` 的 `FORMAL` 条件 include 用来接入外置观测器，正常集成只使用本目录三份 `.v`。

新旧实现等价性、仿真回归与完整形式验证的当前记录见 [Verilog 迁移验证说明](../verification/verilog_20261012/README.md)。历史 SystemVerilog 验收证据保留其原始输入与时间，不作为新的执行记录使用。
