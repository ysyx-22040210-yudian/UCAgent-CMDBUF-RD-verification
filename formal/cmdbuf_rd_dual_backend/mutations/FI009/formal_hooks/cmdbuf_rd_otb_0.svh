// BEGIN CMDBUF NATIVE FORMAL MONITOR

`ifdef FORMAL_CALENDAR

    // Independent per-entry countdown; never advanced from capture_valid.
    reg [8:0] f_live=0, f_issued=0, f_done=0;
    reg [2:0] f_count [0:8];
    wire [8:0] f_due;
    genvar f_e;
    generate for(f_e=0;f_e<9;f_e=f_e+1) begin:F_DUE
        assign f_due[f_e]=f_live[f_e] && f_issued[f_e] &&
                            !f_done[f_e] && f_count[f_e]==1;
    end endgenerate
    always @(posedge clk) begin
        if(!rst_n) begin
            f_live<=0;f_issued<=0;f_done<=0;
            for(integer e=0;e<9;e=e+1) f_count[e]<=0;
        end else begin
            for(integer e=0;e<9;e=e+1) begin
                if(alloc_fire && alloc_entry==e) begin
                    f_live[e]<=1;f_issued[e]<=0;f_done[e]<=0;f_count[e]<=0;
                end else if(retire_fire && retire_entry==e) begin
                    f_live[e]<=0;f_issued[e]<=0;f_done[e]<=0;f_count[e]<=0;
                end else begin
                    if(f_count[e]>0) f_count[e]<=f_count[e]-1;
                    if(issue_success && issue_entry==e) begin
                        f_issued[e]<=1;f_count[e]<=4;
                    end
                    if(f_due[e]) f_done[e]<=1;
                end
            end
        end
    end
    always @(posedge clk) if(rst_n) begin
        assert(capture_valid == (|f_due));
        assert($onehot0(f_due));
        assert(reserved_q==f_live);
        assert(done_q==f_done);
        if(capture_valid) begin
            assert(capture_entry<9);
            assert(f_due[capture_entry]);
        end
        if(alloc_fire) assert(!f_live[alloc_entry] ||
                            (retire_fire && retire_entry==alloc_entry));
        if(issue_success) assert(f_live[issue_entry] &&
                                 !f_issued[issue_entry] && !f_done[issue_entry]);
        if(retire_fire) assert(f_live[retire_entry] && f_done[retire_entry]);
        for(integer e=0;e<9;e=e+1) begin
            assert(f_count[e]<=4);
            if(f_count[e]!=0) assert(f_live[e] && f_issued[e] && !f_done[e]);
        end
        for(integer k=0;k<4;k=k+1)
            if(ret_valid_q[k]) begin
                assert(ret_entry_q[k]<9);
                assert(f_count[ret_entry_q[k]]==(4-k));
            end
        cover(capture_valid);
        cover((|f_done) && !retire_fire && capture_valid);
    end
`ifdef FORMAL_DATA_FULL

    reg [127:0] f_data [0:8];
    reg [8:0] f_pc=0;
    always @(posedge clk) begin
        if(!rst_n) begin
            f_pc<=0;
            for(integer e=0;e<9;e=e+1) f_data[e]<=0;
        end else begin
            for(integer e=0;e<9;e=e+1) begin
                if((alloc_fire && alloc_entry==e) ||
                   (retire_fire && retire_entry==e)) begin
                    f_data[e]<=0;f_pc[e]<=0;
                end else if(f_due[e]) begin
                    f_data[e]<=mem_rdata;f_pc[e]<=pc_err;
                end
            end
        end
    end
    always @(posedge clk) if(rst_n) begin
        for(integer e=0;e<9;e=e+1) begin
            assert(data_q[e]==f_data[e]);
            assert(pc_err_q[e]==f_pc[e]);
        end
        if(rsp_entry<9 && f_done[rsp_entry]) begin
            assert(rsp_data==f_data[rsp_entry]);
            assert(rsp_pc_err==f_pc[rsp_entry]);
        end
        cover(capture_valid && mem_rdata==0 && !pc_err);
        cover(capture_valid && pc_err);
    end
`endif
`endif
// END CMDBUF NATIVE FORMAL MONITOR
