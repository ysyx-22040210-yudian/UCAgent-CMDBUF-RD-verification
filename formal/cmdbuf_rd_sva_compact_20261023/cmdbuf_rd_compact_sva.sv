// CMDBUF RD 直接比较版：只连接原始 24 个 DUT 顶层信号，没有额外观察参数。
// 第 2 节按全部十组输出分别写出 A_COMPARE_*，实际输出名和比较表达式都在 assert 正文。
// 简单数量保持精确；复杂负载在九条有效、未消费记录中任选一条匹配。
// 各 R 字段独立消费，不要求来自同一事务；不检查单源保序、RR 胜者、五项窗口及进度。
// 为了直接比较实际字段，本版保存必要的字段值，不能沿用上一符号参数版的 66 位状态结论。
// 无效负载不检查；组合逻辑均为 assign。模型只记录顶层握手及四拍 MEM 返回历史。
// [EXACT] 局部规则精确；[RELAXED] 允许集合；[MODEL_SELF_CHECK] 模型容量与数量自检。
`default_nettype none
module cmdbuf_rd_compact_sva (
    input wire clk, // 采样时钟
    input wire rst_n, // 低有效复位；属性统一 disable iff
    input wire arvalid, // 上游共享请求有效
    input wire [2:0] arready, // DUT 三源接收资格
    input wire [17:0] araddr, // 上游完整地址
    input wire [1:0] src, // 上游来源 0/1/2
    input wire [7:0] arid, // 上游 ID，允许重复
    input wire [4:0] ar_port_id, // 上游 port_id
    input wire [1:0] arresp, // 上游地址状态：00/11
    input wire [2:0] rvalid, // DUT 响应对象，独热或零
    input wire [2:0] rready, // 上游响应接收资格
    input wire [127:0] rdata, // DUT 返回数据，与九项数据集合匹配
    input wire [7:0] rid, // DUT 返回 ID，与同源 ID 集合匹配
    input wire [4:0] r_port_id, // DUT 返回 port，与同源 port 集合匹配
    input wire [2:0] raddr, // DUT 返回低地址，与同源低地址集合匹配
    input wire [1:0] rresp, // DUT 返回状态，采用字段数量可行性检查
    input wire [7:0] req, // DUT 下游请求，最多一位为 1
    input wire [11:0] arb_addr, // DUT 下游地址，原地址 [17:6]
    input wire [3:0] pending_cnt, // DUT 本拍待发计数，含本拍接收减本拍成功
    input wire [7:0] ar_rd_gnt, // 下游仲裁 grant
    input wire [7:0] rw_rd_gnt, // 下游仲裁为读的 grant
    input wire [1:0] rd_mem_status [7:0], // 下游 Bank-major 二维状态，0 空闲
    input wire [127:0] mem_rdata, // MEM 合并返回数据，仅成功后第四拍采样
    input wire pc_err // MEM 返回的奇偶校验标记
);

    `include "cmdbuf_rd_compact_model.svh"

    // 1. 既有输入协议假设；没有要求 DUT 输出必须命中的 assume。
    // [EXACT] [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 有效 AR 的来源只能为 0/1/2。
    E03_SRC: assume property (
        @(posedge clk) disable iff (!rst_n)
        arvalid |-> src<2'd3
    );

    // [EXACT] [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 有效 AR 的地址状态只能为正常或越界。
    E04_ARRESP: assume property (
        @(posedge clk) disable iff (!rst_n)
        arvalid |-> (arresp==2'b00 || arresp==2'b11)
    );

    // [EXACT] [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 三个 ready 全低时，上游不得发送有效 AR。
    E05_ZERO_READY: assume property (
        @(posedge clk) disable iff (!rst_n)
        arready==3'b000 |-> !arvalid
    );

    genvar b; // 逐 Bank 展开同拍双 grant 成功后的忙状态约束。
    generate for (b=0; b<8; b=b+1) begin : status_contract
    // [EXACT] [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 成功当拍被访问的 Bank/half 必须为忙。
    E06_SUCCESS_BUSY: assume property (
        @(posedge clk) disable iff (!rst_n)
        (req[b] && ar_rd_gnt[b] && rw_rd_gnt[b]) |-> rd_mem_status[b][arb_addr[0]]
    );

    end endgenerate

    // 2. 全部输出的直接比较断言。每个输出都有明确命名，不藏在 query/hit 标志之后。
    // [EXACT] [NO_REF_MODEL_HISTORY] 精确比较三个 ready 位，含同拍 R 回收及每源首项预留。
    A_COMPARE_ARREADY: assert property (
        @(posedge clk) disable iff (!rst_n)
        arready==expected_ready
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 精确比较组合待发数：拍初待发 + 本拍 AR 接收 - 本拍成功发射。
    A_COMPARE_PENDING_CNT: assert property (
        @(posedge clk) disable iff (!rst_n)
        {2'b0,pending_cnt}==pending_now
    );

    // [RELAXED] [REF_MODEL] req 必须为零或某个有合格待发记录的独热 Bank 值；不检查有候选时必须发射。
    A_COMPARE_REQ: assert property (
        @(posedge clk) disable iff (!rst_n)
        req==8'b00000000 ||
        (req==8'b00000001 && allowed_req_bank[0]) ||
        (req==8'b00000010 && allowed_req_bank[1]) ||
        (req==8'b00000100 && allowed_req_bank[2]) ||
        (req==8'b00001000 && allowed_req_bank[3]) ||
        (req==8'b00010000 && allowed_req_bank[4]) ||
        (req==8'b00100000 && allowed_req_bank[5]) ||
        (req==8'b01000000 && allowed_req_bank[6]) ||
        (req==8'b10000000 && allowed_req_bank[7])
    );

    // [RELAXED] [REF_MODEL] 有效请求地址逐项比较九条成熟待发记录，并要求 Bank 与同一项对应；不会拼接不同记录。
    A_COMPARE_ARB_ADDR: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|req) |-> (
            (command_valid[0] && command_eligible[0] && req[command_value[0][2:0]] &&
             arb_addr==command_value[0][14:3]) ||
            (command_valid[1] && command_eligible[1] && req[command_value[1][2:0]] &&
             arb_addr==command_value[1][14:3]) ||
            (command_valid[2] && command_eligible[2] && req[command_value[2][2:0]] &&
             arb_addr==command_value[2][14:3]) ||
            (command_valid[3] && command_eligible[3] && req[command_value[3][2:0]] &&
             arb_addr==command_value[3][14:3]) ||
            (command_valid[4] && command_eligible[4] && req[command_value[4][2:0]] &&
             arb_addr==command_value[4][14:3]) ||
            (command_valid[5] && command_eligible[5] && req[command_value[5][2:0]] &&
             arb_addr==command_value[5][14:3]) ||
            (command_valid[6] && command_eligible[6] && req[command_value[6][2:0]] &&
             arb_addr==command_value[6][14:3]) ||
            (command_valid[7] && command_eligible[7] && req[command_value[7][2:0]] &&
             arb_addr==command_value[7][14:3]) ||
            (command_valid[8] && command_eligible[8] && req[command_value[8][2:0]] &&
             arb_addr==command_value[8][14:3])
        )
    );

    // [RELAXED] [REF_MODEL] rvalid 必须为零或一个允许来源的独热值；不指定 RR 胜者，也不证明逐源命令已完成。
    A_COMPARE_RVALID: assert property (
        @(posedge clk) disable iff (!rst_n)
        rvalid==3'b000 ||
        (rvalid==3'b001 && allowed_r_source[0]) ||
        (rvalid==3'b010 && allowed_r_source[1]) ||
        (rvalid==3'b100 && allowed_r_source[2])
    );

    // [RELAXED] [REF_MODEL] 有效 rid 直接与同源九条有效字段记录逐项比较；任一完整字段相等即通过。
    A_COMPARE_RID: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> (
            (id_valid[0] && r_src==id_value[0][9:8] && rid==id_value[0][7:0]) ||
            (id_valid[1] && r_src==id_value[1][9:8] && rid==id_value[1][7:0]) ||
            (id_valid[2] && r_src==id_value[2][9:8] && rid==id_value[2][7:0]) ||
            (id_valid[3] && r_src==id_value[3][9:8] && rid==id_value[3][7:0]) ||
            (id_valid[4] && r_src==id_value[4][9:8] && rid==id_value[4][7:0]) ||
            (id_valid[5] && r_src==id_value[5][9:8] && rid==id_value[5][7:0]) ||
            (id_valid[6] && r_src==id_value[6][9:8] && rid==id_value[6][7:0]) ||
            (id_valid[7] && r_src==id_value[7][9:8] && rid==id_value[7][7:0]) ||
            (id_valid[8] && r_src==id_value[8][9:8] && rid==id_value[8][7:0])
        )
    );

    // [RELAXED] [REF_MODEL] 有效 r_port_id 直接与同源九条有效字段记录逐项比较；任一完整字段相等即通过。
    A_COMPARE_R_PORT_ID: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> (
            (port_valid[0] && r_src==port_value[0][6:5] && r_port_id==port_value[0][4:0]) ||
            (port_valid[1] && r_src==port_value[1][6:5] && r_port_id==port_value[1][4:0]) ||
            (port_valid[2] && r_src==port_value[2][6:5] && r_port_id==port_value[2][4:0]) ||
            (port_valid[3] && r_src==port_value[3][6:5] && r_port_id==port_value[3][4:0]) ||
            (port_valid[4] && r_src==port_value[4][6:5] && r_port_id==port_value[4][4:0]) ||
            (port_valid[5] && r_src==port_value[5][6:5] && r_port_id==port_value[5][4:0]) ||
            (port_valid[6] && r_src==port_value[6][6:5] && r_port_id==port_value[6][4:0]) ||
            (port_valid[7] && r_src==port_value[7][6:5] && r_port_id==port_value[7][4:0]) ||
            (port_valid[8] && r_src==port_value[8][6:5] && r_port_id==port_value[8][4:0])
        )
    );

    // [RELAXED] [REF_MODEL] 有效 raddr 直接与同源九条有效字段记录逐项比较；任一完整字段相等即通过。
    A_COMPARE_RADDR: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> (
            (low_addr_valid[0] && r_src==low_addr_value[0][4:3] && raddr==low_addr_value[0][2:0]) ||
            (low_addr_valid[1] && r_src==low_addr_value[1][4:3] && raddr==low_addr_value[1][2:0]) ||
            (low_addr_valid[2] && r_src==low_addr_value[2][4:3] && raddr==low_addr_value[2][2:0]) ||
            (low_addr_valid[3] && r_src==low_addr_value[3][4:3] && raddr==low_addr_value[3][2:0]) ||
            (low_addr_valid[4] && r_src==low_addr_value[4][4:3] && raddr==low_addr_value[4][2:0]) ||
            (low_addr_valid[5] && r_src==low_addr_value[5][4:3] && raddr==low_addr_value[5][2:0]) ||
            (low_addr_valid[6] && r_src==low_addr_value[6][4:3] && raddr==low_addr_value[6][2:0]) ||
            (low_addr_valid[7] && r_src==low_addr_value[7][4:3] && raddr==low_addr_value[7][2:0]) ||
            (low_addr_valid[8] && r_src==low_addr_value[8][4:3] && raddr==low_addr_value[8][2:0])
        )
    );

    // [RELAXED] [REF_MODEL] 直接比较 11/01/00 及其可用标记条件；11 可遮住 pc 错误，但不建立逐事务错误配对。
    A_COMPARE_RRESP: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> (
            (rresp==2'b11 && outside[r_src]!=0) ||
            (rresp==2'b01 && occupied[r_src]>outside[r_src] && bad_high!=0) ||
            (rresp==2'b00 && occupied[r_src]>outside[r_src] && bad_low<completed)
        )
    );

    // [RELAXED] [REF_MODEL] 有效 rdata 与九条有效、已捕获且未消费的 128 位数据直接比较；完整相等即通过。
    A_COMPARE_RDATA: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> (
            (data_valid[0] && rdata==data_value[0]) ||
            (data_valid[1] && rdata==data_value[1]) ||
            (data_valid[2] && rdata==data_value[2]) ||
            (data_valid[3] && rdata==data_value[3]) ||
            (data_valid[4] && rdata==data_value[4]) ||
            (data_valid[5] && rdata==data_value[5]) ||
            (data_valid[6] && rdata==data_value[6]) ||
            (data_valid[7] && rdata==data_value[7]) ||
            (data_valid[8] && rdata==data_value[8])
        )
    );

    // 3. 局部协议与数量自检；单独运行时不把其他 assert 提升为 assume。
    // [EXACT] [NO_REF_MODEL_PORTS] 请求最多一个 Bank。
    A_L_REQ_ONEHOT: assert property (
        @(posedge clk) disable iff (!rst_n)
        (req & (req-8'd1))==0
    );

    // [EXACT] [NO_REF_MODEL_PORTS] 共享 R 口最多返回给一个来源。
    A_L_R_ONEHOT: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rvalid & (rvalid-3'd1))==0
    );

    // [EXACT] [NO_REF_MODEL_PORTS] R 只在该源 ready 为 1 时有效。
    A_L_R_READY: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rvalid & ~rready)==0
    );

    // [EXACT] [NO_REF_MODEL_PORTS] 有效响应不得使用 10 编码。
    A_L_RRESP_CODE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> (rresp==2'b00 || rresp==2'b01 || rresp==2'b11)
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 待发数量不得下溢或超过九。
    A_L_PENDING_RANGE: assert property (
        @(posedge clk) disable iff (!rst_n)
        pending_now<=6'd9
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 总未回收命令最多九条。
    A_L_TOTAL: assert property (
        @(posedge clk) disable iff (!rst_n)
        total<=7'd9
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 每个空源至少保留一项；共享部分不可侵占预留。
    A_L_RESERVATION: assert property (
        @(posedge clk) disable iff (!rst_n)
        reserved_total<=7'd9
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 成功发射必须消费先前接收的一条待发命令。
    A_L_ISSUE_BALANCE: assert property (
        @(posedge clk) disable iff (!rst_n)
        issue_fire |-> waiting!=0
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 已捕获但未响应的数据量不得越界。
    A_L_COMPLETED: assert property (
        @(posedge clk) disable iff (!rst_n)
        completed<=5'd9
    );

    // [EXACT] [MODEL_SELF_CHECK] 每次接收 AR 都应有待发地址记录空间。
    M_L_COMMAND_ROOM: assert property (
        @(posedge clk) disable iff (!rst_n)
        ar_fire |-> command_room
    );

    // [EXACT] [MODEL_SELF_CHECK] 各字段都必须存得下新 AR，支持 R 同拍释放。
    M_L_FIELDS_ROOM: assert property (
        @(posedge clk) disable iff (!rst_n)
        ar_fire |-> (id_room && port_room && low_addr_room)
    );

    // [EXACT] [MODEL_SELF_CHECK] MEM 只来一拍，必须能保存，不能丢弃以让后续比较通过。
    M_L_DATA_ROOM: assert property (
        @(posedge clk) disable iff (!rst_n)
        mem_due |-> data_room
    );

    // [EXACT] [MODEL_SELF_CHECK] 地址集合数量与成功发射账本一致。
    M_L_WAITING_COUNT: assert property (
        @(posedge clk) disable iff (!rst_n)
        {1'b0,command_count}==waiting
    );

    // [EXACT] [MODEL_SELF_CHECK] 三种字段独立消费，但各自总量都要守恒。
    M_L_FIELD_COUNTS: assert property (
        @(posedge clk) disable iff (!rst_n)
        ({3'b0,id_count}==total && {3'b0,port_count}==total && {3'b0,low_addr_count}==total)
    );

    // [EXACT] [MODEL_SELF_CHECK] 数据集合数量与四拍日历和 R 握手累计数一致。
    M_L_DATA_COUNT: assert property (
        @(posedge clk) disable iff (!rst_n)
        {1'b0,data_count}==completed
    );

    // [EXACT] [MODEL_SELF_CHECK] pc=1 的可能数量区间必须非空，且不超过已完成数据量。
    M_L_PC_INTERVAL: assert property (
        @(posedge clk) disable iff (!rst_n)
        bad_low<=bad_high && bad_high<=completed
    );

    genvar x; // 分别检查三个来源的占用及越界标记数量。
    generate for (x=0; x<3; x=x+1) begin : sources
    // [EXACT] [NO_REF_MODEL_HISTORY] 一个 XAU 最多占七项。
    A_L_SOURCE_LIMIT: assert property (
        @(posedge clk) disable iff (!rst_n)
        occupied[x]<=5'd7
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 不能向没有未完成请求的来源返回响应。
    A_L_SOURCE_NONEMPTY: assert property (
        @(posedge clk) disable iff (!rst_n)
        rvalid[x] |-> occupied[x]!=0
    );

    // [EXACT] [MODEL_SELF_CHECK] 越界标记数量不能超过该源占用。
    M_L_ERROR_COUNT: assert property (
        @(posedge clk) disable iff (!rst_n)
        outside[x]<=occupied[x]
    );

    end endgenerate

    // 4. 业务见证，只使用真实顶层事件；不注入引导假设。
    // [RELAXED] [REF_MODEL] 完整接收、发射、四拍返回、R 响应至少发生一次。
    C_L_RESPONSE: cover property (
        @(posedge clk) disable iff (!rst_n)
        r_fire
    );

    // [RELAXED] [REF_MODEL] 正常地址发生奇偶校验异常响应。
    C_L_PC_ERROR: cover property (
        @(posedge clk) disable iff (!rst_n)
        r_fire && rresp==2'b01
    );

    // [RELAXED] [REF_MODEL] 地址越界请求经过 MEM 后返回 11。
    C_L_ADDRESS_ERROR: cover property (
        @(posedge clk) disable iff (!rst_n)
        r_fire && rresp==2'b11
    );

    // [RELAXED] [REF_MODEL] 共享九项达到全满。
    C_L_FULL: cover property (
        @(posedge clk) disable iff (!rst_n)
        total==7'd9
    );

    // [RELAXED] [REF_MODEL] 全满时 R 回收和 AR 接收同拍。
    C_L_FULL_REUSE: cover property (
        @(posedge clk) disable iff (!rst_n)
        total==7'd9 && r_fire && ar_fire
    );

    // [RELAXED] [REF_MODEL] 接收、发射成功、MEM 捕获、R 回收四事件同拍。
    C_L_FOUR_EVENTS: cover property (
        @(posedge clk) disable iff (!rst_n)
        ar_fire && issue_fire && mem_due && r_fire
    );

    // [RELAXED] [REF_MODEL] 失败后紧邻下一拍同地址重试。
    C_L_RETRY: cover property (
        @(posedge clk) disable iff (!rst_n)
        previous_failure && |req && previous_request=={arb_addr,req_bank}
    );

    // [RELAXED] [REF_MODEL] 连续两拍成功发射。
    C_L_CONSECUTIVE_ISSUE: cover property (
        @(posedge clk) disable iff (!rst_n)
        previous_issue && issue_fire
    );

    // [RELAXED] [REF_MODEL] 连续两拍返回响应。
    C_L_CONSECUTIVE_R: cover property (
        @(posedge clk) disable iff (!rst_n)
        previous_r && r_fire
    );

    // [RELAXED] [REF_MODEL] 集合中重复数据同时命中，本次只删除一项。
    C_L_DATA_DUPLICATE: cover property (
        @(posedge clk) disable iff (!rst_n)
        r_fire && (data_match & (data_match-9'd1))!=0
    );

    // [RELAXED] [REF_MODEL] 累计接收超过九条后仍能响应，防止简单最近九拍窗口丢失老事务。
    C_L_TURNOVER: cover property (
        @(posedge clk) disable iff (!rst_n)
        accept_saturated>=5'd10 && r_fire
    );

    // [RELAXED] [REF_MODEL] 完整 128 位数据最高位为 1 时仍能正常返回。
    C_D_HIGH_DATA: cover property (
        @(posedge clk) disable iff (!rst_n)
        r_fire && rdata[127]
    );

endmodule
`default_nettype wire
