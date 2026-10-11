module cmdbuf_rd_checker (
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
  input wire [7:0] rw_rd_gnt,
  input wire [2:0] arready,
  input wire [2:0] rvalid,
  input wire [127:0] rdata,
  input wire [7:0] rid,
  input wire [4:0] r_port_id,
  input wire [2:0] raddr,
  input wire [1:0] rresp,
  input wire [7:0] req,
  input wire [11:0] arb_addr,
  input wire [3:0] pending_cnt
);
reg uc_past_valid = 1'b0;
always @(posedge clk) uc_past_valid <= 1'b1;
always @(posedge clk) begin
  if (!uc_past_valid) M_CK_ENV_RESET_FIRST: assume (!rst_n);
end
always @(posedge clk) begin
  if (uc_past_valid) M_CK_ENV_RESET_RELEASE: assume (rst_n);
end
always @(posedge clk) begin
  if (1'b1) M_CK_ENV_SRC: assume (!arvalid || src < 3);
end
always @(posedge clk) begin
  if (1'b1) M_CK_ENV_ARRESP: assume (!arvalid || arresp == 0 || arresp == 3);
end
always @(posedge clk) begin
  if (1'b1) M_CK_ENV_READY: assume ((arready != 0) || !arvalid);
end
always @(posedge clk) begin
  if (1'b1) A_CK_PIPE_REQ_ONEHOT: assert ($onehot0(req));
end
always @(posedge clk) begin
  G_A_CK_PIPE_REQ_ONEHOT: cover ((1'b1) && (1'b1));
end
always @(posedge clk) begin
  if (1'b1) A_CK_R_ONEHOT: assert ($onehot0(rvalid));
end
always @(posedge clk) begin
  G_A_CK_R_ONEHOT: cover ((1'b1) && (1'b1));
end
always @(posedge clk) begin
  if (1'b1) A_CK_R_READY: assert ((rvalid & ~rready) == 0);
end
always @(posedge clk) begin
  G_A_CK_R_READY: cover ((1'b1) && (1'b1));
end
always @(posedge clk) begin
  if (uc_past_valid && !$past(rst_n)) A_CK_RESET_PENDING: assert (pending_cnt == 0);
end
always @(posedge clk) begin
  G_A_CK_RESET_PENDING: cover ((uc_past_valid && !$past(rst_n)) && (1'b1));
end
always @(posedge clk) begin
  if (1'b1) A_CK_RESET_READY: assert ((!rst_n ? arready == 0 : (!uc_past_valid || $past(rst_n) || arready == 7)));
end
always @(posedge clk) begin
  G_A_CK_RESET_READY: cover ((1'b1) && (1'b1));
end
always @(posedge clk) begin
  if (req == 0) A_CK_IDLE_ARB: assert (arb_addr == 0);
end
always @(posedge clk) begin
  G_A_CK_IDLE_ARB: cover ((req == 0) && (1'b1));
end
always @(posedge clk) begin
  if (rvalid == 0) A_CK_IDLE_RPAYLOAD: assert (rdata == 0 && rid == 0 && r_port_id == 0 && raddr == 0 && rresp == 0);
end
always @(posedge clk) begin
  G_A_CK_IDLE_RPAYLOAD: cover ((rvalid == 0) && (1'b1));
end
always @(posedge clk) begin
  if (1'b1) C_CK_CV_AR0: cover (arvalid && src == 0 && arready[0]);
end
always @(posedge clk) begin
  if (1'b1) C_CK_CV_AR1: cover (arvalid && src == 1 && arready[1]);
end
always @(posedge clk) begin
  if (1'b1) C_CK_CV_AR2: cover (arvalid && src == 2 && arready[2]);
end
always @(posedge clk) begin
  if (1'b1) C_CK_CV_R0: cover (rvalid[0] && rready[0]);
end
always @(posedge clk) begin
  if (1'b1) C_CK_CV_R1: cover (rvalid[1] && rready[1]);
end
always @(posedge clk) begin
  if (1'b1) C_CK_CV_R2: cover (rvalid[2] && rready[2]);
end
always @(posedge clk) begin
  if (1'b1) C_CK_CV_AR_ONLY_GRANT: cover ((|req) && (|(req & ar_rd_gnt)) && !(|(req & rw_rd_gnt)));
end
always @(posedge clk) begin
  if (1'b1) C_CK_CV_RW_ONLY_GRANT: cover ((|req) && (|(req & rw_rd_gnt)) && !(|(req & ar_rd_gnt)));
end
always @(posedge clk) begin
  if (1'b1) C_CK_CV_WRONG_GRANT: cover ((|req) && (|(ar_rd_gnt & rw_rd_gnt & ~req)) && !(|(req & ar_rd_gnt & rw_rd_gnt)));
end
endmodule
