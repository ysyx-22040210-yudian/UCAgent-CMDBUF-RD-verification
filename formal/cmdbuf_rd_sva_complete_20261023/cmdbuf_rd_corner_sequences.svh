// 以下状态只跟踪较长 cover 的发生过程，不是 DUT 或约束。
// 所有启动、推进都由真实握手或端口推导的事务记录触发；没有 cover implication。
    reg [3:0] h_prev_due_slot; // 上一采样拍四拍 MEM 日历到期槽号，配合 h_prev_m 使用。
    reg [8:0] h_failed_once; // 各事务是否已出现至少一次仲裁失败，新 AR 复用该槽时清零。
    reg [8:0] h_failed_before_success; // 各事务成功发射时记录其此前是否曾仲裁失败。
    reg [1:0] h_rr012_phase; // 连续三源响应 0/1/2 的覆盖阶段：0 等 0，1 等 1，2 等 2。
    reg [1:0] h_error_sandwich_phase; // XAU0 正常/错误/正常相邻响应的覆盖阶段 0/1/2。
    reg h_rr_gap_seen; // 一次 R 之后是否已出现无响应间隙，下一次 R 后清零。
    reg h_seen_reject; // 是否曾出现有 req 但仲裁失败，供后续恢复场景 cover。
    reg h_seen_partial_ready; // 是否曾出现部分而非全部来源 rready 有效。
    reg [17:0] h_prev_raddr_full; // 最近一次真实 R 返回事务的原始完整地址。
    wire h_hotspot;                        // 至少三条待发命令访问当前请求所在 Bank。
    wire signed [31:0] h_same_bank_count;   // pending 中与 m_attempt_e 的 Bank 相同的条数。
    wire signed [31:0] h_bank_prefix [0:9]; // 扫描前 k 个槽得到的同 Bank 待发条数。
    genvar hs;                             // 编译展开用的逻辑槽扫描索引。
    // 只比较 Bank [5:3]，不比较 half；描述热点覆盖，不改变窗口或发射候选。
    // 扫描起点同 Bank 的待发条数为 0，仅为本拍组合统计的初值。
    assign h_bank_prefix[0] = 0;
    generate for (hs=0; hs<9; hs=hs+1) begin : history_bank_count
        // 当前槽仍在 pending，且地址 Bank 位 [5:3] 等于当前请求事务的 Bank 时加 1；奇偶半区不同也算同 Bank。
        assign h_bank_prefix[hs+1] = h_bank_prefix[hs] +
            ((pending[hs] && m_addr[hs][5:3]==m_addr[m_attempt_e][5:3]) ? 32'sd1 : 32'sd0);
    end endgenerate
    // 扫描完九槽后得到热点条数，包含待发集合中所有同 Bank 项，不限于五项窗口。
    assign h_same_bank_count = h_bank_prefix[9];
    // 同 Bank 待发条数达到 3 即标记热点场景；这是 cover 的业务条件，不用于控制发射或限制输入。
    assign h_hotspot = h_same_bank_count>=3;
    integer hf; // 时序循环的槽索引，用于记录失败及失败后成功。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            h_prev_due_slot<=0;h_failed_once<=0;h_failed_before_success<=0;
            h_rr012_phase<=0;h_error_sandwich_phase<=0;
            h_rr_gap_seen<=0;h_seen_reject<=0;h_seen_partial_ready<=0;h_prev_raddr_full<=0;
        end else begin
            // 保存本拍到期槽号；下拍需结合 h_prev_m 才能判断它是否对应有效 MEM 返回。
            h_prev_due_slot<=mem_capture_slot;
            // 仅 R 真正完成时更新最近返回地址，后续可比较相邻返回事务的地址关系。
            if(r_fire) h_prev_raddr_full<=m_addr[rsp_e];
            // 任意一次有请求但未成功即可留下失败历史，后续 cover 可以寻找失败后的恢复。
            if(req!=0&&!issue_fire) h_seen_reject<=1;
            // 记录曾经出现部分来源 ready 的拍，供有选择地跳过通道等业务见证使用。
            if(rready!=0&&rready!=7) h_seen_partial_ready<=1;
            for(hf=0;hf<9;hf=hf+1) begin
                // 槽复用意味着新的事务开始，旧事务的失败历史不能继承到新命令。
                if(ar_fire&&alloc_e==hf) begin
                    h_failed_once[hf]<=0;h_failed_before_success[hf]<=0;
                end else begin
                    // 当前 C3 请求属于该槽且仲裁失败，则为这个事务留下“曾失败”标记。
                    if(m_attempt&&m_attempt_e==hf&&!issue_fire) h_failed_once[hf]<=1;
                    // 成功当拍冻结此前的失败标记，之后 MEM/R 阶段仍能见证“失败后重试成功”。
                    if(issue_fire&&m_attempt_e==hf) h_failed_before_success[hf]<=h_failed_once[hf];
                end
            end
            // 连续三拍三源都可响应：第一次 RR 从 0 选择，随后 1、2。
            case(h_rr012_phase)
                // 起点必须是 0、三源都 eligible 且实际返回 XAU0，才开始这条连续响应见证。
                0: if(m_rr==0&&eligible==7&&rvalid==1)h_rr012_phase<=1;
                // 紧接下一拍仍三源 eligible 且返回 XAU1 才推进，否则重新寻找完整序列。
                1: h_rr012_phase<=(eligible==7&&rvalid==2)?2'd2:2'd0;
                // 阶段 2 的当前拍由 cover 检查 XAU2 响应，沿后回到起点等待下一次见证。
                default: h_rr012_phase<=0;
            endcase
            // 至少一次 R 之后插入无响应拍，随后再响应。起点正确性由 A_RR_CHOICE 检查。
            if(r_fire)h_rr_gap_seen<=0;
            else if(h_prev_r)h_rr_gap_seen<=1;
            // XAU0 三次真实响应为正常/错误/正常；每次均核对全负载。
            // 由于 A_XAU_R_* 检查接收顺序，这三次响应对应同源 AR 的相邻三项。
            if(rvalid[0]) begin
                case(h_error_sandwich_phase)
                    // 先遇到一条负载完全正确、状态正常的 XAU0 响应，开始跟踪相邻三次响应。
                    0: if(h_response_matches&&rresp==0) h_error_sandwich_phase<=1;
                    // 下一次 XAU0 响应必须负载正确且有错误状态，否则本次“正常/错误/正常”序列中止。
                    1: h_error_sandwich_phase<=(h_response_matches&&rresp!=0)?2'd2:2'd0;
                    // 阶段 2 的当前响应由 cover 检查末尾正常项，沿后重新开始；其他来源的响应不推进该阶段。
                    default:h_error_sandwich_phase<=0;
                endcase
            end
        end
    end
