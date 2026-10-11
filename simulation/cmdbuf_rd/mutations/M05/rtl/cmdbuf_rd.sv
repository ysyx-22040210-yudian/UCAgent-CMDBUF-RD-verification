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
    );
    cmdbuf_rd_otb u_otb (
        .clk, .rst_n, .alloc_fire, .alloc_entry, .retire_fire,
        .retire_entry, .issue_success, .issue_entry, .capture_valid,
        .capture_entry, .mem_rdata, .pc_err, .rsp_entry, .rsp_data,
        .rsp_pc_err
    );
    assign rdata = (|rvalid) ? rsp_data : 128'b0;
endmodule
`default_nettype wire
