`default_nettype none
module cmdbuf_rd (
    input  logic clk,
    input  logic rst_n,
    input  logic arvalid,
    output logic [2:0] arready,
    input  logic [17:0] araddr,
    input  logic [1:0] src,
    input  logic [7:0] arid,
    input  logic [4:0] ar_port_id,
    input  logic [1:0] arresp,
    output logic [2:0] rvalid,
    input  logic [2:0] rready,
    output logic [127:0] rdata,
    output logic [7:0] rid,
    output logic [4:0] r_port_id,
    output logic [2:0] raddr,
    output logic [1:0] rresp,
    output logic [7:0] req,
    output logic [11:0] arb_addr,
    output logic [3:0] pending_cnt,
    input  logic [7:0] ar_rd_gnt,
    input  logic [1:0][7:0] rd_mem_status,
    input  logic [127:0] mem_rdata,
    input  logic pc_err,
    input  logic [7:0] rw_rd_gnt
);
    logic alloc_fire, retire_fire, issue_success, capture_valid;
    logic [3:0] alloc_entry, retire_entry, issue_entry, capture_entry, rsp_entry;
    logic [127:0] rsp_data;
    logic rsp_pc_err;

    cmdbuf_rd_cmd u_cmd (
        .clk, .rst_n, .arvalid, .arready, .araddr, .src, .arid,
        .ar_port_id, .arresp, .rvalid, .rready, .rid, .r_port_id,
        .raddr, .rresp, .req, .arb_addr, .pending_cnt, .ar_rd_gnt,
        .rd_mem_status, .rw_rd_gnt, .alloc_fire, .alloc_entry,
        .retire_fire, .retire_entry, .issue_success, .issue_entry,
        .capture_valid, .capture_entry, .rsp_entry, .rsp_pc_err
// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
        ,.fc_cmd_valid,.fc_cmd_issued,.fc_cmd_done,
        .fc_model_valid,.fc_model_issued,.fc_model_done
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
    );
    cmdbuf_rd_otb u_otb (
        .clk, .rst_n, .alloc_fire, .alloc_entry, .retire_fire,
        .retire_entry, .issue_success, .issue_entry, .capture_valid,
        .capture_entry, .mem_rdata, .pc_err, .rsp_entry, .rsp_data,
        .rsp_pc_err
// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
        ,.fc_obs_data,.fc_obs_pc,.fc_obs_reserved,.fc_obs_done,
        .fc_obs_ret_valid,.fc_obs_ret_entry
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
    );
    assign rdata = (|rvalid) ? rsp_data : 128'b0;
// BEGIN CMDBUF CLOSURE FORMAL MONITOR

`ifdef FORMAL

    // F_EXT: event consistency is asserted, never assumed.
    always @(posedge clk) if (rst_n) begin
        assert(alloc_fire == (arvalid && (src < 3) &&
                             ((src < 3) ? arready[src] : 1'b0)));
        assert(retire_fire == (|(rvalid & rready)));
        assert(issue_success == (|(req & ar_rd_gnt & rw_rd_gnt)));
        assert($onehot0(req));
        assert($onehot0(rvalid));
        assert((rvalid & ~rready) == 0);
        assert(rdata == ((|rvalid) ? rsp_data : 128'b0));
        if (alloc_fire) assert(alloc_entry < 9);
        if (retire_fire) assert(retire_entry < 9);
        if (issue_success) assert(issue_entry < 9);
        if (capture_valid) assert(capture_entry < 9);
    end
    reg [2:0] f_lifecycle = 0;
    reg [3:0] f_life_entry = 0;
    always @(posedge clk) begin
        if (!rst_n) begin f_lifecycle <= 0; f_life_entry <= 0; end
        else begin
            if (f_lifecycle == 0 && alloc_fire) begin
                f_life_entry <= alloc_entry; f_lifecycle <= 1;
            end
            if (f_lifecycle == 1 && issue_success && issue_entry == f_life_entry)
                f_lifecycle <= 2;
            if (f_lifecycle == 2 && capture_valid && capture_entry == f_life_entry)
                f_lifecycle <= 3;
            if (f_lifecycle == 3 && retire_fire && retire_entry == f_life_entry)
                f_lifecycle <= 4;
            cover(f_lifecycle == 4);
            cover(alloc_fire && issue_success && capture_valid && retire_fire);
        end
    end
`endif
`ifdef FORMAL_CLOSURE
    // Proposed supplier: capacity_component_r1/QC_ALLOC_FREE. Do not run this
    // assume-guarantee consumer before the exact supplier is proved.
    // The component supplier quantifies capture/parity freely, so it includes
    // this top-level fixed-latency composition as a subset of environments.
    reg [3:0] lc_pending;
    reg lc_token_owners,lc_token_distinct;
    always @*begin
        lc_pending=0;lc_token_owners=1;lc_token_distinct=1;
        for(integer e=0;e<9;e=e+1)
            if(fc_cmd_valid[e] && !fc_cmd_issued[e])lc_pending=lc_pending+1'b1;
        for(integer k=0;k<4;k=k+1)begin
            if(fc_obs_ret_valid[k])begin
                if(fc_obs_ret_entry[k*4+:4]>=9)lc_token_owners=0;
                else if(!fc_cmd_valid[fc_obs_ret_entry[k*4+:4]] ||
                        !fc_cmd_issued[fc_obs_ret_entry[k*4+:4]] ||
                         fc_cmd_done[fc_obs_ret_entry[k*4+:4]])lc_token_owners=0;
                for(integer j=0;j<k;j=j+1)
                    if(fc_obs_ret_valid[j] && fc_obs_ret_entry[j*4+:4]==fc_obs_ret_entry[k*4+:4])lc_token_distinct=0;
            end
        end
    end
    always @(posedge clk)if(rst_n)begin
        if(alloc_fire)begin
            CONTRACT_ALLOC_RANGE: assume(alloc_entry<9);
            CONTRACT_ALLOC_FREE: assume(!fc_cmd_valid[alloc_entry] || (retire_fire && retire_entry==alloc_entry));
        end
        LIFE_ISSUED_IMPLIES_LIVE: assert((fc_cmd_issued & ~fc_cmd_valid)==0);
        LIFE_DONE_IMPLIES_ISSUED: assert((fc_cmd_done & ~fc_cmd_issued)==0);
        LIFE_ALL_TOKEN_OWNERS: assert(lc_token_owners);
        LIFE_ALL_TOKEN_DISTINCT: assert(lc_token_distinct);
        LIFE_PENDING_EXACT: assert(pending_cnt==lc_pending);
        LIFE_PENDING_RANGE: assert(pending_cnt<=9);
        if(|req)begin
            LIFE_ATTEMPT_OWNERSHIP: assert(issue_entry<9 && fc_cmd_valid[issue_entry] && !fc_cmd_issued[issue_entry]);
            LIFE_ATTEMPT_NOT_DONE: assert(!fc_cmd_done[issue_entry]);
        end
        if(capture_valid)begin
            LIFE_CAPTURE_OWNERSHIP: assert(capture_entry<9 && fc_cmd_valid[capture_entry] &&
                fc_cmd_issued[capture_entry] && !fc_cmd_done[capture_entry]);
            LIFE_NO_CAPTURE_BYPASS: assert(!(retire_fire && retire_entry==capture_entry));
        end
        if(retire_fire)LIFE_RETIRE_OWNERSHIP: assert(retire_entry<9 &&
            fc_cmd_valid[retire_entry] && fc_cmd_issued[retire_entry] && fc_cmd_done[retire_entry]);
    end
`endif
`ifdef FORMAL_CLOSURE
    // Nine independent countdowns, advanced by external success only. This
    // oracle does not read capture_valid or OTB token bits when updating.
    // A fixed four-cycle deadline is recorded for each successful identity.
    wire lc_external_success=|(req & ar_rd_gnt & rw_rd_gnt);
    reg [2:0] lc_remaining[0:8];
    reg [8:0] lc_due_mask;
    reg [3:0] lc_due_count;
    reg lc_calendar_match;
    reg [2:0] lc_token_delay[0:8];
    always @(posedge clk)begin
        if(!rst_n)begin
            for(integer e=0;e<9;e=e+1)lc_remaining[e]<=0;
        end else begin
            for(integer e=0;e<9;e=e+1)begin
                if(lc_external_success && issue_entry==e)lc_remaining[e]<=3'd4;
                else if(lc_remaining[e]!=0)lc_remaining[e]<=lc_remaining[e]-1'b1;
            end
        end
    end
    always @*begin
        lc_due_mask=0;lc_due_count=0;lc_calendar_match=1;
        for(integer e=0;e<9;e=e+1)begin
            lc_due_mask[e]=(lc_remaining[e]==1);
            if(lc_due_mask[e])lc_due_count=lc_due_count+1'b1;
            lc_token_delay[e]=0;
            for(integer k=0;k<4;k=k+1)
                if(fc_obs_ret_valid[k] && fc_obs_ret_entry[k*4+:4]==e)
                    lc_token_delay[e]=3'(4-k);
            if(lc_remaining[e]!=lc_token_delay[e])lc_calendar_match=0;
        end
    end
    always @(posedge clk)if(rst_n)begin
        LIFE_CALENDAR_MATCH: assert(lc_calendar_match);
        LIFE_INDEPENDENT_DUE_UNIQUE: assert(lc_due_count<=1);
        LIFE_INDEPENDENT_CAPTURE: assert(capture_valid==(lc_due_count!=0) &&
            (!capture_valid || (capture_entry<9 && lc_due_mask[capture_entry])));
    end
`endif

`ifdef FORMAL_CLOSURE
    wire [1151:0] fc_obs_data;
    wire [8:0] fc_obs_pc,fc_obs_reserved,fc_obs_done;
    wire [3:0] fc_obs_ret_valid;
    wire [15:0] fc_obs_ret_entry;
`endif

`ifdef FORMAL_CLOSURE
    wire [8:0] fc_cmd_valid,fc_cmd_issued,fc_cmd_done;
    wire [8:0] fc_model_valid,fc_model_issued,fc_model_done;
    always @(posedge clk)if(rst_n)begin
        PAIR_CMD_VALID: assert(fc_cmd_valid==fc_model_valid);
        PAIR_OTB_VALID: assert(fc_obs_reserved==fc_model_valid);
        PAIR_CMD_DONE: assert(fc_cmd_done==fc_model_done);
        PAIR_OTB_DONE: assert(fc_obs_done==fc_model_done);
        PAIR_CMD_ISSUED: assert(fc_cmd_issued==fc_model_issued);
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
endmodule
`default_nettype wire
