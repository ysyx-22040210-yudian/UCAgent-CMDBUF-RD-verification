`default_nettype none
module cmdbuf_rd_formal (
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
    // Prove the unmodified CMD component for a superset of top-level inputs.
    // Capture and selected parity are unconstrained component inputs.
    (* anyseq *) reg capture_valid;
    (* anyseq *) reg [3:0] capture_entry;
    (* anyseq *) reg rsp_pc_err;
    wire alloc_fire,retire_fire,issue_success;
    wire [3:0] alloc_entry,retire_entry,issue_entry,rsp_entry;
    assign rdata=128'b0;
    cmdbuf_rd_cmd dut (.*);
    reg f_started = 0;
    always @(posedge clk) begin
        f_started <= 1;
        if (!f_started) assume(!rst_n);
        else assume(rst_n);
        if(arvalid) begin
            assume(src < 3);
            assume(arresp == 2'b00 || arresp == 2'b11);
        end
        // Stronger-domain proof: no ready-to-valid feedback assumption.
    end
endmodule
