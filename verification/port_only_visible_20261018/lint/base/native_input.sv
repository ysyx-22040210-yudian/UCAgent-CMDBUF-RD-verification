`define CMDBUF_NATIVE_SVA
`define SYNTHESIS
`define TP_COVER_B_BLOCK
`define TP_COVER_B_CAP
`define TP_COVER_B_FLOW
`define TP_COVER_B_ORDER
`define TP_COVER_F_AGE
`define TP_COVER_F_CAP
`define TP_COVER_F_CNT
`define TP_COVER_F_CON
`define TP_COVER_F_DAT
`define TP_COVER_F_ENT
`define TP_COVER_F_ERR
`define TP_COVER_F_MEM
`define TP_COVER_F_PIPE
`define TP_COVER_F_REU
`define TP_COVER_F_RR
`define TP_COVER_F_WIN
`define TP_COVER_P_AR
`define TP_COVER_P_ARB
`define TP_COVER_P_CLK
`define TP_COVER_P_MEM
`define TP_COVER_P_R
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

    assign req = (rst_n && issue_valid_q) ? (8'b1 << issue_bank_q) : 8'b0;
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
endmodule
`default_nettype wire

// Synthesizable Verilog-2001; preserves the aligned CMDBUF/OTB behavior.
`default_nettype none
module cmdbuf_rd_otb (
    input wire clk,
    input wire rst_n,
    input wire alloc_fire,
    input wire [3:0] alloc_entry,
    input wire retire_fire,
    input wire [3:0] retire_entry,
    input wire issue_success,
    input wire [3:0] issue_entry,
    output wire capture_valid,
    output wire [3:0] capture_entry,
    input wire [127:0] mem_rdata,
    input wire pc_err,
    input wire [3:0] rsp_entry,
    output reg [127:0] rsp_data,
    output reg rsp_pc_err
);
    reg [3:0] ret_valid_q;
    reg [3:0] ret_entry_q [0:3];
    reg [127:0] data_q [0:8];
    reg [8:0] pc_err_q, reserved_q, done_q;

    // The old last stage is sampled at the edge four cycles after issue.
    assign capture_valid = rst_n && ret_valid_q[3];
    assign capture_entry = ret_entry_q[3];
    always @* begin
        rsp_data = 128'b0;
        rsp_pc_err = 1'b0;
        if (rsp_entry < 9) begin
            rsp_data = data_q[rsp_entry];
            rsp_pc_err = pc_err_q[rsp_entry];
        end
    end

    always @(posedge clk or negedge rst_n) begin : p_2
        integer k;
        integer i;

        if (!rst_n) begin
            ret_valid_q <= 4'b0;
            pc_err_q <= 9'b0;
            reserved_q <= 9'b0;
            done_q <= 9'b0;
            for (k = 0; k < 4; k = k + 1) ret_entry_q[k] <= 4'b0;
            for (i = 0; i < 9; i = i + 1) data_q[i] <= 128'b0;
        end else begin
            // No stalls, including empty cycles and upstream backpressure.
            ret_valid_q[0] <= issue_success;
            ret_entry_q[0] <= issue_success ? issue_entry : 4'b0;
            for (k = 1; k < 4; k = k + 1) begin
                ret_valid_q[k] <= ret_valid_q[k-1];
                ret_entry_q[k] <= ret_valid_q[k-1] ? ret_entry_q[k-1] : 4'b0;
            end
            for (i = 0; i < 9; i = i + 1) begin
                if (alloc_fire && (alloc_entry == i[3:0])) begin
                    reserved_q[i] <= 1'b1;
                    done_q[i] <= 1'b0;
                    data_q[i] <= 128'b0;
                    pc_err_q[i] <= 1'b0;
                end else if (retire_fire && (retire_entry == i[3:0])) begin
                    reserved_q[i] <= 1'b0;
                    done_q[i] <= 1'b0;
                    data_q[i] <= 128'b0;
                    pc_err_q[i] <= 1'b0;
                end else if (capture_valid && (capture_entry == i[3:0])) begin
                    data_q[i] <= mem_rdata;
                    pc_err_q[i] <= pc_err;
                    done_q[i] <= 1'b1;
                end
            end
        end
    end
`ifndef SYNTHESIS
    // Verilog simulation diagnostics; no SystemVerilog assertion primitives.
    task check_failure;
        input [511:0] message;
        begin
            $display("%0t %m CMDBUF_CHECK_FAILURE: %0s", $time, message);
            $stop;
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Assertions are disabled while the asynchronous reset is active.
        end else begin
            if (alloc_fire)
                if ((!reserved_q[alloc_entry] || (retire_fire && (retire_entry == alloc_entry))) !== 1'b1) check_failure("OTB double allocation");
            if (issue_success)
                if ((reserved_q[issue_entry] && !done_q[issue_entry]) !== 1'b1) check_failure("unreserved OTB issue");
            if (capture_valid)
                if ((reserved_q[capture_entry] && !done_q[capture_entry]) !== 1'b1) check_failure("invalid OTB capture");
            if (retire_fire)
                if ((reserved_q[retire_entry] && done_q[retire_entry]) !== 1'b1) check_failure("OTB retirement before data");
            if (((done_q & ~reserved_q) == 0) !== 1'b1) check_failure("OTB done without reservation");
        end
    end
`endif
endmodule
`default_nettype wire

// Synthesizable Verilog-2001; preserves the aligned CMDBUF/OTB behavior.
`default_nettype none
module cmdbuf_rd (
    input wire clk,
    input wire rst_n,
    input wire arvalid,
    output wire [2:0] arready,
    input wire [17:0] araddr,
    input wire [1:0] src,
    input wire [7:0] arid,
    input wire [4:0] ar_port_id,
    input wire [1:0] arresp,
    output wire [2:0] rvalid,
    input wire [2:0] rready,
    output wire [127:0] rdata,
    output wire [7:0] rid,
    output wire [4:0] r_port_id,
    output wire [2:0] raddr,
    output wire [1:0] rresp,
    output wire [7:0] req,
    output wire [11:0] arb_addr,
    output wire [3:0] pending_cnt,
    input wire [7:0] ar_rd_gnt,
    // [7:0]: even banks; [15:8]: odd banks, matching the original packed order.
    input wire [15:0] rd_mem_status,
    input wire [127:0] mem_rdata,
    input wire pc_err,
    input wire [7:0] rw_rd_gnt
);
    wire alloc_fire, retire_fire, issue_success, capture_valid;
    wire [3:0] alloc_entry, retire_entry, issue_entry, capture_entry, rsp_entry;
    wire [127:0] rsp_data;
    wire rsp_pc_err;

    cmdbuf_rd_cmd u_cmd (
        .clk(clk), .rst_n(rst_n), .arvalid(arvalid), .arready(arready), .araddr(araddr), .src(src), .arid(arid),
        .ar_port_id(ar_port_id), .arresp(arresp), .rvalid(rvalid), .rready(rready), .rid(rid), .r_port_id(r_port_id),
        .raddr(raddr), .rresp(rresp), .req(req), .arb_addr(arb_addr), .pending_cnt(pending_cnt), .ar_rd_gnt(ar_rd_gnt),
        .rd_mem_status(rd_mem_status), .rw_rd_gnt(rw_rd_gnt), .alloc_fire(alloc_fire), .alloc_entry(alloc_entry),
        .retire_fire(retire_fire), .retire_entry(retire_entry), .issue_success(issue_success), .issue_entry(issue_entry),
        .capture_valid(capture_valid), .capture_entry(capture_entry), .rsp_entry(rsp_entry), .rsp_pc_err(rsp_pc_err)
    );
    cmdbuf_rd_otb u_otb (
        .clk(clk), .rst_n(rst_n), .alloc_fire(alloc_fire), .alloc_entry(alloc_entry), .retire_fire(retire_fire),
        .retire_entry(retire_entry), .issue_success(issue_success), .issue_entry(issue_entry), .capture_valid(capture_valid),
        .capture_entry(capture_entry), .mem_rdata(mem_rdata), .pc_err(pc_err), .rsp_entry(rsp_entry), .rsp_data(rsp_data),
        .rsp_pc_err(rsp_pc_err)
    );
    assign rdata = (|rvalid) ? rsp_data : 128'b0;
endmodule
`default_nettype wire

// Port-only specification checker. Exactly the 24 public DUT ports.
// All m_* state is local verification state, never a physical DUT observation.
// Sampling: an issue at N is captured at N+4; earliest R is N+5.
`default_nettype none
`include "cmdbuf_rd_port_macros.svh"
module cmdbuf_rd_port_sva (
    input wire clk, rst_n, arvalid,
    input wire [2:0] arready,
    input wire [17:0] araddr,
    input wire [1:0] src,
    input wire [7:0] arid,
    input wire [4:0] ar_port_id,
    input wire [1:0] arresp,
    input wire [2:0] rvalid, rready,
    input wire [127:0] rdata,
    input wire [7:0] rid,
    input wire [4:0] r_port_id,
    input wire [2:0] raddr,
    input wire [1:0] rresp,
    input wire [7:0] req,
    input wire [11:0] arb_addr,
    input wire [3:0] pending_cnt,
    input wire [7:0] ar_rd_gnt, rw_rd_gnt,
    input wire [15:0] rd_mem_status,
    input wire [127:0] mem_rdata,
    input wire pc_err

);
    // Zero is the only declaration initializer, including on FormalMC 2024.
    reg started = 1'b0;
    reg previous_reset = 1'b0;
    always @(posedge clk) begin
        started <= 1'b1;
        previous_reset <= !rst_n;
    end
    wire active = started && rst_n;
    wire accept = arvalid && (src < 3) && ((src < 3) ? arready[src] : 1'b0);
    wire success = |(req & ar_rd_gnt & rw_rd_gnt);
    wire retire = |(rvalid & rready);
    reg [8:0] m_live, m_sent, m_done, m_pc;
    reg [3:0] m_due;

    // The BASE input contract contains exactly five assumptions.
    /* [NO_REF_MODEL_HISTORY] */`TP_ASSUME(E01_RESET_FIRST, started || !rst_n) // [NO_REF_MODEL_HISTORY]
`ifndef TP_IDLE_RESET
    /* [NO_REF_MODEL_HISTORY] */`TP_ASSUME(E02_RESET_RELEASE, !started || rst_n) // [NO_REF_MODEL_HISTORY]
`else
    // Extension: subsequent resets only in the empty transaction domain.
    `TP_ASSUME(E02_RESET_IDLE_ONLY, !started || rst_n || (m_live == 0 && m_due == 0)) // [REF_MODEL]
`endif
`ifndef TP_NEGATIVE
    /* [NO_REF_MODEL_PORTS] */`TP_ASSUME(E03_SRC, !arvalid || src < 3) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSUME(E04_ARRESP, !arvalid || arresp == 2'b00 || arresp == 2'b11) // [NO_REF_MODEL_PORTS]
`endif
    /* [NO_REF_MODEL_PORTS] */`TP_ASSUME(E05_ZERO_READY, arready != 0 || !arvalid) // [NO_REF_MODEL_PORTS]

    // Independent scoreboard: a compact rank (0=oldest) instead of the DUT's
    // pairwise age matrix. It never reads DUT window/done/selection to decide
    // the expected command. The lowest free logical slot is an implementation detail of this checker.
    // It does not predict or assert the physical allocation slot of the DUT.
    reg [17:0] m_addr [0:8];
    reg [1:0] m_src [0:8], m_err [0:8];
    reg [7:0] m_id [0:8];
    reg [4:0] m_port [0:8];
    reg [3:0] m_age [0:8];
    reg [127:0] m_data [0:8];
    reg [1:0] m_rr;
    reg m_attempt;
    reg [3:0] m_attempt_e;
    reg [3:0] m_due_e [0:3];
    reg [3:0] history;
    wire due = m_due[3];
    wire [3:0] due_e = m_due_e[3];
    wire [3:0] aimr = {accept, success, due, retire};
    reg [8:0] pending, pool, window, idle, candidate, selected;
    reg [3:0] select_e;
    wire select_valid = |selected;
    reg [3:0] head [0:2];
    reg [2:0] head_valid, eligible, expected_rvalid;
    wire model_retire = |expected_rvalid;
    reg [1:0] winner;
    reg [3:0] rsp_e, alloc_e;
    reg free_found;
    reg [2:0] expected_ready;
    integer used, waiting, shared_cost, quota_cost;
    integer occ [0:2];
    integer after_occ [0:2];
    integer used_after, shared_after;
    integer ranks [0:8];
    integer best_age, scan;
    integer i, j, x, off;

    always @* begin
        used = 0; waiting = 0; shared_cost = 0; quota_cost = 0;
        for (x=0; x<3; x=x+1) occ[x] = 0;
        for (i=0; i<9; i=i+1) begin
            if (m_live[i]) begin
                used = used+1;
                if (!m_sent[i]) waiting = waiting+1;
                if (m_src[i]<3) occ[m_src[i]] = occ[m_src[i]]+1;
            end
        end
        for (x=0; x<3; x=x+1) begin
            if (occ[x]>0) shared_cost = shared_cost+occ[x]-1;
            quota_cost = quota_cost+((occ[x]>0)?occ[x]:1);
        end
        // Find the oldest live head first; only then consult done and ready.
        head_valid = 0; eligible = 0;
        for (x=0; x<3; x=x+1) begin
            head[x] = 0; best_age = 9;
            for (i=0; i<9; i=i+1)
                if (m_live[i] && m_src[i]==x && m_age[i]<best_age) begin
                    head_valid[x]=1; head[x]=i; best_age=m_age[i];
                end
            if (head_valid[x]) eligible[x] = m_done[head[x]] && rready[x];
        end
        expected_rvalid=0; winner=0; rsp_e=0; scan=0;
        for (off=0; off<3; off=off+1) begin
            scan=m_rr+off; if(scan>=3) scan=scan-3;
            if (expected_rvalid==0 && eligible[scan]) begin
                expected_rvalid[scan]=1; winner=scan; rsp_e=head[scan];
            end
        end
        if(!rst_n) expected_rvalid=0;
        used_after=0; shared_after=0;
        for(x=0;x<3;x=x+1) begin
            after_occ[x]=occ[x]-((model_retire && winner==x)?1:0);
            used_after=used_after+after_occ[x];
            if(after_occ[x]>0) shared_after=shared_after+after_occ[x]-1;
        end
        expected_ready=0;
        for(x=0;x<3;x=x+1)
            expected_ready[x]=rst_n && used_after<9 &&
                               (after_occ[x]==0 || shared_after<6);
        alloc_e=0; free_found=0;
        for(i=0;i<9;i=i+1)
            if(!free_found && (!m_live[i] || (model_retire && rsp_e==i))) begin
                free_found=1; alloc_e=i;
            end
        pending=m_live & ~m_sent;
        pool=pending;
        // 6B: remove only a successful current issue from the rank pool.
        if(success && m_attempt_e<9) pool[m_attempt_e]=0;
        window=0; idle=0; candidate=0; selected=0; select_e=0;
        for(i=0;i<9;i=i+1) begin
            ranks[i]=0;
            for(j=0;j<9;j=j+1)
                if(pool[j] && m_age[j]<m_age[i]) ranks[i]=ranks[i]+1;
            window[i]=pool[i] && ranks[i]<5;
            idle[i]=!rd_mem_status[m_addr[i][6:3]];
            // Failed current attempt occupies a window position, but cannot
            // be selected again in the immediately following request cycle.
            candidate[i]=window[i] && idle[i] && !(m_attempt && m_attempt_e==i);
        end
        best_age=9;
        for(i=0;i<9;i=i+1)
            if(candidate[i] && m_age[i]<best_age) begin
                best_age=m_age[i]; select_e=i;
            end
        if(best_age<9) selected[select_e]=1;
    end

    integer e,k;
    always @(posedge clk) begin
        if(!rst_n) begin
            m_live<=0; m_sent<=0; m_done<=0; m_pc<=0; m_rr<=0;
            m_attempt<=0; m_attempt_e<=0; m_due<=0; history<=0;
            for(k=0;k<4;k=k+1) m_due_e[k]<=0;
            for(e=0;e<9;e=e+1) begin
                m_addr[e]<=0; m_src[e]<=0; m_err[e]<=0; m_id[e]<=0;
                m_port[e]<=0; m_age[e]<=0; m_data[e]<=0;
            end
        end else begin
            history<={history[2:0],1'b1};
            m_due<={m_due[2:0],success};
            m_due_e[0]<=success?m_attempt_e:4'd0;
            for(k=1;k<4;k=k+1) m_due_e[k]<=m_due[k-1]?m_due_e[k-1]:4'd0;
            m_attempt<=select_valid;
            m_attempt_e<=select_valid?select_e:4'd0;
            if(model_retire) m_rr<=(winner==2)?2'd0:winner+2'd1;
            for(e=0;e<9;e=e+1) begin
                if(accept && alloc_e==e) begin
                    m_live[e]<=1; m_sent[e]<=0; m_done[e]<=0; m_pc[e]<=0;
                    m_addr[e]<=araddr; m_src[e]<=src; m_err[e]<=arresp;
                    m_id[e]<=arid; m_port[e]<=ar_port_id;
                    m_age[e]<=used-(model_retire?1:0); m_data[e]<=0;
                end else if(model_retire && rsp_e==e) begin
                    m_live[e]<=0; m_sent[e]<=0; m_done[e]<=0; m_pc[e]<=0;
                    m_addr[e]<=0; m_src[e]<=0; m_err[e]<=0; m_id[e]<=0;
                    m_port[e]<=0; m_age[e]<=0; m_data[e]<=0;
                end else begin
                    if(model_retire && m_live[e] && m_age[e]>m_age[rsp_e])
                        m_age[e]<=m_age[e]-1'b1;
                    if(success && m_attempt_e==e) m_sent[e]<=1;
                    if(due && due_e==e) begin
                        m_done[e]<=1; m_data[e]<=mem_rdata; m_pc[e]<=pc_err;
                    end
                end
            end
        end
    end

    wire [7:0] expected_req=(rst_n && m_attempt)?(8'b1<<m_addr[m_attempt_e][5:3]):8'd0;
    wire [11:0] expected_addr=(rst_n && m_attempt)?m_addr[m_attempt_e][17:6]:12'd0;
    wire [1:0] expected_resp=(m_err[rsp_e]==2'b11)?2'b11:(m_pc[rsp_e]?2'b01:2'b00);
    wire bad_src=arvalid && src==3;
    wire bad_arresp=arvalid && (arresp==2'b01 || arresp==2'b10);

`ifndef TP_NEGATIVE
    // DUT obligations: all compare externally observable behavior.
    /* [NO_REF_MODEL_PORTS] */`TP_ASSERT(A_RESET_OUTPUTS, rst_n || (arready==0 && rvalid==0 && req==0)) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_HISTORY] */`TP_ASSERT(A_RESET_EMPTY, !started || !previous_reset || (pending_cnt==0 && req==0 && rvalid==0)) // [NO_REF_MODEL_HISTORY]
    `TP_ASSERT(A_READY, !active || arready==expected_ready) // [REF_MODEL]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSERT(A_REQ_ONEHOT, !active || $onehot0(req)) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSERT(A_R_ONEHOT, !active || $onehot0(rvalid)) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSERT(A_R_READY, !active || (rvalid & ~rready)==0) // [NO_REF_MODEL_PORTS]
    `TP_ASSERT(A_PENDING, !active || pending_cnt==waiting) // [REF_MODEL]
    `TP_ASSERT(A_REQ, !active || req==expected_req) // [REF_MODEL]
    `TP_ASSERT(A_ARB_ADDR, !active || arb_addr==expected_addr) // [REF_MODEL]
    `TP_ASSERT(A_RR_CHOICE, !active || rvalid==expected_rvalid) // [REF_MODEL]
    `TP_ASSERT(A_R_METADATA, !active || !retire || (rid==m_id[rsp_e] && r_port_id==m_port[rsp_e] && raddr==m_addr[rsp_e][2:0])) // [REF_MODEL]
    `TP_ASSERT(A_R_RESP, !active || !retire || rresp==expected_resp) // [REF_MODEL]
    `TP_ASSERT(A_R_DATA, !active || !retire || rdata==m_data[rsp_e]) // [REF_MODEL]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSERT(A_R_IDLE_ZERO, !active || rvalid!=0 || (rdata==0 && rid==0 && r_port_id==0 && raddr==0 && rresp==0)) // [NO_REF_MODEL_PORTS]
    // Model sanity properties are not evidence of physical DUT storage state.
    `TP_ASSERT(M_ALLOC, !active || !accept || (free_found && alloc_e<9)) // [MODEL_SELF_CHECK]
    `TP_ASSERT(M_RETIRE, !active || !retire || (model_retire && rsp_e<9 && m_live[rsp_e] && m_sent[rsp_e] && m_done[rsp_e])) // [MODEL_SELF_CHECK]
    `TP_ASSERT(M_SUCCESS, !active || !success || (m_attempt && m_attempt_e<9 && m_live[m_attempt_e] && !m_sent[m_attempt_e])) // [MODEL_SELF_CHECK]
    `TP_ASSERT(M_DUE, !active || !due || (due_e<9 && m_live[due_e] && m_sent[due_e] && !m_done[due_e])) // [MODEL_SELF_CHECK]
    `TP_ASSERT(M_NO_BYPASS, !active || !due || !retire || due_e!=rsp_e) // [MODEL_SELF_CHECK]
    `TP_ASSERT(M_STATE, !active || ((m_sent & ~m_live)==0 && (m_done & ~m_sent)==0)) // [MODEL_SELF_CHECK]
    `TP_ASSERT(M_RANGE, !active || (waiting>=0 && waiting<=used && used<=9)) // [MODEL_SELF_CHECK]
    `TP_ASSERT(M_QUOTA, !active || (shared_cost<=6 && quota_cost<=9)) // [MODEL_SELF_CHECK]
    `TP_ASSERT(M_ATTEMPT, !active || !m_attempt || (m_attempt_e<9 && m_live[m_attempt_e] && !m_sent[m_attempt_e])) // [MODEL_SELF_CHECK]
    genvar g,h;
    generate for(g=0;g<9;g=g+1) begin : slots
        `TP_ASSERT(M_AGE_RANGE, !active || !m_live[g] || m_age[g]<used) // [MODEL_SELF_CHECK]
        wire [3:0] calendar_count = {3'b0,(m_due[0] && m_due_e[0]==g)} + {3'b0,(m_due[1] && m_due_e[1]==g)} + {3'b0,(m_due[2] && m_due_e[2]==g)} + {3'b0,(m_due[3] && m_due_e[3]==g)};
        `TP_ASSERT(M_CALENDAR, !active || calendar_count=={3'b0,(m_live[g] && m_sent[g] && !m_done[g])}) // [MODEL_SELF_CHECK]
        for(h=0;h<9;h=h+1) begin : pairs
            if(g!=h) begin : distinct
                `TP_ASSERT(M_AGE_UNIQUE, !active || !m_live[g] || !m_live[h] || m_age[g]!=m_age[h]) // [MODEL_SELF_CHECK]
            end
        end
    end
    for(g=0;g<3;g=g+1) begin : sources
        reg [1:0] bypass_count;
        always @(posedge clk)
            if(!rst_n || !eligible[g] || rvalid[g]) bypass_count<=0;
            else if(retire) bypass_count<=bypass_count+1'b1;
        `TP_ASSERT(A_RR_BOUND, !active || !eligible[g] || bypass_count<2 || rvalid[g]) // [REF_MODEL]
    end endgenerate
`endif

    // Scenario history is verification state, not an additional input contract.
    reg [12:0] accepted_total, retired_total;
    reg [7:0] success_pattern;
    reg [5:0] pc_pattern;
    reg [5:0] busy_streak;
    reg [6:0] idle_streak;
    reg [15:0] last_status;
    reg [3:0] issue_streak, response_streak, fullrate_streak;
    reg seen_busy6, seen_reuse, seen_out_of_order, seen_noise;
    reg [2:0] seen_accept_src, seen_retire_src;
    reg [2:0] failures [0:8];
    reg [8:0] ever_used, reused, overtaken;
    reg [3:0] age_cycles [0:8];
    reg [3:0] done_cycles [0:8];
    reg [3:0] flow_stage;
    reg [3:0] flow_e;
    reg [1:0] flow_src;
    reg [3:0] flow_target;
    reg [4:0] flow_cycles;
    reg flow_isolated;
    reg [15:0] target_seen;
    wire blocked_six=(waiting>=6 && window!=0 && (window & idle)==0 && (pool & ~window & idle)!=0 && !m_attempt);
    integer z;
    always @(posedge clk) begin
        if(!rst_n) begin
            accepted_total<=0; retired_total<=0; success_pattern<=0; pc_pattern<=0;
            busy_streak<=0; idle_streak<=0; last_status<=0;
            issue_streak<=0; response_streak<=0; fullrate_streak<=0;
            seen_busy6<=0; seen_reuse<=0; seen_out_of_order<=0; seen_noise<=0;
            seen_accept_src<=0; seen_retire_src<=0; ever_used<=0; reused<=0; overtaken<=0;
            flow_stage<=0; flow_e<=0; flow_src<=0; flow_target<=0; flow_cycles<=0; flow_isolated<=0; target_seen<=0;
            for(z=0;z<9;z=z+1) begin failures[z]<=0; age_cycles[z]<=0; done_cycles[z]<=0; end
        end else begin
            if(accept && accepted_total!=8191) accepted_total<=accepted_total+1'b1;
            if(retire && retired_total!=8191) retired_total<=retired_total+1'b1;
            success_pattern<={success_pattern[6:0],success};
            if(due) pc_pattern<={pc_pattern[4:0],pc_err};
            last_status<=rd_mem_status;
            if(blocked_six && rd_mem_status==last_status) begin
                if(busy_streak!=63) busy_streak<=busy_streak+1'b1;
            end else busy_streak<=0;
            if(used==0 && !accept && m_due==0) begin
                if(idle_streak!=127) idle_streak<=idle_streak+1'b1;
            end else idle_streak<=0;
            if(success) begin if(issue_streak!=15) issue_streak<=issue_streak+1'b1; end else issue_streak<=0;
            if(retire) begin if(response_streak!=15) response_streak<=response_streak+1'b1; end else response_streak<=0;
            if(aimr==15) begin if(fullrate_streak!=15) fullrate_streak<=fullrate_streak+1'b1; end else fullrate_streak<=0;
            if(busy_streak>=16) seen_busy6<=1;
            if(accept && retire && alloc_e==rsp_e) seen_reuse<=1;
            if(success && m_age[m_attempt_e]!=0) seen_out_of_order<=1;
            if(used==0 && !accept && (mem_rdata!=0 || pc_err || ar_rd_gnt!=0)) seen_noise<=1;
            if(accept) begin seen_accept_src[src]<=1; ever_used[alloc_e]<=1; end
            if(retire) seen_retire_src[winner]<=1;
            if(success) target_seen[m_addr[m_attempt_e][6:3]]<=1;
            for(z=0;z<9;z=z+1) begin
                if(accept && alloc_e==z) begin
                    failures[z]<=0; reused[z]<=ever_used[z]; age_cycles[z]<=0; done_cycles[z]<=0; overtaken[z]<=0;
                end else begin
                    if(m_live[z] && age_cycles[z]!=15) age_cycles[z]<=age_cycles[z]+1'b1;
                    if(m_done[z] && done_cycles[z]!=15) done_cycles[z]<=done_cycles[z]+1'b1;
                    if(m_attempt && m_attempt_e==z && !success && failures[z]!=7) failures[z]<=failures[z]+1'b1;
                    if(success && m_live[z] && m_src[z]==m_src[m_attempt_e] && m_age[z]<m_age[m_attempt_e]) overtaken[z]<=1;
                end
            end
            // Exact isolated minimal path monitor; begins with the first AR.
            if(flow_stage==0 && accept && used==0) begin
                flow_stage<=1; flow_e<=alloc_e; flow_src<=src;
                flow_target<=araddr[6:3]; flow_cycles<=0; flow_isolated<=1;
            end else if(flow_stage!=0 && flow_stage!=15) begin
                if(accept) flow_isolated<=0;
                if(flow_cycles!=31) flow_cycles<=flow_cycles+1'b1;
                if(flow_stage==1 && select_valid && select_e==flow_e && flow_cycles==0) flow_stage<=2;
                else if(flow_stage==2 && success && m_attempt_e==flow_e && flow_cycles==1) flow_stage<=3;
                else if(flow_stage==3 && due && due_e==flow_e && flow_cycles==5) flow_stage<=4;
                else if(flow_stage==4 && retire && rsp_e==flow_e && flow_cycles==6) flow_stage<=15;
                else if((flow_stage==1 && flow_cycles==0) || (flow_stage==2 && flow_cycles==1) || (flow_stage==3 && flow_cycles==5) || (flow_stage==4 && flow_cycles==6)) flow_stage<=0;
            end
        end
    end

`include "cmdbuf_rd_port_scenarios.svh"
`include "cmdbuf_rd_port_covers.svh"
`include "cmdbuf_rd_port_profiles.svh"
endmodule
`undef TP_ASSERT
`undef TP_ASSUME
`undef TP_COVER
`default_nettype wire

`default_nettype none
module cmdbuf_rd_formal (
    input wire clk,
    input wire rst_n,
    input wire arvalid,
    output wire [2:0] arready,
    input wire [17:0] araddr,
    input wire [1:0] src,
    input wire [7:0] arid,
    input wire [4:0] ar_port_id,
    input wire [1:0] arresp,
    output wire [2:0] rvalid,
    input wire [2:0] rready,
    output wire [127:0] rdata,
    output wire [7:0] rid,
    output wire [4:0] r_port_id,
    output wire [2:0] raddr,
    output wire [1:0] rresp,
    output wire [7:0] req,
    output wire [11:0] arb_addr,
    output wire [3:0] pending_cnt,
    input wire [7:0] ar_rd_gnt,
    // [7:0]: even banks; [15:8]: odd banks, matching the original packed order.
    input wire [15:0] rd_mem_status,
    input wire [127:0] mem_rdata,
    input wire pc_err,
    input wire [7:0] rw_rd_gnt
);
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
