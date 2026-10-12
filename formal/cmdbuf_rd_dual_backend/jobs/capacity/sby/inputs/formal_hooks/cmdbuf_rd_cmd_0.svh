// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
    // Reconstruct occupancy from physical live identities, independently of
    // the quota counters. No success/capture signal appears in this ledger.
    reg [3:0] qm_count[0:2];
    reg [5:0] qm_total,qm_cost,qm_used,qm_shared;
    reg [3:0] qm_after[0:2];
    reg [2:0] qm_ready;
    reg qm_counts_match,qm_cap7,qm_sources_valid,qm_empty_ready;
    always @* begin
        qm_total=0;qm_cost=0;qm_used=0;qm_shared=0;
        qm_counts_match=1;qm_cap7=1;qm_sources_valid=1;qm_empty_ready=1;
        for(integer e=0;e<9;e=e+1)
            if(valid_q[e] && src_q[e]>=3)qm_sources_valid=0;
        for(integer x=0;x<3;x=x+1)begin
            qm_count[x]=0;
            for(integer e=0;e<9;e=e+1)
                qm_count[x]=qm_count[x]+4'(valid_q[e] && src_q[e]==x);
            qm_counts_match=qm_counts_match && occ_q[x]==qm_count[x];
            qm_cap7=qm_cap7 && qm_count[x]<=7;
            qm_total=qm_total+{2'b0,qm_count[x]};
            qm_cost=qm_cost+((qm_count[x]==0)?6'd1:{2'b0,qm_count[x]});
            qm_after[x]=qm_count[x]-4'(rvalid[x] && rready[x]);
            qm_used=qm_used+{2'b0,qm_after[x]};
            qm_shared=qm_shared+((qm_after[x]>0)?({2'b0,qm_after[x]}-6'd1):6'd0);
        end
        for(integer x=0;x<3;x=x+1)begin
            qm_ready[x]=rst_n && qm_used<9 && (qm_after[x]==0 || qm_shared<6);
            qm_empty_ready=qm_empty_ready && (qm_after[x]!=0 || arready[x]);
        end
    end
    always @(posedge clk)if(rst_n)begin
        QM_OCC_ALL: assert(qm_counts_match);
        QM_BUDGET: assert(qm_cost<=9);
        QM_VALID_SOURCES: assert(qm_sources_valid);
        QM_MAX7_ALL: assert(qm_cap7);
        QM_TOTAL: assert(qm_total==$countones(valid_q));
        QM_READY: assert(arready==qm_ready);
        QM_EMPTY_READY_ALL: assert(qm_empty_ready);
        QM_PHYSICAL_FREE: assert((arready==0) || free_found);
        QM_ALLOC_FREE: assert(!alloc_fire || (alloc_entry<9 && (!valid_q[alloc_entry] || (retire_fire && retire_entry==alloc_entry))));
        QM_RETIRE_OWNER: assert(!retire_fire || (retire_entry<9 && winner<3 && valid_q[retire_entry] && src_q[retire_entry]==winner));
        QM_R_ROUTE: assert($onehot0(rvalid) && ((rvalid & ~rready)==0));
        QM_RR_RANGE: assert(rr_ptr_q<3);
        QM_USED_BOUND: assert(qm_used<=9);
        QM_SHARED_BOUND: assert(qm_shared<=6);
        QM_IMPL_COST: assert(quota_cost==qm_cost);
        QM_IMPL_USED: assert(used_after==qm_used);
        QM_IMPL_SHARED: assert(shared_after==qm_shared);
        QM_IMPL_FREE: assert(free_after==9-qm_used);
    end
`endif

`ifdef FORMAL_CLOSURE
    // Previously proved structure contracts; exact provider evidence is kept
    // in capacity_quota_math_r2_contracts.json. No occupancy/quota is assumed.
    reg qm_contract_past=0;
    always @(posedge clk)qm_contract_past<=1;
    always @(posedge clk)if(rst_n)begin
        C_SS_RVALID_PATH: assume($onehot0(rvalid) && ((rvalid & ~rready)==0));
        C_SS_RR_RANGE: assume(rr_ptr_q<3);
        C_SS_ALLOC_INDEX: assume(alloc_entry<9);
        C_SS_FREE_FOUND_EQ: assume(free_found==(|free_mask));
        if(free_found)C_SS_ALLOC_FROM_FREE: assume(!valid_q[alloc_entry] || (retire_fire && retire_entry==alloc_entry));
        if(retire_fire)begin
            C_SS_RETIRE_OWNER: assume(retire_entry<9 && winner<3 && valid_q[retire_entry] && done_q[retire_entry] && src_q[retire_entry]==winner);
            C_SS_RETIRE_ROUTE: assume(rvalid==(3'b1<<src_q[retire_entry]));
        end
        if(qm_contract_past && $past(rst_n))begin
            C_SS_OCC_NET_ALL: assume(
                occ_q[0]==$past(occ_q[0])+4'($past(alloc_fire && src==0))-4'($past(retire_fire && winner==0)) &&
                occ_q[1]==$past(occ_q[1])+4'($past(alloc_fire && src==1))-4'($past(retire_fire && winner==1)) &&
                occ_q[2]==$past(occ_q[2])+4'($past(alloc_fire && src==2))-4'($past(retire_fire && winner==2)));
        end
    end
`endif

`ifdef FORMAL_CLOSURE
    // Instance of the authenticated universal nine-slot mathematics theorem.
    // Inputs below are the actual DUT state/events. Its legal antecedent is
    // preserved, while actual DUT legality remains an assertion below.
    wire [8:0] mn_live=valid_q;
    reg [17:0] mn_sources;
    always @* for(integer i=0;i<9;i=i+1)mn_sources[i*2+:2]=src_q[i];
    wire mn_alloc=alloc_fire,mn_retire=retire_fire;
    wire [3:0] mn_alloc_id=alloc_entry,mn_retire_id=retire_entry;
    wire [1:0] mn_new_src=src;
    reg mn_legal,mn_net;
    reg [8:0] mn_next_live;
    reg [17:0] mn_next_sources;
    reg [3:0] mn_old[0:2],mn_next[0:2],mn_expected[0:2];
    always @*begin
        mn_legal=1;mn_net=1;
        mn_next_live=mn_live;mn_next_sources=mn_sources;
        if(mn_retire)begin
            if(mn_retire_id>=9)mn_legal=0;
            else begin
                if(!mn_live[mn_retire_id])mn_legal=0;
                mn_next_live[mn_retire_id]=0;
            end
        end
        if(mn_alloc)begin
            if(mn_alloc_id>=9 || mn_new_src>=3)mn_legal=0;
            else begin
                if(mn_live[mn_alloc_id] && !(mn_retire && mn_retire_id==mn_alloc_id))mn_legal=0;
                mn_next_live[mn_alloc_id]=1;
                mn_next_sources[mn_alloc_id*2+:2]=mn_new_src;
            end
        end
        for(integer x=0;x<3;x=x+1)begin
            mn_old[x]=0;mn_next[x]=0;mn_expected[x]=0;
            for(integer e=0;e<9;e=e+1)begin
                if(mn_live[e] && mn_sources[e*2+:2]==x)mn_old[x]=mn_old[x]+1'b1;
                if(mn_next_live[e] && mn_next_sources[e*2+:2]==x)mn_next[x]=mn_next[x]+1'b1;
                if(mn_live[e] && mn_sources[e*2+:2]>=3)mn_legal=0;
            end
            mn_expected[x]=mn_old[x];
            if(mn_retire && mn_retire_id<9 && mn_sources[mn_retire_id*2+:2]==x)
                mn_expected[x]=mn_expected[x]-1'b1;
            if(mn_alloc && mn_new_src==x)mn_expected[x]=mn_expected[x]+1'b1;
            if(mn_next[x]!=mn_expected[x])mn_net=0;
        end
    end
    always @(posedge clk)C_MATH_SINGLE_SLOT_SOURCE_NET: assume(!mn_legal || mn_net);
`endif

`ifdef FORMAL_CLOSURE
    wire [3:0] mq_c0=qm_count[0],mq_c1=qm_count[1],mq_c2=qm_count[2];
    wire [2:0] mq_ret=rvalid & rready;
    wire mq_alloc_valid=arvalid;
    wire [1:0] mq_alloc_src=src;
 reg [3:0] mq_c[0:2],mq_d[0:2],mq_n[0:2];
 reg [5:0] mq_cost,mq_used,mq_shared,mq_ncost,mq_dcost;
 reg [2:0] mq_ready;
 reg mq_domain,mq_ret_legal,mq_accept,mq_cap7,mq_empty_ready;
 always @*begin
   mq_c[0]=mq_c0;mq_c[1]=mq_c1;mq_c[2]=mq_c2;
   mq_cost=0;mq_used=0;mq_shared=0;mq_ncost=0;mq_dcost=0;
   mq_ret_legal=$onehot0(mq_ret);mq_domain=1;
   for(integer x=0;x<3;x=x+1)begin
     mq_cost=mq_cost+((mq_c[x]==0)?6'd1:{2'b0,mq_c[x]});
     mq_domain=mq_domain && mq_c[x]<=7;
     mq_ret_legal=mq_ret_legal && (!mq_ret[x] || mq_c[x]!=0);
     mq_d[x]=mq_c[x]-4'(mq_ret[x]);
     mq_used=mq_used+{2'b0,mq_d[x]};
     mq_shared=mq_shared+((mq_d[x]>0)?({2'b0,mq_d[x]}-6'd1):6'd0);
     mq_dcost=mq_dcost+((mq_d[x]==0)?6'd1:{2'b0,mq_d[x]});
   end
   mq_domain=mq_domain && mq_cost<=9 && mq_ret_legal;
   for(integer x=0;x<3;x=x+1)
     mq_ready[x]=(mq_used<9) && ((mq_d[x]==0)||(mq_shared<6));
   mq_accept=mq_alloc_valid && ((mq_alloc_src==0 && mq_ready[0])||(mq_alloc_src==1 && mq_ready[1])||(mq_alloc_src==2 && mq_ready[2]));
   mq_cap7=1;mq_empty_ready=1;
   for(integer x=0;x<3;x=x+1)begin
     mq_n[x]=mq_d[x]+4'(mq_accept && mq_alloc_src==x);
     mq_ncost=mq_ncost+((mq_n[x]==0)?6'd1:{2'b0,mq_n[x]});
     mq_cap7=mq_cap7 && mq_n[x]<=7;
     mq_empty_ready=mq_empty_ready && (mq_d[x]!=0 || mq_ready[x]);
   end
 end
 always @(posedge clk)begin
   C_QUOTA_AFTER_BUDGET: assume(!mq_domain || mq_dcost<=9);
   C_QUOTA_NEXT_BUDGET: assume(!mq_domain || mq_ncost<=9);
   C_QUOTA_NEXT_MAX7: assume(!mq_domain || mq_cap7);
   C_QUOTA_AFTER_TOTAL: assume(!mq_domain || mq_used<=9);
   C_QUOTA_AFTER_SHARED: assume(!mq_domain || mq_shared<=6);
   C_QUOTA_EMPTY_READY: assume(!mq_domain || mq_empty_ready);
 end
    // These remain assertions about the actual state/updates, not imported facts.
    always @(posedge clk)if(rst_n)begin
        QM_MATH_DOMAIN: assert(mq_domain);
        QM_MATH_LEGAL: assert(mn_legal);
        QM_MATH_ACCEPT: assert(mq_accept==alloc_fire);
        QM_STEP_REFCOUNT: assert(mn_next[0]==mq_n[0] && mn_next[1]==mq_n[1] && mn_next[2]==mq_n[2]);
        QM_CURRENT_REFCOUNT: assert(qm_count[0]==mn_old[0] && qm_count[1]==mn_old[1] && qm_count[2]==mn_old[2]);
        if(qm_contract_past && $past(rst_n))begin
            QM_COUNT_FOLLOWS_NEXT: assert(qm_count[0]==$past(mn_next[0]) && qm_count[1]==$past(mn_next[1]) && qm_count[2]==$past(mn_next[2]));
        end
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
