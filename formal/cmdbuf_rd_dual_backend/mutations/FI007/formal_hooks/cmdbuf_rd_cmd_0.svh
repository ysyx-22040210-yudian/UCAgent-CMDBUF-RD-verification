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

`ifdef FORMAL

    (* anyconst *) reg[3:0] f_local_entry;
    always @* assume(f_local_entry<9);
    reg f_local_past=0;
    always @(posedge clk) f_local_past<=1;
    always @(posedge clk) if(rst_n && f_local_past && $past(rst_n)) begin
        assert(issue_valid_q==$past(select_valid));
        if(issue_valid_q) begin
            assert(issue_entry_q==$past(select_entry));
            assert(issue_bank_q==$past(addr_q[select_entry][5:3]));
            assert(issue_addr_q==$past(addr_q[select_entry][17:6]));
        end
        if($past(alloc_fire) && $past(alloc_entry)==f_local_entry) begin
            assert(valid_q[f_local_entry] && !issued_q[f_local_entry] &&
                   !done_q[f_local_entry]);
            assert(addr_q[f_local_entry]==$past(araddr));
            assert(src_q[f_local_entry]==$past(src));
            assert(id_q[f_local_entry]==$past(arid));
            assert(port_q[f_local_entry]==$past(ar_port_id));
            assert(arresp_q[f_local_entry]==$past(arresp));
        end else if($past(retire_fire) && $past(retire_entry)==f_local_entry) begin
            assert(!valid_q[f_local_entry] && !issued_q[f_local_entry] &&
                   !done_q[f_local_entry]);
        end else begin
            assert(valid_q[f_local_entry]==$past(valid_q[f_local_entry]));
            assert(issued_q[f_local_entry]==($past(issued_q[f_local_entry]) ||
                  ($past(issue_success) && $past(issue_entry)==f_local_entry)));
            assert(done_q[f_local_entry]==($past(done_q[f_local_entry]) ||
                  ($past(capture_valid) && $past(capture_entry)==f_local_entry)));
            assert(addr_q[f_local_entry]==$past(addr_q[f_local_entry]));
            assert(src_q[f_local_entry]==$past(src_q[f_local_entry]));
            assert(id_q[f_local_entry]==$past(id_q[f_local_entry]));
            assert(port_q[f_local_entry]==$past(port_q[f_local_entry]));
            assert(arresp_q[f_local_entry]==$past(arresp_q[f_local_entry]));
        end
    end
`endif
// END CMDBUF NATIVE FORMAL MONITOR
