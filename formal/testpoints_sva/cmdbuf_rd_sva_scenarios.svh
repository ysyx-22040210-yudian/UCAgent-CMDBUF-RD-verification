// Finite monitors for multi-cycle business scenarios. These contain no assume.
// Observed slot identities are never reused while a monitor still owns them.
reg [2:0] retry_stage;
reg [3:0] retry_slot;
reg retry_busy, retry_reselected;
reg retry_finished, exact_retry_finished;
reg [2:0] exact_retry_stage;
wire attempt_ar = |(req & ar_rd_gnt);
wire attempt_rw = |(req & rw_rd_gnt);
wire wrong_grant = (ar_rd_gnt & rw_rd_gnt)!=0 && !success;
reg [3:0] burst_count, burst_length;
reg [1:0] burst_phase;
reg burst_restart;
reg long_idle_pending, long_idle_finished;
reg [3:0] long_idle_slot;
reg [3:0] drain9_count;
reg drain9_started, drain9_finished;
reg rr_backlog_seen, rr_release_seen;
reg [2:0] rr_release_srcs;
reg [2:0] rr_release_count;
reg [3:0] ready_sequence;
reg ready_sequence_done;
reg [3:0] pc_run;
reg [5:0] pc_contiguous;
reg pc_run_done;
reg success_bubble_seen;
reg [8:0] bubble_live;
reg bubble_drained;
reg [2:0] bubble_delay;
reg [7:0] bubble_expected;
reg [8:0] same_source_pair;
reg same_source_old_r, same_source_pair_done;
reg [3:0] pair_old, pair_young;
reg pair_active;
reg [2:0] hotspot_sources;
reg hotspot_seen, hotspot_failure, hotspot_retired;
reg [2:0] hotspot_bank;
reg [1:0] hotspot_halves;
reg [8:0] hotspot_live;
reg half_flip_seen;
reg [15:0] prev_status;
reg reserved_outside_seen;
reg [3:0] reserved_outside_slot;
reg [4:0] reserved_outside_cycles;
reg opposite_reuse_seen;
reg [3:0] opposite_reuse_slot;
reg opposite_reuse_completed;
reg [3:0] completed_error_types;
reg [2:0] duplicate_completed;
reg [8:0] dup_same, dup_cross, dup_desc;
reg [3:0] shifted_selections;
reg wrap_accepted, wrap_completed;
reg [3:0] wrap_slot;
integer si,sj;
always @(posedge clk) begin
  if(!rst_n) begin
    retry_stage<=0;retry_slot<=0;retry_busy<=0;retry_reselected<=0;
    retry_finished<=0;exact_retry_finished<=0;exact_retry_stage<=0;
    burst_count<=0;burst_length<=0;burst_phase<=0;burst_restart<=0;
    long_idle_pending<=0;long_idle_finished<=0;long_idle_slot<=0;
    drain9_count<=0;drain9_started<=0;drain9_finished<=0;
    rr_backlog_seen<=0;rr_release_seen<=0;rr_release_srcs<=0;rr_release_count<=0;
    ready_sequence<=0;ready_sequence_done<=0;pc_run<=0;pc_contiguous<=0;pc_run_done<=0;
    success_bubble_seen<=0;bubble_live<=0;bubble_drained<=0;bubble_delay<=0;bubble_expected<=0;
    same_source_pair<=0;same_source_old_r<=0;same_source_pair_done<=0;pair_old<=0;pair_young<=0;pair_active<=0;
    hotspot_sources<=0;hotspot_seen<=0;hotspot_failure<=0;hotspot_retired<=0;hotspot_bank<=0;hotspot_halves<=0;hotspot_live<=0;
    half_flip_seen<=0;prev_status<=0;reserved_outside_seen<=0;reserved_outside_slot<=0;reserved_outside_cycles<=0;
    opposite_reuse_seen<=0;opposite_reuse_slot<=0;opposite_reuse_completed<=0;
    completed_error_types<=0;duplicate_completed<=0;dup_same<=0;dup_cross<=0;dup_desc<=0;
    shifted_selections<=0;wrap_accepted<=0;wrap_completed<=0;wrap_slot<=0;
  end else begin
    // One tracked command: fail00, fail10, fail01, wrong-bank11, success,
    // capture and retire, preserving identity across the complete path.
    if(retry_stage==0 && m_attempt && !success && !attempt_ar && !attempt_rw) begin
      retry_stage<=1;retry_slot<=m_attempt_e;exact_retry_stage<=1;
    end
    if(retry_stage==1) begin
      if(m_live[retry_slot] && rd_mem_status[m_addr[retry_slot][6:3]]) retry_busy<=1;
      if(retry_busy && select_valid && select_e==retry_slot) retry_reselected<=1;
      if(m_attempt && m_attempt_e==retry_slot) begin
        if(exact_retry_stage==1 && attempt_ar && !attempt_rw && !success) exact_retry_stage<=2;
        if(exact_retry_stage==2 && !attempt_ar && attempt_rw && !success) exact_retry_stage<=3;
        if(exact_retry_stage==3 && wrong_grant && !attempt_ar && !attempt_rw) exact_retry_stage<=4;
        if(success) retry_stage<=2;
      end
    end
    if(retry_stage==2 && due && due_e==retry_slot) retry_stage<=3;
    if(retry_stage==3 && retire && rsp_e==retry_slot) begin
      retry_finished<=1;retry_stage<=4;
      if(exact_retry_stage==4) exact_retry_finished<=1;
    end
    // Burst lengths are accepted-command lengths, not raw arvalid pulses.
    burst_restart<=0;
    if(burst_phase==0 && accept && used==0) begin burst_phase<=1;burst_count<=1;end
    else if(burst_phase==1) begin
      if(accept) begin if(burst_count!=15) burst_count<=burst_count+1'b1;end
      else begin burst_phase<=2;burst_length<=burst_count;end
    end else if(burst_phase==2) begin
      if(accept && used==0) begin burst_restart<=1;burst_phase<=1;burst_count<=1;end
      else if(accept) burst_phase<=0;
    end
    if(idle_streak>=64 && seen_noise && accept) begin long_idle_pending<=1;long_idle_slot<=alloc_e;end
    if(long_idle_pending && retire && rsp_e==long_idle_slot) begin long_idle_pending<=0;long_idle_finished<=1;end
    // Hold all nine completed entries, then release and retire those nine
    // without accepting replacements. New traffic invalidates this witness.
    if(m_done==9'h1ff && rready==0) begin drain9_started<=1;drain9_count<=0;end
    if(drain9_started) begin
      if(accept) begin drain9_started<=0;drain9_count<=0;end
      else if(retire) begin
        drain9_count<=drain9_count+1'b1;
        if(drain9_count==8) begin drain9_finished<=1;drain9_started<=0;end
      end
    end
    if(head_valid==7 && m_done[head[0]] && m_done[head[1]] && m_done[head[2]] && rready==0) rr_backlog_seen<=1;
    if(rr_backlog_seen && rready==7 && retire && !rr_release_seen) begin
      rr_release_seen<=1;rr_release_srcs<=rvalid;rr_release_count<=1;
    end else if(rr_release_seen && rr_release_count<3) begin
      if(retire && rready==7) begin rr_release_count<=rr_release_count+1'b1;rr_release_srcs<=rr_release_srcs|rvalid;end
      else begin rr_release_seen<=0;rr_release_count<=0;end
    end
    // Dynamic ready sequence 000,001,010,011,100,101,110,111 while data exists.
    if(m_done!=0 && rready==ready_sequence[2:0]) begin
      if(ready_sequence==7) ready_sequence_done<=1;
      else ready_sequence<=ready_sequence+1'b1;
    end else ready_sequence<=0;
    if(due) begin
      pc_contiguous<={pc_contiguous[4:0],pc_err};
      if(pc_run!=15) pc_run<=pc_run+1'b1;
      if(pc_run>=5 && {pc_contiguous[4:0],pc_err}==6'b010110) pc_run_done<=1;
    end else pc_run<=0;
    if(success_pattern==8'b10100110 && !success_bubble_seen) begin
      success_bubble_seen<=1;bubble_live<=m_live;bubble_delay<=0;bubble_expected<=success_pattern;
    end
    if(success_bubble_seen) begin
      if(retire) bubble_live[rsp_e]<=0;
      if(bubble_live==0) bubble_drained<=1;
    end
    // A live old head waits while a younger command of the same source is done.
    if(!pair_active && !same_source_pair_done)
      for(si=0;si<9;si=si+1) for(sj=0;sj<9;sj=sj+1)
        if(m_live[si] && m_live[sj] && m_src[si]==m_src[sj] && m_age[si]<m_age[sj] && !m_done[si] && m_done[sj]) begin
          pair_active<=1;pair_old<=si;pair_young<=sj;same_source_old_r<=0;
        end
    if(pair_active && retire && rsp_e==pair_old) same_source_old_r<=1;
    if(pair_active && same_source_old_r && retire && rsp_e==pair_young) begin same_source_pair_done<=1;pair_active<=0;end
    // Fixed-bank hotspot prefix starts in an empty system and includes all
    // three sources, both halves, at least one failure, and their retirement.
    prev_status<=rd_mem_status;
    if(!hotspot_seen && accept && used==0) begin
      hotspot_seen<=1;hotspot_bank<=araddr[5:3];hotspot_sources<=(3'b1<<src);
      hotspot_halves<=(2'b1<<araddr[6]);hotspot_live<=(9'b1<<alloc_e);
    end else if(hotspot_seen && !hotspot_retired) begin
      if(accept && araddr[5:3]!=hotspot_bank) begin hotspot_seen<=0;hotspot_sources<=0;hotspot_halves<=0;hotspot_live<=0;hotspot_failure<=0;half_flip_seen<=0;end
      else begin
        if(accept) begin hotspot_sources[src]<=1;hotspot_halves[araddr[6]]<=1;hotspot_live[alloc_e]<=1;end
        if(m_attempt && m_addr[m_attempt_e][5:3]==hotspot_bank && !success) hotspot_failure<=1;
        if(prev_status[hotspot_bank]!=rd_mem_status[hotspot_bank] && prev_status[hotspot_bank+8]!=rd_mem_status[hotspot_bank+8] && rd_mem_status[hotspot_bank]!=rd_mem_status[hotspot_bank+8]) half_flip_seen<=1;
        if(retire && !(accept && alloc_e==rsp_e)) hotspot_live[rsp_e]<=0;
        if(hotspot_sources==7 && hotspot_halves==3 && hotspot_failure && hotspot_live==0) hotspot_retired<=1;
      end
    end
    if(!reserved_outside_seen && accept && occ[src]==0 && waiting>=5 && (window & idle)==0 && !rd_mem_status[araddr[6:3]]) begin
      reserved_outside_seen<=1;reserved_outside_slot<=alloc_e;reserved_outside_cycles<=0;
    end else if(reserved_outside_seen && reserved_outside_cycles<16) begin
      if(m_live[reserved_outside_slot] && !window[reserved_outside_slot] && !m_sent[reserved_outside_slot] && rd_mem_status==prev_status) reserved_outside_cycles<=reserved_outside_cycles+1'b1;
      else begin reserved_outside_seen<=0;reserved_outside_cycles<=0;end
    end
    if(retire && accept && alloc_e==rsp_e && rid!=arid && r_port_id!=ar_port_id && raddr!=araddr[2:0]) begin
      opposite_reuse_seen<=1;opposite_reuse_slot<=alloc_e;
    end
    if(opposite_reuse_seen && retire && rsp_e==opposite_reuse_slot) opposite_reuse_completed<=1;
    if(retire && failures[rsp_e]!=0 && done_cycles[rsp_e]>=2)
      completed_error_types[{(m_err[rsp_e]==3),m_pc[rsp_e]}]<=1;
    if(accept) begin
      dup_same[alloc_e]<=0;dup_cross[alloc_e]<=0;dup_desc[alloc_e]<=0;
      for(si=0;si<9;si=si+1) if(m_live[si] && !(retire && rsp_e==si)) begin
        if(m_id[si]==arid && m_src[si]==src && (m_port[si]!=ar_port_id || m_addr[si][2:0]!=araddr[2:0])) dup_same[alloc_e]<=1;
        if(m_id[si]==arid && m_src[si]!=src && (m_port[si]!=ar_port_id || m_addr[si][2:0]!=araddr[2:0])) dup_cross[alloc_e]<=1;
        if(m_id[si]>arid && m_src[si]==src) dup_desc[alloc_e]<=1;
      end
    end
    if(retire) duplicate_completed<=duplicate_completed|{dup_desc[rsp_e],dup_cross[rsp_e],dup_same[rsp_e]};
    if(success && select_valid && shifted_selections!=15) shifted_selections<=shifted_selections+1'b1;
    if(accept && accepted_total>=256 && arid==0 && !wrap_accepted) begin wrap_accepted<=1;wrap_slot<=alloc_e;end
    if(wrap_accepted && retire && rsp_e==wrap_slot) wrap_completed<=1;
  end
end
