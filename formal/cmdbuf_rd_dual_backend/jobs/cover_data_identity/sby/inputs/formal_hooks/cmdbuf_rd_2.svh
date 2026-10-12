// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE

    // Accepted transaction metadata and data are independently tracked by slot.
    reg [8:0] ct_live=0,ct_done=0,ct_issued=0,ct_no_ready=0,ct_reused=0;
    reg [1:0] ct_src[0:8],ct_resp[0:8];
    reg [7:0] ct_id[0:8];
    reg [17:0] ct_addr[0:8];
    reg [4:0] ct_port[0:8];
    (* anyconst *) reg [3:0] ct_a,ct_b;
    reg [3:0] ct_pair_state=0;
    reg [3:0] ct_types=0;
    reg [127:0] ct_first_data=0;
    reg ct_first_data_seen=0,ct_pair_ok=0;
    always @* begin assume(ct_a<9);assume(ct_b<9);assume(ct_a!=ct_b);end
    wire ct_a_r=fd_retire && retire_entry==ct_a;
    wire ct_b_r=fd_retire && retire_entry==ct_b;
    wire ct_pair_start=ct_pair_state==0 && fd_accept && alloc_entry==ct_b && ct_live[ct_a] && !(fd_retire && retire_entry==ct_a);
    wire ct_response_ok=fd_retire && rvalid==(3'b1<<ct_src[retire_entry]) && rid==ct_id[retire_entry] && r_port_id==ct_port[retire_entry] && raddr==ct_addr[retire_entry][2:0] && rdata==fd_data_q[retire_entry] && rresp==((ct_resp[retire_entry]==3)?2'd3:(fd_pc_q[retire_entry]?2'd1:2'd0));
    always @(posedge clk)begin
        if(!rst_n)begin
            ct_live<=0;ct_done<=0;ct_issued<=0;ct_no_ready<=0;ct_reused<=0;ct_pair_state<=0;ct_types<=0;ct_first_data<=0;ct_first_data_seen<=0;ct_pair_ok<=0;
            for(integer i=0;i<9;i=i+1)begin ct_src[i]<=0;ct_resp[i]<=0;ct_id[i]<=0;ct_addr[i]<=0;ct_port[i]<=0;end
        end else begin
            for(integer i=0;i<9;i=i+1)begin
                if(fd_accept && alloc_entry==i)begin
                    ct_live[i]<=1;ct_done[i]<=0;ct_issued[i]<=0;ct_no_ready[i]<=0;
                    ct_reused[i]<=fd_retire && retire_entry==i && (&ct_live);
                    ct_src[i]<=src;ct_resp[i]<=arresp;ct_id[i]<=arid;ct_addr[i]<=araddr;ct_port[i]<=ar_port_id;
                end else if(fd_retire && retire_entry==i)begin
                    ct_live[i]<=0;ct_done[i]<=0;ct_issued[i]<=0;ct_no_ready[i]<=0;ct_reused[i]<=0;
                    ct_src[i]<=0;ct_resp[i]<=0;ct_id[i]<=0;ct_addr[i]<=0;ct_port[i]<=0;
                end else begin
                    if(fd_success && issue_entry==i)ct_issued[i]<=1;
                    if(capture_valid && capture_entry==i)begin ct_done[i]<=1;ct_no_ready[i]<=rready==0;end
                end
            end
            if(ct_pair_start)begin
                ct_pair_state<=1;ct_first_data_seen<=0;ct_pair_ok<=1;
                ct_types[0]<=ct_src[ct_a]==src && ct_id[ct_a]==arid && (ct_addr[ct_a]!=araddr || ct_port[ct_a]!=ar_port_id);
                ct_types[1]<=ct_src[ct_a]==src && ct_id[ct_a]>arid;
                ct_types[2]<=ct_src[ct_a]!=src && ct_id[ct_a]==arid;
                ct_types[3]<=ct_src[ct_a]==src && !ct_done[ct_a];
            end else if(ct_pair_state==1)begin
                if(ct_a_r || ct_b_r)ct_pair_ok<=ct_pair_ok && ct_response_ok;
                if(ct_a_r)begin ct_first_data<=rdata;ct_first_data_seen<=1;ct_pair_state<=2;ct_types[3]<=0;end
                else if(ct_b_r)begin ct_first_data<=rdata;ct_first_data_seen<=1;ct_pair_state<=3;end
                else if(ct_types[3] && ct_done[ct_b] && !ct_done[ct_a])ct_pair_state<=4;
            end else if(ct_pair_state==4)begin
                if(ct_a_r || ct_b_r)ct_pair_ok<=ct_pair_ok && ct_response_ok;
                if(ct_a_r)begin ct_first_data<=rdata;ct_first_data_seen<=1;ct_pair_state<=5;end
                else if(ct_b_r)ct_pair_state<=0;
            end else if((ct_pair_state==2 || ct_pair_state==5) && ct_b_r)ct_pair_state<=0;
            else if(ct_pair_state==3 && ct_a_r)ct_pair_state<=0;
        end
    end

    always @(posedge clk) if(rst_n) begin
        CK_CV_ERR00: cover(fd_retire && ct_done[retire_entry] && ct_issued[retire_entry] && ct_resp[retire_entry]==0 && !fd_pc_q[retire_entry] && rresp==0 && ct_response_ok);
        CK_CV_ERR01: cover(fd_retire && ct_done[retire_entry] && ct_issued[retire_entry] && ct_resp[retire_entry]==0 && fd_pc_q[retire_entry] && rresp==1 && ct_response_ok);
        CK_CV_ERR10: cover(fd_retire && ct_done[retire_entry] && ct_issued[retire_entry] && ct_resp[retire_entry]==3 && !fd_pc_q[retire_entry] && rresp==3 && ct_response_ok);
        CK_CV_ERR11: cover(fd_retire && ct_done[retire_entry] && ct_issued[retire_entry] && ct_resp[retire_entry]==3 && fd_pc_q[retire_entry] && rresp==3 && ct_response_ok);
        CK_CV_ZERO_DATA: cover(fd_retire && ct_done[retire_entry] && ct_resp[retire_entry]==0 && fd_data_q[retire_entry]==0 && !fd_pc_q[retire_entry] && rdata==0 && rresp==0 && ct_response_ok);
        CK_CV_UPPER_DATA: cover(fd_retire && ct_done[retire_entry] && fd_data_q[retire_entry][127:64]!=0 && fd_data_q[retire_entry][127:64]!=fd_data_q[retire_entry][63:0] && rdata==fd_data_q[retire_entry] && ct_response_ok);
        CK_CV_DUPLICATE_ID: cover((ct_pair_state==2 || ct_pair_state==5) && ct_b_r && ct_types[0] && ct_first_data_seen && rdata!=ct_first_data && rdata==fd_data_q[retire_entry] && ct_response_ok && ct_pair_ok);
        CK_CV_NONMONOTONIC_ID: cover((ct_pair_state==2 || ct_pair_state==5) && ct_b_r && ct_types[1] && ct_first_data_seen && ct_response_ok && ct_pair_ok);
        CK_CV_CROSS_SRC_ID: cover(((ct_pair_state==2 && ct_b_r) || (ct_pair_state==3 && ct_a_r)) && ct_types[2] && ct_first_data_seen && ct_response_ok && ct_pair_ok);
        CK_CV_REORDER_TO_ORDER: cover(ct_pair_state==5 && ct_b_r && ct_types[3] && ct_first_data_seen && ct_response_ok && ct_pair_ok);
        CK_CV_FULL_SLOT_REUSE: cover(fd_retire && ct_reused[retire_entry] && ct_issued[retire_entry] && ct_done[retire_entry] && rdata==fd_data_q[retire_entry] && ct_response_ok);
        CK_CV_CAPTURE_NOREADY: cover(fd_retire && ct_no_ready[retire_entry] && ct_done[retire_entry] && rdata==fd_data_q[retire_entry] && mem_rdata!=fd_data_q[retire_entry] && ct_response_ok);
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
