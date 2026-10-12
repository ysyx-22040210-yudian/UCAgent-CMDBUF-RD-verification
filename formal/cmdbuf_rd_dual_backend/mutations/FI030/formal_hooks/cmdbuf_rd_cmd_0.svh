// BEGIN CMDBUF NATIVE FORMAL MONITOR

`ifdef FORMAL

    always @(posedge clk) begin
        assert(req==((rst_n && issue_valid_q)?(8'b1<<issue_bank_q):8'b0));
        assert(arb_addr==((rst_n && issue_valid_q)?issue_addr_q:12'b0));
        assert(pending_cnt==pending_q);
        assert(retire_entry==rsp_entry);
        assert(issue_entry==issue_entry_q);
    end
`endif
// END CMDBUF NATIVE FORMAL MONITOR
