module before_comb(
input wire clk,
    
    input wire rst_n,
    
    
    input wire arvalid,
    
    input wire [2:0] arready,
    
    input wire [17:0] araddr,
    
    input wire [1:0] src,
    
    input wire [7:0] arid,
    
    input wire [4:0] ar_port_id,
    
    input wire [1:0] arresp,
    
    
    input wire [2:0] rvalid,
    
    input wire [2:0] rready,
    
    input wire [127:0] rdata,
    
    input wire [7:0] rid,
    
    input wire [4:0] r_port_id,
    
    input wire [2:0] raddr,
    
    input wire [1:0] rresp,
    
    
    input wire [7:0] req,
    
    input wire [11:0] arb_addr,
    
    input wire [3:0] pending_cnt,
    
    input wire [7:0] ar_rd_gnt,
    
    input wire [7:0] rw_rd_gnt,
    
    
    input wire [1:0] rd_mem_status [7:0],
    
    input wire [127:0] mem_rdata,
    
    input wire pc_err,
input wire [8:0] m_live ,
input wire [8:0] m_sent ,
input wire [8:0] m_done ,
input wire [8:0] m_pc ,
input wire [17:0] m_addr [0:8],
input wire [1:0] m_src [0:8],
input wire [1:0] m_err [0:8],
input wire [7:0] m_id [0:8],
input wire [4:0] m_port [0:8],
input wire [3:0] m_age [0:8],
input wire [127:0] m_data [0:8],
input wire [1:0] m_rr ,
input wire  m_attempt ,
input wire [3:0] m_attempt_e ,
input wire [3:0] m_due ,
input wire [3:0] m_due_e [0:3],
input wire  retry_selected ,
input wire  refill_selected ,
input wire  nonhead_refill_selected ,
input wire [11:0] last_retry_addr ,
input wire [11:0] last_refill_addr ,
input wire [7:0] last_retry_req ,
input wire [7:0] last_refill_req ,
input wire [2:0] blocked_streak ,
input wire [3:0] issue_streak ,
input wire [4:0] h_occ [0:2],
input wire  h_prev_a ,
input wire  h_prev_i ,
input wire  h_prev_r ,
input wire  h_prev_m ,
input wire  h_prev_valid ,
input wire  h_prev_pc ,
input wire [1:0] h_prev_src ,
input wire [1:0] h_prev_rsrc ,
input wire [1:0] h_prev_rr ,
input wire [2:0] h_prev_ready ,
input wire [2:0] h_prev_rready ,
input wire [2:0] h_prev_eligible ,
input wire [7:0] h_prev_req ,
input wire [7:0] h_prev_id ,
input wire [11:0] h_prev_arb ,
input wire [17:0] h_prev_addr ,
input wire [4:0] h_prev_port ,
input wire [127:0] h_prev_mem ,
input wire [3:0] h_prev_n ,
input wire [3:0] h_prev_p ,
input wire [3:0] h_prev_occ [0:2],
input wire [15:0] h_prev_status ,
input wire [5:0] h_i_history ,
input wire [5:0] h_a_history ,
input wire [5:0] h_m_history ,
input wire [6:0] h_single_start ,
input wire [5:0] h_src_history ,
input wire [2:0] h_rsrc_history ,
input wire [2:0] h_pc_history ,
input wire [2:0] h_ar_sources ,
input wire [5:0] h_total_a ,
input wire [5:0] h_total_r ,
input wire [3:0] h_same_ar_run ,
input wire [3:0] h_ar_run ,
input wire [3:0] h_r_run ,
input wire [3:0] h_ar_r_run ,
input wire [3:0] h_reject_run ,
input wire [3:0] h_quiet_run ,
input wire [3:0] h_empty_run ,
input wire [3:0] h_notready_run [0:2],
input wire  h_ever_full ,
input wire  h_was_drained ,
input wire [3:0] h_done_wait [0:8],
input wire [8:0] h_retired_bad ,
input wire [8:0] h_clean_reuse ,
input wire  h_failed_none ,
input wire  h_failed_other ,
input wire  h_blocked_prev ,
input wire  h_selected_prev ,
input wire  h_accepted_empty ,
input wire [7:0] h_selected_req ,
input wire [11:0] h_selected_addr ,
input wire [3:0] h_prev_due_slot ,
input wire [8:0] h_failed_once ,
input wire [8:0] h_failed_before_success ,
input wire [1:0] h_rr012_phase ,
input wire [1:0] h_error_sandwich_phase ,
input wire  h_rr_gap_seen ,
input wire  h_seen_reject ,
input wire  h_seen_partial_ready ,
input wire [17:0] h_prev_raddr_full ,
output wire [9999:0] result
);
wire ar_fire; assign ar_fire=arvalid && src<3 && ((src<3)?arready[src]:1'b0);
wire issue_fire; assign issue_fire=|(req & ar_rd_gnt & rw_rd_gnt);
wire r_fire; assign r_fire=|(rvalid & rready);










    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    
    wire mem_capture_due = m_due[3];
    wire [3:0] mem_capture_slot = m_due_e[3];
    
    
    reg [8:0] pending, pool, window, idle, candidate, selected;
    reg [3:0] select_e;
    wire select_valid = |selected;
    
    
    reg [3:0] head [0:2];
    reg [2:0] head_valid, eligible, expected_rvalid;
    
    
    reg model_retire;
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
        model_retire = |expected_rvalid;
        
        
        
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
        
        
        
        
        if(issue_fire && m_attempt_e<9) pool[m_attempt_e]=0;
        window=0; idle=0; candidate=0; selected=0; select_e=0;
        for(i=0;i<9;i=i+1) begin
            ranks[i]=0;
            for(j=0;j<9;j=j+1)
                if(pool[j] && m_age[j]<m_age[i]) ranks[i]=ranks[i]+1;
            window[i]=pool[i] && ranks[i]<5;
            
            
            idle[i]=!rd_mem_status[m_addr[i][5:3]][m_addr[i][6]];
            
            candidate[i]=window[i] && idle[i];
        end
        
        
        best_age=9;
        for(i=0;i<9;i=i+1)
            if(candidate[i] && m_age[i]<best_age) begin
                best_age=m_age[i]; select_e=i;
            end
        if(best_age<9) selected[select_e]=1;
    end

    integer e,k;
    

    
    
    wire [7:0] expected_req=(rst_n && m_attempt)?(8'b1<<m_addr[m_attempt_e][5:3]):8'd0;
    wire [11:0] expected_addr=(rst_n && m_attempt)?m_addr[m_attempt_e][17:6]:12'd0;
    
    wire [1:0] expected_resp=(m_err[rsp_e]==2'b11)?2'b11:(m_pc[rsp_e]?2'b01:2'b00);


    
    
    
    
    
    
    
    
    
    
    integer selected_old_rank;
    integer c;
    always @* begin
        
        selected_old_rank=0;
        for(c=0;c<9;c=c+1)
            if(pending[c] && m_age[c]<m_age[select_e]) selected_old_rank=selected_old_rank+1;
    end
    
    
    wire blocked_six=waiting>=6 && (window & idle)==0 && (pool & ~window & idle)!=0 && !m_attempt;
    





    
    
    
    integer h_total, h_budget, h_after_total, h_shared_after;
    integer h_after [0:2];
    reg [2:0] h_ready;
    integer hi;
    always @* begin
        h_total=0; h_budget=0; h_after_total=0; h_shared_after=0;
        for(hi=0;hi<3;hi=hi+1) begin
            h_total=h_total+h_occ[hi];
            h_budget=h_budget+((h_occ[hi]==0)?1:h_occ[hi]);
            h_after[hi]=h_occ[hi]-((rvalid[hi]&&rready[hi])?1:0);
            h_after_total=h_after_total+h_after[hi];
            if(h_after[hi]>1) h_shared_after=h_shared_after+h_after[hi]-1;
        end
        for(hi=0;hi<3;hi=hi+1)
            h_ready[hi]=(h_after_total<9) && (h_after[hi]==0 || h_shared_after<6);
    end
    integer hx;
    

    
    
    
    
    
    
    
    
    
    
    
    
    
    wire [15:0] h_status={rd_mem_status[7],rd_mem_status[6],rd_mem_status[5],rd_mem_status[4],
                           rd_mem_status[3],rd_mem_status[2],rd_mem_status[1],rd_mem_status[0]};
    
    
    
    
    
    
    
    
    
    
    integer ht;
    

    
    reg [8:0] h_rank_idle,h_rank_valid;
    reg h_other_done,h_hole_reused,h_duplicate_id;
    integer hr;
    always @* begin
        h_rank_idle=0;h_rank_valid=0;h_other_done=0;h_hole_reused=0;h_duplicate_id=0;
        for(hr=0;hr<9;hr=hr+1) begin
            if(pool[hr]&&ranks[hr]<9) begin
                h_rank_valid[ranks[hr]]=1;h_rank_idle[ranks[hr]]=idle[hr];
            end
            if(m_live[hr]&&m_done[hr]&&head_valid[m_src[hr]]&&hr!=head[m_src[hr]]) h_other_done=1;
            if(ar_fire && m_live[hr] && hr>alloc_e) h_hole_reused=1;
            if(ar_fire && m_live[hr] && m_id[hr]==arid) h_duplicate_id=1;
        end
    end
    
    
    
    integer he;
    
    wire h_response_matches=r_fire && rvalid==expected_rvalid &&
        {raddr,rid,r_port_id,rdata,rresp}=={m_addr[rsp_e][2:0],m_id[rsp_e],m_port[rsp_e],m_data[rsp_e],expected_resp};

    
    
    
    
    



    
    
    
    
    
    reg h_hotspot;
    integer hs,h_same_bank_count;
    always @* begin
        h_same_bank_count=0;
        for(hs=0;hs<9;hs=hs+1)
            if(pending[hs] && m_addr[hs][5:3]==m_addr[m_attempt_e][5:3])
                h_same_bank_count=h_same_bank_count+1;
        h_hotspot=h_same_bank_count>=3;
    end
    integer hf;
    

assign result={used,waiting,shared_cost,quota_cost,used_after,shared_after,head_valid,eligible,expected_rvalid,winner,rsp_e,model_retire,expected_ready,alloc_e,free_found,pending,pool,window,idle,candidate,selected,select_e,select_valid,mem_capture_due,mem_capture_slot,expected_req,expected_addr,expected_resp,selected_old_rank,blocked_six,h_total,h_budget,h_after_total,h_shared_after,h_ready,h_status,h_rank_idle,h_rank_valid,h_other_done,h_hole_reused,h_duplicate_id,h_response_matches,h_same_bank_count,h_hotspot,occ[0],occ[1],occ[2],after_occ[0],after_occ[1],after_occ[2],head[0],head[1],head[2],ranks[0],ranks[1],ranks[2],ranks[3],ranks[4],ranks[5],ranks[6],ranks[7],ranks[8],h_after[0],h_after[1],h_after[2]};
endmodule

module after_comb(
input wire clk,
    
    input wire rst_n,
    
    
    input wire arvalid,
    
    input wire [2:0] arready,
    
    input wire [17:0] araddr,
    
    input wire [1:0] src,
    
    input wire [7:0] arid,
    
    input wire [4:0] ar_port_id,
    
    input wire [1:0] arresp,
    
    
    input wire [2:0] rvalid,
    
    input wire [2:0] rready,
    
    input wire [127:0] rdata,
    
    input wire [7:0] rid,
    
    input wire [4:0] r_port_id,
    
    input wire [2:0] raddr,
    
    input wire [1:0] rresp,
    
    
    input wire [7:0] req,
    
    input wire [11:0] arb_addr,
    
    input wire [3:0] pending_cnt,
    
    input wire [7:0] ar_rd_gnt,
    
    input wire [7:0] rw_rd_gnt,
    
    
    input wire [1:0] rd_mem_status [7:0],
    
    input wire [127:0] mem_rdata,
    
    input wire pc_err,
input wire [8:0] m_live ,
input wire [8:0] m_sent ,
input wire [8:0] m_done ,
input wire [8:0] m_pc ,
input wire [17:0] m_addr [0:8],
input wire [1:0] m_src [0:8],
input wire [1:0] m_err [0:8],
input wire [7:0] m_id [0:8],
input wire [4:0] m_port [0:8],
input wire [3:0] m_age [0:8],
input wire [127:0] m_data [0:8],
input wire [1:0] m_rr ,
input wire  m_attempt ,
input wire [3:0] m_attempt_e ,
input wire [3:0] m_due ,
input wire [3:0] m_due_e [0:3],
input wire  retry_selected ,
input wire  refill_selected ,
input wire  nonhead_refill_selected ,
input wire [11:0] last_retry_addr ,
input wire [11:0] last_refill_addr ,
input wire [7:0] last_retry_req ,
input wire [7:0] last_refill_req ,
input wire [2:0] blocked_streak ,
input wire [3:0] issue_streak ,
input wire [4:0] h_occ [0:2],
input wire  h_prev_a ,
input wire  h_prev_i ,
input wire  h_prev_r ,
input wire  h_prev_m ,
input wire  h_prev_valid ,
input wire  h_prev_pc ,
input wire [1:0] h_prev_src ,
input wire [1:0] h_prev_rsrc ,
input wire [1:0] h_prev_rr ,
input wire [2:0] h_prev_ready ,
input wire [2:0] h_prev_rready ,
input wire [2:0] h_prev_eligible ,
input wire [7:0] h_prev_req ,
input wire [7:0] h_prev_id ,
input wire [11:0] h_prev_arb ,
input wire [17:0] h_prev_addr ,
input wire [4:0] h_prev_port ,
input wire [127:0] h_prev_mem ,
input wire [3:0] h_prev_n ,
input wire [3:0] h_prev_p ,
input wire [3:0] h_prev_occ [0:2],
input wire [15:0] h_prev_status ,
input wire [5:0] h_i_history ,
input wire [5:0] h_a_history ,
input wire [5:0] h_m_history ,
input wire [6:0] h_single_start ,
input wire [5:0] h_src_history ,
input wire [2:0] h_rsrc_history ,
input wire [2:0] h_pc_history ,
input wire [2:0] h_ar_sources ,
input wire [5:0] h_total_a ,
input wire [5:0] h_total_r ,
input wire [3:0] h_same_ar_run ,
input wire [3:0] h_ar_run ,
input wire [3:0] h_r_run ,
input wire [3:0] h_ar_r_run ,
input wire [3:0] h_reject_run ,
input wire [3:0] h_quiet_run ,
input wire [3:0] h_empty_run ,
input wire [3:0] h_notready_run [0:2],
input wire  h_ever_full ,
input wire  h_was_drained ,
input wire [3:0] h_done_wait [0:8],
input wire [8:0] h_retired_bad ,
input wire [8:0] h_clean_reuse ,
input wire  h_failed_none ,
input wire  h_failed_other ,
input wire  h_blocked_prev ,
input wire  h_selected_prev ,
input wire  h_accepted_empty ,
input wire [7:0] h_selected_req ,
input wire [11:0] h_selected_addr ,
input wire [3:0] h_prev_due_slot ,
input wire [8:0] h_failed_once ,
input wire [8:0] h_failed_before_success ,
input wire [1:0] h_rr012_phase ,
input wire [1:0] h_error_sandwich_phase ,
input wire  h_rr_gap_seen ,
input wire  h_seen_reject ,
input wire  h_seen_partial_ready ,
input wire [17:0] h_prev_raddr_full ,
output wire [9999:0] result
);
wire ar_fire; assign ar_fire=arvalid && src<3 && ((src<3)?arready[src]:1'b0);
wire issue_fire; assign issue_fire=|(req & ar_rd_gnt & rw_rd_gnt);
wire r_fire; assign r_fire=|(rvalid & rready);







    
                    
                    
                    
                      
             
               
               
                
              
               
            
                      
                       
               
                     
             
    wire mem_capture_due;           
    wire [3:0] mem_capture_slot;     
    assign mem_capture_due = m_due[3];
    assign mem_capture_slot = m_due_e[3];

    
    
    wire signed [31:0] used;                
    wire signed [31:0] waiting;             
    wire signed [31:0] occ [0:2];           
    wire signed [31:0] shared_cost;         
    wire signed [31:0] quota_cost;          
    wire signed [31:0] used_prefix [0:9];   
    wire signed [31:0] wait_prefix [0:9];   
    wire signed [31:0] shared_part [0:2];   
    wire signed [31:0] quota_part [0:2];    
    genvar mi;                              
    genvar mx;                              
    genvar mj;                              
    genvar mo;                              
    assign used_prefix[0] = 0;
    assign wait_prefix[0] = 0;
    generate for (mi=0; mi<9; mi=mi+1) begin : count_slots
        assign used_prefix[mi+1] = used_prefix[mi] + (m_live[mi] ? 32'sd1 : 32'sd0);
        assign wait_prefix[mi+1] = wait_prefix[mi] +
                                  ((m_live[mi] && !m_sent[mi]) ? 32'sd1 : 32'sd0);
    end endgenerate
    assign used = used_prefix[9];
    assign waiting = wait_prefix[9];
    generate for (mx=0; mx<3; mx=mx+1) begin : count_sources
        wire signed [31:0] occ_prefix [0:9]; 
        assign occ_prefix[0] = 0;
        for (mi=0; mi<9; mi=mi+1) begin : slots
            assign occ_prefix[mi+1] = occ_prefix[mi] +
                ((m_live[mi] && m_src[mi]==mx) ? 32'sd1 : 32'sd0);
        end
        assign occ[mx] = occ_prefix[9];
        assign shared_part[mx] = occ[mx]>0 ? occ[mx]-1 : 0;
        assign quota_part[mx] = occ[mx]>0 ? occ[mx] : 1;
    end endgenerate
    assign shared_cost = shared_part[0]+shared_part[1]+shared_part[2];
    assign quota_cost = quota_part[0]+quota_part[1]+quota_part[2];

    
    
    wire [3:0] head [0:2];                  
    wire [2:0] head_valid;                  
    wire [2:0] eligible;                    
    generate for (mx=0; mx<3; mx=mx+1) begin : source_heads
        wire [3:0] head_age_prefix [0:9];  
        wire [3:0] head_slot_prefix [0:9]; 
        wire head_found_prefix [0:9];     
        wire head_take [0:8];             
        assign head_age_prefix[0] = 4'd9;
        assign head_slot_prefix[0] = 4'd0;
        assign head_found_prefix[0] = 1'b0;
        for (mi=0; mi<9; mi=mi+1) begin : slots
            assign head_take[mi] = m_live[mi] && m_src[mi]==mx && m_age[mi]<head_age_prefix[mi];
            assign head_age_prefix[mi+1] = head_take[mi] ? m_age[mi] : head_age_prefix[mi];
            assign head_slot_prefix[mi+1] = head_take[mi] ? 4'(mi) : head_slot_prefix[mi];
            assign head_found_prefix[mi+1] = head_found_prefix[mi] || head_take[mi];
        end
        assign head[mx] = head_slot_prefix[9];
        assign head_valid[mx] = head_found_prefix[9];
        assign eligible[mx] = head_valid[mx] && m_done[head[mx]] && rready[mx];
    end endgenerate

    
    
    wire [2:0] expected_rvalid;             
    wire [1:0] winner;                      
    wire [3:0] rsp_e;                       
    wire model_retire;                      
    wire signed [31:0] rr_scan [0:2];       
    wire [2:0] rr_valid_prefix [0:3];       
    wire [1:0] rr_winner_prefix [0:3];      
    wire [3:0] rr_slot_prefix [0:3];        
    wire rr_take [0:2];                     
    assign rr_valid_prefix[0] = 0;
    assign rr_winner_prefix[0] = 0;
    assign rr_slot_prefix[0] = 0;
    generate for (mo=0; mo<3; mo=mo+1) begin : response_rr
        assign rr_scan[mo] = (m_rr+mo>=3) ? m_rr+mo-3 : m_rr+mo;
        assign rr_take[mo] = rr_valid_prefix[mo]==0 && eligible[rr_scan[mo]];
        assign rr_valid_prefix[mo+1] = rr_take[mo] ? (3'b001 << rr_scan[mo]) : rr_valid_prefix[mo];
        assign rr_winner_prefix[mo+1] = rr_take[mo] ? rr_scan[mo][1:0] : rr_winner_prefix[mo];
        assign rr_slot_prefix[mo+1] = rr_take[mo] ? head[rr_scan[mo]] : rr_slot_prefix[mo];
    end endgenerate
    assign expected_rvalid = rst_n ? rr_valid_prefix[3] : 3'b000;
    assign winner = rr_winner_prefix[3];
    assign rsp_e = rr_slot_prefix[3];
    assign model_retire = |expected_rvalid;

    
    
    wire signed [31:0] after_occ [0:2];      
    wire signed [31:0] used_after;           
    wire signed [31:0] shared_after;         
    wire signed [31:0] after_shared_part [0:2]; 
    wire [2:0] expected_ready;               
    generate for (mx=0; mx<3; mx=mx+1) begin : admission
        assign after_occ[mx] = occ[mx] - ((model_retire && winner==mx) ? 1 : 0);
        assign after_shared_part[mx] = after_occ[mx]>0 ? after_occ[mx]-1 : 0;
        assign expected_ready[mx] = rst_n && used_after<9 &&
                                    (after_occ[mx]==0 || shared_after<6);
    end endgenerate
    assign used_after = after_occ[0]+after_occ[1]+after_occ[2];
    assign shared_after = after_shared_part[0]+after_shared_part[1]+after_shared_part[2];

    
    
    wire [3:0] alloc_e;                      
    wire free_found;                         
    wire alloc_free [0:8];                   
    wire alloc_found_prefix [0:9];          
    wire [3:0] alloc_slot_prefix [0:9];      
    assign alloc_found_prefix[0] = 0;
    assign alloc_slot_prefix[0] = 0;
    generate for (mi=0; mi<9; mi=mi+1) begin : allocation
        assign alloc_free[mi] = !m_live[mi] || (model_retire && rsp_e==mi);
        assign alloc_found_prefix[mi+1] = alloc_found_prefix[mi] || alloc_free[mi];
        assign alloc_slot_prefix[mi+1] = (!alloc_found_prefix[mi] && alloc_free[mi]) ?
                                         4'(mi) : alloc_slot_prefix[mi];
    end endgenerate
    assign alloc_e = alloc_slot_prefix[9];
    assign free_found = alloc_found_prefix[9];

    
    
    
    wire [8:0] pending;                      
    wire [8:0] pool;                         
    wire [8:0] window;                       
    wire [8:0] idle;                         
    wire [8:0] candidate;                    
    wire signed [31:0] ranks [0:8];          
    assign pending = m_live & ~m_sent;
    generate for (mi=0; mi<9; mi=mi+1) begin : issue_window
        wire signed [31:0] rank_prefix [0:9]; 
        assign pool[mi] = pending[mi] && !(issue_fire && m_attempt_e==mi);
        assign rank_prefix[0] = 0;
        for (mj=0; mj<9; mj=mj+1) begin : compare_age
            assign rank_prefix[mj+1] = rank_prefix[mj] +
                ((pool[mj] && m_age[mj]<m_age[mi]) ? 32'sd1 : 32'sd0);
        end
        assign ranks[mi] = rank_prefix[9];
        assign window[mi] = pool[mi] && ranks[mi]<5;
        assign idle[mi] = !rd_mem_status[m_addr[mi][5:3]][m_addr[mi][6]];
        assign candidate[mi] = window[mi] && idle[mi];
    end endgenerate

    
    
    wire [8:0] selected;                    
    wire [3:0] select_e;                    
    wire select_valid;                      
    wire [3:0] select_age_prefix [0:9];     
    wire [3:0] select_slot_prefix [0:9];    
    wire select_take [0:8];                 
    assign select_age_prefix[0] = 4'd9;
    assign select_slot_prefix[0] = 0;
    generate for (mi=0; mi<9; mi=mi+1) begin : issue_oldest
        assign select_take[mi] = candidate[mi] && m_age[mi]<select_age_prefix[mi];
        assign select_age_prefix[mi+1] = select_take[mi] ? m_age[mi] : select_age_prefix[mi];
        assign select_slot_prefix[mi+1] = select_take[mi] ? 4'(mi) : select_slot_prefix[mi];
    end endgenerate
    assign select_e = select_slot_prefix[9];
    assign selected = (select_age_prefix[9]<9) ? (9'b1 << select_e) : 9'd0;
    assign select_valid = |selected;

    
    integer e; 
    integer k; 
    

    
    
    
    
    wire [7:0] expected_req;
    assign expected_req = (rst_n && m_attempt)?(8'b1<<m_addr[m_attempt_e][5:3]):8'd0;
    
    wire [11:0] expected_addr;
    assign expected_addr = (rst_n && m_attempt)?m_addr[m_attempt_e][17:6]:12'd0;
    
    
    wire [1:0] expected_resp;
    assign expected_resp = (m_err[rsp_e]==2'b11)?2'b11:(m_pc[rsp_e]?2'b01:2'b00);


    
                     
                    
             
              
             
                
               
                
                  
    wire signed [31:0] selected_old_rank; 
    wire signed [31:0] old_rank_prefix [0:9]; 
    genvar mc;                          
    
    assign old_rank_prefix[0] = 0;
    generate for (mc=0; mc<9; mc=mc+1) begin : previous_window_rank
        assign old_rank_prefix[mc+1] = old_rank_prefix[mc] +
            ((pending[mc] && m_age[mc]<m_age[select_e]) ? 32'sd1 : 32'sd0);
    end endgenerate
    assign selected_old_rank = old_rank_prefix[9];
    
    
    
    wire blocked_six;
    assign blocked_six = waiting>=6 && (window & idle)==0 && (pool & ~window & idle)!=0 && !m_attempt;
    





    
    
     
    wire signed [31:0] h_total;             
    wire signed [31:0] h_budget;            
    wire signed [31:0] h_after_total;       
    wire signed [31:0] h_shared_after;      
    wire signed [31:0] h_after [0:2];       
    wire signed [31:0] h_quota_part [0:2];  
    wire signed [31:0] h_shared_part [0:2]; 
    wire [2:0] h_ready;                     
    genvar hi;                              
    
    assign h_total = {27'd0,h_occ[0]}+{27'd0,h_occ[1]}+{27'd0,h_occ[2]};
    generate for (hi=0; hi<3; hi=hi+1) begin : history_admission
        assign h_quota_part[hi] = h_occ[hi]==0 ? 1 : {27'd0,h_occ[hi]};
        assign h_after[hi] = h_occ[hi] - ((rvalid[hi] && rready[hi]) ? 1 : 0);
        assign h_shared_part[hi] = h_after[hi]>1 ? h_after[hi]-1 : 0;
        assign h_ready[hi] = h_after_total<9 && (h_after[hi]==0 || h_shared_after<6);
    end endgenerate
    assign h_budget = h_quota_part[0]+h_quota_part[1]+h_quota_part[2];
    assign h_after_total = h_after[0]+h_after[1]+h_after[2];
    assign h_shared_after = h_shared_part[0]+h_shared_part[1]+h_shared_part[2];
    integer hx; 
    

    
    
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    wire [15:0] h_status; 
    assign h_status = {rd_mem_status[7],rd_mem_status[6],rd_mem_status[5],rd_mem_status[4],
                           rd_mem_status[3],rd_mem_status[2],rd_mem_status[1],rd_mem_status[0]};
    
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    integer ht; 
    

    
    wire [8:0] h_rank_idle;        
    wire [8:0] h_rank_valid;       
    wire h_other_done;            
    wire h_hole_reused;           
    wire h_duplicate_id;          
    wire [8:0] h_other_done_mask;  
    wire [8:0] h_hole_mask;        
    wire [8:0] h_duplicate_mask;   
    genvar hr;                     
    genvar hj;                     
    
    generate for (hr=0; hr<9; hr=hr+1) begin : history_rank_map
        wire h_rank_idle_prefix [0:9];  
        wire h_rank_valid_prefix [0:9]; 
        assign h_rank_idle_prefix[0] = 0;
        assign h_rank_valid_prefix[0] = 0;
        for (hj=0; hj<9; hj=hj+1) begin : slots
            assign h_rank_idle_prefix[hj+1] = (pool[hj] && ranks[hj]==hr) ?
                                                  idle[hj] : h_rank_idle_prefix[hj];
            assign h_rank_valid_prefix[hj+1] = h_rank_valid_prefix[hj] ||
                                                   (pool[hj] && ranks[hj]==hr);
        end
        assign h_rank_idle[hr] = h_rank_idle_prefix[9];
        assign h_rank_valid[hr] = h_rank_valid_prefix[9];
        assign h_other_done_mask[hr] = m_live[hr] && m_done[hr] &&
                                      head_valid[m_src[hr]] && hr!=head[m_src[hr]];
        
        if (hr==0) begin : first_slot
            assign h_hole_mask[hr] = 1'b0;
        end else begin : later_slot
            assign h_hole_mask[hr] = ar_fire && m_live[hr] && hr>alloc_e;
        end
        assign h_duplicate_mask[hr] = ar_fire && m_live[hr] && m_id[hr]==arid;
    end endgenerate
    assign h_other_done = |h_other_done_mask;
    assign h_hole_reused = |h_hole_mask;
    assign h_duplicate_id = |h_duplicate_mask;
    
     
     
     
    integer he; 
    
    wire h_response_matches; 
    assign h_response_matches = r_fire && rvalid==expected_rvalid &&
        {raddr,rid,r_port_id,rdata,rresp}=={m_addr[rsp_e][2:0],m_id[rsp_e],m_port[rsp_e],m_data[rsp_e],expected_resp};

    
     
     
     
     
     
     
     
    



     
     
     
     
     
     
     
     
     
    wire h_hotspot;                        
    wire signed [31:0] h_same_bank_count;   
    wire signed [31:0] h_bank_prefix [0:9]; 
    genvar hs;                             
    
    assign h_bank_prefix[0] = 0;
    generate for (hs=0; hs<9; hs=hs+1) begin : history_bank_count
        assign h_bank_prefix[hs+1] = h_bank_prefix[hs] +
            ((pending[hs] && m_addr[hs][5:3]==m_addr[m_attempt_e][5:3]) ? 32'sd1 : 32'sd0);
    end endgenerate
    assign h_same_bank_count = h_bank_prefix[9];
    assign h_hotspot = h_same_bank_count>=3;
    integer hf; 
    

assign result={used,waiting,shared_cost,quota_cost,used_after,shared_after,head_valid,eligible,expected_rvalid,winner,rsp_e,model_retire,expected_ready,alloc_e,free_found,pending,pool,window,idle,candidate,selected,select_e,select_valid,mem_capture_due,mem_capture_slot,expected_req,expected_addr,expected_resp,selected_old_rank,blocked_six,h_total,h_budget,h_after_total,h_shared_after,h_ready,h_status,h_rank_idle,h_rank_valid,h_other_done,h_hole_reused,h_duplicate_id,h_response_matches,h_same_bank_count,h_hotspot,occ[0],occ[1],occ[2],after_occ[0],after_occ[1],after_occ[2],head[0],head[1],head[2],ranks[0],ranks[1],ranks[2],ranks[3],ranks[4],ranks[5],ranks[6],ranks[7],ranks[8],h_after[0],h_after[1],h_after[2]};
endmodule

module assign_model_miter(
input wire clk,
    
    input wire rst_n,
    
    
    input wire arvalid,
    
    input wire [2:0] arready,
    
    input wire [17:0] araddr,
    
    input wire [1:0] src,
    
    input wire [7:0] arid,
    
    input wire [4:0] ar_port_id,
    
    input wire [1:0] arresp,
    
    
    input wire [2:0] rvalid,
    
    input wire [2:0] rready,
    
    input wire [127:0] rdata,
    
    input wire [7:0] rid,
    
    input wire [4:0] r_port_id,
    
    input wire [2:0] raddr,
    
    input wire [1:0] rresp,
    
    
    input wire [7:0] req,
    
    input wire [11:0] arb_addr,
    
    input wire [3:0] pending_cnt,
    
    input wire [7:0] ar_rd_gnt,
    
    input wire [7:0] rw_rd_gnt,
    
    
    input wire [1:0] rd_mem_status [7:0],
    
    input wire [127:0] mem_rdata,
    
    input wire pc_err,
input wire [8:0] m_live ,
input wire [8:0] m_sent ,
input wire [8:0] m_done ,
input wire [8:0] m_pc ,
input wire [17:0] m_addr [0:8],
input wire [1:0] m_src [0:8],
input wire [1:0] m_err [0:8],
input wire [7:0] m_id [0:8],
input wire [4:0] m_port [0:8],
input wire [3:0] m_age [0:8],
input wire [127:0] m_data [0:8],
input wire [1:0] m_rr ,
input wire  m_attempt ,
input wire [3:0] m_attempt_e ,
input wire [3:0] m_due ,
input wire [3:0] m_due_e [0:3],
input wire  retry_selected ,
input wire  refill_selected ,
input wire  nonhead_refill_selected ,
input wire [11:0] last_retry_addr ,
input wire [11:0] last_refill_addr ,
input wire [7:0] last_retry_req ,
input wire [7:0] last_refill_req ,
input wire [2:0] blocked_streak ,
input wire [3:0] issue_streak ,
input wire [4:0] h_occ [0:2],
input wire  h_prev_a ,
input wire  h_prev_i ,
input wire  h_prev_r ,
input wire  h_prev_m ,
input wire  h_prev_valid ,
input wire  h_prev_pc ,
input wire [1:0] h_prev_src ,
input wire [1:0] h_prev_rsrc ,
input wire [1:0] h_prev_rr ,
input wire [2:0] h_prev_ready ,
input wire [2:0] h_prev_rready ,
input wire [2:0] h_prev_eligible ,
input wire [7:0] h_prev_req ,
input wire [7:0] h_prev_id ,
input wire [11:0] h_prev_arb ,
input wire [17:0] h_prev_addr ,
input wire [4:0] h_prev_port ,
input wire [127:0] h_prev_mem ,
input wire [3:0] h_prev_n ,
input wire [3:0] h_prev_p ,
input wire [3:0] h_prev_occ [0:2],
input wire [15:0] h_prev_status ,
input wire [5:0] h_i_history ,
input wire [5:0] h_a_history ,
input wire [5:0] h_m_history ,
input wire [6:0] h_single_start ,
input wire [5:0] h_src_history ,
input wire [2:0] h_rsrc_history ,
input wire [2:0] h_pc_history ,
input wire [2:0] h_ar_sources ,
input wire [5:0] h_total_a ,
input wire [5:0] h_total_r ,
input wire [3:0] h_same_ar_run ,
input wire [3:0] h_ar_run ,
input wire [3:0] h_r_run ,
input wire [3:0] h_ar_r_run ,
input wire [3:0] h_reject_run ,
input wire [3:0] h_quiet_run ,
input wire [3:0] h_empty_run ,
input wire [3:0] h_notready_run [0:2],
input wire  h_ever_full ,
input wire  h_was_drained ,
input wire [3:0] h_done_wait [0:8],
input wire [8:0] h_retired_bad ,
input wire [8:0] h_clean_reuse ,
input wire  h_failed_none ,
input wire  h_failed_other ,
input wire  h_blocked_prev ,
input wire  h_selected_prev ,
input wire  h_accepted_empty ,
input wire [7:0] h_selected_req ,
input wire [11:0] h_selected_addr ,
input wire [3:0] h_prev_due_slot ,
input wire [8:0] h_failed_once ,
input wire [8:0] h_failed_before_success ,
input wire [1:0] h_rr012_phase ,
input wire [1:0] h_error_sandwich_phase ,
input wire  h_rr_gap_seen ,
input wire  h_seen_reject ,
input wire  h_seen_partial_ready ,
input wire [17:0] h_prev_raddr_full ,
output wire mismatch,
output wire legal_index_state
);
wire [9999:0] a,b;
before_comb before_i(.clk(clk),.rst_n(rst_n),.arvalid(arvalid),.arready(arready),.araddr(araddr),.src(src),.arid(arid),.ar_port_id(ar_port_id),.arresp(arresp),.rvalid(rvalid),.rready(rready),.rdata(rdata),.rid(rid),.r_port_id(r_port_id),.raddr(raddr),.rresp(rresp),.req(req),.arb_addr(arb_addr),.pending_cnt(pending_cnt),.ar_rd_gnt(ar_rd_gnt),.rw_rd_gnt(rw_rd_gnt),.rd_mem_status(rd_mem_status),.mem_rdata(mem_rdata),.pc_err(pc_err),.m_live(m_live),.m_sent(m_sent),.m_done(m_done),.m_pc(m_pc),.m_addr(m_addr),.m_src(m_src),.m_err(m_err),.m_id(m_id),.m_port(m_port),.m_age(m_age),.m_data(m_data),.m_rr(m_rr),.m_attempt(m_attempt),.m_attempt_e(m_attempt_e),.m_due(m_due),.m_due_e(m_due_e),.retry_selected(retry_selected),.refill_selected(refill_selected),.nonhead_refill_selected(nonhead_refill_selected),.last_retry_addr(last_retry_addr),.last_refill_addr(last_refill_addr),.last_retry_req(last_retry_req),.last_refill_req(last_refill_req),.blocked_streak(blocked_streak),.issue_streak(issue_streak),.h_occ(h_occ),.h_prev_a(h_prev_a),.h_prev_i(h_prev_i),.h_prev_r(h_prev_r),.h_prev_m(h_prev_m),.h_prev_valid(h_prev_valid),.h_prev_pc(h_prev_pc),.h_prev_src(h_prev_src),.h_prev_rsrc(h_prev_rsrc),.h_prev_rr(h_prev_rr),.h_prev_ready(h_prev_ready),.h_prev_rready(h_prev_rready),.h_prev_eligible(h_prev_eligible),.h_prev_req(h_prev_req),.h_prev_id(h_prev_id),.h_prev_arb(h_prev_arb),.h_prev_addr(h_prev_addr),.h_prev_port(h_prev_port),.h_prev_mem(h_prev_mem),.h_prev_n(h_prev_n),.h_prev_p(h_prev_p),.h_prev_occ(h_prev_occ),.h_prev_status(h_prev_status),.h_i_history(h_i_history),.h_a_history(h_a_history),.h_m_history(h_m_history),.h_single_start(h_single_start),.h_src_history(h_src_history),.h_rsrc_history(h_rsrc_history),.h_pc_history(h_pc_history),.h_ar_sources(h_ar_sources),.h_total_a(h_total_a),.h_total_r(h_total_r),.h_same_ar_run(h_same_ar_run),.h_ar_run(h_ar_run),.h_r_run(h_r_run),.h_ar_r_run(h_ar_r_run),.h_reject_run(h_reject_run),.h_quiet_run(h_quiet_run),.h_empty_run(h_empty_run),.h_notready_run(h_notready_run),.h_ever_full(h_ever_full),.h_was_drained(h_was_drained),.h_done_wait(h_done_wait),.h_retired_bad(h_retired_bad),.h_clean_reuse(h_clean_reuse),.h_failed_none(h_failed_none),.h_failed_other(h_failed_other),.h_blocked_prev(h_blocked_prev),.h_selected_prev(h_selected_prev),.h_accepted_empty(h_accepted_empty),.h_selected_req(h_selected_req),.h_selected_addr(h_selected_addr),.h_prev_due_slot(h_prev_due_slot),.h_failed_once(h_failed_once),.h_failed_before_success(h_failed_before_success),.h_rr012_phase(h_rr012_phase),.h_error_sandwich_phase(h_error_sandwich_phase),.h_rr_gap_seen(h_rr_gap_seen),.h_seen_reject(h_seen_reject),.h_seen_partial_ready(h_seen_partial_ready),.h_prev_raddr_full(h_prev_raddr_full),.result(a));
after_comb after_i(.clk(clk),.rst_n(rst_n),.arvalid(arvalid),.arready(arready),.araddr(araddr),.src(src),.arid(arid),.ar_port_id(ar_port_id),.arresp(arresp),.rvalid(rvalid),.rready(rready),.rdata(rdata),.rid(rid),.r_port_id(r_port_id),.raddr(raddr),.rresp(rresp),.req(req),.arb_addr(arb_addr),.pending_cnt(pending_cnt),.ar_rd_gnt(ar_rd_gnt),.rw_rd_gnt(rw_rd_gnt),.rd_mem_status(rd_mem_status),.mem_rdata(mem_rdata),.pc_err(pc_err),.m_live(m_live),.m_sent(m_sent),.m_done(m_done),.m_pc(m_pc),.m_addr(m_addr),.m_src(m_src),.m_err(m_err),.m_id(m_id),.m_port(m_port),.m_age(m_age),.m_data(m_data),.m_rr(m_rr),.m_attempt(m_attempt),.m_attempt_e(m_attempt_e),.m_due(m_due),.m_due_e(m_due_e),.retry_selected(retry_selected),.refill_selected(refill_selected),.nonhead_refill_selected(nonhead_refill_selected),.last_retry_addr(last_retry_addr),.last_refill_addr(last_refill_addr),.last_retry_req(last_retry_req),.last_refill_req(last_refill_req),.blocked_streak(blocked_streak),.issue_streak(issue_streak),.h_occ(h_occ),.h_prev_a(h_prev_a),.h_prev_i(h_prev_i),.h_prev_r(h_prev_r),.h_prev_m(h_prev_m),.h_prev_valid(h_prev_valid),.h_prev_pc(h_prev_pc),.h_prev_src(h_prev_src),.h_prev_rsrc(h_prev_rsrc),.h_prev_rr(h_prev_rr),.h_prev_ready(h_prev_ready),.h_prev_rready(h_prev_rready),.h_prev_eligible(h_prev_eligible),.h_prev_req(h_prev_req),.h_prev_id(h_prev_id),.h_prev_arb(h_prev_arb),.h_prev_addr(h_prev_addr),.h_prev_port(h_prev_port),.h_prev_mem(h_prev_mem),.h_prev_n(h_prev_n),.h_prev_p(h_prev_p),.h_prev_occ(h_prev_occ),.h_prev_status(h_prev_status),.h_i_history(h_i_history),.h_a_history(h_a_history),.h_m_history(h_m_history),.h_single_start(h_single_start),.h_src_history(h_src_history),.h_rsrc_history(h_rsrc_history),.h_pc_history(h_pc_history),.h_ar_sources(h_ar_sources),.h_total_a(h_total_a),.h_total_r(h_total_r),.h_same_ar_run(h_same_ar_run),.h_ar_run(h_ar_run),.h_r_run(h_r_run),.h_ar_r_run(h_ar_r_run),.h_reject_run(h_reject_run),.h_quiet_run(h_quiet_run),.h_empty_run(h_empty_run),.h_notready_run(h_notready_run),.h_ever_full(h_ever_full),.h_was_drained(h_was_drained),.h_done_wait(h_done_wait),.h_retired_bad(h_retired_bad),.h_clean_reuse(h_clean_reuse),.h_failed_none(h_failed_none),.h_failed_other(h_failed_other),.h_blocked_prev(h_blocked_prev),.h_selected_prev(h_selected_prev),.h_accepted_empty(h_accepted_empty),.h_selected_req(h_selected_req),.h_selected_addr(h_selected_addr),.h_prev_due_slot(h_prev_due_slot),.h_failed_once(h_failed_once),.h_failed_before_success(h_failed_before_success),.h_rr012_phase(h_rr012_phase),.h_error_sandwich_phase(h_error_sandwich_phase),.h_rr_gap_seen(h_rr_gap_seen),.h_seen_reject(h_seen_reject),.h_seen_partial_ready(h_seen_partial_ready),.h_prev_raddr_full(h_prev_raddr_full),.result(b));
assign mismatch=|(a^b);
assign legal_index_state=(m_attempt_e<9) && (m_src[0]<3) && (m_src[1]<3) && (m_src[2]<3) && (m_src[3]<3) && (m_src[4]<3) && (m_src[5]<3) && (m_src[6]<3) && (m_src[7]<3) && (m_src[8]<3);
endmodule
