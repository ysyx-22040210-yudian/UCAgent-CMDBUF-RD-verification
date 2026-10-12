// BEGIN CMDBUF CLOSURE FORMAL MONITOR

`ifdef FORMAL

    always @(posedge clk) begin
        assert(req==((rst_n && issue_valid_q)?(8'b1<<issue_bank_q):8'b0));
        assert(arb_addr==((rst_n && issue_valid_q)?issue_addr_q:12'b0));
        assert(pending_cnt==pending_q);
        assert(retire_entry==rsp_entry);
        assert(issue_entry==issue_entry_q);
    end
`endif
`ifdef FORMAL_CLOSURE
    // Accepted-slot shadow: events are external handshake expressions.
    // Physical entry identity is checked by separate ownership obligations.
    wire fa_accept=arvalid && src<3 && ((src<3)?arready[src]:1'b0);
    wire fa_retire=|(rvalid&rready);
    wire fa_success=|(req&ar_rd_gnt&rw_rd_gnt);
    (* anyconst *) reg [3:0] fa_watch;
    always @* assume(fa_watch<9);
    reg [8:0] fm_live_q,fm_issued_q,fm_done_q;
    reg [17:0] fa_addr;
    reg [1:0] fa_src,fa_resp;
    reg [7:0] fa_id;
    reg [4:0] fa_port;
    reg fa_history=0;
    always @(posedge clk)begin
        fa_history<=1;
        if(!rst_n)begin
            fm_live_q<=0;fm_issued_q<=0;fm_done_q<=0;
            fa_addr<=0;fa_src<=0;fa_resp<=0;fa_id<=0;fa_port<=0;
        end else begin
            for(integer e=0;e<9;e=e+1)begin
                if(fa_accept && alloc_entry==e)begin
                    fm_live_q[e]<=1;fm_issued_q[e]<=0;fm_done_q[e]<=0;
                end else if(fa_retire && retire_entry==e)begin
                    fm_live_q[e]<=0;fm_issued_q[e]<=0;fm_done_q[e]<=0;
                end else begin
                    if(fa_success && issue_entry==e)fm_issued_q[e]<=1;
                    // The supplier D_ORIGIN_CAPTURE_TIME proves this event is
                    // exactly external double-grant success four cycles ago.
                    if(capture_valid && capture_entry==e)fm_done_q[e]<=1;
                end
            end
            if(fa_accept && alloc_entry==fa_watch)begin
                fa_addr<=araddr;fa_src<=src;fa_resp<=arresp;fa_id<=arid;fa_port<=ar_port_id;
            end else if(fa_retire && retire_entry==fa_watch)begin
                fa_addr<=0;fa_src<=0;fa_resp<=0;fa_id<=0;fa_port<=0;
            end
        end
    end
    always @(posedge clk)if(rst_n)begin
        ANYCONST_LIVE_META: assert(
            {addr_q[fa_watch],src_q[fa_watch],id_q[fa_watch],port_q[fa_watch],arresp_q[fa_watch]}==
            {fa_addr,fa_src,fa_id,fa_port,fa_resp});
        FA_STATE_SHADOW: assert(valid_q==fm_live_q && issued_q==fm_issued_q && done_q==fm_done_q);
        if(fa_history && $past(rst_n))begin
            if($past(fa_accept) && $past(alloc_entry)==fa_watch)begin
                NEW_ALLOC_STATE_AND_META: assert(valid_q[fa_watch] && !issued_q[fa_watch] && !done_q[fa_watch] &&
                    {addr_q[fa_watch],src_q[fa_watch],id_q[fa_watch],port_q[fa_watch],arresp_q[fa_watch]}==
                    $past({araddr,src,arid,ar_port_id,arresp}));
            end
            if($past(issue_valid_q && !fa_success) && $past(issue_entry)==fa_watch &&
               !$past(fa_accept && alloc_entry==fa_watch) && !$past(fa_retire && retire_entry==fa_watch))begin
                ANYCONST_FAILED_STATE: assert(issued_q[fa_watch]==$past(issued_q[fa_watch]) &&
                    valid_q[fa_watch]==$past(valid_q[fa_watch]));
            end
        end
    end
`endif
`ifdef FORMAL_CLOSURE
    reg ss_past=0;
    always @(posedge clk)ss_past<=1;
    always @(posedge clk)if(rst_n)begin
        SS_RVALID_PATH: assert($onehot0(rvalid) && ((rvalid & ~rready)==0));
        SS_RR_RANGE: assert(rr_ptr_q<3);
        SS_ALLOC_INDEX: assert(alloc_entry<9);
        SS_FREE_FOUND_EQ: assert(free_found==(|free_mask));
        if(free_found)SS_ALLOC_FROM_FREE: assert(!valid_q[alloc_entry] || (retire_fire && retire_entry==alloc_entry));
        if(retire_fire)begin
            SS_RETIRE_OWNER: assert(retire_entry<9 && winner<3 && valid_q[retire_entry] && done_q[retire_entry] && src_q[retire_entry]==winner);
            SS_RETIRE_ROUTE: assert(rvalid==(3'b1<<src_q[retire_entry]));
        end
        if(select_valid)SS_SELECT_PENDING: assert(select_entry<9 && candidate_mask[select_entry] &&
            valid_q[select_entry] && !issued_q[select_entry] && !current_issue_mask[select_entry]);
        if(ss_past && $past(rst_n))begin
            SS_OCC_NET_ALL: assert(
                occ_q[0]==$past(occ_q[0])+4'($past(alloc_fire && src==0))-4'($past(retire_fire && winner==0)) &&
                occ_q[1]==$past(occ_q[1])+4'($past(alloc_fire && src==1))-4'($past(retire_fire && winner==1)) &&
                occ_q[2]==$past(occ_q[2])+4'($past(alloc_fire && src==2))-4'($past(retire_fire && winner==2)));
            SS_PENDING_NET: assert(pending_q==$past(pending_q)+4'($past(alloc_fire))-4'($past(issue_success)));
            SS_ATTEMPT_VALID_NEXT: assert(issue_valid_q==$past(select_valid));
        end
    end
`endif

`ifdef FORMAL_CLOSURE
    assign fc_cmd_valid=valid_q;
    assign fc_cmd_issued=issued_q;
    assign fc_cmd_done=done_q;
    assign fc_model_valid=fm_live_q;
    assign fc_model_issued=fm_issued_q;
    assign fc_model_done=fm_done_q;
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
