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
// auxiliary cover omitted in this cover-only partition:             cover(f_lifecycle == 4);
// auxiliary cover omitted in this cover-only partition:             cover(alloc_fire && issue_success && capture_valid && retire_fire);
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
    wire [1151:0] fc_obs_data;
    wire [8:0] fc_obs_pc,fc_obs_reserved,fc_obs_done;
    wire [3:0] fc_obs_ret_valid;
    wire [15:0] fc_obs_ret_entry;
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
