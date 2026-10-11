`default_nettype none
module cmdbuf_rd_cmd (
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
    output logic [7:0] rid,
    output logic [4:0] r_port_id,
    output logic [2:0] raddr,
    output logic [1:0] rresp,
    output logic [7:0] req,
    output logic [11:0] arb_addr,
    output logic [3:0] pending_cnt,
    input  logic [7:0] ar_rd_gnt,
    input  logic [1:0][7:0] rd_mem_status,
    input  logic [7:0] rw_rd_gnt,
    output logic alloc_fire,
    output logic [3:0] alloc_entry,
    output logic retire_fire,
    output logic [3:0] retire_entry,
    output logic issue_success,
    output logic [3:0] issue_entry,
    input  logic capture_valid,
    input  logic [3:0] capture_entry,
    output logic [3:0] rsp_entry,
    input  logic rsp_pc_err
);
    localparam int ENTRIES = 9;
    logic [8:0] valid_q, valid_next, issued_q, done_q;
    logic [17:0] addr_q [0:ENTRIES-1];
    logic [1:0] src_q [0:ENTRIES-1];
    logic [7:0] id_q [0:ENTRIES-1];
    logic [4:0] port_q [0:ENTRIES-1];
    logic [1:0] arresp_q [0:ENTRIES-1];
    // older_q[i][j] means that j was accepted before i.
    logic [8:0] older_q [0:ENTRIES-1];
    logic [8:0] older_next [0:ENTRIES-1];
    logic [3:0] occ_q [0:2];
    logic [3:0] pending_q;
    logic [1:0] rr_ptr_q;
    logic issue_valid_q;
    logic [3:0] issue_entry_q;
    logic [2:0] issue_bank_q;
    logic [11:0] issue_addr_q;
    logic [8:0] current_issue_mask, success_mask, rank_pool;
    logic [8:0] pending_mask, window_mask, bank_idle_mask, candidate_mask;
    logic [8:0] select_onehot, free_mask, retire_mask;
    logic select_valid, free_found, src_ready;
    logic [3:0] select_entry;
    logic [8:0] src_mask [0:2];
    logic [8:0] head_onehot [0:2];
    logic [3:0] head_entry [0:2];
    logic [2:0] head_valid, r_candidate;
    logic winner_valid;
    logic [1:0] winner;
    integer unsigned rank_count [0:ENTRIES-1];
    integer unsigned occ_after [0:2];
    integer unsigned shared_after, free_after, used_after, quota_cost;
    integer unsigned scan;

    assign req = (rst_n && issue_valid_q) ? (8'b1 << issue_bank_q) : 8'b0;
    assign arb_addr = (rst_n && issue_valid_q) ? issue_addr_q : 12'b0;
    // Successful issue requires the same requested bank in both grants.
    assign issue_success = |(req & ar_rd_gnt & rw_rd_gnt);
    assign issue_entry = issue_entry_q;
    assign pending_cnt = pending_q;
    assign retire_fire = |(rvalid & rready);
    assign retire_entry = rsp_entry;

    // Source heads are found before testing completion (cross-ID ordering).
    always_comb begin
        head_valid = '0;
        r_candidate = '0;
        for (int x = 0; x < 3; x++) begin
            src_mask[x] = '0;
            head_onehot[x] = '0;
            head_entry[x] = '0;
            for (int i = 0; i < ENTRIES; i++)
                src_mask[x][i] = valid_q[i] && (src_q[i] == 2'(x));
            for (int i = 0; i < ENTRIES; i++) begin
                head_onehot[x][i] = src_mask[x][i] &&
                                   ((older_q[i] & src_mask[x]) == 9'b0);
                if (head_onehot[x][i]) begin
                    head_entry[x] = 4'(i);
                    head_valid[x] = 1'b1;
                end
            end
            if (head_valid[x])
                r_candidate[x] = done_q[head_entry[x]] && rready[x];
        end
    end

    // Default implementation choice: 0 -> 1 -> 2, advance on transfer only.
    always_comb begin
        winner_valid = 1'b0;
        winner = 2'b0;
        scan = 0;
        for (int offset = 0; offset < 3; offset++) begin
            scan = int'(rr_ptr_q) + offset;
            if (scan >= 3) scan = scan - 3;
            if (!winner_valid && r_candidate[scan]) begin
                winner_valid = 1'b1;
                winner = 2'(scan);
            end
        end
        rsp_entry = '0;
        rvalid = '0;
        rid = '0;
        r_port_id = '0;
        raddr = '0;
        if (rst_n && winner_valid) begin
            rsp_entry = head_entry[winner];
            rvalid[winner] = 1'b1;
            rid = id_q[rsp_entry];
            r_port_id = port_q[rsp_entry];
            raddr = addr_q[rsp_entry][2:0];
        end
    end

    always_comb begin
        rresp = 2'b00;
        if (|rvalid) begin
            if (arresp_q[rsp_entry] == 2'b11)
                rresp = 2'b11;
            else if (rsp_pc_err)
                rresp = 2'b01;
        end
    end

    // 10B: subtract the current R retirement before evaluating admission.
    always_comb begin
        retire_mask = '0;
        if (retire_fire) retire_mask[retire_entry] = 1'b1;
        used_after = 0;
        shared_after = 0;
        quota_cost = 0;
        for (int x = 0; x < 3; x++) begin
            occ_after[x] = int'(occ_q[x]);
            if (retire_fire && (winner == 2'(x))) occ_after[x] = occ_after[x] - 1;
            used_after = used_after + occ_after[x];
            if (occ_after[x] > 0) shared_after = shared_after + occ_after[x] - 1;
            quota_cost = quota_cost + ((occ_q[x] == 0) ? 1 : int'(occ_q[x]));
        end
        free_after = 9 - used_after;
        arready = '0;
        for (int x = 0; x < 3; x++)
            arready[x] = rst_n && (free_after > 0) &&
                         ((occ_after[x] == 0) || (shared_after < 6));

        src_ready = 1'b0;
        if (src < 3) src_ready = arready[src];
        alloc_fire = arvalid && src_ready;
        free_mask = ~valid_q | retire_mask;
        free_found = 1'b0;
        alloc_entry = '0;
        for (int i = 0; i < ENTRIES; i++) begin
            if (free_mask[i] && !free_found) begin
                free_found = 1'b1;
                alloc_entry = 4'(i);
            end
        end
        valid_next = valid_q & ~retire_mask & ~success_mask;
        if (alloc_fire) valid_next[alloc_entry] = 1'b1;
    end

    // 6B: forward successful issue into this cycle's rank calculation.
    // A failed current issue still occupies the window but cannot be reselected.
    always_comb begin
        pending_mask = valid_q & ~issued_q;
        current_issue_mask = '0;
        if (issue_valid_q) current_issue_mask[issue_entry_q] = 1'b1;
        success_mask = issue_success ? current_issue_mask : 9'b0;
        rank_pool = pending_mask & ~success_mask;
        window_mask = '0;
        bank_idle_mask = '0;
        candidate_mask = '0;
        select_onehot = '0;
        select_entry = '0;
        for (int i = 0; i < ENTRIES; i++) begin
            rank_count[i] = 0;
            for (int j = 0; j < ENTRIES; j++)
                if (rank_pool[j] && older_q[i][j]) rank_count[i] = rank_count[i] + 1;
            window_mask[i] = rank_pool[i] && (rank_count[i] < 5);
            bank_idle_mask[i] = !(addr_q[i][6] ? rd_mem_status[1][addr_q[i][5:3]] : rd_mem_status[0][addr_q[i][5:3]]);
        end
        candidate_mask = window_mask & bank_idle_mask & ~current_issue_mask;
        for (int i = 0; i < ENTRIES; i++) begin
            select_onehot[i] = candidate_mask[i] &&
                              ((older_q[i] & candidate_mask) == 9'b0);
            if (select_onehot[i]) select_entry = 4'(i);
        end
        select_valid = |select_onehot;
    end

    // Pairwise age updates depend only on allocation and retirement.
    always_comb begin
        for (int i = 0; i < ENTRIES; i++) begin
            for (int j = 0; j < ENTRIES; j++) begin
                if (!valid_next[i] || !valid_next[j] || (i == j))
                    older_next[i][j] = 1'b0;
                else if (alloc_fire && (alloc_entry == 4'(i)))
                    older_next[i][j] = 1'b1;
                else if (alloc_fire && (alloc_entry == 4'(j)))
                    older_next[i][j] = 1'b0;
                else
                    older_next[i][j] = older_q[i][j];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_q <= '0;
            issued_q <= '0;
            done_q <= '0;
            pending_q <= '0;
            rr_ptr_q <= '0;
            issue_valid_q <= 1'b0;
            issue_entry_q <= '0;
            issue_bank_q <= '0;
            issue_addr_q <= '0;
            for (int x = 0; x < 3; x++) occ_q[x] <= '0;
            for (int i = 0; i < ENTRIES; i++) begin
                addr_q[i] <= '0;
                src_q[i] <= '0;
                id_q[i] <= '0;
                port_q[i] <= '0;
                arresp_q[i] <= '0;
                older_q[i] <= '0;
            end
        end else begin
            valid_q <= valid_next;
            pending_q <= pending_q + 4'(alloc_fire) - 4'(issue_success);
            for (int x = 0; x < 3; x++)
                occ_q[x] <= occ_q[x] + 4'(alloc_fire && (src == 2'(x)))
                           - 4'(retire_fire && (winner == 2'(x)));
            if (retire_fire) rr_ptr_q <= (winner == 2) ? 2'd0 : winner + 2'd1;

            // 5A: always replace the attempt with this cycle's selection.
            issue_valid_q <= select_valid;
            if (select_valid) begin
                issue_entry_q <= select_entry;
                issue_bank_q <= addr_q[select_entry][5:3];
                issue_addr_q <= addr_q[select_entry][17:6];
            end else begin
                issue_entry_q <= '0;
                issue_bank_q <= '0;
                issue_addr_q <= '0;
            end
            for (int i = 0; i < ENTRIES; i++) begin
                older_q[i] <= older_next[i];
                // New allocation wins over retiring the previous owner.
                if (alloc_fire && (alloc_entry == 4'(i))) begin
                    issued_q[i] <= 1'b0;
                    done_q[i] <= 1'b0;
                    addr_q[i] <= araddr;
                    src_q[i] <= src;
                    id_q[i] <= arid;
                    port_q[i] <= ar_port_id;
                    arresp_q[i] <= arresp;
                end else if (retire_mask[i]) begin
                    issued_q[i] <= 1'b0;
                    done_q[i] <= 1'b0;
                    addr_q[i] <= '0;
                    src_q[i] <= '0;
                    id_q[i] <= '0;
                    port_q[i] <= '0;
                    arresp_q[i] <= '0;
                end else begin
                    if (issue_success && (issue_entry_q == 4'(i))) issued_q[i] <= 1'b1;
                    if (capture_valid && (capture_entry == 4'(i))) done_q[i] <= 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Assertions are disabled while the asynchronous reset is active.
        end else begin
            assert ($onehot0(req)) else $fatal(1, "req is not onehot0");
            assert ($onehot0(rvalid)) else $fatal(1, "rvalid is not onehot0");
            assert ((rvalid & ~rready) == 0) else $fatal(1, "response without ready");
            assert ($onehot0(select_onehot)) else $fatal(1, "ambiguous oldest selection");
            assert (pending_q == 4'($countones(valid_q & ~issued_q))) else $fatal(1, "pending count mismatch");
            assert (int'(occ_q[0]) + int'(occ_q[1]) + int'(occ_q[2]) == $countones(valid_q)) else $fatal(1, "occupancy mismatch");
            assert (quota_cost <= 9) else $fatal(1, "reserved capacity stolen");
            if (alloc_fire) begin
                assert (free_found && free_mask[alloc_entry]) else $fatal(1, "allocation without a free entry");
                assert (src < 3) else $fatal(1, "invalid accepted source");
                assert ((arresp == 2'b00) || (arresp == 2'b11)) else $fatal(1, "undefined arresp input");
            end
            if (issue_valid_q)
                assert (valid_q[issue_entry_q] && !issued_q[issue_entry_q]) else $fatal(1, "duplicate or invalid issue");
            if (capture_valid) begin
                assert (capture_entry < 9) else $fatal(1, "invalid capture entry");
                assert (valid_q[capture_entry] && issued_q[capture_entry] && !done_q[capture_entry]) else $fatal(1, "capture ownership mismatch");
                assert (!(retire_fire && (retire_entry == capture_entry))) else $fatal(1, "same-cycle MEM bypass");
            end
            for (int x = 0; x < 3; x++) begin
                assert (occ_q[x] == 4'($countones(src_mask[x]))) else $fatal(1, "source count mismatch");
                assert ($onehot0(head_onehot[x])) else $fatal(1, "ambiguous source head");
            end
            for (int i = 0; i < ENTRIES; i++) begin
                assert (!done_q[i] || (valid_q[i] && issued_q[i])) else $fatal(1, "done without issue");
                assert (!older_q[i][i]) else $fatal(1, "self age bit set");
                for (int j = 0; j < ENTRIES; j++) begin
                    if (valid_q[i] && valid_q[j] && (i != j))
                        assert (older_q[i][j] != older_q[j][i]) else $fatal(1, "age ordering mismatch");
                end
            end
        end
    end
`endif
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
endmodule
`default_nettype wire
