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
    // Independent data origin oracle uses the TOP input and external handshake.
    // Observation ports are read-only induction witnesses, never assumptions.
    wire fd_accept = arvalid && src<3 && ((src<3)?arready[src]:1'b0);
    wire fd_success = |(req & ar_rd_gnt & rw_rd_gnt);
    wire fd_retire = |(rvalid & rready);
    reg [3:0] fd_history_q=0;
    reg [127:0] fd_data_q[0:8];
    reg [8:0] fd_pc_q;
    always @(posedge clk) begin
        if(!rst_n) begin
            fd_history_q<=0;
            fd_pc_q<=0;
            for(integer e=0;e<9;e=e+1)fd_data_q[e]<=0;
        end else begin
            fd_history_q<={fd_history_q[2:0],1'b1};
            for(integer e=0;e<9;e=e+1) begin
                if((fd_accept && alloc_entry==e) ||
                   (fd_retire && retire_entry==e)) begin
                    fd_data_q[e]<=0;
                    fd_pc_q[e]<=0;
                end else if(fd_history_q[3] && $past(fd_success,4) &&
                            $past(issue_entry,4)==e) begin
                    fd_data_q[e]<=mem_rdata;
                    fd_pc_q[e]<=pc_err;
                end
            end
        end
    end
    always @(posedge clk) if(rst_n) begin
        D_ORIGIN_ACCEPT: assert(alloc_fire==fd_accept);
        D_ORIGIN_SUCCESS: assert(issue_success==fd_success);
        D_ORIGIN_RETIRE: assert(retire_fire==fd_retire);
        if(fd_history_q[3]) begin
            D_ORIGIN_CAPTURE_TIME: assert(capture_valid==$past(fd_success,4));
            if(capture_valid)
                D_ORIGIN_CAPTURE_ID: assert(capture_entry==$past(issue_entry,4));
        end else D_ORIGIN_INITIAL_NO_CAPTURE: assert(!capture_valid);
        for(integer e=0;e<9;e=e+1) begin
            // Every stored bit must keep matching the TOP-source oracle,
            // including while no source is ready and other MEM data arrives.
            assert(fc_obs_data[e*128+:128]==fd_data_q[e]);
            assert(fc_obs_pc[e]==fd_pc_q[e]);
        end
        if(fd_retire) begin
            D_ORIGIN_R_SLOT: assert(rsp_entry<9 && rsp_entry==retire_entry);
            D_ORIGIN_R_DATA: assert(rdata==fd_data_q[rsp_entry]);
            D_ORIGIN_R_PC: assert(rsp_pc_err==fd_pc_q[rsp_entry]);
        end
    end
`endif

`ifdef FORMAL_CLOSURE
    (* anyconst *) reg [3:0] fa_top_watch;
    always @* assume(fa_top_watch<9);
    reg fa_top_past=0;
    reg fa_any_accept=0,fa_any_completion=0;
    always @(posedge clk)begin
        fa_top_past<=1;
        if(!rst_n)begin fa_any_accept<=0;fa_any_completion<=0;end
        else begin
            if(fd_accept)fa_any_accept<=1;
            if(fd_history_q[3] && $past(fd_success,4))fa_any_completion<=1;
        end
        if(!rst_n || !fa_any_accept)INITIAL_REQ_WITH_NO_HISTORY: assert(req==0);
        if(!rst_n || !fa_any_completion)INITIAL_R_WITH_NO_COMPLETION: assert(rvalid==0);
        if(rst_n)begin
            if(!fa_any_accept)INITIAL_EMPTY_FROM_NO_ACCEPT: assert(fc_model_valid==0);
            if(!fa_any_completion)INITIAL_DONE_FROM_NO_COMPLETION: assert(fc_model_done==0);
            PAIR_ALL: assert(fc_cmd_valid==fc_model_valid && fc_obs_reserved==fc_model_valid &&
                fc_cmd_done==fc_model_done && fc_obs_done==fc_model_done);
            ENTRY_RANGES_ALL: assert((!fd_accept || alloc_entry<9) && (!fd_success || issue_entry<9) &&
                (!capture_valid || capture_entry<9) && (!fd_retire || retire_entry<9));
            if(fa_top_past && $past(rst_n) &&
                ($past(fd_accept && alloc_entry==fa_top_watch) || $past(fd_retire && retire_entry==fa_top_watch)))begin
                ANYCONST_DATA_PC_CLEAR: assert(fc_obs_data[fa_top_watch*128+:128]==128'b0 && !fc_obs_pc[fa_top_watch]);
            end

        end
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
