// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
    // Matrix age is a proved semantic primitive, not an assumed arrival order:
    // age_projection_r1/ANYCONST_FIFO_AGE relates every pair to the filtered
    // external-acceptance FIFO. Its four order lemmas supply this conjunction.
    // Do not submit until all exact supplier properties have unbounded PASS.
    reg po_order_contract;
    always @*begin
        po_order_contract=1;
        for(integer i=0;i<9;i=i+1)for(integer j=0;j<9;j=j+1)begin
            if(!valid_q[i] || !valid_q[j] || i==j)begin
                if(older_q[i][j])po_order_contract=0;
            end else if(older_q[i][j]==older_q[j][i])po_order_contract=0;
            for(integer k=0;k<9;k=k+1)
                if(valid_q[i] && valid_q[j] && valid_q[k] && older_q[i][j] && older_q[j][k] && !older_q[i][k])po_order_contract=0;
        end
    end
    always @(posedge clk)if(rst_n)CONTRACT_STRICT_ORDER: assume(po_order_contract);

    wire po_success=|(req&ar_rd_gnt&rw_rd_gnt);
    reg [8:0] po_pool,po_window,po_idle,po_candidates;
    reg [3:0] po_rank[0:8],po_select;
    reg po_selected;
    reg [2:0] po_hvalid,po_eligible,po_rvalid;
    reg [3:0] po_head[0:2],po_rsp;
    reg [1:0] po_rr,po_win,po_resp;
    reg [7:0] po_rid;
    reg [4:0] po_port;
    reg [2:0] po_raddr;
    always @*begin
        po_pool=valid_q & ~issued_q;
        if(po_success)po_pool[issue_entry]=0;
        po_window=0;po_idle=0;po_candidates=0;po_selected=0;po_select=0;
        po_hvalid=0;po_eligible=0;po_rvalid=0;
        for(integer x=0;x<3;x=x+1)po_head[x]=0;
        for(integer e=0;e<9;e=e+1)begin
            po_rank[e]=0;
            for(integer j=0;j<9;j=j+1)
                if(po_pool[j] && older_q[e][j])po_rank[e]=po_rank[e]+1'b1;
            po_window[e]=po_pool[e] && po_rank[e]<5;
            po_idle[e]=!rd_mem_status[addr_q[e][6:3]];
            po_candidates[e]=po_window[e] && po_idle[e] && !(issue_valid_q && issue_entry==e);
            // Scan-and-replace oldest, independent from DUT's per-entry mask
            // of all older candidates and final encoded onehot.
            if(po_candidates[e] && (!po_selected || older_q[po_select][e]))begin
                po_selected=1;po_select=4'(e);
            end
            for(integer x=0;x<3;x=x+1)
                if(valid_q[e] && src_q[e]==x && (!po_hvalid[x] || older_q[po_head[x]][e]))begin
                    po_head[x]=4'(e);po_hvalid[x]=1;
                end
        end
        for(integer x=0;x<3;x=x+1)
            po_eligible[x]=po_hvalid[x] && done_q[po_head[x]] && rready[x];
        po_win=0;
        case(po_rr)
            0:if(po_eligible[0])po_win=0;else if(po_eligible[1])po_win=1;else if(po_eligible[2])po_win=2;
            1:if(po_eligible[1])po_win=1;else if(po_eligible[2])po_win=2;else if(po_eligible[0])po_win=0;
            2:if(po_eligible[2])po_win=2;else if(po_eligible[0])po_win=0;else if(po_eligible[1])po_win=1;
            default:po_win=0;
        endcase
        po_rsp=0;po_rid=0;po_port=0;po_raddr=0;po_resp=0;
        if(rst_n && |po_eligible)begin
            po_rvalid=3'b1<<po_win;po_rsp=po_head[po_win];
            po_rid=id_q[po_rsp];po_port=port_q[po_rsp];po_raddr=addr_q[po_rsp][2:0];
            po_resp=(arresp_q[po_rsp]==3)?2'b11:(rsp_pc_err?2'b01:2'b00);
        end
    end
    always @(posedge clk)begin
        if(!rst_n)po_rr<=0;
        else if(|(rvalid&rready))case(rvalid)
            3'b001:po_rr<=1;
            3'b010:po_rr<=2;
            3'b100:po_rr<=0;
            default:po_rr<=3;
        endcase
        if(rst_n)begin
            POLICY_POOL: assert(rank_pool==po_pool);
            POLICY_WINDOW: assert(window_mask==po_window);
            POLICY_HALF_IDLE: assert(bank_idle_mask==po_idle);
            POLICY_CANDIDATES: assert(candidate_mask==po_candidates);
            POLICY_SELECT: assert(select_valid==po_selected && select_entry==po_select);
            POLICY_SELECT_ONEHOT: assert($onehot0(select_onehot));
            POLICY_RR_STATE: assert(rr_ptr_q==po_rr && po_rr<3);
            POLICY_RVALID: assert(rvalid==po_rvalid);
            POLICY_R_IDENTITY: assert(retire_entry==po_rsp && rsp_entry==po_rsp);
            POLICY_R_METADATA: assert(rid==po_rid && r_port_id==po_port && raddr==po_raddr && rresp==po_resp);
            POLICY_HEAD_VALID: assert(head_valid==po_hvalid);
            POLICY_ELIGIBLE: assert(r_candidate==po_eligible);
            for(integer x=0;x<3;x=x+1)if(po_hvalid[x])assert(head_entry[x]==po_head[x]);
        end
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
