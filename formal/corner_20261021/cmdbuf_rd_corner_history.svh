// Corner 检查辅助记录。只读取本检查器的顶层端口和既有参考表，不读取 DUT 内部。
// h_occ / h_*_history 是端口历史；其余使用 m_* 的记录明确依赖参考模型。
// 所有历史只帮助描述跨拍条件，不是 assume，不限制输入，也不为 DUT 产生驱动。

    // 【独立容量账本】只在真实 AR/R 握手时加减，不按预期 R、发射或 MEM 修改。
    // 使用 5 位，错误的第 8 次入队或空队列出队不会在 0..7 内静默回绕。
    reg [4:0] h_occ [0:2]; // 每源真实 AR 接收数减真实 R 返回数；5 位可暴露超额接收或下溢。
    wire signed [31:0] h_total;             // 三源真实 AR-R 历史累计的总占用。
    wire signed [31:0] h_budget;            // 空源仍计 1 项预留后的总预算。
    wire signed [31:0] h_after_total;       // 扣除本拍真实 R 后的总占用。
    wire signed [31:0] h_shared_after;      // 扣真实 R 后，三源超过首项的共享占用。
    wire signed [31:0] h_after [0:2];       // 每源 h_occ 扣本拍该源真实 R 的结果。
    wire signed [31:0] h_quota_part [0:2];  // 每源实际占用或首项预留，至少为 1。
    wire signed [31:0] h_shared_part [0:2]; // 每源扣 R 后的共享预算消耗。
    wire [2:0] h_ready;                     // 独立历史账本计算的 AR 接收许可。
    genvar hi;                              // 编译展开用的来源编号，与时序循环 hx 分离。
    // 用真实握手账本计算 ready，独立于 m_live 和 model_retire，可发现参考表共同偏移。
    // 将三源真实握手账本先扩到 32 位再相加，得到独立于参考事务表的总占用。
    assign h_total = {27'd0,h_occ[0]}+{27'd0,h_occ[1]}+{27'd0,h_occ[2]};
    generate for (hi=0; hi<3; hi=hi+1) begin : history_admission
        // 空来源也保留一个名额，非空来源按实际条数计算，供首项预留总预算检查。
        assign h_quota_part[hi] = h_occ[hi]==0 ? 1 : {27'd0,h_occ[hi]};
        // 仅当来源 hi 本拍真实 R 握手时减 1；这里依据 DUT 公开输出，不使用 model_retire 的预测。
        assign h_after[hi] = h_occ[hi] - ((rvalid[hi] && rready[hi]) ? 1 : 0);
        // 扣过 R 后，超过首项的条数才消耗共享容量；剩 0 或 1 条时共享消耗为 0。
        assign h_shared_part[hi] = h_after[hi]>1 ? h_after[hi]-1 : 0;
        // 真实 R 回收后要有物理空间；空来源可用预留项，非空来源还要有共享余量。
        // A_CC_READY 用它独立核对 arready，复位禁用由属性自身的 disable iff 负责。
        assign h_ready[hi] = h_after_total<9 && (h_after[hi]==0 || h_shared_after<6);
    end endgenerate
    // 合计三个来源含首项预留的预算，检查总预算是否超过九项。
    assign h_budget = h_quota_part[0]+h_quota_part[1]+h_quota_part[2];
    // 三源扣除本拍真实 R 后求和，供满载同进同出时的物理空间判断。
    assign h_after_total = h_after[0]+h_after[1]+h_after[2];
    // 将各源扣 R 后的共享消耗相加，供非空来源新增事务的准入判断。
    assign h_shared_after = h_shared_part[0]+h_shared_part[1]+h_shared_part[2];
    integer hx; // 时序循环的来源编号，用于更新独立 AR/R 容量账本。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(hx=0;hx<3;hx=hx+1) h_occ[hx]<=0;
        end else begin
            // 三个来源独立记账：只给 src 匹配且握手的来源加一，只给实际 R 握手的来源减一。
            // 同一来源同时进出时加减抵消；跨来源同时进出时，一个来源加一、另一个减一。
            for(hx=0;hx<3;hx=hx+1)
                h_occ[hx]<=h_occ[hx]+((ar_fire&&src==hx)?5'd1:5'd0)
                                      -((rvalid[hx]&&rready[hx])?5'd1:5'd0);
        end
    end

    // 【上一拍快照】h_prev_* 是上一个采样沿的值，不表示全局 started/active 开关。
    // 对非法历史不会假设它正确；持续正确性始终由 assert 检查。
    reg h_prev_a; // 上一采样拍是否真实接受 AR。
    reg h_prev_i; // 上一采样拍是否双 grant 成功发射。
    reg h_prev_r; // 上一采样拍是否真实 R 握手。
    reg h_prev_m; // 上一采样拍是否四拍 MEM 日历到期。
    reg h_prev_valid; // 上一采样拍 arvalid 的值，包含未握手的有效请求。
    reg h_prev_pc; // 上一采样拍 MEM 的 pc_err 值。
    reg [1:0] h_prev_src; // 上一采样拍 AR src，是否有效由 h_prev_a/h_prev_valid 判定。
    reg [1:0] h_prev_rsrc; // 上一采样拍响应来源编码，配合 h_prev_r 使用。
    reg [1:0] h_prev_rr; // 上一采样拍的参考 RR 起点。
    reg [2:0] h_prev_ready; // 上一采样拍三位 arready 快照。
    reg [2:0] h_prev_rready; // 上一采样拍三位 rready 快照。
    reg [2:0] h_prev_eligible; // 上一采样拍三源队头响应资格快照。
    reg [7:0] h_prev_req; // 上一采样拍下游 Bank 请求向量。
    reg [7:0] h_prev_id; // 上一采样拍 AR ID，配合接受事件使用。
    reg [11:0] h_prev_arb; // 上一采样拍下游请求地址 [17:6]。
    reg [17:0] h_prev_addr; // 上一采样拍完整 AR 地址。
    reg [4:0] h_prev_port; // 上一采样拍 AR port_id。
    reg [127:0] h_prev_mem; // 上一采样拍完整 128 位 MEM 返回数据。
    reg [3:0] h_prev_n; // 上一采样拍参考表全部有效事务数 used。
    reg [3:0] h_prev_p; // 上一采样拍参考表待发数 waiting，未计该拍组合端口的增减。
    reg [3:0] h_prev_occ [0:2]; // 上一采样拍各源参考表占用数。
    reg [15:0] h_prev_status; // 上一采样拍所有 Bank/half 状态，供稳定性比较。
    wire [15:0] h_status; // 仅用于历史比较的状态拼接视图；不改变顶层二维 rd_mem_status 接口。
    // 依 Bank 7 到 Bank 0 拼接，仅作为跨拍状态是否相同的比较值；每个 Bank 的两个半区位均保留。
    assign h_status = {rd_mem_status[7],rd_mem_status[6],rd_mem_status[5],rd_mem_status[4],
                           rd_mem_status[3],rd_mem_status[2],rd_mem_status[1],rd_mem_status[0]};
    // h_status 仅用于历史比较，不改变接口的逐 Bank 二维声明。
    reg [5:0] h_i_history; // 最近六个已采样拍的成功发射记录，bit0 是上一拍。
    reg [5:0] h_a_history; // 最近六个已采样拍的 AR 接受记录，bit0 是上一拍。
    reg [5:0] h_m_history; // 最近六个已采样拍的 MEM 到期记录，bit0 是上一拍。
    reg [6:0] h_single_start; // 最近七拍“空表接收新 AR”事件的移位记录，bit0 是上一拍。
    reg [5:0] h_src_history; // 最近三拍 AR 来源的 2 位编码串，低两位是上一拍，配合 AR 历史使用。
    reg [2:0] h_rsrc_history; // 旧实现保留的三位移位快照；低两位是上一拍 R 来源，高位是再前拍来源编码 bit0。
    reg [2:0] h_pc_history; // 最近三拍 MEM pc_err 快照，bit0 是上一拍，配合到期历史使用。
    reg [2:0] h_ar_sources; // 从记录开始曾真实接收 AR 的来源集合，置位后保持。
    reg [5:0] h_total_a; // 累计真实 AR 接受数，达到 63 后饱和，用于长生命周期 cover。
    reg [5:0] h_total_r; // 累计真实 R 返回数，达到 63 后饱和，用于排空和复用 cover。
    reg [3:0] h_same_ar_run; // 同一 src 连续 AR 握手的拍数，饱和于 15，换源时从 1 重计。
    reg [3:0] h_ar_run; // 连续 AR 握手拍数，饱和于 15，中断即清零。
    reg [3:0] h_r_run; // 连续 R 握手拍数，饱和于 15，中断即清零。
    reg [3:0] h_ar_r_run; // 连续同拍 AR 与 R 握手的拍数，饱和于 15。
    reg [3:0] h_reject_run; // 连续有 req 但双 grant 未成功的拍数，饱和于 15。
    reg [3:0] h_quiet_run; // 连续无 AR/成功发射/R/MEM 到期四类事件的拍数，饱和于 15。
    reg [3:0] h_empty_run; // 参考表连续为空的拍数，饱和于 15。
    reg [3:0] h_notready_run [0:2]; // 各源队头已完成但 rready 为 0 的连续拍数，饱和于 15。
    reg h_ever_full; // 是否曾达到 used==9，置位后保持以见证满载后行为。
    reg h_was_drained; // 是否曾在有过 R 响应后排空，置位后保持。
    integer ht; // 时序循环的来源编号，用于源占用快照及不 ready 计数。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            h_prev_a<=0;h_prev_i<=0;h_prev_r<=0;h_prev_m<=0;h_prev_valid<=0;h_prev_pc<=0;
            h_prev_src<=0;h_prev_rsrc<=0;h_prev_rr<=0;h_prev_ready<=0;h_prev_rready<=0;h_prev_eligible<=0;
            h_prev_req<=0;h_prev_id<=0;h_prev_arb<=0;h_prev_addr<=0;h_prev_port<=0;h_prev_mem<=0;
            h_prev_n<=0;h_prev_p<=0;h_prev_status<=0;
            h_i_history<=0;h_a_history<=0;h_m_history<=0;h_single_start<=0;
            h_src_history<=0;h_rsrc_history<=0;h_pc_history<=0;h_ar_sources<=0;
            h_total_a<=0;h_total_r<=0;h_same_ar_run<=0;h_ar_run<=0;h_r_run<=0;h_ar_r_run<=0;
            h_reject_run<=0;h_quiet_run<=0;h_empty_run<=0;h_ever_full<=0;h_was_drained<=0;
            for(ht=0;ht<3;ht=ht+1) begin h_prev_occ[ht]<=0;h_notready_run[ht]<=0;end
        end else begin
            // 采样四类事件是否发生，下一拍的属性可同时引用“本拍事件”和这些“上拍事件”。
            h_prev_a<=ar_fire;h_prev_i<=issue_fire;h_prev_r<=r_fire;h_prev_m<=mem_capture_due;
            // 有效位、异常位、AR 来源按原值保存；读取是否有意义由相应握手或有效条件限定。
            h_prev_valid<=arvalid;h_prev_pc<=pc_err;h_prev_src<=src;
            // 将独热 R 来源编码为 0/1/2，同时保存 RR 起点，以检查响应后推进和空拍保持。
            h_prev_rsrc<=rvalid[2]?2'd2:(rvalid[1]?2'd1:2'd0);h_prev_rr<=m_rr;
            // 保存准入、上游接收能力和本源队头资格，供相邻两拍的 ready/RR 场景比较。
            h_prev_ready<=arready;h_prev_rready<=rready;h_prev_eligible<=eligible;
            // 分别保存 C3 请求/地址和本拍 AR 的 ID/完整地址；使用时须配合各自通道的有效事件。
            h_prev_req<=req;h_prev_id<=arid;h_prev_arb<=arb_addr;h_prev_addr<=araddr;
            // 数据、port 和两类占用数一起保存；这里没有把 MEM 返回当作 entry 回收事件。
            h_prev_port<=ar_port_id;h_prev_mem<=mem_rdata;h_prev_n<=used;h_prev_p<=waiting;
            // 保存全部半区状态，下一拍可与 h_status 比较，识别状态保持或变化。
            h_prev_status<=h_status;
            // 以下三条分别把本拍发射/接收/MEM 到期事件推入最低位，原有较早记录向高位移动。
            h_i_history<={h_i_history[4:0],issue_fire};
            h_a_history<={h_a_history[4:0],ar_fire};
            h_m_history<={h_m_history[4:0],mem_capture_due};
            // 仅把“空表时真实接收 AR”记为起点，供后续跨多拍跟踪一条命令的完整生命周期。
            h_single_start<={h_single_start[5:0],(ar_fire&&used==0)};
            // 每拍追加两位 AR 来源；是否真的接收该来源，必须结合 h_a_history 一起判断。
            h_src_history<={h_src_history[3:0],src};
            // 沿用原三位存储宽度：低两位保存上拍 R 来源，最高位仅保留再前拍编码的最低位。
            // 它不能单独表示两次完整的来源编码，不作为完整来源序列使用。
            h_rsrc_history<={h_rsrc_history[0],(rvalid[2]?2'd2:(rvalid[1]?2'd1:2'd0))};
            // 每拍记录 pc_err；只有到期历史也有效的拍才对应一次真实 MEM 返回。
            h_pc_history<={h_pc_history[1:0],pc_err};
            if(ar_fire) begin
                // 将本拍来源加入“曾接收过”的集合，不清除此前已出现的来源。
                h_ar_sources<=h_ar_sources|(3'b1<<src);
                // 总接收数到 63 后保持，避免长序列计数回绕影响 cover 判断。
                if(h_total_a!=63) h_total_a<=h_total_a+1'b1;
            end
            // 总返回数同样饱和累计，只统计真正完成的 R 握手。
            if(r_fire && h_total_r!=63) h_total_r<=h_total_r+1'b1;
            // 连续接收每拍加一，断流立即清零；这个计数不要求连续命令属于同一来源。
            if(ar_fire) begin if(h_ar_run!=15)h_ar_run<=h_ar_run+1'b1;end else h_ar_run<=0;
            // 另一个计数只跟踪同来源连续接收：前后拍都握手且 src 相同才延长。
            if(ar_fire && h_prev_a && src==h_prev_src) begin
                if(h_same_ar_run!=15)h_same_ar_run<=h_same_ar_run+1'b1;
            end else h_same_ar_run<=ar_fire?4'd1:4'd0;
            // 连续 R 握手加一；没有响应就清零，用于观察连续输出吞吐。
            if(r_fire) begin if(h_r_run!=15)h_r_run<=h_r_run+1'b1;end else h_r_run<=0;
            // 只有本拍同时 AR 接收和 R 回收才延长同进同出计数，缺任意一个事件即中断。
            if(ar_fire&&r_fire) begin if(h_ar_r_run!=15)h_ar_r_run<=h_ar_r_run+1'b1;end else h_ar_r_run<=0;
            // 有 req 而双 grant 未成功才算一次连续失败；没有请求或成功发射都结束失败串。
            if(req!=0&&!issue_fire) begin if(h_reject_run!=15)h_reject_run<=h_reject_run+1'b1;end else h_reject_run<=0;
            // 四类进展事件均未发生才累计“无进展”拍数；失败的 req 可以仍存在，故不等于所有端口空闲。
            if(!ar_fire&&!issue_fire&&!r_fire&&!mem_capture_due) begin
                if(h_quiet_run!=15)h_quiet_run<=h_quiet_run+1'b1;
            end else h_quiet_run<=0;
            // 当前没有任何未回收事务才累计空表拍数，一旦有占用就归零。
            if(used==0) begin if(h_empty_run!=15)h_empty_run<=h_empty_run+1'b1;end else h_empty_run<=0;
            // 记住曾满九项，便于后续 cover 区分“满载后的行为”和普通空载行为。
            if(used==9) h_ever_full<=1;
            // 只有确实有过 R 返回，随后又变为空表，才记录一次业务排空，初始空表不算。
            if(used==0&&h_total_r>0) h_was_drained<=1;
            for(ht=0;ht<3;ht=ht+1) begin
                // 分源保存上拍参考占用，用于检查同源或跨源同进同出的占用变化。
                h_prev_occ[ht]<=occ[ht];
                // 本源队头已经完成但接收方不 ready 时累计等待；条件解除就清零。
                if(head_valid[ht]&&m_done[head[ht]]&&!rready[ht]) begin
                    if(h_notready_run[ht]!=15)h_notready_run[ht]<=h_notready_run[ht]+1'b1;
                end else h_notready_run[ht]<=0;
            end
        end
    end

    // 按当前待发排名排列的空闲掩码。例如 11010 表示第 2/4/5 项空闲。
    wire [8:0] h_rank_idle;        // 按 pool 排名而非物理槽号排列的 Bank 空闲位图。
    wire [8:0] h_rank_valid;       // 每个 pool 排名位置是否存在有效事务。
    wire h_other_done;            // 是否存在某源的非队头事务已经完成 MEM 捕获。
    wire h_hole_reused;           // 本拍 AR 分配槽之后仍有有效槽，见证中间空洞复用。
    wire h_duplicate_id;          // 本拍 AR 的 ID 是否与任意尚未回收事务相同。
    wire [8:0] h_other_done_mask;  // 按参考槽标记“已完成但不是本源队头”。
    wire [8:0] h_hole_mask;        // 按参考槽标记“本拍分配槽之后仍有有效项”。
    wire [8:0] h_duplicate_mask;   // 按参考槽标记“与本拍 AR 相同 ID”。
    genvar hr;                     // 编译展开的 pool 排名位置 0..8。
    genvar hj;                     // 编译展开的参考槽扫描位置 0..8。
    // 重新排成“第几老”掩码供 cover 描述窗口。相同排名时后扫描槽覆盖 idle，保持原扫描语义。
    generate for (hr=0; hr<9; hr=hr+1) begin : history_rank_map
        wire h_rank_idle_prefix [0:9];  // 前 k 槽映射到排名 hr 的空闲值，后扫描槽可覆盖同排名旧值。
        wire h_rank_valid_prefix [0:9]; // 前 k 槽是否存在排名 hr 的事务；各排名分别展开。
        // 还没扫描任何参考槽时，该排名的空闲比较值先置 0；是否有事务另用 valid 标志区分。
        assign h_rank_idle_prefix[0] = 0;
        // 扫描起点没有发现占据排名 hr 的事务，排名有效标志从 0 开始。
        assign h_rank_valid_prefix[0] = 0;
        for (hj=0; hj<9; hj=hj+1) begin : slots
            // 当前槽 hj 在 pool 且排名正好为 hr 时，把它的 idle 映射到该排名；否则沿用已有值。
            // 若异常状态出现重复排名，保留旧实现的后扫描槽覆盖语义，不通过辅助记录掩盖模型自检失败。
            assign h_rank_idle_prefix[hj+1] = (pool[hj] && ranks[hj]==hr) ?
                                                  idle[hj] : h_rank_idle_prefix[hj];
            // 此前或当前找到过排名 hr 的 pool 事务，就保持该排名有效，不因后面不匹配的槽而清零。
            assign h_rank_valid_prefix[hj+1] = h_rank_valid_prefix[hj] ||
                                                   (pool[hj] && ranks[hj]==hr);
        end
        // 九槽扫描后取最终映射值，使 cover 能按“第几老”描述哪些命令的目标 Bank 空闲。
        assign h_rank_idle[hr] = h_rank_idle_prefix[9];
        // 取最终存在标志，区分“该排名不存在”和“该排名存在但目标忙”这两种情况。
        assign h_rank_valid[hr] = h_rank_valid_prefix[9];
        // 把 hr 当参考槽号，检查它有效且数据已到，同时它不是所属来源的最老事务。
        // 命中表示年轻事务先完成并等待队头，供单源保序场景观察；它不改变 RR 选择。
        assign h_other_done_mask[hr] = m_live[hr] && m_done[hr] &&
                                      head_valid[m_src[hr]] && hr!=head[m_src[hr]];
        // 槽 0 前没有更小槽号；单独展开，避免常量比较被工具当作无效分支警告。
        if (hr==0) begin : first_slot
            // 槽 0 前不存在更小编号的分配位置，因此它永远不能作为“新分配槽之后仍有效”的见证槽。
            assign h_hole_mask[hr] = 1'b0;
        end else begin : later_slot
            // 本拍 AR 分配槽号比某个仍有效的槽更小，说明复用了参考表前部的空洞，而非只在末尾追加。
            assign h_hole_mask[hr] = ar_fire && m_live[hr] && hr>alloc_e;
        end
        // 本拍新 AR 与任一尚未回收参考事务的 ID 相同时置位，用于见证重复 ID 业务。
        assign h_duplicate_mask[hr] = ar_fire && m_live[hr] && m_id[hr]==arid;
    end endgenerate
    // 任一参考槽属于“已完成非队头”就置位；这是存在性观察，不授权该事务提前返回。
    assign h_other_done = |h_other_done_mask;
    // 任一较高编号槽仍有效且本拍分配了更低槽号，就标记本次空洞复用见证。
    assign h_hole_reused = |h_hole_mask;
    // 任一有效参考槽的 ID 与本拍 AR 相同，就标记重复 ID 场景，不把重复 ID 当作非法输入。
    assign h_duplicate_id = |h_duplicate_mask;
    // 跟踪一次等待、失败重选、槽位重新使用。token 都是参考表身份，绝不是物理地址要求。
    reg [3:0] h_done_wait [0:8]; // 各槽已完成但尚未真实 R 回收的持续拍数，饱和于 15。
    reg [8:0] h_retired_bad; // 各槽最近一次回收是否同时携带 pc_err 和全 1 数据，供残留检测 cover。
    reg [8:0] h_clean_reuse; // 各槽本次新 AR 是否复用了上述错误/全 1 数据旧槽，保存复用见证。
    integer he; // 时序循环的参考槽索引，用于完成等待及槽复用记录。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            h_retired_bad<=0;h_clean_reuse<=0;
            for(he=0;he<9;he=he+1)h_done_wait[he]<=0;
        end else begin
            for(he=0;he<9;he=he+1) begin
                // 已完成、仍有效且本拍没有 R 回收该槽时，累计其在 OTB 中继续等待的拍数。
                if(m_live[he]&&m_done[he]&&!(r_fire&&rsp_e==he)) begin
                    if(h_done_wait[he]!=15)h_done_wait[he]<=h_done_wait[he]+1'b1;
                end else h_done_wait[he]<=0;
                // 回收时记录旧事务是否恰为“pc_err=1 且数据全 1”，供后续复用残留场景构造见证。
                if(r_fire&&rsp_e==he) h_retired_bad[he]<=m_pc[he] && (&m_data[he]);
                // 新 AR 复用槽时，既检查此前留下的回收标记，也检查本拍边回收边复用的旧事务。
                // 后一项使用当前沿更新前的 m_pc/m_data，防止漏掉同拍回收的特殊数据。
                if(ar_fire&&alloc_e==he) h_clean_reuse[he]<=h_retired_bad[he] ||
                    (r_fire&&rsp_e==he&&m_pc[he]&&(&m_data[he]));
            end
        end
    end
    wire h_response_matches; // 本拍真实 R 的对象及五类负载均与参考队头一致，供业务 cover 使用。
    // 要求真实 R 握手、接收来源与预期一致，再逐组比较地址低位、ID、port、数据及错误状态。
    // 只有这些条件同时成立才记录一次正确响应的业务见证，防止仅 ID 碰巧相同就算通过。
    assign h_response_matches = r_fire && rvalid==expected_rvalid &&
        {raddr,rid,r_port_id,rdata,rresp}=={m_addr[rsp_e][2:0],m_id[rsp_e],m_port[rsp_e],m_data[rsp_e],expected_resp};

    // C2 选择条件快照，供下一拍 req 见证；失败不转移年龄，成功才补第六项。
    reg h_failed_none; // 上拍请求失败、目标半区忙，且同拍未选中任何下一条命令。
    reg h_failed_other; // 上拍请求失败、目标半区忙，且同拍选中了另一条命令。
    reg h_blocked_prev; // 上一采样拍 blocked_six 的值，见证五项窗口持续受阻。
    reg h_selected_prev; // 上一采样拍 C2 是否预选出下一条命令。
    reg h_accepted_empty; // 上一采样拍是否从空表接受了一条 AR。
    reg [7:0] h_selected_req; // 上拍 C2 选中命令应在本拍 C3 发出的 Bank 请求位图。
    reg [11:0] h_selected_addr; // 上拍 C2 选中命令的地址 [17:6]，供本拍 C3 比较。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            h_failed_none<=0;h_failed_other<=0;h_blocked_prev<=0;h_selected_prev<=0;
            h_accepted_empty<=0;h_selected_req<=0;h_selected_addr<=0;
        end else begin
            // 当前请求失败、目标半区已忙且没有别的预选项，记为下一拍应无新请求的场景条件。
            h_failed_none<=m_attempt&&!issue_fire&&!idle[m_attempt_e]&&!select_valid;
            // 当前失败项目标忙，但另一个槽被预选，记为下一拍改发其他命令的场景条件。
            h_failed_other<=m_attempt&&!issue_fire&&!idle[m_attempt_e]&&select_valid&&select_e!=m_attempt_e;
            // 保存五项窗口受阻条件，下一拍可检查仍受阻时窗外命令不会越过窗口。
            h_blocked_prev<=blocked_six;
            // 保存本拍是否有 C2 结果，和下面的 req/地址快照组成下一拍 C3 的对照信息。
            h_selected_prev<=select_valid;
            // 将 C2 事务的 Bank 位提前译成独热请求；未选中则保存全 0。
            h_selected_req<=select_valid?(8'b1<<m_addr[select_e][5:3]):8'd0;
            // 保存同一个 C2 事务的地址 [17:6]；仅 h_selected_prev 有效时比较这个负载。
            h_selected_addr<=m_addr[select_e][17:6];
            // 记录空表第一次接受 AR，随后可以检查 C1/C2/C3 最快三拍路径。
            h_accepted_empty<=ar_fire&&used==0;
        end
    end
