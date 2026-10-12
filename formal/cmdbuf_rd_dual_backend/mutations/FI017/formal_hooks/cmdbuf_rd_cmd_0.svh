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
// Independent specification FIFO, inserted inside cmdbuf_rd_cmd.
// No DUT state/event drives the reference machine.  alloc_entry is only
// an observed physical identity, checked before binding a new FIFO record.
`ifdef FORMAL_ORDER
    reg [3:0] fo_count_q, fo_count_d;
    reg [3:0] fo_entry_q [0:8], fo_entry_d [0:8];
    reg [17:0] fo_addr_q [0:8], fo_addr_d [0:8];
    reg [1:0] fo_src_q [0:8], fo_src_d [0:8];
    reg [7:0] fo_id_q [0:8], fo_id_d [0:8];
    reg [4:0] fo_port_q [0:8], fo_port_d [0:8];
    reg [1:0] fo_arresp_q [0:8], fo_arresp_d [0:8];
    reg fo_issued_q [0:8], fo_issued_d [0:8];
    reg fo_done_q [0:8], fo_done_d [0:8];
    reg [2:0] fo_left_q [0:8], fo_left_d [0:8];
    reg [1:0] fo_rr_q;
    reg fo_issue_valid_q;
    reg [3:0] fo_issue_entry_q;
    reg [2:0] fo_issue_bank_q;
    reg [11:0] fo_issue_addr_q;

    (* anyconst *) reg [3:0] fo_ei, fo_ej;
    always @* begin
        assume(fo_ei < 9);
        assume(fo_ej < 9);
    end

    reg [8:0] fo_live, fo_issued, fo_done, fo_due_mask;
    reg [8:0] fo_window, fo_base_window, fo_candidates;
    reg [7:0] fo_req;
    reg [11:0] fo_arb_addr;
    reg fo_success, fo_capture, fo_select_valid;
    reg [3:0] fo_capture_entry, fo_select_entry;
    reg [2:0] fo_select_bank;
    reg [11:0] fo_select_addr;
    reg [2:0] fo_head_valid, fo_head_done, fo_rvalid, fo_ready;
    reg [3:0] fo_head_pos [0:2];
    reg [3:0] fo_head_entry [0:2];
    reg fo_retire, fo_accept, fo_rsp_found;
    reg [1:0] fo_winner;
    reg [3:0] fo_retire_pos, fo_retire_entry;
    reg [7:0] fo_rid;
    reg [4:0] fo_rport;
    reg [2:0] fo_raddr;
    reg [1:0] fo_rresp;
    integer fo_occ [0:2];
    integer fo_after [0:2];
    integer fo_pending, fo_rank, fo_base_rank, fo_shared, fo_used_after;
    integer fo_scan, fo_write_pos, fo_pos_i, fo_pos_j;
    integer fo_issue_pos, fo_due_count;
    reg fo_sixth_idle, fo_older_pending, fo_reorder_wait;
    reg fo_seen_reorder_q, fo_seen_fail_q;
    reg [3:0] fo_failed_entry_q;
    reg fo_history_valid = 1'b0;
    always @(posedge clk) fo_history_valid <= 1'b1;

    // The current attempt is independently registered from the preceding
    // cycle's FIFO selection.  Grant success never gates the request itself.
    always @* begin
        fo_req = 8'b0;
        fo_arb_addr = 12'b0;
        if (rst_n && fo_issue_valid_q) begin
            fo_req = 8'b1 << fo_issue_bank_q;
            fo_arb_addr = fo_issue_addr_q;
        end
        fo_success = |(fo_req & ar_rd_gnt & rw_rd_gnt);
    end

    // FIFO order is acceptance order.  First locate each source's head over
    // ALL live records; only then test completion and current ready.
    always @* begin
        fo_live = 9'b0;
        fo_issued = 9'b0;
        fo_done = 9'b0;
        fo_due_mask = 9'b0;
        fo_due_count = 0;
        fo_capture = 1'b0;
        fo_capture_entry = 4'b0;
        fo_head_valid = 3'b0;
        fo_head_done = 3'b0;
        fo_pending = 0;
        fo_pos_i = 9;
        fo_pos_j = 9;
        fo_issue_pos = 9;
        for (integer x = 0; x < 3; x = x + 1) begin
            fo_occ[x] = 0;
            fo_head_pos[x] = 4'b0;
            fo_head_entry[x] = 4'b0;
        end
        for (integer p = 0; p < 9; p = p + 1) begin
            if (p < fo_count_q) begin
                fo_live[fo_entry_q[p]] = 1'b1;
                fo_issued[fo_entry_q[p]] = fo_issued_q[p];
                fo_done[fo_entry_q[p]] = fo_done_q[p];
                if (!fo_issued_q[p]) fo_pending = fo_pending + 1;
                if (fo_entry_q[p] == fo_ei) fo_pos_i = p;
                if (fo_entry_q[p] == fo_ej) fo_pos_j = p;
                if (fo_issue_valid_q && fo_entry_q[p] == fo_issue_entry_q)
                    fo_issue_pos = p;
                if (fo_left_q[p] == 3'd1) begin
                    fo_due_count = fo_due_count + 1;
                    fo_due_mask[fo_entry_q[p]] = 1'b1;
                    if (rst_n) begin
                        fo_capture = 1'b1;
                        fo_capture_entry = fo_entry_q[p];
                    end
                end
                for (integer x = 0; x < 3; x = x + 1) begin
                    if (fo_src_q[p] == x) begin
                        fo_occ[x] = fo_occ[x] + 1;
                        if (!fo_head_valid[x]) begin
                            fo_head_valid[x] = 1'b1;
                            fo_head_done[x] = fo_done_q[p];
                            fo_head_pos[x] = 4'(p);
                            fo_head_entry[x] = fo_entry_q[p];
                        end
                    end
                end
            end
        end

        fo_rsp_found = 1'b0;
        fo_winner = 2'b0;
        fo_scan = 0;
        for (integer offset = 0; offset < 3; offset = offset + 1) begin
            fo_scan = int'(fo_rr_q) + offset;
            if (fo_scan >= 3) fo_scan = fo_scan - 3;
            if (!fo_rsp_found && fo_head_valid[fo_scan] &&
                fo_head_done[fo_scan] && rready[fo_scan]) begin
                fo_rsp_found = 1'b1;
                fo_winner = 2'(fo_scan);
            end
        end
        fo_retire = rst_n && fo_rsp_found;
        fo_retire_pos = 4'b0;
        fo_retire_entry = 4'b0;
        fo_rvalid = 3'b0;
        fo_rid = 8'b0;
        fo_rport = 5'b0;
        fo_raddr = 3'b0;
        fo_rresp = 2'b0;
        if (fo_retire) begin
            fo_retire_pos = fo_head_pos[fo_winner];
            fo_retire_entry = fo_head_entry[fo_winner];
            fo_rvalid[fo_winner] = 1'b1;
            fo_rid = fo_id_q[fo_retire_pos];
            fo_rport = fo_port_q[fo_retire_pos];
            fo_raddr = fo_addr_q[fo_retire_pos][2:0];
            if (fo_arresp_q[fo_retire_pos] == 2'b11)
                fo_rresp = 2'b11;
            else if (rsp_pc_err)
                fo_rresp = 2'b01;
        end

        // Admission is computed from the model retirement, not DUT rvalid.
        fo_shared = 0;
        fo_used_after = 0;
        fo_ready = 3'b0;
        for (integer x = 0; x < 3; x = x + 1) begin
            fo_after[x] = fo_occ[x];
            if (fo_retire && fo_winner == x)
                fo_after[x] = fo_after[x] - 1;
            fo_used_after = fo_used_after + fo_after[x];
            if (fo_after[x] > 1)
                fo_shared = fo_shared + fo_after[x] - 1;
        end
        for (integer x = 0; x < 3; x = x + 1)
            fo_ready[x] = rst_n && (fo_used_after < 9) &&
                          ((fo_after[x] == 0) || (fo_shared < 6));
        fo_accept = 1'b0;
        if (src < 3) fo_accept = arvalid && fo_ready[src];

        // Count the unissued records before testing idle status.  A success
        // removes the current request before rank construction (6B); failure
        // preserves its window position while excluding it as a candidate.
        fo_rank = 0;
        fo_base_rank = 0;
        fo_window = 9'b0;
        fo_base_window = 9'b0;
        fo_candidates = 9'b0;
        fo_select_valid = 1'b0;
        fo_select_entry = 4'b0;
        fo_select_bank = 3'b0;
        fo_select_addr = 12'b0;
        fo_sixth_idle = 1'b0;
        fo_older_pending = 1'b0;
        fo_reorder_wait = 1'b0;
        for (integer p = 0; p < 9; p = p + 1) begin
            if (p < fo_count_q) begin
                if (!fo_issued_q[p]) begin
                    if (p < fo_issue_pos) fo_older_pending = 1'b1;
                    if (fo_base_rank < 5)
                        fo_base_window[fo_entry_q[p]] = 1'b1;
                    if (fo_base_rank == 5 &&
                        !rd_mem_status[fo_addr_q[p][6]][fo_addr_q[p][5:3]])
                        fo_sixth_idle = 1'b1;
                    fo_base_rank = fo_base_rank + 1;
                    if (!(fo_success && fo_entry_q[p] == fo_issue_entry_q)) begin
                        if (fo_rank < 5) begin
                            fo_window[fo_entry_q[p]] = 1'b1;
                            if (!(fo_issue_valid_q &&
                                  fo_entry_q[p] == fo_issue_entry_q) &&
                                !rd_mem_status[fo_addr_q[p][6]][fo_addr_q[p][5:3]]) begin
                                fo_candidates[fo_entry_q[p]] = 1'b1;
                                if (!fo_select_valid) begin
                                    fo_select_valid = 1'b1;
                                    fo_select_entry = fo_entry_q[p];
                                    fo_select_bank = fo_addr_q[p][5:3];
                                    fo_select_addr = fo_addr_q[p][17:6];
                                end
                            end
                        end
                        fo_rank = fo_rank + 1;
                    end
                end
                for (integer x = 0; x < 3; x = x + 1)
                    if (fo_src_q[p] == x && fo_done_q[p] &&
                        fo_head_valid[x] && !fo_head_done[x])
                        fo_reorder_wait = 1'b1;
            end
        end
    end

    // Delete the model RR winner, preserve the order of surviving records,
    // and append an independently accepted AR transaction as the youngest.
    // A four-count calendar advances every cycle, without reading capture.
    always @* begin
        fo_count_d = 4'b0;
        fo_write_pos = 0;
        for (integer p = 0; p < 9; p = p + 1) begin
            fo_entry_d[p] = 4'b0;
            fo_addr_d[p] = 18'b0;
            fo_src_d[p] = 2'b0;
            fo_id_d[p] = 8'b0;
            fo_port_d[p] = 5'b0;
            fo_arresp_d[p] = 2'b0;
            fo_issued_d[p] = 1'b0;
            fo_done_d[p] = 1'b0;
            fo_left_d[p] = 3'b0;
        end
        for (integer p = 0; p < 9; p = p + 1) begin
            if (p < fo_count_q && !(fo_retire && fo_retire_pos == p)) begin
                if (fo_write_pos < 9) begin
                    fo_entry_d[fo_write_pos] = fo_entry_q[p];
                    fo_addr_d[fo_write_pos] = fo_addr_q[p];
                    fo_src_d[fo_write_pos] = fo_src_q[p];
                    fo_id_d[fo_write_pos] = fo_id_q[p];
                    fo_port_d[fo_write_pos] = fo_port_q[p];
                    fo_arresp_d[fo_write_pos] = fo_arresp_q[p];
                    fo_issued_d[fo_write_pos] = fo_issued_q[p];
                    fo_done_d[fo_write_pos] = fo_done_q[p];
                    fo_left_d[fo_write_pos] = fo_left_q[p];
                    if (fo_left_q[p] != 0)
                        fo_left_d[fo_write_pos] = fo_left_q[p] - 3'd1;
                    if (fo_left_q[p] == 3'd1)
                        fo_done_d[fo_write_pos] = 1'b1;
                    if (fo_success && fo_entry_q[p] == fo_issue_entry_q) begin
                        fo_issued_d[fo_write_pos] = 1'b1;
                        fo_left_d[fo_write_pos] = 3'd4;
                    end
                end
                fo_write_pos = fo_write_pos + 1;
            end
        end
        if (fo_accept) begin
            if (fo_write_pos < 9) begin
                fo_entry_d[fo_write_pos] = alloc_entry;
                fo_addr_d[fo_write_pos] = araddr;
                fo_src_d[fo_write_pos] = src;
                fo_id_d[fo_write_pos] = arid;
                fo_port_d[fo_write_pos] = ar_port_id;
                fo_arresp_d[fo_write_pos] = arresp;
                fo_issued_d[fo_write_pos] = 1'b0;
                fo_done_d[fo_write_pos] = 1'b0;
                fo_left_d[fo_write_pos] = 3'b0;
            end
            fo_write_pos = fo_write_pos + 1;
        end
        fo_count_d = 4'(fo_write_pos);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fo_count_q <= 4'b0;
            fo_rr_q <= 2'b0;
            fo_issue_valid_q <= 1'b0;
            fo_issue_entry_q <= 4'b0;
            fo_issue_bank_q <= 3'b0;
            fo_issue_addr_q <= 12'b0;
            fo_seen_reorder_q <= 1'b0;
            fo_seen_fail_q <= 1'b0;
            fo_failed_entry_q <= 4'b0;
            for (integer p = 0; p < 9; p = p + 1) begin
                fo_entry_q[p] <= 4'b0;
                fo_addr_q[p] <= 18'b0;
                fo_src_q[p] <= 2'b0;
                fo_id_q[p] <= 8'b0;
                fo_port_q[p] <= 5'b0;
                fo_arresp_q[p] <= 2'b0;
                fo_issued_q[p] <= 1'b0;
                fo_done_q[p] <= 1'b0;
                fo_left_q[p] <= 3'b0;
            end
        end else begin
            fo_count_q <= fo_count_d;
            if (fo_retire)
                fo_rr_q <= (fo_winner == 2) ? 2'd0 : fo_winner + 2'd1;
            fo_issue_valid_q <= fo_select_valid;
            fo_issue_entry_q <= fo_select_valid ? fo_select_entry : 4'b0;
            fo_issue_bank_q <= fo_select_valid ? fo_select_bank : 3'b0;
            fo_issue_addr_q <= fo_select_valid ? fo_select_addr : 12'b0;
            if (fo_reorder_wait) fo_seen_reorder_q <= 1'b1;
            if (fo_issue_valid_q && !fo_success && !fo_seen_fail_q) begin
                fo_seen_fail_q <= 1'b1;
                fo_failed_entry_q <= fo_issue_entry_q;
            end
            for (integer p = 0; p < 9; p = p + 1) begin
                fo_entry_q[p] <= fo_entry_d[p];
                fo_addr_q[p] <= fo_addr_d[p];
                fo_src_q[p] <= fo_src_d[p];
                fo_id_q[p] <= fo_id_d[p];
                fo_port_q[p] <= fo_port_d[p];
                fo_arresp_q[p] <= fo_arresp_d[p];
                fo_issued_q[p] <= fo_issued_d[p];
                fo_done_q[p] <= fo_done_d[p];
                fo_left_q[p] <= fo_left_d[p];
            end
        end
    end

    always @(posedge clk) if (rst_n) begin
        A_ORDER_FIFO_COUNT: assert(fo_count_q <= 9 && fo_count_d <= 9);
        A_ORDER_FIFO_IDENTITIES: assert($countones(fo_live) == fo_count_q);
        A_ORDER_VALID_SET: assert(valid_q == fo_live);
        A_ORDER_ISSUED_SET: assert(issued_q == fo_issued);
        A_ORDER_DONE_SET: assert(done_q == fo_done);
        A_ORDER_PENDING_COUNT: assert(pending_cnt == fo_pending);
        A_ORDER_RR_POINTER: assert(rr_ptr_q == fo_rr_q && fo_rr_q < 3);
        A_ORDER_READY: assert(arready == fo_ready);
        A_ORDER_ACCEPT: assert(alloc_fire == fo_accept);
        if (fo_accept) begin
            A_ORDER_ALLOC_ID: assert(alloc_entry < 9);
            A_ORDER_ALLOC_OWNERSHIP:
                assert(!fo_live[alloc_entry] ||
                       (fo_retire && fo_retire_entry == alloc_entry));
        end
        A_ORDER_REQ: assert(req == fo_req);
        A_ORDER_ARB_ADDR: assert(arb_addr == fo_arb_addr);
        A_ORDER_ISSUE_VALID: assert(issue_valid_q == fo_issue_valid_q);
        A_ORDER_ISSUE_SUCCESS: assert(issue_success == fo_success);
        if (fo_issue_valid_q) begin
            A_ORDER_ISSUE_ID: assert(issue_entry == fo_issue_entry_q);
            A_ORDER_ISSUE_OWNER: assert(fo_issue_pos < fo_count_q);
            A_ORDER_ISSUE_PENDING: assert(!fo_issued[fo_issue_entry_q]);
        end
        A_ORDER_WINDOW: assert(window_mask == fo_window);
        A_ORDER_CANDIDATES: assert(candidate_mask == fo_candidates);
        A_ORDER_SELECT_VALID: assert(select_valid == fo_select_valid);
        if (fo_select_valid)
            A_ORDER_SELECT_ID: assert(select_entry == fo_select_entry);
        A_ORDER_DUE_UNIQUE: assert(fo_due_count <= 1);
        A_ORDER_CAPTURE_VALID: assert(capture_valid == fo_capture);
        if (fo_capture) begin
            A_ORDER_CAPTURE_ID: assert(capture_entry == fo_capture_entry);
            A_ORDER_NO_MEM_R_BYPASS:
                assert(!(fo_retire && fo_retire_entry == fo_capture_entry));
        end
        A_ORDER_RVALID: assert(rvalid == fo_rvalid);
        A_ORDER_RETIRE: assert(retire_fire == fo_retire);
        if (fo_retire) begin
            A_ORDER_RETIRE_ID: assert(retire_entry == fo_retire_entry &&
                                      rsp_entry == fo_retire_entry);
            A_ORDER_R_META: assert(rid == fo_rid && r_port_id == fo_rport &&
                                   raddr == fo_raddr && rresp == fo_rresp);
        end
        for (integer x = 0; x < 3; x = x + 1) begin
            // A_ORDER_SOURCE_COUNT
                 assert(occ_q[x] == fo_occ[x]);
            // A_ORDER_SOURCE_RESERVATION
                 assert(fo_occ[x] <= 7);
        end
        for (integer p = 0; p < 9; p = p + 1) begin
            if (p < fo_count_q) begin
                // A_ORDER_LIVE_ID_RANGE
                 assert(fo_entry_q[p] < 9);
                // A_ORDER_LIVE_SRC_RANGE
                 assert(fo_src_q[p] < 3);
                // A_ORDER_CALENDAR_STATE
                
                    assert(fo_left_q[p] <= 4 &&
                           (!fo_done_q[p] || fo_issued_q[p]) &&
                           ((fo_left_q[p] != 0) ==
                            (fo_issued_q[p] && !fo_done_q[p])));
                // A_ORDER_LIVE_META
                
                    assert(addr_q[fo_entry_q[p]] == fo_addr_q[p] &&
                           src_q[fo_entry_q[p]] == fo_src_q[p] &&
                           id_q[fo_entry_q[p]] == fo_id_q[p] &&
                           port_q[fo_entry_q[p]] == fo_port_q[p] &&
                           arresp_q[fo_entry_q[p]] == fo_arresp_q[p]);
            end
        end
        // older_q[i][j] means j precedes i.  The oracle is FIFO position,
        // with zero relations for dead entries and the diagonal.
        A_ORDER_FIFO_AGE:
            assert(older_q[fo_ei][fo_ej] ==
                   ((fo_pos_i < fo_count_q) && (fo_pos_j < fo_count_q) &&
                    (fo_pos_j < fo_pos_i)));

        C_ORDER_6B_WINDOW_ADVANCE:
            cover(fo_success && fo_select_valid &&
                  !fo_base_window[fo_select_entry]);
        C_ORDER_WINDOW_SIXTH_BLOCKED:
            cover(fo_history_valid && $past(rst_n) &&
                  !fo_issue_valid_q && fo_pending >= 6 && fo_sixth_idle &&
                  fo_candidates == 0 && !fo_select_valid &&
                  rd_mem_status == $past(rd_mem_status) &&
                  $past(!fo_issue_valid_q && fo_candidates == 0));
        C_ORDER_OUT_OF_ORDER_ISSUE:
            cover(fo_success && fo_older_pending);
        C_ORDER_YOUNGER_DONE_HEAD_WAIT:
            cover(fo_reorder_wait);
        C_ORDER_RETIRE_AFTER_REORDER:
            cover(fo_seen_reorder_q && fo_retire);
        C_ORDER_RETIRE_AFTER_RETRY:
            cover(fo_seen_fail_q && fo_retire &&
                  fo_retire_entry == fo_failed_entry_q);
        C_ORDER_ALL_PIPELINE_BOUNDARIES:
            cover(fo_accept && fo_select_valid && fo_success &&
                  fo_capture && fo_retire);
        C_ORDER_FULL_REUSE:
            cover(fo_count_q == 9 && fo_accept && fo_retire &&
                  alloc_entry == fo_retire_entry);
        C_ORDER_SEVEN_SOURCE_REFILL:
            cover(fo_occ[0] == 7 && fo_retire && fo_winner == 0 &&
                  fo_accept && src == 0);
        C_ORDER_RR_ALL_READY:
            cover(fo_head_valid == 3'b111 && fo_head_done == 3'b111 &&
                  rready == 3'b111 && fo_retire);
        if (fo_history_valid && $past(rst_n)) begin
            C_ORDER_5A_PRESERVE_SELECTED:
                cover($past(fo_issue_valid_q && !fo_success &&
                            fo_select_valid) &&
                      fo_issue_valid_q &&
                      fo_issue_entry_q == $past(fo_select_entry));
            C_ORDER_5A_RESELECT_FAILED_NEXT:
                cover($past(fo_issue_valid_q && !fo_success &&
                            fo_select_valid) &&
                      fo_issue_valid_q && fo_select_valid &&
                      fo_select_entry == $past(fo_issue_entry_q));
            C_ORDER_RETURN_THEN_NEXT_R:
                cover($past(fo_capture) && fo_retire &&
                      fo_retire_entry == $past(fo_capture_entry));
        end
    end
`endif
// END CMDBUF NATIVE FORMAL MONITOR
