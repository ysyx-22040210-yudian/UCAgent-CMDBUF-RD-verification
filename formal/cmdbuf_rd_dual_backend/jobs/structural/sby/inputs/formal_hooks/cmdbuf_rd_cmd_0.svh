// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
    reg ss_past=0;
    always @(posedge clk)ss_past<=1;
    always @(posedge clk)if(rst_n)begin
        SS_RVALID_PATH: assert($onehot0(rvalid) && ((rvalid & ~rready)==0));
        SS_RR_RANGE: assert(rr_ptr_q<3);
        SS_ALLOC_INDEX: assert(alloc_entry<9);
        SS_FREE_FOUND_EQ: assert(free_found==(|free_mask));
        if(free_found)SS_ALLOC_FROM_FREE: assert(!valid_q[alloc_entry] || (retire_fire && retire_entry==alloc_entry));
        if(retire_fire)begin
            SS_RETIRE_OWNER: assert(retire_entry<9 && winner<3 && valid_q[retire_entry] && done_q[retire_entry] && src_q[retire_entry]==winner);
            SS_RETIRE_ROUTE: assert(rvalid==(3'b1<<src_q[retire_entry]));
        end
        if(select_valid)SS_SELECT_PENDING: assert(select_entry<9 && candidate_mask[select_entry] &&
            valid_q[select_entry] && !issued_q[select_entry] && !current_issue_mask[select_entry]);
        if(ss_past && $past(rst_n))begin
            SS_OCC_NET_ALL: assert(
                occ_q[0]==$past(occ_q[0])+4'($past(alloc_fire && src==0))-4'($past(retire_fire && winner==0)) &&
                occ_q[1]==$past(occ_q[1])+4'($past(alloc_fire && src==1))-4'($past(retire_fire && winner==1)) &&
                occ_q[2]==$past(occ_q[2])+4'($past(alloc_fire && src==2))-4'($past(retire_fire && winner==2)));
            SS_PENDING_NET: assert(pending_q==$past(pending_q)+4'($past(alloc_fire))-4'($past(issue_success)));
            SS_ATTEMPT_VALID_NEXT: assert(issue_valid_q==$past(select_valid));
        end
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
