// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
    // Independent acceptance-order oracle. Physical slots are observation IDs;
    // numerical positions change only on AR acceptance and R retirement.
    // No DUT valid/issued/done/older/selection result advances this machine.
    reg [8:0] fm_live_q,fm_issued_q,fm_done_q;
    reg [3:0] fm_age_q[0:8];
    reg [17:0] fm_addr_q[0:8];
    reg [1:0] fm_src_q[0:8],fm_resp_q[0:8];
    reg [7:0] fm_id_q[0:8];
    reg [4:0] fm_port_q[0:8];
    reg [2:0] fm_left_q[0:8];
    reg [1:0] fm_rr_q;
    reg fm_attempt_q;
    reg [3:0] fm_attempt_id_q;
    reg [2:0] fm_attempt_bank_q;
    reg [11:0] fm_attempt_addr_q;
    reg [3:0] fm_hist_q=0;
    reg [3:0] fm_count,fm_pending,fm_occ[0:2],fm_after[0:2];
    reg [5:0] fm_used,fm_shared,fm_cost;
    reg [2:0] fm_ready,fm_rvalid,fm_eligible,fm_head_valid;
    reg [3:0] fm_head[0:2];
    reg [3:0] fm_head_age[0:2];
    reg fm_retire,fm_accept,fm_success,fm_select,fm_due;
    reg [1:0] fm_winner;
    reg [3:0] fm_retire_id,fm_select_id,fm_select_age,fm_due_id;
    reg [7:0] fm_req;
    reg [11:0] fm_req_addr;
    reg [8:0] fm_pool,fm_window,fm_candidates,fm_due_mask;
    reg [3:0] fm_rank[0:8],fm_older_count[0:8];
    reg [7:0] fm_rid;
    reg [4:0] fm_rport;
    reg [2:0] fm_raddr;
    reg [1:0] fm_rresp;
    always @* begin
        fm_req=(rst_n && fm_attempt_q)?(8'b1<<fm_attempt_bank_q):8'b0;
        fm_req_addr=(rst_n && fm_attempt_q)?fm_attempt_addr_q:12'b0;
        fm_success=|(fm_req & ar_rd_gnt & rw_rd_gnt);
        fm_count=0;fm_pending=0;fm_used=0;fm_shared=0;fm_cost=0;
        fm_head_valid=0;fm_eligible=0;fm_ready=0;
        fm_due=0;fm_due_id=0;fm_due_mask=0;
        for(integer x=0;x<3;x=x+1) begin
            fm_occ[x]=0;fm_after[x]=0;fm_head[x]=0;fm_head_age[x]=9;
        end
        for(integer e=0;e<9;e=e+1)begin
            if(fm_live_q[e]) begin
                fm_count=fm_count+1'b1;
                if(!fm_issued_q[e])fm_pending=fm_pending+1'b1;
                for(integer x=0;x<3;x=x+1) if(fm_src_q[e]==x) begin
                    fm_occ[x]=fm_occ[x]+1'b1;
                    if(fm_age_q[e]<fm_head_age[x])begin
                        fm_head_valid[x]=1;fm_head[x]=4'(e);fm_head_age[x]=fm_age_q[e];
                    end
                end
            end
            if(fm_left_q[e]==1)begin fm_due=1;fm_due_id=4'(e);fm_due_mask[e]=1;end
            fm_older_count[e]=0;
            for(integer j=0;j<9;j=j+1)
                if(fm_live_q[j] && fm_age_q[j]<fm_age_q[e])fm_older_count[e]=fm_older_count[e]+1'b1;
        end
        for(integer x=0;x<3;x=x+1)
            fm_eligible[x]=fm_head_valid[x] && fm_done_q[fm_head[x]] && rready[x];
        fm_winner=0;
        case(fm_rr_q)
            0: if(fm_eligible[0])fm_winner=0;else if(fm_eligible[1])fm_winner=1;else if(fm_eligible[2])fm_winner=2;
            1: if(fm_eligible[1])fm_winner=1;else if(fm_eligible[2])fm_winner=2;else if(fm_eligible[0])fm_winner=0;
            2: if(fm_eligible[2])fm_winner=2;else if(fm_eligible[0])fm_winner=0;else if(fm_eligible[1])fm_winner=1;
            default: fm_winner=0;
        endcase
        fm_retire=rst_n && (|fm_eligible);
        fm_retire_id=fm_retire?fm_head[fm_winner]:4'b0;
        fm_rvalid=fm_retire?(3'b1<<fm_winner):3'b0;
        fm_rid=0;fm_rport=0;fm_raddr=0;fm_rresp=0;
        if(fm_retire)begin
            fm_rid=fm_id_q[fm_retire_id];fm_rport=fm_port_q[fm_retire_id];fm_raddr=fm_addr_q[fm_retire_id][2:0];
            fm_rresp=(fm_resp_q[fm_retire_id]==3)?2'b11:(rsp_pc_err?2'b01:2'b00);
        end
        for(integer x=0;x<3;x=x+1)begin
            fm_cost=fm_cost+((fm_occ[x]!=0)?{2'b0,fm_occ[x]}:6'd1);
            fm_after[x]=fm_occ[x]-4'(fm_retire && fm_winner==x);
            fm_used=fm_used+{2'b0,fm_after[x]};
            if(fm_after[x]>1)fm_shared=fm_shared+{2'b0,fm_after[x]}-6'd1;
        end
        for(integer x=0;x<3;x=x+1)
            fm_ready[x]=rst_n && fm_used<9 && (fm_after[x]==0 || fm_shared<6);
        fm_accept=arvalid && src<3 && ((src<3)?fm_ready[src]:1'b0);
        fm_pool=fm_live_q & ~fm_issued_q;
        if(fm_success)fm_pool[fm_attempt_id_q]=0;
        fm_window=0;fm_candidates=0;fm_select=0;fm_select_id=0;fm_select_age=9;
        for(integer e=0;e<9;e=e+1)begin
            fm_rank[e]=0;
            for(integer j=0;j<9;j=j+1)
                if(fm_pool[j] && fm_age_q[j]<fm_age_q[e])fm_rank[e]=fm_rank[e]+1'b1;
            fm_window[e]=fm_pool[e] && fm_rank[e]<5;
            fm_candidates[e]=fm_window[e] && !(fm_attempt_q && fm_attempt_id_q==e) &&
                !rd_mem_status[fm_addr_q[e][6:3]];
            if(fm_candidates[e] && fm_age_q[e]<fm_select_age)begin
                fm_select=1;fm_select_id=4'(e);fm_select_age=fm_age_q[e];
            end
        end
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            fm_live_q<=0;fm_issued_q<=0;fm_done_q<=0;fm_rr_q<=0;
            fm_attempt_q<=0;fm_attempt_id_q<=0;fm_attempt_bank_q<=0;fm_attempt_addr_q<=0;fm_hist_q<=0;
            for(integer e=0;e<9;e=e+1)begin
                fm_age_q[e]<=0;fm_addr_q[e]<=0;fm_src_q[e]<=0;fm_resp_q[e]<=0;fm_id_q[e]<=0;fm_port_q[e]<=0;fm_left_q[e]<=0;
            end
        end else begin
            fm_hist_q<={fm_hist_q[2:0],1'b1};
            if(fm_retire)fm_rr_q<=(fm_winner==2)?2'd0:fm_winner+2'd1;
            fm_attempt_q<=fm_select;
            fm_attempt_id_q<=fm_select?fm_select_id:4'b0;
            fm_attempt_bank_q<=fm_select?fm_addr_q[fm_select_id][5:3]:3'b0;
            fm_attempt_addr_q<=fm_select?fm_addr_q[fm_select_id][17:6]:12'b0;
            for(integer e=0;e<9;e=e+1)begin
                if(fm_accept && alloc_entry==e)begin
                    fm_live_q[e]<=1;fm_issued_q[e]<=0;fm_done_q[e]<=0;
                    fm_age_q[e]<=fm_count-4'(fm_retire);
                    fm_addr_q[e]<=araddr;fm_src_q[e]<=src;fm_resp_q[e]<=arresp;fm_id_q[e]<=arid;fm_port_q[e]<=ar_port_id;fm_left_q[e]<=0;
                end else if(fm_retire && fm_retire_id==e)begin
                    fm_live_q[e]<=0;fm_issued_q[e]<=0;fm_done_q[e]<=0;
                    fm_age_q[e]<=0;fm_addr_q[e]<=0;fm_src_q[e]<=0;fm_resp_q[e]<=0;fm_id_q[e]<=0;fm_port_q[e]<=0;fm_left_q[e]<=0;
                end else begin
                    if(fm_retire && fm_live_q[e] && fm_age_q[e]>fm_age_q[fm_retire_id])fm_age_q[e]<=fm_age_q[e]-1'b1;
                    if(fm_left_q[e]!=0)fm_left_q[e]<=fm_left_q[e]-1'b1;
                    if(fm_left_q[e]==1)fm_done_q[e]<=1;
                    if(fm_success && fm_attempt_id_q==e)begin fm_issued_q[e]<=1;fm_left_q[e]<=4;end
                end
            end
        end
    end
    always @(posedge clk)if(rst_n)begin
        FM_LIVE: assert(valid_q==fm_live_q);
        FM_ISSUED: assert(issued_q==fm_issued_q);
        FM_DONE: assert(done_q==fm_done_q);
        FM_PENDING: assert(pending_cnt==fm_pending);
        FM_RR: assert(rr_ptr_q==fm_rr_q && fm_rr_q<3);
        FM_COST: assert(fm_cost<=9);
        FM_READY: assert(arready==fm_ready);
        FM_ACCEPT: assert(alloc_fire==fm_accept);
        if(fm_accept)begin
            FM_ALLOC_ID: assert(alloc_entry<9);
            FM_ALLOC_FREE: assert(!fm_live_q[alloc_entry] || (fm_retire && fm_retire_id==alloc_entry));
        end
        FM_REQ: assert(req==fm_req);
        FM_ADDR: assert(arb_addr==fm_req_addr);
        FM_ATTEMPT: assert(issue_valid_q==fm_attempt_q && issue_entry_q==fm_attempt_id_q && issue_bank_q==fm_attempt_bank_q && issue_addr_q==fm_attempt_addr_q);
        FM_SUCCESS: assert(issue_success==fm_success);
        if(fm_attempt_q)begin
            FM_ISSUE_OWN: assert(fm_attempt_id_q<9 && fm_live_q[fm_attempt_id_q] && !fm_issued_q[fm_attempt_id_q]);
        end
        FM_POOL: assert(rank_pool==fm_pool);
        FM_WINDOW: assert(window_mask==fm_window);
        FM_CANDIDATE: assert(candidate_mask==fm_candidates);
        FM_SELECT: assert(select_valid==fm_select && select_entry==fm_select_id);
        FM_DUE_UNIQUE: assert($onehot0(fm_due_mask));
        FM_CAPTURE: assert(capture_valid==fm_due);
        if(fm_due)begin
            FM_CAPTURE_ID: assert(capture_entry==fm_due_id);
            FM_NO_BYPASS: assert(!(fm_retire && fm_retire_id==fm_due_id));
        end
        FM_RVALID: assert(rvalid==fm_rvalid);
        FM_RETIRE: assert(retire_fire==fm_retire && retire_entry==fm_retire_id);
        FM_RMETA: assert(rid==fm_rid && r_port_id==fm_rport && raddr==fm_raddr && rresp==fm_rresp);
        for(integer x=0;x<3;x=x+1)begin
            assert(occ_q[x]==fm_occ[x]);assert(fm_occ[x]<=7);assert(fm_after[x]<=7);
        end
        for(integer e=0;e<9;e=e+1)begin
            assert(addr_q[e]==fm_addr_q[e] && src_q[e]==fm_src_q[e] && id_q[e]==fm_id_q[e] && port_q[e]==fm_port_q[e] && arresp_q[e]==fm_resp_q[e]);
            if(fm_live_q[e])begin
                assert(fm_src_q[e]<3);
                assert(fm_age_q[e]<fm_count && fm_age_q[e]==fm_older_count[e]);
            end
            assert(fm_left_q[e]<=4);
            assert(!fm_issued_q[e] || fm_live_q[e]);
            assert(!fm_done_q[e] || fm_issued_q[e]);
            assert((fm_left_q[e]!=0)==(fm_issued_q[e] && !fm_done_q[e]));
            if(fm_hist_q[0])assert((fm_left_q[e]==4)==($past(fm_success) && $past(fm_attempt_id_q)==e));
            if(fm_hist_q[1])assert((fm_left_q[e]==3)==($past(fm_success,2) && $past(fm_attempt_id_q,2)==e));
            if(fm_hist_q[2])assert((fm_left_q[e]==2)==($past(fm_success,3) && $past(fm_attempt_id_q,3)==e));
            if(fm_hist_q[3])assert((fm_left_q[e]==1)==($past(fm_success,4) && $past(fm_attempt_id_q,4)==e));
            for(integer j=0;j<9;j=j+1)begin
                assert(older_q[e][j]==(fm_live_q[e] && fm_live_q[j] && fm_age_q[j]<fm_age_q[e]));
                if(e!=j && fm_live_q[e] && fm_live_q[j])assert(fm_age_q[e]!=fm_age_q[j]);
            end
        end
// auxiliary cover omitted in this cover-only partition:         FM_COVER_LIFECYCLE: cover(fm_retire);
// auxiliary cover omitted in this cover-only partition:         FM_COVER_ALL_STAGES: cover(fm_accept && fm_select && fm_success && fm_due && fm_retire);
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
