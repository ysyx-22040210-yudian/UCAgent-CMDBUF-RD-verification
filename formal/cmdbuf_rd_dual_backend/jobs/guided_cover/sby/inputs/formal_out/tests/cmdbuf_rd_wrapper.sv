module cmdbuf_rd_wrapper (
  input wire clk,
  input wire rst_n,
  input wire arvalid,
  input wire [17:0] araddr,
  input wire [1:0] src,
  input wire [7:0] arid,
  input wire [4:0] ar_port_id,
  input wire [1:0] arresp,
  input wire [2:0] rready,
  input wire [7:0] ar_rd_gnt,
  input wire [15:0] rd_mem_status,
  input wire [127:0] mem_rdata,
  input wire pc_err,
  input wire [7:0] rw_rd_gnt
);
wire [2:0] arready;
wire [2:0] rvalid;
wire [127:0] rdata;
wire [7:0] rid;
wire [4:0] r_port_id;
wire [2:0] raddr;
wire [1:0] rresp;
wire [7:0] req;
wire [11:0] arb_addr;
wire [3:0] pending_cnt;
cmdbuf_rd u_dut (.clk(clk), .rst_n(rst_n), .arvalid(arvalid), .araddr(araddr), .src(src), .arid(arid), .ar_port_id(ar_port_id), .arresp(arresp), .rready(rready), .ar_rd_gnt(ar_rd_gnt), .rd_mem_status(rd_mem_status), .mem_rdata(mem_rdata), .pc_err(pc_err), .rw_rd_gnt(rw_rd_gnt), .arready(arready), .rvalid(rvalid), .rdata(rdata), .rid(rid), .r_port_id(r_port_id), .raddr(raddr), .rresp(rresp), .req(req), .arb_addr(arb_addr), .pending_cnt(pending_cnt));
cmdbuf_rd_checker u_checker (.clk(clk), .rst_n(rst_n), .arvalid(arvalid), .araddr(araddr), .src(src), .arid(arid), .ar_port_id(ar_port_id), .arresp(arresp), .rready(rready), .ar_rd_gnt(ar_rd_gnt), .rd_mem_status(rd_mem_status), .mem_rdata(mem_rdata), .pc_err(pc_err), .rw_rd_gnt(rw_rd_gnt), .arready(arready), .rvalid(rvalid), .rdata(rdata), .rid(rid), .r_port_id(r_port_id), .raddr(raddr), .rresp(rresp), .req(req), .arb_addr(arb_addr), .pending_cnt(pending_cnt));
reg [0:0] uc_reset_count = 0;
always @(posedge clk) begin
  if (uc_reset_count < 1) uc_reset_count <= uc_reset_count + 1'b1;
  M_ENV_RESET: assume (rst_n == ((uc_reset_count < 1) ? 1'b0 : 1'b1));
end
endmodule
