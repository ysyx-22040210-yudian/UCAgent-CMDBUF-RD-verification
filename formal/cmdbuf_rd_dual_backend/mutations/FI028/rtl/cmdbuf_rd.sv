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
        .capture_entry, .mem_rdata, .pc_err, .mutation_rready(rready), .rsp_entry, .rsp_data,
        .rsp_pc_err
    );
    assign rdata = (|rvalid) ? rsp_data : 128'b0;
// BEGIN CMDBUF NATIVE FORMAL MONITOR

`ifdef FORMAL

    // F_EXT: event consistency is asserted, never assumed.
    always @(posedge clk) if (rst_n) begin
        assert(alloc_fire == (arvalid && (src < 3) &&
                             ((src < 3) ? arready[src] : 1'b0)));
        assert(retire_fire == (|(rvalid & rready)));
        assert(issue_success == (|(req & ar_rd_gnt & rw_rd_gnt)));
        assert($onehot0(req));
        assert($onehot0(rvalid));
        assert((rvalid & ~rready) == 0);
        assert(rdata == ((|rvalid) ? rsp_data : 128'b0));
        if (alloc_fire) assert(alloc_entry < 9);
        if (retire_fire) assert(retire_entry < 9);
        if (issue_success) assert(issue_entry < 9);
        if (capture_valid) assert(capture_entry < 9);
    end
    reg [2:0] f_lifecycle = 0;
    reg [3:0] f_life_entry = 0;
    always @(posedge clk) begin
        if (!rst_n) begin f_lifecycle <= 0; f_life_entry <= 0; end
        else begin
            if (f_lifecycle == 0 && alloc_fire) begin
                f_life_entry <= alloc_entry; f_lifecycle <= 1;
            end
            if (f_lifecycle == 1 && issue_success && issue_entry == f_life_entry)
                f_lifecycle <= 2;
            if (f_lifecycle == 2 && capture_valid && capture_entry == f_life_entry)
                f_lifecycle <= 3;
            if (f_lifecycle == 3 && retire_fire && retire_entry == f_life_entry)
                f_lifecycle <= 4;
            cover(f_lifecycle == 4);
            cover(alloc_fire && issue_success && capture_valid && retire_fire);
        end
    end
`endif
// END CMDBUF NATIVE FORMAL MONITOR
endmodule
`default_nettype wire
