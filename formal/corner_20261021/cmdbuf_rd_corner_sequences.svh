// 以下状态只跟踪较长 cover 的发生过程，不是 DUT 或约束。
// 所有启动、推进都由真实握手或端口推导的事务记录触发；没有 cover implication。
    reg [3:0] h_prev_due_slot;
    reg [8:0] h_failed_once,h_failed_before_success;
    reg [1:0] h_rr012_phase,h_error_sandwich_phase;
    reg h_rr_gap_seen,h_seen_reject,h_seen_partial_ready;
    reg [17:0] h_prev_raddr_full;
    reg h_hotspot;
    integer hs,h_same_bank_count;
    always @* begin
        h_same_bank_count=0;
        for(hs=0;hs<9;hs=hs+1)
            if(pending[hs] && m_addr[hs][5:3]==m_addr[m_attempt_e][5:3])
                h_same_bank_count=h_same_bank_count+1;
        h_hotspot=h_same_bank_count>=3;
    end
    integer hf;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            h_prev_due_slot<=0;h_failed_once<=0;h_failed_before_success<=0;
            h_rr012_phase<=0;h_error_sandwich_phase<=0;
            h_rr_gap_seen<=0;h_seen_reject<=0;h_seen_partial_ready<=0;h_prev_raddr_full<=0;
        end else begin
            h_prev_due_slot<=mem_capture_slot;
            if(r_fire) h_prev_raddr_full<=m_addr[rsp_e];
            if(req!=0&&!issue_fire) h_seen_reject<=1;
            if(rready!=0&&rready!=7) h_seen_partial_ready<=1;
            for(hf=0;hf<9;hf=hf+1) begin
                if(ar_fire&&alloc_e==hf) begin
                    h_failed_once[hf]<=0;h_failed_before_success[hf]<=0;
                end else begin
                    if(m_attempt&&m_attempt_e==hf&&!issue_fire) h_failed_once[hf]<=1;
                    if(issue_fire&&m_attempt_e==hf) h_failed_before_success[hf]<=h_failed_once[hf];
                end
            end
            // 连续三拍三源都可响应：第一次 RR 从 0 选择，随后 1、2。
            case(h_rr012_phase)
                0: if(m_rr==0&&eligible==7&&rvalid==1)h_rr012_phase<=1;
                1: h_rr012_phase<=(eligible==7&&rvalid==2)?2'd2:2'd0;
                default: h_rr012_phase<=0;
            endcase
            // 至少一次 R 之后插入无响应拍，随后再响应。起点正确性由 A_RR_CHOICE 检查。
            if(r_fire)h_rr_gap_seen<=0;
            else if(h_prev_r)h_rr_gap_seen<=1;
            // XAU0 三次真实响应为正常/错误/正常；每次均核对全负载。
            // 由于 A_XAU_R_* 检查接收顺序，这三次响应对应同源 AR 的相邻三项。
            if(rvalid[0]) begin
                case(h_error_sandwich_phase)
                    0: if(h_response_matches&&rresp==0) h_error_sandwich_phase<=1;
                    1: h_error_sandwich_phase<=(h_response_matches&&rresp!=0)?2'd2:2'd0;
                    default:h_error_sandwich_phase<=0;
                endcase
            end
        end
    end
