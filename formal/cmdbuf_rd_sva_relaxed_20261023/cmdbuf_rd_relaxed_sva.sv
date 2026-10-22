// CMDBUF RD 简化 Formal SVA：存在匹配即可，不复现完整调度模型。
// 精确版保留在 ../cmdbuf_rd_sva_complete_20261023，本文件不能替代其保序/窗口/RR 证明。
// 精确检查：端口合法性、数量守恒、准入和首项预留、最低请求延迟、全局 MEM 返回日历。
// 放宽检查：每个 R 字段独立在九项集合中匹配；不同字段可以来自不同事务。
// 数据来自任一已捕获、未消费的 MEM 记录，不检查 source/ID/地址与数据的配对。
// req 可选择任一满足历史空闲资格的待发命令，不检查最老五项、最老选择、无气泡或 RR。
// rresp 检查合法编码与数量可行性，不证明逐事务 pc_err 关联或逐事务错误优先级。
// [EXACT] 表示该局部规则精确；[RELAXED] 表示集合/数量存在性检查。
// [NO_REF_MODEL_PORTS] 本拍端口；[NO_REF_MODEL_HISTORY] 简单历史；[REF_MODEL] 九项集合；
// [MODEL_SELF_CHECK] 模型自洽，不能当作 DUT 内部结构证明。
`default_nettype none
module cmdbuf_rd_relaxed_sva (
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

    `include "cmdbuf_rd_relaxed_model.svh"

    // 1. 环境只保留已对齐的四类假设；不强迫 DUT 输出命中，不约束输入 ID/数据唯一。
    // [EXACT] [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 有效 AR 来源合法；无效拍不限制 src。
    E03_SRC: assume property (
        @(posedge clk) disable iff (!rst_n)
        arvalid |-> (src < 2'd3)
    );

    // [EXACT] [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 有效 AR 的地址状态只允许 00 或 11。
    E04_ARRESP: assume property (
        @(posedge clk) disable iff (!rst_n)
        arvalid |-> (arresp==2'b00 || arresp==2'b11)
    );

    // [EXACT] [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 所有 ready 为零时，上游不发送有效 AR。
    E05_ZERO_READY: assume property (
        @(posedge clk) disable iff (!rst_n)
        (arready==3'b000) |-> !arvalid
    );

    genvar b; // 逐 Bank 展开成功当拍忙状态契约。
    generate for (b=0; b<8; b=b+1) begin : status_contract
        // [EXACT] [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 成功当拍被访问半区必须忙；不是请求前空闲检查。
        E06_SUCCESS_BUSY: assume property (
            @(posedge clk) disable iff (!rst_n)
            (req[b] && ar_rd_gnt[b] && rw_rd_gnt[b]) |-> rd_mem_status[b][arb_addr[0]]
        );

    end endgenerate

    // 2. 简单端口与数量规则保持精确；无效负载不比较。
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

    // [EXACT] [NO_REF_MODEL_HISTORY] 精确检查本拍 pending，不从 DUT 的计数自我递推。
    A_L_PENDING: assert property (
        @(posedge clk) disable iff (!rst_n)
        {2'b0,pending_cnt}==pending_now
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 待发数量不得下溢或超过九。
    A_L_PENDING_RANGE: assert property (
        @(posedge clk) disable iff (!rst_n)
        pending_now<=6'd9
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 按实际 AR/R 账本精确计算三源 ready，支持同拍回收。
    A_L_READY: assert property (
        @(posedge clk) disable iff (!rst_n)
        arready==expected_ready
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

    // [EXACT] [NO_REF_MODEL_HISTORY] 当前 R 必须有之前已捕获的 MEM 返回，不能消费本拍刚到的数据。
    A_L_R_AFTER_CAPTURE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> completed!=0
    );

    // [EXACT] [NO_REF_MODEL_HISTORY] 已捕获但未响应的数据量不得越界。
    A_L_COMPLETED: assert property (
        @(posedge clk) disable iff (!rst_n)
        completed<=5'd9
    );

    genvar x; // 各来源数量及错误标记义务，不重建各源响应顺序。
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

        // [RELAXED] [REF_MODEL] 11 至少能消费该源一个越界标记，不与本拍 rid 绑定。
        A_L_ADDR_ERROR_ANY: assert property (
            @(posedge clk) disable iff (!rst_n)
            (rvalid[x] && rresp==2'b11) |-> outside[x]!=0
        );

        // [RELAXED] [REF_MODEL] 非 11 至少能消费该源一个正常地址标记。
        A_L_NORMAL_ADDR_ANY: assert property (
            @(posedge clk) disable iff (!rst_n)
            (rvalid[x] && rresp!=2'b11) |-> occupied[x]>outside[x]
        );

        // [EXACT] [MODEL_SELF_CHECK] 越界标记数量不能超过该源占用。
        M_L_ERROR_COUNT: assert property (
            @(posedge clk) disable iff (!rst_n)
            outside[x]<=occupied[x]
        );

    end endgenerate

    // 3. 放宽的输出匹配：字段彼此不要求命中同一槽，成功消费后不留旧值兜底。
    // [RELAXED] [REF_MODEL] req/arb_addr 联合匹配任一合格待发地址；不检查五项窗口和最老选择。
    A_L_COMMAND_ANY: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|req) |-> command_hit
    );

    // [RELAXED] [REF_MODEL] rid 匹配该源九项未消费 ID 中任一项，重复 ID 每次只消费一个。
    A_L_RID_ANY: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> id_hit
    );

    // [RELAXED] [REF_MODEL] port_id 独立匹配该源字段集合，可以与 rid 命中不同命令。
    A_L_RPORT_ANY: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> port_hit
    );

    // [RELAXED] [REF_MODEL] raddr 独立匹配该源低地址集合，不证明单源顺序。
    A_L_RADDR_ANY: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> low_addr_hit
    );

    // [RELAXED] [REF_MODEL] 128 位 rdata 逐项比较九项有效数据，任一项相同即通过，不绑定 XAU。
    A_L_RDATA_ANY: assert property (
        @(posedge clk) disable iff (!rst_n)
        (|rvalid) |-> data_hit
    );

    // [RELAXED] [REF_MODEL] 00 要求仍有可能消费一个 pc=0 的返回，不绑定本拍 rdata。
    A_L_PC_CLEAN_POSSIBLE: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((|rvalid) && rresp==2'b00) |-> bad_low<completed
    );

    // [RELAXED] [REF_MODEL] 01 要求仍有可能消费一个 pc=1 的返回；11 可遮住任意 pc。
    A_L_PC_BAD_POSSIBLE: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((|rvalid) && rresp==2'b01) |-> bad_high!=0
    );

    // 4. 模型自检：容量和更新守恒；不能把这些 assert 改为 assume 掩盖 DUT 错误。
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

    // 5. 业务见证：cover 命中不代表保序/窗口/RR 已证明，也不增加任何引导假设。
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

endmodule
`default_nettype wire
