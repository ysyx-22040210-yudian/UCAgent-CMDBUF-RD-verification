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
            ret_entry_q[0] <= issue_success ? (issue_entry ^ 4'd1) : 4'b0;
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

`ifdef FORMAL

    reg [3:0] f_delay_history=0;
    always @(posedge clk)
        if(!rst_n) f_delay_history<=0;
        else f_delay_history<={f_delay_history[2:0],1'b1};
    always @(posedge clk) if(rst_n) begin
        if(f_delay_history[0]) begin
            assert(ret_valid_q[0]==$past(issue_success));
            if(ret_valid_q[0]) assert(ret_entry_q[0]==$past(issue_entry));
        end
        if(f_delay_history[1]) begin
            assert(ret_valid_q[1]==$past(issue_success,2));
            if(ret_valid_q[1]) assert(ret_entry_q[1]==$past(issue_entry,2));
        end
        if(f_delay_history[2]) begin
            assert(ret_valid_q[2]==$past(issue_success,3));
            if(ret_valid_q[2]) assert(ret_entry_q[2]==$past(issue_entry,3));
        end
        if(f_delay_history[3]) begin
            assert(capture_valid==$past(issue_success,4));
            if(capture_valid) assert(capture_entry==$past(issue_entry,4));
        end else assert(!capture_valid);
        cover(capture_valid);
    end
`endif
// END CMDBUF NATIVE FORMAL MONITOR
endmodule
`default_nettype wire
