`default_nettype none
module cmdbuf_rd_formal(input wire clk);

    wire rst_n;
    wire arvalid;
    wire [2:0] arready;
    wire [17:0] araddr;
    wire [1:0] src;
    wire [7:0] arid;
    wire [4:0] ar_port_id;
    wire [1:0] arresp;
    wire [2:0] rvalid;
    wire [2:0] rready;
    wire [127:0] rdata;
    wire [7:0] rid;
    wire [4:0] r_port_id;
    wire [2:0] raddr;
    wire [1:0] rresp;
    wire [7:0] req;
    wire [11:0] arb_addr;
    wire [3:0] pending_cnt;
    wire [7:0] ar_rd_gnt;
    // [7:0]: even banks; [15:8]: odd banks, matching the original packed order.
    wire [15:0] rd_mem_status;
    wire [127:0] mem_rdata;
    wire pc_err;
    wire [7:0] rw_rd_gnt;
reg [12:0] input_cycle = 13'd0;
reg [1:0] input_source = 2'd0;
always @(posedge clk) begin
    if (input_cycle!=8191) input_cycle<=input_cycle+1'b1;
    if (input_cycle==0 || input_source==2) input_source<=0;
    else input_source<=input_source+1'b1;
end
assign rst_n=(input_cycle!=0);
assign arvalid=(input_cycle!=0 && input_cycle<=4100 && (|arready));
assign src=input_source;
assign araddr=18'd0;
assign arid=input_cycle[7:0];
assign ar_port_id=input_cycle[4:0];
assign arresp=2'b00;
assign rready=3'b111;
assign rd_mem_status=16'd0;
assign ar_rd_gnt=8'hff;
assign rw_rd_gnt=8'hff;
assign mem_rdata=128'd0;
assign pc_err=1'b0;

cmdbuf_rd dut (
    .clk(clk),
    .rst_n(rst_n),
    .arvalid(arvalid),
    .arready(arready),
    .araddr(araddr),
    .src(src),
    .arid(arid),
    .ar_port_id(ar_port_id),
    .arresp(arresp),
    .rvalid(rvalid),
    .rready(rready),
    .rdata(rdata),
    .rid(rid),
    .r_port_id(r_port_id),
    .raddr(raddr),
    .rresp(rresp),
    .req(req),
    .arb_addr(arb_addr),
    .pending_cnt(pending_cnt),
    .ar_rd_gnt(ar_rd_gnt),
    .rd_mem_status(rd_mem_status),
    .mem_rdata(mem_rdata),
    .pc_err(pc_err),
    .rw_rd_gnt(rw_rd_gnt)
);
cmdbuf_rd_port_sva check_ports (
    .clk(clk),
    .rst_n(rst_n),
    .arvalid(arvalid),
    .arready(arready),
    .araddr(araddr),
    .src(src),
    .arid(arid),
    .ar_port_id(ar_port_id),
    .arresp(arresp),
    .rvalid(rvalid),
    .rready(rready),
    .rdata(rdata),
    .rid(rid),
    .r_port_id(r_port_id),
    .raddr(raddr),
    .rresp(rresp),
    .req(req),
    .arb_addr(arb_addr),
    .pending_cnt(pending_cnt),
    .ar_rd_gnt(ar_rd_gnt),
    .rd_mem_status(rd_mem_status),
    .mem_rdata(mem_rdata),
    .pc_err(pc_err),
    .rw_rd_gnt(rw_rd_gnt)
);
endmodule
`default_nettype wire
