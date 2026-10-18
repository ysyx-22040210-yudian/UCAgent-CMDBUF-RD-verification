// One expression source for native concurrent SVA and Yosys immediate properties.
// Select CMDBUF_NATIVE_SVA for a SystemVerilog assertion frontend.
`ifdef CMDBUF_NATIVE_SVA
  `define TP_ASSERT(name, expr) name: assert property (@(posedge clk) (expr));
  `define TP_ASSUME(name, expr) name: assume property (@(posedge clk) (expr));
  `define TP_COVER(name, expr) name: cover property (@(posedge clk) (expr));
`else
  `define TP_ASSERT(name, expr) always @(posedge clk) begin : name assert (expr); end
  `define TP_ASSUME(name, expr) always @(posedge clk) begin : name assume (expr); end
  `define TP_COVER(name, expr) always @(posedge clk) begin : name cover (expr); end
`endif
