// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE

    reg [7:0] cv_hist=0;
    reg cv_rejected=0;
    reg [1:0] cv_rejected_src=0;
    reg [8:0] cv_failed=0,cv_aronly=0;
    reg [3:0] cv_rr_state=0,cv_mask_state=0;
    reg [3:0] cv_5a_state=0,cv_5a_a=0,cv_5a_b=0;
    reg [3:0] cv_base_rank[0:8];
    reg cv_sixth_idle,cv_five0_busy,cv_ooo,cv_younger_done;
    reg [3:0] cv_sixth;
    reg [2:0] cv_head_done;
    always @* begin
        cv_head_done=0;
        for(integer s=0;s<3;s=s+1)
            if(fm_head_valid[s])cv_head_done[s]=fm_done_q[fm_head[s]];
        cv_sixth_idle=0;cv_sixth=0;cv_five0_busy=1;cv_ooo=0;cv_younger_done=0;
        for(integer i=0;i<9;i=i+1)begin
            cv_base_rank[i]=0;
            for(integer j=0;j<9;j=j+1)begin
                if(fm_live_q[j] && !fm_issued_q[j] && fm_age_q[j]<fm_age_q[i])cv_base_rank[i]=cv_base_rank[i]+1'b1;
                if(fm_live_q[i] && fm_live_q[j] && fm_src_q[i]==fm_src_q[j] && fm_age_q[i]<fm_age_q[j] && !fm_done_q[i] && fm_done_q[j])cv_younger_done=1;
            end
            if(fm_live_q[i] && !fm_issued_q[i] && cv_base_rank[i]==5 && bank_idle_mask[i])begin cv_sixth_idle=1;cv_sixth=4'(i);end
            if(fm_live_q[i] && !fm_issued_q[i] && cv_base_rank[i]<5 && (fm_src_q[i]!=0 || bank_idle_mask[i]))cv_five0_busy=0;
            if(fm_success && fm_live_q[i] && !fm_issued_q[i] && fm_age_q[i]<fm_age_q[fm_attempt_id_q])cv_ooo=1;
        end
    end
    wire cv_blocked=fm_pending>=6 && !fm_attempt_q && !(|(fm_window & bank_idle_mask)) && cv_sixth_idle && !select_valid && req==0;
    always @(posedge clk)begin
        if(!rst_n)begin
            cv_hist<=0;cv_rejected<=0;cv_rejected_src<=0;cv_failed<=0;cv_aronly<=0;
            cv_rr_state<=0;cv_mask_state<=0;cv_5a_state<=0;cv_5a_a<=0;cv_5a_b<=0;
        end else begin
            cv_hist<={cv_hist[6:0],1'b1};
            if(arvalid && src<3 && arready!=0 && !arready[src])begin cv_rejected<=1;cv_rejected_src<=src;end
            for(integer i=0;i<9;i=i+1)begin
                if(fm_accept && alloc_entry==i)begin cv_failed[i]<=0;cv_aronly[i]<=0;end
                else if(fm_attempt_q && fm_attempt_id_q==i && !fm_success)begin
                    cv_failed[i]<=1;
                    cv_aronly[i]<=(|(req & ar_rd_gnt)) && !(|(req & rw_rd_gnt));
                end
            end
            if(cv_5a_state==0 && fm_attempt_q && !fm_success && fm_select && fm_select_id!=fm_attempt_id_q)begin
                cv_5a_state<=1;cv_5a_a<=fm_attempt_id_q;cv_5a_b<=fm_select_id;
            end else if(cv_5a_state==1)begin
                if(fm_attempt_q && fm_attempt_id_q==cv_5a_b && fm_select && fm_select_id==cv_5a_a)cv_5a_state<=2;
                else cv_5a_state<=0;
            end else if(cv_5a_state==2)cv_5a_state<=0;
            case(cv_rr_state)
              0: if(fm_eligible==7 && rready==7 && fm_rr_q==0 && rvalid==1)cv_rr_state<=1;
              1: if(fm_eligible==7 && rready==7 && rvalid==2)cv_rr_state<=2;else cv_rr_state<=0;
              2: cv_rr_state<=0;
              default:cv_rr_state<=0;
            endcase
            case(cv_mask_state)
              0: if(rready==6 && (|rvalid))cv_mask_state<=1;
              1: if(rready==1 && rvalid==1)cv_mask_state<=2;else cv_mask_state<=0;
              2: if(rready==0 && rvalid==0 && cv_head_done[2])cv_mask_state<=3;else cv_mask_state<=0;
              3: cv_mask_state<=0;
              default:cv_mask_state<=0;
            endcase
        end
    end

    always @(posedge clk) if(rst_n) begin
        CK_CV_SIXTH_BLOCKED: cover(cv_hist[0] && cv_blocked && $past(cv_blocked) && rd_mem_status==$past(rd_mem_status));
        CK_CV_6B: cover(cv_hist[0] && $past(fm_success && fm_select && cv_base_rank[fm_select_id]==5) && fm_attempt_q && fm_attempt_id_q==$past(fm_select_id));
        CK_CV_FAIL_KEEPS_WINDOW: cover(fm_attempt_q && !fm_success && fm_pending>=6 && cv_sixth_idle && !fm_window[cv_sixth]);
        CK_CV_QUOTA_NO_ESCAPE: cover(cv_hist[0] && cv_blocked && cv_five0_busy && fm_src_q[cv_sixth]==1 && $past(fm_accept && src==1) && cv_sixth==$past(alloc_entry) && $past(fm_pending)==5 && $past(fm_occ[0])==5);
        CK_CV_OUT_OF_ORDER: cover(cv_ooo);
        CK_CV_CAP700: cover(fm_occ[0]==7 && fm_occ[1]==0 && fm_occ[2]==0 && !fm_retire && arready==6);
        CK_CV_CAP440: cover(fm_occ[0]==4 && fm_occ[1]==4 && fm_occ[2]==0 && !fm_retire && arready==4);
        CK_CV_CAP711: cover(fm_occ[0]==7 && fm_occ[1]==1 && fm_occ[2]==1 && !fm_retire && arready==0 && !arvalid);
        CK_CV_UNIQUE_REFILL: cover(fm_occ[0]==7 && fm_occ[1]==1 && fm_occ[2]==1 && fm_retire && fm_winner==1 && arready==2 && fm_accept && src==1);
        CK_CV_SHARED_REFILL: cover(fm_occ[0]==7 && fm_occ[1]==1 && fm_occ[2]==1 && fm_retire && fm_winner==0 && arready==7 && fm_accept && src!=0);
        CK_CV_SAME_SRC_NETZERO: cover(cv_hist[0] && $past(fm_occ[0])==7 && $past(fm_retire && fm_winner==0 && fm_accept && src==0) && fm_occ[0]==7 && fm_live_q[$past(alloc_entry)] && fm_id_q[$past(alloc_entry)]==$past(arid));
        CK_CV_YOUNGER_DONE: cover(cv_younger_done);
        CK_CV_CROSS_SRC_PROGRESS: cover(fm_head_valid[0] && !fm_done_q[fm_head[0]] && fm_retire && fm_winner==1);
        CK_CV_RR_ROTATE: cover(cv_rr_state==2 && fm_eligible==7 && rready==7 && rvalid==4);
        CK_CV_RR_MASKS: cover(cv_mask_state==3 && rready==4 && rvalid==4);
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
