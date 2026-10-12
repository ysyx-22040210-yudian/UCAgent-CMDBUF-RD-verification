// BEGIN CMDBUF CLOSURE FORMAL MONITOR
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
    // Separate primitive suppliers prevent false proof-dependency cycles.
    always @(posedge clk)if(rst_n)begin
        FA_LIVE_MATCH: assert(valid_q==fm_live_q);
        FA_ISSUED_MATCH: assert(issued_q==fm_issued_q);
        FA_DONE_MATCH: assert(done_q==fm_done_q);
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
