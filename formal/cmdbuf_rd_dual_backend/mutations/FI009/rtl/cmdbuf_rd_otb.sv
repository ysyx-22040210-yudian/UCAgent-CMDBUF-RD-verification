`default_nettype none
module cmdbuf_rd_otb (
    input  logic clk,
    input  logic rst_n,
    input  logic alloc_fire,
    input  logic [3:0] alloc_entry,
    input  logic retire_fire,
    input  logic [3:0] retire_entry,
    input  logic issue_success,
    input  logic [3:0] issue_entry,
    output logic capture_valid,
    output logic [3:0] capture_entry,
    input  logic [127:0] mem_rdata,
    input  logic pc_err,
    input  logic [3:0] rsp_entry,
    output logic [127:0] rsp_data,
    output logic rsp_pc_err
);
    logic [3:0] ret_valid_q;
    logic [3:0] ret_entry_q [0:3];
    logic [127:0] data_q [0:8];
    logic [8:0] pc_err_q, reserved_q, done_q;

    // The old last stage is sampled at the edge four cycles after issue.
    assign capture_valid = rst_n && ret_valid_q[3];
    assign capture_entry = ret_entry_q[3];
    always_comb begin
        rsp_data = '0;
        rsp_pc_err = 1'b0;
        if (rsp_entry < 9) begin
            rsp_data = data_q[rsp_entry];
            rsp_pc_err = pc_err_q[rsp_entry];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ret_valid_q <= '0;
            pc_err_q <= '0;
            reserved_q <= '0;
            done_q <= '0;
            for (int k = 0; k < 4; k++) ret_entry_q[k] <= '0;
            for (int i = 0; i < 9; i++) data_q[i] <= '0;
        end else begin
            // No stalls, including empty cycles and upstream backpressure.
            ret_valid_q[0] <= issue_success;
            ret_entry_q[0] <= issue_success ? issue_entry : 4'b0;
            for (int k = 1; k < 4; k++) begin
                ret_valid_q[k] <= ret_valid_q[k-1];
                ret_entry_q[k] <= ret_valid_q[k-1] ? ret_entry_q[k-1] : 4'b0;
            end
            for (int i = 0; i < 9; i++) begin
                if (alloc_fire && (alloc_entry == 4'(i))) begin
                    reserved_q[i] <= 1'b1;
                    done_q[i] <= 1'b0;
                    data_q[i] <= '0;
                    pc_err_q[i] <= 1'b0;
                end else if (retire_fire && (retire_entry == 4'(i))) begin
                    reserved_q[i] <= 1'b0;
                    done_q[i] <= 1'b0;
                    data_q[i] <= '0;
                    pc_err_q[i] <= 1'b0;
                end else if (capture_valid && (capture_entry == 4'(i))) begin
                    data_q[i] <= mem_rdata;
                    pc_err_q[i] <= pc_err;
                    done_q[i] <= 1'b1;
                end
            end
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Assertions are disabled while the asynchronous reset is active.
        end else begin
            if (alloc_fire)
                assert (!reserved_q[alloc_entry] || (retire_fire && (retire_entry == alloc_entry))) else $fatal(1, "OTB double allocation");
            if (issue_success)
                assert (reserved_q[issue_entry] && !done_q[issue_entry]) else $fatal(1, "unreserved OTB issue");
            if (capture_valid)
                assert (reserved_q[capture_entry] && !done_q[capture_entry]) else $fatal(1, "invalid OTB capture");
            if (retire_fire)
                assert (reserved_q[retire_entry] && done_q[retire_entry]) else $fatal(1, "OTB retirement before data");
            assert ((done_q & ~reserved_q) == 0) else $fatal(1, "OTB done without reservation");
        end
    end
`endif
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
endmodule
`default_nettype wire
