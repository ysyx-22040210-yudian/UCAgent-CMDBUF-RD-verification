// 简化模型：只记录端口事件、数量和“尚未消费的值”，没有年龄排序、窗口或 RR 状态。
// 五个九项集合彼此独立，槽号之间没有事务对应关系：
//   command：AR 地址 -> 成功 req；id/port/low_addr：AR 字段 -> 相同来源 R 字段；
//   data：成功后第 4 拍的 MEM 数据 -> 任意来源 R 数据。
// 每个 R 字段可以匹配不同槽，故本版本不证明字段配对、单 XAU 保序或跨源数据归属。
// 只使用顶层端口；组合逻辑全部用 assign，always 只保存跨拍历史。

    wire ar_fire; // 本拍真正接收 AR，而非仅看到 arvalid。
    wire issue_fire; // req 与两个 grant 在同一 Bank 位成功。
    wire r_fire; // 本拍 R 被上游实际接收。
    wire [1:0] r_src; // 独热 rvalid 指定的来源；非法多位由端口断言单独报告。
    wire [2:0] req_bank; // 独热 req 指定的 Bank；req=0 时默认值不参加比较。
    // 有效且 src 合法，并且对应 ready 位为 1，才计为 AR 接收。
    assign ar_fire = arvalid && src<2'd3 && ((src<2'd3) ? arready[src] : 1'b0);
    // 两个 grant 必须与 req 同位，不能跨 Bank 拼接。
    assign issue_fire = |(req & ar_rd_gnt & rw_rd_gnt);
    // 只按实际 R 握手减少数量或消费模型记录。
    assign r_fire = |(rvalid & rready);
    // 合法独热输入时得到唯一来源；全零时的默认 0 无业务含义。
    assign r_src = rvalid[2] ? 2'd2 : (rvalid[1] ? 2'd1 : 2'd0);
    // 这是简单编码器，不是 Bank 仲裁器；多位 req 由 A_L_REQ_ONEHOT 禁止。
    assign req_bank = req[7] ? 3'd7 : req[6] ? 3'd6 : req[5] ? 3'd5 :
                      req[4] ? 3'd4 : req[3] ? 3'd3 : req[2] ? 3'd2 :
                      req[1] ? 3'd1 : 3'd0;

    // 1. 精确数量账本：AR/R 占用、AR/成功发射待发数、MEM/R 已返回数据量。
    reg [4:0] occupied [0:2]; // 各 XAU 的累计 AR 接收减累计 R 回收，合法值 0..7。
    reg [4:0] outside [0:2]; // 各源未消费的“AR 地址越界”标记数；按 R 的 11 消费。
    reg [4:0] waiting; // 拍初累计 AR 减成功发射，不使用 DUT 的 pending_cnt 反馈更新。
    reg [4:0] completed; // 拍初累计有效 MEM 捕获减实际 R；不区分数据来源。
    reg [3:0] due; // 四拍成功历史；due[3] 对应成功拍 N 的 N+4 返回。
    wire mem_due; // 本拍是否应捕获 MEM 数据和 pc_err，不能用当前 req 代替。
    wire [5:0] pending_now; // 含本拍 AR 和成功发射的精确待发数量，额外位防止下溢被掩盖。
    wire [6:0] total; // 三源拍初总占用，宽度覆盖非法状态，便于断言发现错误。
    wire [4:0] after_r [0:2]; // 扣除本拍该源 R 后的占用，用来精确计算 arready。
    wire [4:0] shared_part [0:2]; // 每源超过首项保留空间的占用。
    wire [6:0] total_after_r; // 本拍 R 回收后的总占用。
    wire [6:0] shared_after_r; // 本拍 R 回收后占用的六项共享预算。
    wire [2:0] expected_ready; // 三源接收许可；允许多个位同时为 1。
    wire [4:0] reserve_part [0:2]; // 每个空源也按 1 项计入预算，检查首项预留。
    wire [6:0] reserved_total; // 三源已占用加空源首项预留的总预算。
    genvar s; // 生成三个来源的准入和错误标记检查。
    // 成功事件移位四次后才解释 MEM 输入，其余拍 MEM 的数值不进入集合。
    assign mem_due = due[3];
    // pending_cnt 是组合输出，本拍新接收加一、本拍双 grant 成功减一。
    assign pending_now = {1'b0,waiting} + {5'b0,ar_fire} - {5'b0,issue_fire};
    // 三源数量独立累计后求和；没有按输出字段寻找事务的复杂逻辑。
    assign total = {2'b0,occupied[0]} + {2'b0,occupied[1]} + {2'b0,occupied[2]};
    generate for (s=0; s<3; s=s+1) begin : admission
        // 本拍该源真正响应才释放其占用；未 ready 的 rvalid 不释放。
        assign after_r[s] = occupied[s] - {4'b0,(rvalid[s] && rready[s])};
        // 每源第一项使用自身保留空间，其余项使用六项共享空间。
        assign shared_part[s] = after_r[s]!=0 ? after_r[s]-5'd1 : 5'd0;
        // 有物理空位且没有占用其他空源预留项时才允许继续接收。
        assign expected_ready[s] = rst_n && total_after_r<7'd9 &&
                                   (after_r[s]==0 || shared_after_r<7'd6);
        // 即使来源当前为空，也保留一项；7/0/0 合法，8/0/0 和 5/4/0 不合法。
        assign reserve_part[s] = occupied[s]==0 ? 5'd1 : occupied[s];
    end endgenerate
    // 准入先扣本拍 R，从而支持满九项时的 AR/R 同进同出。
    assign total_after_r = {2'b0,after_r[0]} + {2'b0,after_r[1]} + {2'b0,after_r[2]};
    // 共享预算总共六项，另有每个来源的一项保留。
    assign shared_after_r = {2'b0,shared_part[0]} + {2'b0,shared_part[1]} + {2'b0,shared_part[2]};
    // 拍初预算只用于检查容量规则，不参与值匹配。
    assign reserved_total = {2'b0,reserve_part[0]} + {2'b0,reserve_part[1]} + {2'b0,reserve_part[2]};

    // 2. 待发地址集合：保存 araddr[17:3]，成功才消费，失败保留。
    wire [8:0] command_valid; // 已接收且尚未成功发射的地址记录。
    wire [14:0] command_value [0:8]; // 每项为 {araddr[17:6],araddr[5:3]}。
    wire [8:0] command_match; // 本拍 req/arb_addr 命中的地址项，含历史空闲资格。
    wire command_hit; // 请求是否至少匹配一条有资格的待发地址。
    wire command_room; // 同拍成功删除后，是否有地方保存新 AR。
    wire [8:0] command_pop; // 本拍成功发射消费的一个地址项。
    wire [8:0] command_push; // 本拍 AR 分配的一个地址项。
    wire [3:0] command_count; // 地址集合项数，应等于 waiting。
    reg [8:0] command_eligible; // 每项上一拍已存在且其半区空闲；不是五项窗口命中位。
    wire [8:0] command_idle; // 每条已记录地址所选 Bank/half 的本拍空闲状态。
    genvar c; // 展开九条地址的状态查找。
    generate for (c=0; c<9; c=c+1) begin : command_status
        // key[2:0] 是原地址 [5:3]，key[3] 是原地址 [6]；保持 Bank-major 二维访问。
        assign command_idle[c] = !rd_mem_status[command_value[c][2:0]][command_value[c][3]];
    end endgenerate
    cmdbuf_rd_value_bag #(.WIDTH(15)) command_bag (
        .clk(clk), .rst_n(rst_n), .push(ar_fire), .push_value(araddr[17:3]),
        .pop(issue_fire), .query_value({arb_addr,req_bank}), .qualify(command_eligible),
        .valid(command_valid), .value(command_value), .match_mask(command_match),
        .hit(command_hit), .room(command_room), .pop_slot(command_pop),
        .push_slot(command_push), .count(command_count)
    );

    // 3. 三个来源字段集合：各自独立消费。相同源、相同字段值的重复项也分别计数。
    wire id_hit, port_hit, low_addr_hit; // rid、r_port_id、raddr 各自在九项中是否匹配。
    wire id_room, port_room, low_addr_room; // 三个集合本拍是否可接收新 AR 字段。
    wire [3:0] id_count, port_count, low_addr_count; // 三个集合的有效数量，应各自等于 total。
    cmdbuf_rd_value_bag #(.WIDTH(10)) id_bag (
        .clk(clk), .rst_n(rst_n), .push(ar_fire), .push_value({src,arid}),
        .pop(r_fire), .query_value({r_src,rid}), .qualify(9'h1ff),
        .hit(id_hit), .room(id_room), .count(id_count),
        .valid(), .value(), .match_mask(), .pop_slot(), .push_slot()
    );
    cmdbuf_rd_value_bag #(.WIDTH(7)) port_bag (
        .clk(clk), .rst_n(rst_n), .push(ar_fire), .push_value({src,ar_port_id}),
        .pop(r_fire), .query_value({r_src,r_port_id}), .qualify(9'h1ff),
        .hit(port_hit), .room(port_room), .count(port_count),
        .valid(), .value(), .match_mask(), .pop_slot(), .push_slot()
    );
    cmdbuf_rd_value_bag #(.WIDTH(5)) low_addr_bag (
        .clk(clk), .rst_n(rst_n), .push(ar_fire), .push_value({src,araddr[2:0]}),
        .pop(r_fire), .query_value({r_src,raddr}), .qualify(9'h1ff),
        .hit(low_addr_hit), .room(low_addr_room), .count(low_addr_count),
        .valid(), .value(), .match_mask(), .pop_slot(), .push_slot()
    );

    // 4. 数据集合：仅到期 MEM 数据入集合，每次实际 R 删除一个相等值。
    // 不限制数据属于哪个 XAU/ID；但不保留已消费旧数据，也不比较本拍尚未入库的 MEM 数据。
    wire data_hit; // rdata 是否等于任一有效的已捕获数据。
    wire data_room; // 捕获 MEM 时是否有可用槽，包括本拍 R 消费槽。
    wire [8:0] data_match; // 九项 rdata 比较结果，便于波形定位命中了哪些重复数据。
    wire [3:0] data_count; // 已捕获且尚未被 R 消费的数据项数。
    cmdbuf_rd_value_bag #(.WIDTH(128)) data_bag (
        .clk(clk), .rst_n(rst_n), .push(mem_due), .push_value(mem_rdata),
        .pop(r_fire), .query_value(rdata), .qualify(9'h1ff),
        .hit(data_hit), .room(data_room), .count(data_count), .match_mask(data_match),
        .valid(), .value(), .pop_slot(), .push_slot()
    );

    // 5. 错误状态采用数量范围，不把 pc_err 绑定到某条命令或某个数据值。
    // bad_low..bad_high 表示“尚未消费的 MEM 返回中，pc_err=1 的可能数量”。
    // 00 消费一个 pc=0；01 消费一个 pc=1；11 的优先级遮住 pc，故可能消费 0 或 1。
    // 不能在 11 时任意固定删除某个 pc 值，否则相同数据/不同 pc 的合法轨迹会被误报。
    reg [4:0] bad_low; // 仍在集合的 pc=1 数量下界。
    reg [4:0] bad_high; // 仍在集合的 pc=1 数量上界。
    wire [4:0] completed_after_r; // 本拍 R 消费之后、MEM 新捕获之前的数据项数。
    wire [4:0] bad_low_after_r; // 本拍响应消费后 pc=1 数量下界。
    wire [4:0] bad_high_after_r; // 本拍响应消费后 pc=1 数量上界。
    wire captured_bad; // 本拍到期数据携带 pc_err=1，需要给上下界各加一。
    // 使用拍初 completed，当前 MEM 数据尚不能为当前 R 提供消费资格。
    assign completed_after_r = completed - {4'b0,r_fire};
    // 01 必须删一个坏标记；11 可能删坏标记。下界最多减一，最小为零。
    assign bad_low_after_r = r_fire && rresp!=2'b00 && bad_low!=0 ? bad_low-5'd1 : bad_low;
    // 01 的上界也减一；00 或 11 的上界不能大于消费后剩余总量。
    assign bad_high_after_r = !r_fire ? bad_high :
        (rresp==2'b01 ? (bad_high!=0 ? bad_high-5'd1 : 5'd0) :
                       (bad_high>completed_after_r ? completed_after_r : bad_high));
    // 非到期拍的 pc_err 不计入错误历史。
    assign captured_bad = mem_due && pc_err;

    integer i; // 时序更新循环索引，仅用于已有计数和九项资格位。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            waiting<=0; completed<=0; due<=0; command_eligible<=0;
            bad_low<=0; bad_high<=0;
            for (i=0; i<3; i=i+1) begin occupied[i]<=0; outside[i]<=0; end
        end else begin
            // 不把 started/active 或复位序列 assume 引入本模型。
            waiting <= pending_now[4:0];
            completed <= completed_after_r + {4'b0,mem_due};
            due <= {due[2:0],issue_fire};
            bad_low <= bad_low_after_r + {4'b0,captured_bad};
            bad_high <= bad_high_after_r + {4'b0,captured_bad};
            for (i=0; i<3; i=i+1) begin
                // AR 接收与同源 R 可同拍发生，两个事件相抵后数量不变。
                occupied[i] <= after_r[i] + {4'b0,(ar_fire && src==i)};
                // 只按该源的 11 响应消费越界标记；标记不与 rid/rdata 建立配对。
                outside[i] <= outside[i] + {4'b0,(ar_fire && src==i && arresp==2'b11)}
                                            - {4'b0,(r_fire && r_src==i && rresp==2'b11)};
            end
            for (i=0; i<9; i=i+1) begin
                // C1 新写入尚未经过 C2，不许立即作为下一采样拍请求；新写入优先于复用旧资格。
                if (command_push[i]) command_eligible[i] <= 1'b0;
                // C2 保存空闲观察；当前失败项仍有效，允许同拍重选后下一拍再次请求。
                else command_eligible[i] <= command_valid[i] && !command_pop[i] && command_idle[i];
            end
        end
    end

    // 6. 少量跨拍 cover 历史：不增加环境约束，也不参与集合或期望输出计算。
    reg previous_r; // 上一拍是否 R 握手，用于连续响应见证。
    reg previous_issue; // 上一拍是否成功发射，用于连续成功见证。
    reg previous_failure; // 上一拍有 req 但双 grant 失败。
    reg [14:0] previous_request; // 上一拍 {arb_addr,Bank}，用于同地址紧邻重试见证。
    reg [4:0] accept_saturated; // 累计接收数，饱和在 16，见证超过九次生命周期周转。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_r<=0; previous_issue<=0; previous_failure<=0;
            previous_request<=0; accept_saturated<=0;
        end else begin
            previous_r<=r_fire; previous_issue<=issue_fire;
            previous_failure<=|req && !issue_fire;
            previous_request<={arb_addr,req_bank};
            if (ar_fire && accept_saturated<5'd16) accept_saturated<=accept_saturated+5'd1;
        end
    end
