// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
    // Universal projection of the acceptance FIFO onto two physical identities.
    // This observer is two entries; the unmodified DUT remains nine entries.
    (* anyconst *) reg [3:0] ap_a,ap_b,ap_c;
    always @*begin assume(ap_a<9);assume(ap_b<9);assume(ap_c<9);end
    wire ap_accept=arvalid && src<3 && ((src<3)?arready[src]:1'b0);
    wire ap_retire=|(rvalid&rready);
    reg [1:0] ap_count,ap_ncount;
    reg [3:0] ap_fifo[0:1],ap_next[0:1];
    reg ap_live_a,ap_live_b,ap_shape;
    wire ap_ab=(ap_a!=ap_b && ap_count==2 && ap_fifo[0]==ap_b && ap_fifo[1]==ap_a);
    wire ap_ba=(ap_a!=ap_b && ap_count==2 && ap_fifo[0]==ap_a && ap_fifo[1]==ap_b);
    always @*begin
        ap_ncount=0;ap_next[0]=0;ap_next[1]=0;
        ap_live_a=0;ap_live_b=0;ap_shape=(ap_count<=2);
        for(integer p=0;p<2;p=p+1)begin
            if(p<ap_count)begin
                if(ap_fifo[p]==ap_a)ap_live_a=1;
                if(ap_fifo[p]==ap_b)ap_live_b=1;
                if(ap_fifo[p]!=ap_a && ap_fifo[p]!=ap_b)ap_shape=0;
                if(!((ap_retire && retire_entry==ap_fifo[p]) ||
                     (ap_accept && alloc_entry==ap_fifo[p])))begin
                    if(ap_ncount<2)ap_next[ap_ncount]=ap_fifo[p];
                    ap_ncount=ap_ncount+1'b1;
                end
            end
        end
        if(ap_count==2 && ap_fifo[0]==ap_fifo[1])ap_shape=0;
        // a==b still appends exactly once.
        if(ap_accept && (alloc_entry==ap_a || alloc_entry==ap_b))begin
            if(ap_ncount<2)ap_next[ap_ncount]=alloc_entry;
            ap_ncount=ap_ncount+1'b1;
        end
    end
    always @(posedge clk)begin
        if(!rst_n)begin ap_count<=0;ap_fifo[0]<=0;ap_fifo[1]<=0;end
        else begin ap_count<=ap_ncount;ap_fifo[0]<=ap_next[0];ap_fifo[1]<=ap_next[1];end
        if(rst_n)begin
            AP_FIFO_SHAPE: assert(ap_shape);
            AP_FIFO_NEXT_BOUNDED: assert(ap_ncount<=2);
            AP_LIVE_A: assert(valid_q[ap_a]==ap_live_a);
            AP_LIVE_B: assert(valid_q[ap_b]==ap_live_b);
            ANYCONST_FIFO_AGE: assert(older_q[ap_a][ap_b]==ap_ab);
            AP_REVERSE_AGE: assert(older_q[ap_b][ap_a]==ap_ba);
            AP_IRREFLEXIVE: assert(!older_q[ap_a][ap_a]);
            AP_INVALID_BITS_ZERO: assert((valid_q[ap_a] && valid_q[ap_b]) || !older_q[ap_a][ap_b]);
            if(valid_q[ap_a] && valid_q[ap_b] && ap_a!=ap_b)
                AP_TOTAL_ANTISYMMETRY: assert(older_q[ap_a][ap_b]!=older_q[ap_b][ap_a]);
            if(valid_q[ap_a] && valid_q[ap_b] && valid_q[ap_c] &&
                older_q[ap_a][ap_b] && older_q[ap_b][ap_c])
                AP_TRANSITIVITY: assert(older_q[ap_a][ap_c]);
            AP_EXTERNAL_EVENTS: assert(alloc_fire==ap_accept && retire_fire==ap_retire);
            AP_COVER_TWO: cover(ap_count==2);
            AP_COVER_REPLACE: cover(ap_count==2 && ap_accept && ap_retire && alloc_entry==retire_entry && alloc_entry==ap_a);
        end
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
