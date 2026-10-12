// BEGIN CMDBUF NATIVE FORMAL MONITOR

`ifdef FORMAL

    always @(posedge clk) begin
        assert(req==((rst_n && issue_valid_q)?(8'b1<<issue_bank_q):8'b0));
        assert(arb_addr==((rst_n && issue_valid_q)?issue_addr_q:12'b0));
        assert(pending_cnt==pending_q);
        assert(retire_entry==rsp_entry);
        assert(issue_entry==issue_entry_q);
    end
`endif

`ifdef FORMAL

    integer fq_count[0:2];
    integer fq_after[0:2];
    integer fq_total,fq_cost,fq_after_total,fq_shared;
    reg [2:0] fq_ready;
    always @* begin
        fq_total=0;fq_cost=0;fq_after_total=0;fq_shared=0;fq_ready=0;
        for(integer x=0;x<3;x=x+1) begin
            fq_count[x]=0;
            for(integer e=0;e<9;e=e+1)
                if(valid_q[e]&&src_q[e]==x)fq_count[x]=fq_count[x]+1;
            fq_total=fq_total+fq_count[x];
            fq_cost=fq_cost+((fq_count[x]>0)?fq_count[x]:1);
            fq_after[x]=fq_count[x]-((rvalid[x]&&rready[x])?1:0);
            fq_after_total=fq_after_total+fq_after[x];
            if(fq_after[x]>1)fq_shared=fq_shared+fq_after[x]-1;
        end
        for(integer x=0;x<3;x=x+1)
            fq_ready[x]=rst_n && fq_after_total<9 &&
                        (fq_after[x]==0 || fq_shared<6);
    end
    always @(posedge clk) if(rst_n) begin
        assert(arready==fq_ready);
        assert(fq_cost<=9);
        assert(fq_total==$countones(valid_q));
        for(integer x=0;x<3;x=x+1) begin
            assert(occ_q[x]==fq_count[x]);
            assert(occ_q[x]<=7);
        end
        if(retire_fire)begin
            assert(valid_q[retire_entry]);
            assert(src_q[retire_entry]==winner);
        end
        if(alloc_fire)begin
            assert(alloc_entry<9);
            assert(!valid_q[alloc_entry] ||
                   (retire_fire && retire_entry==alloc_entry));
        end
        for(integer e=0;e<9;e=e+1)
            if(valid_q[e])assert(src_q[e]<3);
        cover(fq_count[0]==7 && fq_count[1]==0 && fq_count[2]==0);
        cover(fq_count[0]==4 && fq_count[1]==4 && fq_count[2]==0);
        cover(fq_count[0]==7 && fq_count[1]==1 && fq_count[2]==1 &&
              rvalid==3'b010 && arready==3'b010 && alloc_fire);
    end
`endif
// END CMDBUF NATIVE FORMAL MONITOR
