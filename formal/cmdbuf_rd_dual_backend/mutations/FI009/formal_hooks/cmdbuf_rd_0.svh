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
