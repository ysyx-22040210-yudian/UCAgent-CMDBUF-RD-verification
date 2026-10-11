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
        valid_next = valid_q & ~retire_mask;
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
// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
    // Independent acceptance-order oracle. Physical slots are observation IDs;
    // numerical positions change only on AR acceptance and R retirement.
    // No DUT valid/issued/done/older/selection result advances this machine.
    reg [8:0] fm_live_q,fm_issued_q,fm_done_q;
    reg [3:0] fm_age_q[0:8];
    reg [17:0] fm_addr_q[0:8];
    reg [1:0] fm_src_q[0:8],fm_resp_q[0:8];
    reg [7:0] fm_id_q[0:8];
    reg [4:0] fm_port_q[0:8];
    reg [2:0] fm_left_q[0:8];
    reg [1:0] fm_rr_q;
    reg fm_attempt_q;
    reg [3:0] fm_attempt_id_q;
    reg [2:0] fm_attempt_bank_q;
    reg [11:0] fm_attempt_addr_q;
    reg [3:0] fm_hist_q=0;
    reg [3:0] fm_count,fm_pending,fm_occ[0:2],fm_after[0:2];
    reg [5:0] fm_used,fm_shared,fm_cost;
    reg [2:0] fm_ready,fm_rvalid,fm_eligible,fm_head_valid;
    reg [3:0] fm_head[0:2];
    reg [3:0] fm_head_age[0:2];
    reg fm_retire,fm_accept,fm_success,fm_select,fm_due;
    reg [1:0] fm_winner;
    reg [3:0] fm_retire_id,fm_select_id,fm_select_age,fm_due_id;
    reg [7:0] fm_req;
    reg [11:0] fm_req_addr;
    reg [8:0] fm_pool,fm_window,fm_candidates,fm_due_mask;
    reg [3:0] fm_rank[0:8],fm_older_count[0:8];
    reg [7:0] fm_rid;
    reg [4:0] fm_rport;
    reg [2:0] fm_raddr;
    reg [1:0] fm_rresp;
    always @* begin
        fm_req=(rst_n && fm_attempt_q)?(8'b1<<fm_attempt_bank_q):8'b0;
        fm_req_addr=(rst_n && fm_attempt_q)?fm_attempt_addr_q:12'b0;
        fm_success=|(fm_req & ar_rd_gnt & rw_rd_gnt);
        fm_count=0;fm_pending=0;fm_used=0;fm_shared=0;fm_cost=0;
        fm_head_valid=0;fm_eligible=0;fm_ready=0;
        fm_due=0;fm_due_id=0;fm_due_mask=0;
        for(integer x=0;x<3;x=x+1) begin
            fm_occ[x]=0;fm_after[x]=0;fm_head[x]=0;fm_head_age[x]=9;
        end
        for(integer e=0;e<9;e=e+1)begin
            if(fm_live_q[e]) begin
                fm_count=fm_count+1'b1;
                if(!fm_issued_q[e])fm_pending=fm_pending+1'b1;
                for(integer x=0;x<3;x=x+1) if(fm_src_q[e]==x) begin
                    fm_occ[x]=fm_occ[x]+1'b1;
                    if(fm_age_q[e]<fm_head_age[x])begin
                        fm_head_valid[x]=1;fm_head[x]=4'(e);fm_head_age[x]=fm_age_q[e];
                    end
                end
            end
            if(fm_left_q[e]==1)begin fm_due=1;fm_due_id=4'(e);fm_due_mask[e]=1;end
            fm_older_count[e]=0;
            for(integer j=0;j<9;j=j+1)
                if(fm_live_q[j] && fm_age_q[j]<fm_age_q[e])fm_older_count[e]=fm_older_count[e]+1'b1;
        end
        for(integer x=0;x<3;x=x+1)
            fm_eligible[x]=fm_head_valid[x] && fm_done_q[fm_head[x]] && rready[x];
        fm_winner=0;
        case(fm_rr_q)
            0: if(fm_eligible[0])fm_winner=0;else if(fm_eligible[1])fm_winner=1;else if(fm_eligible[2])fm_winner=2;
            1: if(fm_eligible[1])fm_winner=1;else if(fm_eligible[2])fm_winner=2;else if(fm_eligible[0])fm_winner=0;
            2: if(fm_eligible[2])fm_winner=2;else if(fm_eligible[0])fm_winner=0;else if(fm_eligible[1])fm_winner=1;
            default: fm_winner=0;
        endcase
        fm_retire=rst_n && (|fm_eligible);
        fm_retire_id=fm_retire?fm_head[fm_winner]:4'b0;
        fm_rvalid=fm_retire?(3'b1<<fm_winner):3'b0;
        fm_rid=0;fm_rport=0;fm_raddr=0;fm_rresp=0;
        if(fm_retire)begin
            fm_rid=fm_id_q[fm_retire_id];fm_rport=fm_port_q[fm_retire_id];fm_raddr=fm_addr_q[fm_retire_id][2:0];
            fm_rresp=(fm_resp_q[fm_retire_id]==3)?2'b11:(rsp_pc_err?2'b01:2'b00);
        end
        for(integer x=0;x<3;x=x+1)begin
            fm_cost=fm_cost+((fm_occ[x]!=0)?{2'b0,fm_occ[x]}:6'd1);
            fm_after[x]=fm_occ[x]-4'(fm_retire && fm_winner==x);
            fm_used=fm_used+{2'b0,fm_after[x]};
            if(fm_after[x]>1)fm_shared=fm_shared+{2'b0,fm_after[x]}-6'd1;
        end
        for(integer x=0;x<3;x=x+1)
            fm_ready[x]=rst_n && fm_used<9 && (fm_after[x]==0 || fm_shared<6);
        fm_accept=arvalid && src<3 && ((src<3)?fm_ready[src]:1'b0);
        fm_pool=fm_live_q & ~fm_issued_q;
        if(fm_success)fm_pool[fm_attempt_id_q]=0;
        fm_window=0;fm_candidates=0;fm_select=0;fm_select_id=0;fm_select_age=9;
        for(integer e=0;e<9;e=e+1)begin
            fm_rank[e]=0;
            for(integer j=0;j<9;j=j+1)
                if(fm_pool[j] && fm_age_q[j]<fm_age_q[e])fm_rank[e]=fm_rank[e]+1'b1;
            fm_window[e]=fm_pool[e] && fm_rank[e]<5;
            fm_candidates[e]=fm_window[e] && !(fm_attempt_q && fm_attempt_id_q==e) &&
                !(fm_addr_q[e][6]?rd_mem_status[1][fm_addr_q[e][5:3]]:rd_mem_status[0][fm_addr_q[e][5:3]]);
            if(fm_candidates[e] && fm_age_q[e]<fm_select_age)begin
                fm_select=1;fm_select_id=4'(e);fm_select_age=fm_age_q[e];
            end
        end
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            fm_live_q<=0;fm_issued_q<=0;fm_done_q<=0;fm_rr_q<=0;
            fm_attempt_q<=0;fm_attempt_id_q<=0;fm_attempt_bank_q<=0;fm_attempt_addr_q<=0;fm_hist_q<=0;
            for(integer e=0;e<9;e=e+1)begin
                fm_age_q[e]<=0;fm_addr_q[e]<=0;fm_src_q[e]<=0;fm_resp_q[e]<=0;fm_id_q[e]<=0;fm_port_q[e]<=0;fm_left_q[e]<=0;
            end
        end else begin
            fm_hist_q<={fm_hist_q[2:0],1'b1};
            if(fm_retire)fm_rr_q<=(fm_winner==2)?2'd0:fm_winner+2'd1;
            fm_attempt_q<=fm_select;
            fm_attempt_id_q<=fm_select?fm_select_id:4'b0;
            fm_attempt_bank_q<=fm_select?fm_addr_q[fm_select_id][5:3]:3'b0;
            fm_attempt_addr_q<=fm_select?fm_addr_q[fm_select_id][17:6]:12'b0;
            for(integer e=0;e<9;e=e+1)begin
                if(fm_accept && alloc_entry==e)begin
                    fm_live_q[e]<=1;fm_issued_q[e]<=0;fm_done_q[e]<=0;
                    fm_age_q[e]<=fm_count-4'(fm_retire);
                    fm_addr_q[e]<=araddr;fm_src_q[e]<=src;fm_resp_q[e]<=arresp;fm_id_q[e]<=arid;fm_port_q[e]<=ar_port_id;fm_left_q[e]<=0;
                end else if(fm_retire && fm_retire_id==e)begin
                    fm_live_q[e]<=0;fm_issued_q[e]<=0;fm_done_q[e]<=0;
                    fm_age_q[e]<=0;fm_addr_q[e]<=0;fm_src_q[e]<=0;fm_resp_q[e]<=0;fm_id_q[e]<=0;fm_port_q[e]<=0;fm_left_q[e]<=0;
                end else begin
                    if(fm_retire && fm_live_q[e] && fm_age_q[e]>fm_age_q[fm_retire_id])fm_age_q[e]<=fm_age_q[e]-1'b1;
                    if(fm_left_q[e]!=0)fm_left_q[e]<=fm_left_q[e]-1'b1;
                    if(fm_left_q[e]==1)fm_done_q[e]<=1;
                    if(fm_success && fm_attempt_id_q==e)begin fm_issued_q[e]<=1;fm_left_q[e]<=4;end
                end
            end
        end
    end
    always @(posedge clk)if(rst_n)begin
        FM_LIVE: assert(valid_q==fm_live_q);
        FM_ISSUED: assert(issued_q==fm_issued_q);
        FM_DONE: assert(done_q==fm_done_q);
        FM_PENDING: assert(pending_cnt==fm_pending);
        FM_RR: assert(rr_ptr_q==fm_rr_q && fm_rr_q<3);
        FM_COST: assert(fm_cost<=9);
        FM_READY: assert(arready==fm_ready);
        FM_ACCEPT: assert(alloc_fire==fm_accept);
        if(fm_accept)begin
            FM_ALLOC_ID: assert(alloc_entry<9);
            FM_ALLOC_FREE: assert(!fm_live_q[alloc_entry] || (fm_retire && fm_retire_id==alloc_entry));
        end
        FM_REQ: assert(req==fm_req);
        FM_ADDR: assert(arb_addr==fm_req_addr);
        FM_ATTEMPT: assert(issue_valid_q==fm_attempt_q && issue_entry_q==fm_attempt_id_q && issue_bank_q==fm_attempt_bank_q && issue_addr_q==fm_attempt_addr_q);
        FM_SUCCESS: assert(issue_success==fm_success);
        if(fm_attempt_q)begin
            FM_ISSUE_OWN: assert(fm_attempt_id_q<9 && fm_live_q[fm_attempt_id_q] && !fm_issued_q[fm_attempt_id_q]);
        end
        FM_POOL: assert(rank_pool==fm_pool);
        FM_WINDOW: assert(window_mask==fm_window);
        FM_CANDIDATE: assert(candidate_mask==fm_candidates);
        FM_SELECT: assert(select_valid==fm_select && select_entry==fm_select_id);
        FM_DUE_UNIQUE: assert($onehot0(fm_due_mask));
        FM_CAPTURE: assert(capture_valid==fm_due);
        if(fm_due)begin
            FM_CAPTURE_ID: assert(capture_entry==fm_due_id);
            FM_NO_BYPASS: assert(!(fm_retire && fm_retire_id==fm_due_id));
        end
        FM_RVALID: assert(rvalid==fm_rvalid);
        FM_RETIRE: assert(retire_fire==fm_retire && retire_entry==fm_retire_id);
        FM_RMETA: assert(rid==fm_rid && r_port_id==fm_rport && raddr==fm_raddr && rresp==fm_rresp);
        for(integer x=0;x<3;x=x+1)begin
            assert(occ_q[x]==fm_occ[x]);assert(fm_occ[x]<=7);assert(fm_after[x]<=7);
        end
        for(integer e=0;e<9;e=e+1)begin
            assert(addr_q[e]==fm_addr_q[e] && src_q[e]==fm_src_q[e] && id_q[e]==fm_id_q[e] && port_q[e]==fm_port_q[e] && arresp_q[e]==fm_resp_q[e]);
            if(fm_live_q[e])begin
                assert(fm_src_q[e]<3);
                assert(fm_age_q[e]<fm_count && fm_age_q[e]==fm_older_count[e]);
            end
            assert(fm_left_q[e]<=4);
            assert(!fm_issued_q[e] || fm_live_q[e]);
            assert(!fm_done_q[e] || fm_issued_q[e]);
            assert((fm_left_q[e]!=0)==(fm_issued_q[e] && !fm_done_q[e]));
            if(fm_hist_q[0])assert((fm_left_q[e]==4)==($past(fm_success) && $past(fm_attempt_id_q)==e));
            if(fm_hist_q[1])assert((fm_left_q[e]==3)==($past(fm_success,2) && $past(fm_attempt_id_q,2)==e));
            if(fm_hist_q[2])assert((fm_left_q[e]==2)==($past(fm_success,3) && $past(fm_attempt_id_q,3)==e));
            if(fm_hist_q[3])assert((fm_left_q[e]==1)==($past(fm_success,4) && $past(fm_attempt_id_q,4)==e));
            for(integer j=0;j<9;j=j+1)begin
                assert(older_q[e][j]==(fm_live_q[e] && fm_live_q[j] && fm_age_q[j]<fm_age_q[e]));
                if(e!=j && fm_live_q[e] && fm_live_q[j])assert(fm_age_q[e]!=fm_age_q[j]);
            end
        end
// auxiliary cover omitted in this cover-only partition:         FM_COVER_LIFECYCLE: cover(fm_retire);
// auxiliary cover omitted in this cover-only partition:         FM_COVER_ALL_STAGES: cover(fm_accept && fm_select && fm_success && fm_due && fm_retire);
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
endmodule
`default_nettype wire
