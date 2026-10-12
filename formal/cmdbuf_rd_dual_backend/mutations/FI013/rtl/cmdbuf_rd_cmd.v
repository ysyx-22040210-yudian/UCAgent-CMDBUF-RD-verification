// Synthesizable Verilog-2001; preserves the aligned CMDBUF/OTB behavior.
`default_nettype none
module cmdbuf_rd_cmd (
    input wire clk,
    input wire rst_n,
    input wire arvalid,
    output reg [2:0] arready,
    input wire [17:0] araddr,
    input wire [1:0] src,
    input wire [7:0] arid,
    input wire [4:0] ar_port_id,
    input wire [1:0] arresp,
    output reg [2:0] rvalid,
    input wire [2:0] rready,
    output reg [7:0] rid,
    output reg [4:0] r_port_id,
    output reg [2:0] raddr,
    output reg [1:0] rresp,
    output wire [7:0] req,
    output wire [11:0] arb_addr,
    output wire [3:0] pending_cnt,
    input wire [7:0] ar_rd_gnt,
    // [7:0]: even banks; [15:8]: odd banks, matching the original packed order.
    input wire [15:0] rd_mem_status,
    input wire [7:0] rw_rd_gnt,
    output reg alloc_fire,
    output reg [3:0] alloc_entry,
    output wire retire_fire,
    output wire [3:0] retire_entry,
    output wire issue_success,
    output wire [3:0] issue_entry,
    input wire capture_valid,
    input wire [3:0] capture_entry,
    output reg [3:0] rsp_entry,
    input wire rsp_pc_err
);
    localparam integer ENTRIES = 9;
    reg [8:0] valid_q, valid_next, issued_q, done_q;
    reg [17:0] addr_q [0:ENTRIES-1];
    reg [1:0] src_q [0:ENTRIES-1];
    reg [7:0] id_q [0:ENTRIES-1];
    reg [4:0] port_q [0:ENTRIES-1];
    reg [1:0] arresp_q [0:ENTRIES-1];
    // older_q[i][j] means that j was accepted before i.
    reg [8:0] older_q [0:ENTRIES-1];
    reg [8:0] older_next [0:ENTRIES-1];
    reg [3:0] occ_q [0:2];
    reg [3:0] pending_q;
    reg [1:0] rr_ptr_q;
    reg issue_valid_q;
    reg [3:0] issue_entry_q;
    reg [2:0] issue_bank_q;
    reg [11:0] issue_addr_q;
    reg [8:0] current_issue_mask, success_mask, rank_pool;
    reg [8:0] pending_mask, window_mask, bank_idle_mask, candidate_mask;
    reg [8:0] select_onehot, free_mask, retire_mask;
    reg select_valid, free_found, src_ready;
    reg [3:0] select_entry;
    reg [8:0] src_mask [0:2];
    reg [8:0] head_onehot [0:2];
    reg [3:0] head_entry [0:2];
    reg [2:0] head_valid, r_candidate;
    reg winner_valid;
    reg [1:0] winner;
    reg [31:0] rank_count [0:ENTRIES-1];
    reg [31:0] occ_after [0:2];
    reg [31:0] shared_after, free_after, used_after, quota_cost;
    reg [31:0] scan;

    assign req = (rst_n && arvalid && src_ready) ? (8'b1 << araddr[5:3]) : ((rst_n && issue_valid_q) ? (8'b1 << issue_bank_q) : 8'b0);
    assign arb_addr = (rst_n && issue_valid_q) ? issue_addr_q : 12'b0;
    // Successful issue requires the same requested bank in both grants.
    assign issue_success = |(req & ar_rd_gnt & rw_rd_gnt);
    assign issue_entry = issue_entry_q;
    assign pending_cnt = pending_q;
    assign retire_fire = |(rvalid & rready);
    assign retire_entry = rsp_entry;

    // Source heads are found before testing completion (cross-ID ordering).
    always @* begin : p_1
        integer x;
        integer i;

        head_valid = 3'b0;
        r_candidate = 3'b0;
        for (x = 0; x < 3; x = x + 1) begin
            src_mask[x] = 9'b0;
            head_onehot[x] = 9'b0;
            head_entry[x] = 4'b0;
            for (i = 0; i < ENTRIES; i = i + 1)
                src_mask[x][i] = valid_q[i] && (src_q[i] == x[1:0]);
            for (i = 0; i < ENTRIES; i = i + 1) begin
                head_onehot[x][i] = src_mask[x][i] &&
                                   ((older_q[i] & src_mask[x]) == 9'b0);
                if (head_onehot[x][i]) begin
                    head_entry[x] = i[3:0];
                    head_valid[x] = 1'b1;
                end
            end
            if (head_valid[x])
                r_candidate[x] = done_q[head_entry[x]] && rready[x];
        end
    end

    // Default implementation choice: 0 -> 1 -> 2, advance on transfer only.
    always @* begin : p_2
        integer offset;

        winner_valid = 1'b0;
        winner = 2'b0;
        scan = 0;
        for (offset = 0; offset < 3; offset = offset + 1) begin
            scan = {30'b0, rr_ptr_q} + offset;
            if (scan >= 3) scan = scan - 3;
            if (!winner_valid && r_candidate[scan]) begin
                winner_valid = 1'b1;
                winner = scan[1:0];
            end
        end
        rsp_entry = 4'b0;
        rvalid = 3'b0;
        rid = 8'b0;
        r_port_id = 5'b0;
        raddr = 3'b0;
        if (rst_n && winner_valid) begin
            rsp_entry = head_entry[winner];
            rvalid[winner] = 1'b1;
            rid = id_q[rsp_entry];
            r_port_id = port_q[rsp_entry];
            raddr = addr_q[rsp_entry][2:0];
        end
    end

    always @* begin
        rresp = 2'b00;
        if (|rvalid) begin
            if (arresp_q[rsp_entry] == 2'b11)
                rresp = 2'b11;
            else if (rsp_pc_err)
                rresp = 2'b01;
        end
    end

    // 10B: subtract the current R retirement before evaluating admission.
    always @* begin : p_4
        integer x;
        integer i;

        retire_mask = 9'b0;
        if (retire_fire) retire_mask[retire_entry] = 1'b1;
        used_after = 0;
        shared_after = 0;
        quota_cost = 0;
        for (x = 0; x < 3; x = x + 1) begin
            occ_after[x] = {28'b0, occ_q[x]};
            if (retire_fire && (winner == x[1:0])) occ_after[x] = occ_after[x] - 1;
            used_after = used_after + occ_after[x];
            if (occ_after[x] > 0) shared_after = shared_after + occ_after[x] - 1;
            quota_cost = quota_cost + ((occ_q[x] == 0) ? 1 : {28'b0, occ_q[x]});
        end
        free_after = 9 - used_after;
        arready = 3'b0;
        for (x = 0; x < 3; x = x + 1)
            arready[x] = rst_n && (free_after > 0) &&
                         ((occ_after[x] == 0) || (shared_after < 6));

        src_ready = 1'b0;
        if (src < 3) src_ready = arready[src];
        alloc_fire = arvalid && src_ready;
        free_mask = ~valid_q | retire_mask;
        free_found = 1'b0;
        alloc_entry = 4'b0;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            if (free_mask[i] && !free_found) begin
                free_found = 1'b1;
                alloc_entry = i[3:0];
            end
        end
        valid_next = valid_q & ~retire_mask;
        if (alloc_fire) valid_next[alloc_entry] = 1'b1;
    end

    // 6B: forward successful issue into this cycle's rank calculation.
    // A failed current issue still occupies the window but cannot be reselected.
    always @* begin : p_5
        integer i;
        integer j;

        pending_mask = valid_q & ~issued_q;
        current_issue_mask = 9'b0;
        if (issue_valid_q) current_issue_mask[issue_entry_q] = 1'b1;
        success_mask = issue_success ? current_issue_mask : 9'b0;
        rank_pool = pending_mask & ~success_mask;
        window_mask = 9'b0;
        bank_idle_mask = 9'b0;
        candidate_mask = 9'b0;
        select_onehot = 9'b0;
        select_entry = 4'b0;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            rank_count[i] = 0;
            for (j = 0; j < ENTRIES; j = j + 1)
                if (rank_pool[j] && older_q[i][j]) rank_count[i] = rank_count[i] + 1;
            window_mask[i] = rank_pool[i] && (rank_count[i] < 5);
            bank_idle_mask[i] = !rd_mem_status[addr_q[i][6:3]];
        end
        candidate_mask = window_mask & bank_idle_mask & ~current_issue_mask;
        for (i = 0; i < ENTRIES; i = i + 1) begin
            select_onehot[i] = candidate_mask[i] &&
                              ((older_q[i] & candidate_mask) == 9'b0);
            if (select_onehot[i]) select_entry = i[3:0];
        end
        select_valid = |select_onehot;
    end

    // Pairwise age updates depend only on allocation and retirement.
    always @* begin : p_6
        integer i;
        integer j;

        for (i = 0; i < ENTRIES; i = i + 1) begin
            for (j = 0; j < ENTRIES; j = j + 1) begin
                if (!valid_next[i] || !valid_next[j] || (i == j))
                    older_next[i][j] = 1'b0;
                else if (alloc_fire && (alloc_entry == i[3:0]))
                    older_next[i][j] = 1'b1;
                else if (alloc_fire && (alloc_entry == j[3:0]))
                    older_next[i][j] = 1'b0;
                else
                    older_next[i][j] = older_q[i][j];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin : p_7
        integer x;
        integer i;

        if (!rst_n) begin
            valid_q <= 9'b0;
            issued_q <= 9'b0;
            done_q <= 9'b0;
            pending_q <= 4'b0;
            rr_ptr_q <= 2'b0;
            issue_valid_q <= 1'b0;
            issue_entry_q <= 4'b0;
            issue_bank_q <= 3'b0;
            issue_addr_q <= 12'b0;
            for (x = 0; x < 3; x = x + 1) occ_q[x] <= 4'b0;
            for (i = 0; i < ENTRIES; i = i + 1) begin
                addr_q[i] <= 18'b0;
                src_q[i] <= 2'b0;
                id_q[i] <= 8'b0;
                port_q[i] <= 5'b0;
                arresp_q[i] <= 2'b0;
                older_q[i] <= 9'b0;
            end
        end else begin
            valid_q <= valid_next;
            pending_q <= pending_q + {3'b0, (alloc_fire)} - {3'b0, (issue_success)};
            for (x = 0; x < 3; x = x + 1)
                occ_q[x] <= occ_q[x] + {3'b0, (alloc_fire && (src == x[1:0]))}
                           - {3'b0, (retire_fire && (winner == x[1:0]))};
            if (retire_fire) rr_ptr_q <= (winner == 2) ? 2'd0 : winner + 2'd1;

            // 5A: always replace the attempt with this cycle's selection.
            issue_valid_q <= select_valid;
            if (select_valid) begin
                issue_entry_q <= select_entry;
                issue_bank_q <= addr_q[select_entry][5:3];
                issue_addr_q <= addr_q[select_entry][17:6];
            end else begin
                issue_entry_q <= 4'b0;
                issue_bank_q <= 3'b0;
                issue_addr_q <= 12'b0;
            end
            for (i = 0; i < ENTRIES; i = i + 1) begin
                older_q[i] <= older_next[i];
                // New allocation wins over retiring the previous owner.
                if (alloc_fire && (alloc_entry == i[3:0])) begin
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
                    addr_q[i] <= 18'b0;
                    src_q[i] <= 2'b0;
                    id_q[i] <= 8'b0;
                    port_q[i] <= 5'b0;
                    arresp_q[i] <= 2'b0;
                end else begin
                    if (issue_success && (issue_entry_q == i[3:0])) issued_q[i] <= 1'b1;
                    if (capture_valid && (capture_entry == i[3:0])) done_q[i] <= 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // Verilog simulation diagnostics; no SystemVerilog assertion primitives.
    function [3:0] popcount9;
        input [8:0] value;
        integer bit_index;
        begin
            popcount9 = 4'b0;
            for (bit_index = 0; bit_index < 9; bit_index = bit_index + 1)
                if (value[bit_index] === 1'b1) popcount9 = popcount9 + 4'd1;
        end
    endfunction

    function onehot0_9;
        input [8:0] value;
        begin
            onehot0_9 = (popcount9(value) <= 4'd1);
        end
    endfunction

    task check_failure;
        input [511:0] message;
        begin
            $display("%0t %m CMDBUF_CHECK_FAILURE: %0s", $time, message);
            $stop;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin : p_8
        integer x;
        integer i;
        integer j;

        if (!rst_n) begin
            // Assertions are disabled while the asynchronous reset is active.
        end else begin
            if ((onehot0_9({1'b0, req})) !== 1'b1) check_failure("req is not onehot0");
            if ((onehot0_9({6'b0, rvalid})) !== 1'b1) check_failure("rvalid is not onehot0");
            if (((rvalid & ~rready) == 0) !== 1'b1) check_failure("response without ready");
            if ((onehot0_9(select_onehot)) !== 1'b1) check_failure("ambiguous oldest selection");
            if ((pending_q == popcount9(valid_q & ~issued_q)) !== 1'b1) check_failure("pending count mismatch");
            if (({28'b0, occ_q[0]} + {28'b0, occ_q[1]} + {28'b0, occ_q[2]} == {28'b0, popcount9(valid_q)}) !== 1'b1) check_failure("occupancy mismatch");
            if ((quota_cost <= 9) !== 1'b1) check_failure("reserved capacity stolen");
            if (alloc_fire) begin
                if ((free_found && free_mask[alloc_entry]) !== 1'b1) check_failure("allocation without a free entry");
                if ((src < 3) !== 1'b1) check_failure("invalid accepted source");
                if (((arresp == 2'b00) || (arresp == 2'b11)) !== 1'b1) check_failure("undefined arresp input");
            end
            if (issue_valid_q)
                if ((valid_q[issue_entry_q] && !issued_q[issue_entry_q]) !== 1'b1) check_failure("duplicate or invalid issue");
            if (capture_valid) begin
                if ((capture_entry < 9) !== 1'b1) check_failure("invalid capture entry");
                if ((valid_q[capture_entry] && issued_q[capture_entry] && !done_q[capture_entry]) !== 1'b1) check_failure("capture ownership mismatch");
                if ((!(retire_fire && (retire_entry == capture_entry))) !== 1'b1) check_failure("same-cycle MEM bypass");
            end
            for (x = 0; x < 3; x = x + 1) begin
                if ((occ_q[x] == popcount9(src_mask[x])) !== 1'b1) check_failure("source count mismatch");
                if ((onehot0_9(head_onehot[x])) !== 1'b1) check_failure("ambiguous source head");
            end
            for (i = 0; i < ENTRIES; i = i + 1) begin
                if ((!done_q[i] || (valid_q[i] && issued_q[i])) !== 1'b1) check_failure("done without issue");
                if ((!older_q[i][i]) !== 1'b1) check_failure("self age bit set");
                for (j = 0; j < ENTRIES; j = j + 1) begin
                    if (valid_q[i] && valid_q[j] && (i != j))
                        if ((older_q[i][j] != older_q[j][i]) !== 1'b1) check_failure("age ordering mismatch");
                end
            end
        end
    end
`endif

`ifdef FORMAL
`include "inputs/formal_hooks/cmdbuf_rd_cmd_0.svh"
`endif
endmodule
`default_nettype wire
