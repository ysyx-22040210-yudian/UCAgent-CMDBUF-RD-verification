// Current SystemVerilog RTL: protocol corrections confirmed 2026-10-21.
// Compile rtl/files.f; the sibling .v files are the historical implementation.
`default_nettype none
module cmdbuf_rd_otb (
    input wire clk,
    input wire rst_n,
    input wire alloc_fire,
    input wire [3:0] alloc_entry,
    input wire retire_fire,
    input wire [3:0] retire_entry,
    input wire issue_success,
    input wire [3:0] issue_entry,
    output wire capture_valid,
    output wire [3:0] capture_entry,
    input wire [127:0] mem_rdata,
    input wire pc_err,
    input wire [3:0] rsp_entry,
    output reg [127:0] rsp_data,
    output reg rsp_pc_err
);
    reg [3:0] ret_valid_q;
    reg [3:0] ret_entry_q [0:3];
    reg [127:0] data_q [0:8];
    reg [8:0] pc_err_q, reserved_q, done_q;

    // The old last stage is sampled at the edge four cycles after issue.
    assign capture_valid = rst_n && ret_valid_q[3];
    assign capture_entry = ret_entry_q[3];
    always @* begin
        rsp_data = 128'b0;
        rsp_pc_err = 1'b0;
        if (rsp_entry < 9) begin
            rsp_data = data_q[rsp_entry];
            rsp_pc_err = pc_err_q[rsp_entry];
        end
    end

    always @(posedge clk or negedge rst_n) begin : p_2
        integer k;
        integer i;

        if (!rst_n) begin
            ret_valid_q <= 4'b0;
            pc_err_q <= 9'b0;
            reserved_q <= 9'b0;
            done_q <= 9'b0;
            for (k = 0; k < 4; k = k + 1) ret_entry_q[k] <= 4'b0;
            for (i = 0; i < 9; i = i + 1) data_q[i] <= 128'b0;
        end else begin
            // No stalls, including empty cycles and upstream backpressure.
            ret_valid_q[0] <= issue_success;
            ret_entry_q[0] <= issue_success ? issue_entry : 4'b0;
            for (k = 1; k < 4; k = k + 1) begin
                ret_valid_q[k] <= ret_valid_q[k-1];
                ret_entry_q[k] <= ret_valid_q[k-1] ? ret_entry_q[k-1] : 4'b0;
            end
            for (i = 0; i < 9; i = i + 1) begin
                if (alloc_fire && (alloc_entry == i[3:0])) begin
                    reserved_q[i] <= 1'b1;
                    done_q[i] <= 1'b0;
                    data_q[i] <= 128'b0;
                    pc_err_q[i] <= 1'b0;
                end else if (retire_fire && (retire_entry == i[3:0])) begin
                    reserved_q[i] <= 1'b0;
                    done_q[i] <= 1'b0;
                    data_q[i] <= 128'b0;
                    pc_err_q[i] <= 1'b0;
                end else if (capture_valid && (capture_entry == i[3:0])) begin
                    data_q[i] <= mem_rdata;
                    pc_err_q[i] <= pc_err;
                    done_q[i] <= 1'b1;
                end
            end
        end
    end
`ifndef SYNTHESIS
    // Verilog simulation diagnostics; no SystemVerilog assertion primitives.
    task check_failure;
        input [511:0] message;
        begin
            $display("%0t %m CMDBUF_CHECK_FAILURE: %0s", $time, message);
            $stop;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Assertions are disabled while the asynchronous reset is active.
        end else begin
            if (alloc_fire)
                if ((!reserved_q[alloc_entry] || (retire_fire && (retire_entry == alloc_entry))) !== 1'b1) check_failure("OTB double allocation");
            if (issue_success)
                if ((reserved_q[issue_entry] && !done_q[issue_entry]) !== 1'b1) check_failure("unreserved OTB issue");
            if (capture_valid)
                if ((reserved_q[capture_entry] && !done_q[capture_entry]) !== 1'b1) check_failure("invalid OTB capture");
            if (retire_fire)
                if ((reserved_q[retire_entry] && done_q[retire_entry]) !== 1'b1) check_failure("OTB retirement before data");
            if (((done_q & ~reserved_q) == 0) !== 1'b1) check_failure("OTB done without reservation");
        end
    end
`endif
endmodule
`default_nettype wire
