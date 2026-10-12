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
    always @* begin
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
                    if((|(req & ar_rd_gnt)) && !(|(req & rw_rd_gnt)))cv_aronly[i]<=1;
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
              1: if(rready==7 && rvalid==2)cv_rr_state<=2;else cv_rr_state<=0;
              2: cv_rr_state<=0;
              default:cv_rr_state<=0;
            endcase
            case(cv_mask_state)
              0: if(rready==6 && (|rvalid))cv_mask_state<=1;
              1: if(rready==1 && rvalid==1)cv_mask_state<=2;else cv_mask_state<=0;
              2: if(rready==0 && rvalid==0)cv_mask_state<=3;else cv_mask_state<=0;
              3: cv_mask_state<=0;
              default:cv_mask_state<=0;
            endcase
        end
    end

    always @(posedge clk) if(rst_n) begin
        CK_CV_H0_B0: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hfffe && $past(fm_addr_q[fm_select_id][6:3])==4'd0 && fm_success && req==8'h01 && arb_addr[0]==1'b0);
        CK_CV_H0_B1: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hfffd && $past(fm_addr_q[fm_select_id][6:3])==4'd1 && fm_success && req==8'h02 && arb_addr[0]==1'b0);
        CK_CV_H0_B2: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hfffb && $past(fm_addr_q[fm_select_id][6:3])==4'd2 && fm_success && req==8'h04 && arb_addr[0]==1'b0);
        CK_CV_H0_B3: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hfff7 && $past(fm_addr_q[fm_select_id][6:3])==4'd3 && fm_success && req==8'h08 && arb_addr[0]==1'b0);
        CK_CV_H0_B4: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hffef && $past(fm_addr_q[fm_select_id][6:3])==4'd4 && fm_success && req==8'h10 && arb_addr[0]==1'b0);
        CK_CV_H0_B5: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hffdf && $past(fm_addr_q[fm_select_id][6:3])==4'd5 && fm_success && req==8'h20 && arb_addr[0]==1'b0);
        CK_CV_H0_B6: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hffbf && $past(fm_addr_q[fm_select_id][6:3])==4'd6 && fm_success && req==8'h40 && arb_addr[0]==1'b0);
        CK_CV_H0_B7: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hff7f && $past(fm_addr_q[fm_select_id][6:3])==4'd7 && fm_success && req==8'h80 && arb_addr[0]==1'b0);
        CK_CV_H1_B0: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hfeff && $past(fm_addr_q[fm_select_id][6:3])==4'd8 && fm_success && req==8'h01 && arb_addr[0]==1'b1);
        CK_CV_H1_B1: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hfdff && $past(fm_addr_q[fm_select_id][6:3])==4'd9 && fm_success && req==8'h02 && arb_addr[0]==1'b1);
        CK_CV_H1_B2: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hfbff && $past(fm_addr_q[fm_select_id][6:3])==4'd10 && fm_success && req==8'h04 && arb_addr[0]==1'b1);
        CK_CV_H1_B3: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hf7ff && $past(fm_addr_q[fm_select_id][6:3])==4'd11 && fm_success && req==8'h08 && arb_addr[0]==1'b1);
        CK_CV_H1_B4: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hefff && $past(fm_addr_q[fm_select_id][6:3])==4'd12 && fm_success && req==8'h10 && arb_addr[0]==1'b1);
        CK_CV_H1_B5: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hdfff && $past(fm_addr_q[fm_select_id][6:3])==4'd13 && fm_success && req==8'h20 && arb_addr[0]==1'b1);
        CK_CV_H1_B6: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'hbfff && $past(fm_addr_q[fm_select_id][6:3])==4'd14 && fm_success && req==8'h40 && arb_addr[0]==1'b1);
        CK_CV_H1_B7: cover(cv_hist[0] && $past(fm_select) && $past(rd_mem_status)==16'h7fff && $past(fm_addr_q[fm_select_id][6:3])==4'd15 && fm_success && req==8'h80 && arb_addr[0]==1'b1);
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
