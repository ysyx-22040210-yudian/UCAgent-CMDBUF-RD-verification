// Specification checker for the 200-point CMDBUF_RD test plan.
// No DUT assertion is assumed. All observations are read-only.
// Sampling: an issue at N is captured at N+4; earliest R is N+5.
`default_nettype none
`include "cmdbuf_rd_sva_macros.svh"
module cmdbuf_rd_sva (
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
    input wire pc_err,
    input wire o_alloc, o_retire, o_issue, o_capture,
    input wire [3:0] o_alloc_e, o_retire_e, o_issue_e, o_capture_e, o_rsp_e,
    input wire [8:0] o_valid, o_issued, o_done,
    input wire [161:0] o_addr,
    input wire [17:0] o_src, o_arresp,
    input wire [71:0] o_id,
    input wire [44:0] o_port,
    input wire [80:0] o_older,
    input wire [11:0] o_occ,
    input wire [1:0] o_rr,
    input wire o_attempt, o_select,
    input wire [3:0] o_select_e,
    input wire [8:0] o_pending, o_pool, o_window, o_idle, o_candidate, o_selected,
    input wire [1151:0] o_data,
    input wire [8:0] o_pc, o_reserved, o_otb_done,
    input wire [3:0] o_ret_valid,
    input wire [15:0] o_ret_entry
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
    `TP_ASSUME(E01_RESET_FIRST, started || !rst_n)
`ifndef TP_IDLE_RESET
    `TP_ASSUME(E02_RESET_RELEASE, !started || rst_n)
`else
    // Extension: subsequent resets only in the empty transaction domain.
    `TP_ASSUME(E02_RESET_IDLE_ONLY, !started || rst_n || (m_live == 0 && m_due == 0))
`endif
`ifndef TP_NEGATIVE
    `TP_ASSUME(E03_SRC, !arvalid || src < 3)
    `TP_ASSUME(E04_ARRESP, !arvalid || arresp == 2'b00 || arresp == 2'b11)
`endif
    `TP_ASSUME(E05_ZERO_READY, arready != 0 || !arvalid)

    // Independent scoreboard: a compact rank (0=oldest) instead of the DUT's
    // pairwise age matrix. It never reads DUT window/done/selection to decide
    // the expected command. Physical allocation follows the documented first
    // free slot policy, including current R release, independently of o_alloc_e.
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
            after_occ[x]=occ[x]-((retire && winner==x)?1:0);
            used_after=used_after+after_occ[x];
            if(after_occ[x]>0) shared_after=shared_after+after_occ[x]-1;
        end
        expected_ready=0;
        for(x=0;x<3;x=x+1)
            expected_ready[x]=rst_n && used_after<9 &&
                               (after_occ[x]==0 || shared_after<6);
        alloc_e=0; free_found=0;
        for(i=0;i<9;i=i+1)
            if(!free_found && (!m_live[i] || (retire && rsp_e==i))) begin
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
            if(retire) m_rr<=(winner==2)?2'd0:winner+2'd1;
            for(e=0;e<9;e=e+1) begin
                if(accept && alloc_e==e) begin
                    m_live[e]<=1; m_sent[e]<=0; m_done[e]<=0; m_pc[e]<=0;
                    m_addr[e]<=araddr; m_src[e]<=src; m_err[e]<=arresp;
                    m_id[e]<=arid; m_port[e]<=ar_port_id;
                    m_age[e]<=used-(retire?1:0); m_data[e]<=0;
                end else if(retire && rsp_e==e) begin
                    m_live[e]<=0; m_sent[e]<=0; m_done[e]<=0; m_pc[e]<=0;
                    m_addr[e]<=0; m_src[e]<=0; m_err[e]<=0; m_id[e]<=0;
                    m_port[e]<=0; m_age[e]<=0; m_data[e]<=0;
                end else begin
                    if(retire && m_live[e] && m_age[e]>m_age[rsp_e])
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
    // Reset is checked after its sampling edge. No assumption of DUT reset state.
    `TP_ASSERT(A_RESET_OUTPUTS, rst_n || (arready==0 && rvalid==0 && req==0 && !o_capture))
    `TP_ASSERT(A_RESET_STATE, !started || !previous_reset || (o_valid==0 && o_issued==0 && o_done==0 && o_reserved==0 && o_otb_done==0 && o_occ==0 && pending_cnt==0 && o_rr==0 && o_ret_valid==0 && !o_attempt))
    `TP_ASSERT(A_ACCEPT, !active || o_alloc==accept)
    `TP_ASSERT(A_RETIRE, !active || o_retire==retire)
    `TP_ASSERT(A_SUCCESS, !active || o_issue==success)
    `TP_ASSERT(A_READY, !active || arready==expected_ready)
    `TP_ASSERT(A_REQ_ONEHOT, !active || $onehot0(req))
    `TP_ASSERT(A_R_ONEHOT, !active || $onehot0(rvalid))
    `TP_ASSERT(A_R_READY, !active || (rvalid & ~rready)==0)
    `TP_ASSERT(A_ALLOC_SLOT, !active || !accept || (free_found && o_alloc_e==alloc_e && o_alloc_e<9))
    `TP_ASSERT(A_RETIRE_SLOT, !active || !retire || (o_retire_e==rsp_e && o_rsp_e==rsp_e && rsp_e<9 && m_live[rsp_e] && m_sent[rsp_e] && m_done[rsp_e]))
    `TP_ASSERT(A_SUCCESS_OWNER, !active || !success || (m_attempt && o_issue_e==m_attempt_e && m_live[m_attempt_e] && !m_sent[m_attempt_e]))
    `TP_ASSERT(A_CAPTURE_TIME, !active || o_capture==due)
    `TP_ASSERT(A_CAPTURE_OWNER, !active || !due || (o_capture_e==due_e && due_e<9 && m_live[due_e] && m_sent[due_e] && !m_done[due_e]))
    `TP_ASSERT(A_NO_CAPTURE_BYPASS, !active || !due || !retire || due_e!=rsp_e)
    `TP_ASSERT(A_NO_ISSUE_CAPTURE_ALIAS, !active || !success || !due || m_attempt_e!=due_e)
    `TP_ASSERT(A_NO_ISSUE_RETIRE_ALIAS, !active || !success || !retire || m_attempt_e!=rsp_e)
    `TP_ASSERT(A_NO_ALLOC_CAPTURE_ALIAS, !active || !accept || !due || alloc_e!=due_e)
    `TP_ASSERT(A_NO_ALLOC_ISSUE_ALIAS, !active || !accept || !success || alloc_e!=m_attempt_e)
    `TP_ASSERT(A_ALLOC_NOT_OLD_LIVE, !active || !accept || !m_live[alloc_e] || (retire && rsp_e==alloc_e))
    `TP_ASSERT(A_STATE_VALID, !active || (o_valid==m_live && o_reserved==m_live))
    `TP_ASSERT(A_STATE_SENT, !active || o_issued==m_sent)
    `TP_ASSERT(A_STATE_DONE, !active || (o_done==m_done && o_otb_done==m_done))
    `TP_ASSERT(A_STATE_LEGAL, !active || ((m_sent & ~m_live)==0 && (m_done & ~m_sent)==0))
    `TP_ASSERT(A_PENDING, !active || (pending_cnt==waiting && o_pending==pending))
    `TP_ASSERT(A_COUNT_RANGE, !active || (waiting>=0 && waiting<=used && used<=9))
    `TP_ASSERT(A_QUOTA, !active || (shared_cost<=6 && quota_cost<=9))
    `TP_ASSERT(A_ATTEMPT, !active || (o_attempt==m_attempt && (!m_attempt || o_issue_e==m_attempt_e)))
    `TP_ASSERT(A_ATTEMPT_OWNER, !active || !m_attempt || (m_attempt_e<9 && m_live[m_attempt_e] && !m_sent[m_attempt_e]))
    `TP_ASSERT(A_REQ, !active || req==expected_req)
    `TP_ASSERT(A_ARB_ADDR, !active || arb_addr==expected_addr)
    `TP_ASSERT(A_POOL, !active || o_pool==pool)
    `TP_ASSERT(A_WINDOW, !active || o_window==window)
    `TP_ASSERT(A_IDLE, !active || o_idle==idle)
    `TP_ASSERT(A_CANDIDATE, !active || o_candidate==candidate)
    `TP_ASSERT(A_SELECT, !active || (o_selected==selected && o_select==select_valid && (!select_valid || o_select_e==select_e)))
    `TP_ASSERT(A_RR_POINTER, !active || (o_rr==m_rr && m_rr<3))
    `TP_ASSERT(A_RR_CHOICE, !active || rvalid==expected_rvalid)
    `TP_ASSERT(A_R_METADATA, !active || !retire || (rid==m_id[rsp_e] && r_port_id==m_port[rsp_e] && raddr==m_addr[rsp_e][2:0]))
    `TP_ASSERT(A_R_RESP, !active || !retire || rresp==expected_resp)
    `TP_ASSERT(A_R_DATA, !active || !retire || rdata==m_data[rsp_e])
    `TP_ASSERT(A_R_IDLE_ZERO, !active || rvalid!=0 || (rdata==0 && rid==0 && r_port_id==0 && raddr==0 && rresp==0))

    genvar g,h,t;
    generate for(g=0;g<9;g=g+1) begin : slots
        `TP_ASSERT(A_METADATA, !active || (o_addr[g*18+:18]==m_addr[g] && o_src[g*2+:2]==m_src[g] && o_id[g*8+:8]==m_id[g] && o_port[g*5+:5]==m_port[g] && o_arresp[g*2+:2]==m_err[g]))
        `TP_ASSERT(A_DATA, !active || o_data[g*128+:128]==m_data[g])
        `TP_ASSERT(A_PC, !active || o_pc[g]==m_pc[g])
        `TP_ASSERT(A_AGE_RANGE, !active || !m_live[g] || m_age[g]<used)
        `TP_ASSERT(A_STORED_LEGAL, !active || !m_live[g] || (m_src[g]<3 && (m_err[g]==0 || m_err[g]==3)))
        wire [3:0] calendar_count = {3'b0,(m_due[0] && m_due_e[0]==g)} +
                                    {3'b0,(m_due[1] && m_due_e[1]==g)} +
                                    {3'b0,(m_due[2] && m_due_e[2]==g)} +
                                    {3'b0,(m_due[3] && m_due_e[3]==g)};
        `TP_ASSERT(A_INFLIGHT_CALENDAR, !active || calendar_count=={3'b0,(m_live[g] && m_sent[g] && !m_done[g])})
        for(h=0;h<9;h=h+1) begin : pairs
            `TP_ASSERT(A_AGE, !active || o_older[g*9+h]==(m_live[g] && m_live[h] && m_age[h]<m_age[g]))
            if(g!=h) begin : distinct
                `TP_ASSERT(A_AGE_UNIQUE, !active || !m_live[g] || !m_live[h] || m_age[g]!=m_age[h])
            end
        end
    end
    for(g=0;g<3;g=g+1) begin : sources
        `TP_ASSERT(A_OCC, !active || (o_occ[g*4+:4]==occ[g] && occ[g]<=7))
        // Consecutive eligibility only: the environment may drop ready at will.
        reg [1:0] bypass_count;
        always @(posedge clk)
            if(!rst_n || !eligible[g] || rvalid[g]) bypass_count<=0;
            else if(retire) bypass_count<=bypass_count+1'b1;
        `TP_ASSERT(A_RR_BOUND, !active || !eligible[g] || bypass_count<2 || rvalid[g])
    end
    for(t=0;t<4;t=t+1) begin : return_calendar
        `TP_ASSERT(A_TOKEN_VALID, !active || o_ret_valid[t]==m_due[t])
        `TP_ASSERT(A_TOKEN_ID, !active || o_ret_entry[t*4+:4]==m_due_e[t])
        `TP_ASSERT(A_TOKEN_OWNER, !active || !m_due[t] || (m_due_e[t]<9 && m_live[m_due_e[t]] && m_sent[m_due_e[t]] && !m_done[m_due_e[t]]))
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

`include "cmdbuf_rd_sva_scenarios.svh"
`include "cmdbuf_rd_sva_covers.svh"
`include "cmdbuf_rd_sva_profiles.svh"
endmodule
`undef TP_ASSERT
`undef TP_ASSUME
`undef TP_COVER
`default_nettype wire
