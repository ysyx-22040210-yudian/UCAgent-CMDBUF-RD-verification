// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
    // A mathematical supplier over arbitrary nine-slot state. None of these
    // symbols are assigned from DUT state. Preconditions guard the theorem;
    // they are not assumptions about the DUT and are not global capacity CKs.
    (* anyconst *) reg [8:0] mn_live;
    (* anyconst *) reg [17:0] mn_sources;
    (* anyconst *) reg mn_alloc,mn_retire;
    (* anyconst *) reg [3:0] mn_alloc_id,mn_retire_id;
    (* anyconst *) reg [1:0] mn_new_src;
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
    always @(posedge clk)MATH_SINGLE_SLOT_SOURCE_NET: assert(!mn_legal || mn_net);
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
