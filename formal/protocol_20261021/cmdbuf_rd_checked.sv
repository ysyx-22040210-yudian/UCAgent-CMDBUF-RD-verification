`default_nettype none
module cmdbuf_rd_checked (
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
    // Checker-only adversarial values in domains the contract leaves unchecked.
    // The DUT and C++ oracle still exchange the actual top-level signals.
    cmdbuf_rd_port_sva checks (
        .arvalid(rst_n ? arvalid : 1'b1), .src(rst_n ? src : 2'd3),
        .arresp(rst_n ? arresp : 2'b01),
        .req(rst_n ? req : 8'hff), .rvalid(rst_n ? rvalid : 3'b111),
        .arb_addr((|req) ? arb_addr : 12'hbad),
        .rdata((|rvalid) ? rdata : 128'hdeadc0de_01234567_89abcdef_76543210),
        .rid((|rvalid) ? rid : 8'ha5),
        .r_port_id((|rvalid) ? r_port_id : 5'h17),
        .raddr((|rvalid) ? raddr : 3'b101),
        .rresp((|rvalid) ? rresp : 2'b10),
        .*
    );
endmodule
`default_nettype wire
