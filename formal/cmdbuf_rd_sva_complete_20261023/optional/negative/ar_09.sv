// CMDBUF RD 顶层端口 SVA 阅读入口
// 1 环境假设 -> 2 端口/历史检查 -> 3 发射与 RR -> 4 单 XAU 保序
// -> 5 参考模型自检 -> 6 业务场景覆盖。
// 所有属性显式写出 posedge clk / disable iff (!rst_n)，不检查复位协议。
// |-> 表示同一采样拍；此文件不把本拍义务推迟到下一拍。
// [NO_REF_MODEL_PORTS] 仅本拍端口；[NO_REF_MODEL_HISTORY] 仅端口历史；
// [NO_REF_MODEL_ENV] 环境责任；[REF_MODEL] 依赖事务参考记录；
// [MODEL_SELF_CHECK] 检查器自洽检查，不等于验证 DUT 物理 entry。
// 属性标签保持不变，以便对照测试点、反例和历史结果。
`default_nettype none
// 【采样约定】所有属性在时钟上升沿读取同一拍的采样值；状态用非阻塞赋值在沿后更新。
// 以成功发射的采样拍为 N：N+4 采样并保存 MEM 数据，R 最早在 N+5 的采样拍合法返回。
// 当前用 disable iff 关闭复位期间的属性；参考记录清零与工具初态设置是另一个问题。
// 【责任边界】本模块所有端口均声明为 input，是因为它只观察 DUT 与环境之间的连线。
// 环境 assume 描述已确认契约；DUT assert 检查输出；模型自检不访问 DUT 内部层次。
// 【阅读方法】先看每条触发前提，再看期望结果；生成块中的 g 是来源编号，slots 中 g 是逻辑槽编号。
// cover 表示存在一条满足条件的轨迹，未命中不等于断言失败，命中也不等于无界正确性证明。
module cmdbuf_rd_port_sva (
    // 观测时钟：所有接口义务按此上升沿采样。
    input wire clk,
    // 低有效复位：属性在低电平时禁用；模型寄存器由复位分支建立空状态。
    input wire rst_n,
    // AR 通道：一组命令负载，三位 ready 表示各来源接收资格。
    // 来自上游：共享一条 AR 命令，由 src 指定来源，不是三路独立 arvalid。
    input wire arvalid,
    // 来自 DUT：每位表示该 XAU 当前可接收；可多位同时为 1，握手只看 src 对应位。
    input wire [2:0] arready,
    // 来自上游：完整 18 位地址；[5:3] 选 Bank，[6] 选奇偶，[2:0] 在 R 口透传。
    input wire [17:0] araddr,
    // 来源编码 0/1/2 分别是 XAU0/1/2；3 在有效 AR 时由环境契约排除。
    input wire [1:0] src,
    // 上游事务 ID：8 位原样保存，允许重复，不能以它替代接收 FIFO 的顺序 token。
    input wire [7:0] arid,
    // 上游 5 位 port_id：与同一事务的数据、ID、低地址一起保序返回。
    input wire [4:0] ar_port_id,
    // 上游地址状态：00 正常、11 越界；越界请求仍发 MEM，最终错误优先级最高。
    input wire [1:0] arresp,
    // R 通道：一组共享负载，单源保序，跨源按 RR 选择。
    // rvalid 来自 DUT、rready 来自上游；共享 R 负载由唯一有效的 rvalid 位指定接收者。
    input wire [2:0] rvalid, rready,
    // 来自 DUT：共享 128 位返回数据；无 rvalid 的拍不检查其取值。
    input wire [127:0] rdata,
    // 来自 DUT：应等于本次返回事务在 AR 接受时的 arid。
    input wire [7:0] rid,
    // 来自 DUT：应透传同一次 AR 的 port_id。
    input wire [4:0] r_port_id,
    // 来自 DUT：只返回原 araddr[2:0]，不是完整地址。
    input wire [2:0] raddr,
    // 来自 DUT：00 正常、01 校验异常、11 地址越界；无效拍不比较。
    input wire [1:0] rresp,
    // Arbit 通道：请求和地址已流水一拍；双 grant 才能推进待发窗口。
    // 来自 DUT：八个 Bank 的独热或全零请求；仲裁失败的请求不算成功发射。
    input wire [7:0] req,
    // 来自 DUT：请求事务的 araddr[17:6]；bit0 将奇偶半区送到下游。
    input wire [11:0] arb_addr,
    // 来自 DUT：组合输出的待发数，含本拍新 AR、扣本拍成功发射，不是总占用数。
    input wire [3:0] pending_cnt,
    // 来自 Arbit/MEM：只有同一 req 位的两个 grant 都为 1，本拍才算发射成功。
    input wire [7:0] ar_rd_gnt, rw_rd_gnt,
    // MEM 通道：逐 Bank 半区状态；数据和校验异常只有一组合并返回。
    // 二维状态：rd_mem_status[Bank编号][奇偶位]，0 空闲、1 占用；保持逐 Bank 数组形式。
    input wire [1:0] rd_mem_status [7:0],
    // 来自 MEM：一组合并后的 128 位数据，仅在四拍日历到期的采样沿保存。
    input wire [127:0] mem_rdata,
    // 来自 MEM：与本次返回数据同拍的 1 位校验异常；非到期拍数值不用于该事务。
    input wire pc_err

);


// 独立负向环境检查：没有正常事务模型；本文件不能用于宣称 DUT 正常证明。
wire bad_busy;
wire [7:0] bad_bits;
genvar nb;
generate for(nb=0;nb<8;nb=nb+1) begin: busy_contract
assign bad_bits[nb]=req[nb]&&ar_rd_gnt[nb]&&rw_rd_gnt[nb]&&!rd_mem_status[nb][arb_addr[0]];
end endgenerate
assign bad_busy=|bad_bits;
// [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 全不 ready 时环境仍发送有效请求；本项改为监测断言，预期检出。
V_AR_09: assert property (
    @(posedge clk) disable iff (!rst_n)
    (arready==0) |-> (!arvalid)
);
// [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 有效请求使用不存在的第四个来源；保留其他环境约束。
E03_SRC: assume property (
    @(posedge clk) disable iff (!rst_n)
    arvalid |-> (src<3)
);
// [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] req 同位双 grant 成功但对应半区仍空闲；保留其他环境约束。
E06_SUCCESS_BUSY: assume property (
    @(posedge clk) disable iff (!rst_n)
    !bad_busy
);
// [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 有效请求携带未定义的 arresp；保留其他环境约束。
E04_ARRESP: assume property (
    @(posedge clk) disable iff (!rst_n)
    arvalid |-> (arresp==0 || arresp==3)
);
// [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 真正违规条件共现；不是蕴含空真。
N_AR_09: cover property (
    @(posedge clk) disable iff (!rst_n)
    arready==0 && arvalid
);
endmodule
`default_nettype wire
