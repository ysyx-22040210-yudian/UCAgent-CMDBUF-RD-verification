`default_nettype none
module cmdbuf_rd_formal (
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
    // Bank-major unpacked array: status[bank][half], 0=idle, 1=busy.
    input wire [1:0] rd_mem_status [7:0],
    input wire [127:0] mem_rdata,
    input wire pc_err,
    input wire [7:0] rw_rd_gnt
);
    cmdbuf_rd dut (.*);
    cmdbuf_rd_relaxed_sva checks (.*);
endmodule
`default_nettype wire
