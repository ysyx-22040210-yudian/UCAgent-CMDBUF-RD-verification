// Synthesizable Verilog-2001; preserves the aligned CMDBUF/OTB behavior.
`default_nettype none
module cmdbuf_rd (
    input wire clk,
    input wire rst_n,
    input wire arvalid,
    output wire [2:0] arready,
    input wire [17:0] araddr,
    input wire [1:0] src,
    input wire [7:0] arid,
    input wire [4:0] ar_port_id,
    input wire [1:0] arresp,
    output wire [2:0] rvalid,
    input wire [2:0] rready,
    output wire [127:0] rdata,
    output wire [7:0] rid,
    output wire [4:0] r_port_id,
    output wire [2:0] raddr,
    output wire [1:0] rresp,
    output wire [7:0] req,
    output wire [11:0] arb_addr,
    output wire [3:0] pending_cnt,
    input wire [7:0] ar_rd_gnt,
    // [7:0]: even banks; [15:8]: odd banks, matching the original packed order.
    input wire [15:0] rd_mem_status,
    input wire [127:0] mem_rdata,
    input wire pc_err,
    input wire [7:0] rw_rd_gnt
);
    wire alloc_fire, retire_fire, issue_success, capture_valid;
    wire [3:0] alloc_entry, retire_entry, issue_entry, capture_entry, rsp_entry;
    wire [127:0] rsp_data;
    wire rsp_pc_err;

    cmdbuf_rd_cmd u_cmd (
        .clk(clk), .rst_n(rst_n), .arvalid(arvalid), .arready(arready), .araddr(araddr), .src(src), .arid(arid),
        .ar_port_id(ar_port_id), .arresp(arresp), .rvalid(rvalid), .rready(rready), .rid(rid), .r_port_id(r_port_id),
        .raddr(raddr), .rresp(rresp), .req(req), .arb_addr(arb_addr), .pending_cnt(pending_cnt), .ar_rd_gnt(ar_rd_gnt),
        .rd_mem_status(rd_mem_status), .rw_rd_gnt(rw_rd_gnt), .alloc_fire(alloc_fire), .alloc_entry(alloc_entry),
        .retire_fire(retire_fire), .retire_entry(retire_entry), .issue_success(issue_success), .issue_entry(issue_entry),
        .capture_valid(capture_valid), .capture_entry(capture_entry), .rsp_entry(rsp_entry), .rsp_pc_err(rsp_pc_err)
    );
    cmdbuf_rd_otb u_otb (
        .clk(clk), .rst_n(rst_n), .alloc_fire(alloc_fire), .alloc_entry(alloc_entry), .retire_fire(retire_fire),
        .retire_entry(retire_entry), .issue_success(issue_success), .issue_entry(issue_entry), .capture_valid(capture_valid),
        .capture_entry(capture_entry), .mem_rdata(mem_rdata), .pc_err(pc_err), .rsp_entry(rsp_entry), .rsp_data(rsp_data),
        .rsp_pc_err(rsp_pc_err)
    );
    assign rdata = (|rvalid) ? rsp_data : 128'b0;

`ifdef FORMAL
`include "inputs/formal_hooks/cmdbuf_rd_0.svh"
`endif
endmodule
`default_nettype wire
