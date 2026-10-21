// Corner 检查辅助记录。只读取本检查器的顶层端口和既有参考表，不读取 DUT 内部。
// h_occ / h_*_history 是端口历史；其余使用 m_* 的记录明确依赖参考模型。
// 所有历史只帮助描述跨拍条件，不是 assume，不限制输入，也不为 DUT 产生驱动。

    // 【独立容量账本】只在真实 AR/R 握手时加减，不按预期 R、发射或 MEM 修改。
    // 使用 5 位，错误的第 8 次入队或空队列出队不会在 0..7 内静默回绕。
    reg [4:0] h_occ [0:2];
    integer h_total, h_budget, h_after_total, h_shared_after;
    integer h_after [0:2];
    reg [2:0] h_ready;
    integer hi;
    always @* begin
        h_total=0; h_budget=0; h_after_total=0; h_shared_after=0;
        for(hi=0;hi<3;hi=hi+1) begin
            h_total=h_total+h_occ[hi];
            h_budget=h_budget+((h_occ[hi]==0)?1:h_occ[hi]);
            h_after[hi]=h_occ[hi]-((rvalid[hi]&&rready[hi])?1:0);
            h_after_total=h_after_total+h_after[hi];
            if(h_after[hi]>1) h_shared_after=h_shared_after+h_after[hi]-1;
        end
        for(hi=0;hi<3;hi=hi+1)
            h_ready[hi]=(h_after_total<9) && (h_after[hi]==0 || h_shared_after<6);
    end
    integer hx;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(hx=0;hx<3;hx=hx+1) h_occ[hx]<=0;
        end else begin
            for(hx=0;hx<3;hx=hx+1)
                h_occ[hx]<=h_occ[hx]+((ar_fire&&src==hx)?5'd1:5'd0)
                                      -((rvalid[hx]&&rready[hx])?5'd1:5'd0);
        end
    end

    // 【上一拍快照】h_prev_* 是上一个采样沿的值，不表示全局 started/active 开关。
    // 对非法历史不会假设它正确；持续正确性始终由 assert 检查。
    reg h_prev_a,h_prev_i,h_prev_r,h_prev_m,h_prev_valid,h_prev_pc;
    reg [1:0] h_prev_src,h_prev_rsrc,h_prev_rr;
    reg [2:0] h_prev_ready,h_prev_rready,h_prev_eligible;
    reg [7:0] h_prev_req,h_prev_id;
    reg [11:0] h_prev_arb;
    reg [17:0] h_prev_addr;
    reg [4:0] h_prev_port;
    reg [127:0] h_prev_mem;
    reg [3:0] h_prev_n,h_prev_p;
    reg [3:0] h_prev_occ [0:2];
    reg [15:0] h_prev_status;
    wire [15:0] h_status={rd_mem_status[7],rd_mem_status[6],rd_mem_status[5],rd_mem_status[4],
                           rd_mem_status[3],rd_mem_status[2],rd_mem_status[1],rd_mem_status[0]};
    // h_status 仅用于历史比较，不改变接口的逐 Bank 二维声明。
    reg [5:0] h_i_history,h_a_history,h_m_history;
    reg [6:0] h_single_start;
    reg [5:0] h_src_history;
    reg [2:0] h_rsrc_history,h_pc_history;
    reg [2:0] h_ar_sources;
    reg [5:0] h_total_a,h_total_r;
    reg [3:0] h_same_ar_run,h_ar_run,h_r_run,h_ar_r_run,h_reject_run,h_quiet_run,h_empty_run;
    reg [3:0] h_notready_run [0:2];
    reg h_ever_full,h_was_drained;
    integer ht;
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
            h_prev_a<=ar_fire;h_prev_i<=issue_fire;h_prev_r<=r_fire;h_prev_m<=mem_capture_due;
            h_prev_valid<=arvalid;h_prev_pc<=pc_err;h_prev_src<=src;
            h_prev_rsrc<=rvalid[2]?2'd2:(rvalid[1]?2'd1:2'd0);h_prev_rr<=m_rr;
            h_prev_ready<=arready;h_prev_rready<=rready;h_prev_eligible<=eligible;
            h_prev_req<=req;h_prev_id<=arid;h_prev_arb<=arb_addr;h_prev_addr<=araddr;
            h_prev_port<=ar_port_id;h_prev_mem<=mem_rdata;h_prev_n<=used;h_prev_p<=waiting;
            h_prev_status<=h_status;
            h_i_history<={h_i_history[4:0],issue_fire};
            h_a_history<={h_a_history[4:0],ar_fire};
            h_m_history<={h_m_history[4:0],mem_capture_due};
            h_single_start<={h_single_start[5:0],(ar_fire&&used==0)};
            h_src_history<={h_src_history[3:0],src};
            h_rsrc_history<={h_rsrc_history[0],(rvalid[2]?2'd2:(rvalid[1]?2'd1:2'd0))};
            h_pc_history<={h_pc_history[1:0],pc_err};
            if(ar_fire) begin
                h_ar_sources<=h_ar_sources|(3'b1<<src);
                if(h_total_a!=63) h_total_a<=h_total_a+1'b1;
            end
            if(r_fire && h_total_r!=63) h_total_r<=h_total_r+1'b1;
            if(ar_fire) begin if(h_ar_run!=15)h_ar_run<=h_ar_run+1'b1;end else h_ar_run<=0;
            if(ar_fire && h_prev_a && src==h_prev_src) begin
                if(h_same_ar_run!=15)h_same_ar_run<=h_same_ar_run+1'b1;
            end else h_same_ar_run<=ar_fire?4'd1:4'd0;
            if(r_fire) begin if(h_r_run!=15)h_r_run<=h_r_run+1'b1;end else h_r_run<=0;
            if(ar_fire&&r_fire) begin if(h_ar_r_run!=15)h_ar_r_run<=h_ar_r_run+1'b1;end else h_ar_r_run<=0;
            if(req!=0&&!issue_fire) begin if(h_reject_run!=15)h_reject_run<=h_reject_run+1'b1;end else h_reject_run<=0;
            if(!ar_fire&&!issue_fire&&!r_fire&&!mem_capture_due) begin
                if(h_quiet_run!=15)h_quiet_run<=h_quiet_run+1'b1;
            end else h_quiet_run<=0;
            if(used==0) begin if(h_empty_run!=15)h_empty_run<=h_empty_run+1'b1;end else h_empty_run<=0;
            if(used==9) h_ever_full<=1;
            if(used==0&&h_total_r>0) h_was_drained<=1;
            for(ht=0;ht<3;ht=ht+1) begin
                h_prev_occ[ht]<=occ[ht];
                if(head_valid[ht]&&m_done[head[ht]]&&!rready[ht]) begin
                    if(h_notready_run[ht]!=15)h_notready_run[ht]<=h_notready_run[ht]+1'b1;
                end else h_notready_run[ht]<=0;
            end
        end
    end

    // 按当前待发排名排列的空闲掩码。例如 11010 表示第 2/4/5 项空闲。
    reg [8:0] h_rank_idle,h_rank_valid;
    reg h_other_done,h_hole_reused,h_duplicate_id;
    integer hr;
    always @* begin
        h_rank_idle=0;h_rank_valid=0;h_other_done=0;h_hole_reused=0;h_duplicate_id=0;
        for(hr=0;hr<9;hr=hr+1) begin
            if(pool[hr]&&ranks[hr]<9) begin
                h_rank_valid[ranks[hr]]=1;h_rank_idle[ranks[hr]]=idle[hr];
            end
            if(m_live[hr]&&m_done[hr]&&head_valid[m_src[hr]]&&hr!=head[m_src[hr]]) h_other_done=1;
            if(ar_fire && m_live[hr] && hr>alloc_e) h_hole_reused=1;
            if(ar_fire && m_live[hr] && m_id[hr]==arid) h_duplicate_id=1;
        end
    end
    // 跟踪一次等待、失败重选、槽位重新使用。token 都是参考表身份，绝不是物理地址要求。
    reg [3:0] h_done_wait [0:8];
    reg [8:0] h_retired_bad,h_clean_reuse;
    integer he;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            h_retired_bad<=0;h_clean_reuse<=0;
            for(he=0;he<9;he=he+1)h_done_wait[he]<=0;
        end else begin
            for(he=0;he<9;he=he+1) begin
                if(m_live[he]&&m_done[he]&&!(r_fire&&rsp_e==he)) begin
                    if(h_done_wait[he]!=15)h_done_wait[he]<=h_done_wait[he]+1'b1;
                end else h_done_wait[he]<=0;
                if(r_fire&&rsp_e==he) h_retired_bad[he]<=m_pc[he] && (&m_data[he]);
                if(ar_fire&&alloc_e==he) h_clean_reuse[he]<=h_retired_bad[he] ||
                    (r_fire&&rsp_e==he&&m_pc[he]&&(&m_data[he]));
            end
        end
    end
    wire h_response_matches=r_fire && rvalid==expected_rvalid &&
        {raddr,rid,r_port_id,rdata,rresp}=={m_addr[rsp_e][2:0],m_id[rsp_e],m_port[rsp_e],m_data[rsp_e],expected_resp};

    // C2 选择条件快照，供下一拍 req 见证；失败不转移年龄，成功才补第六项。
    reg h_failed_none,h_failed_other,h_blocked_prev,h_selected_prev,h_accepted_empty;
    reg [7:0] h_selected_req;
    reg [11:0] h_selected_addr;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            h_failed_none<=0;h_failed_other<=0;h_blocked_prev<=0;h_selected_prev<=0;
            h_accepted_empty<=0;h_selected_req<=0;h_selected_addr<=0;
        end else begin
            h_failed_none<=m_attempt&&!issue_fire&&!idle[m_attempt_e]&&!select_valid;
            h_failed_other<=m_attempt&&!issue_fire&&!idle[m_attempt_e]&&select_valid&&select_e!=m_attempt_e;
            h_blocked_prev<=blocked_six;
            h_selected_prev<=select_valid;
            h_selected_req<=select_valid?(8'b1<<m_addr[select_e][5:3]):8'd0;
            h_selected_addr<=m_addr[select_e][17:6];
            h_accepted_empty<=ar_fire&&used==0;
        end
    end
