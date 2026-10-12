// BEGIN CMDBUF NATIVE FORMAL MONITOR

`ifdef FORMAL

    (* anyconst *) reg [3:0] f_i;
    (* anyconst *) reg [3:0] f_j;
    (* anyconst *) reg [3:0] f_k;
    always @* begin assume(f_i < 9); assume(f_j < 9); assume(f_k < 9); end
    reg f_past_valid = 0;
    always @(posedge clk) f_past_valid <= 1;
    integer f_src_count [0:2];
    integer f_after_count [0:2];
    integer f_shared, f_after_total, f_reserve_cost;
    reg [2:0] f_expected_ready;
    always @* begin
        f_shared=0; f_after_total=0; f_reserve_cost=0; f_expected_ready=0;
        for (integer x=0;x<3;x=x+1) begin
            f_src_count[x]=0;
            for(integer e=0;e<9;e=e+1)
                if(valid_q[e] && src_q[e]==x) f_src_count[x]=f_src_count[x]+1;
            f_after_count[x]=f_src_count[x]-((rvalid[x]&&rready[x])?1:0);
            f_after_total=f_after_total+f_after_count[x];
            if(f_after_count[x]>1) f_shared=f_shared+f_after_count[x]-1;
            f_reserve_cost=f_reserve_cost+((f_src_count[x]>0)?f_src_count[x]:1);
        end
        for(integer x=0;x<3;x=x+1)
            f_expected_ready[x]=rst_n && f_after_total<9 &&
                              ((f_after_count[x]==0)||(f_shared<6));
    end
    always @(posedge clk) if(rst_n) begin
        assert(pending_q == $countones(valid_q & ~issued_q));
        assert($countones(valid_q) <= 9);
        assert(f_reserve_cost <= 9);
        assert(arready == f_expected_ready);
        assert((issued_q & ~valid_q)==0);
        assert((done_q & ~(valid_q & issued_q))==0);
        assert(rr_ptr_q<3);
        for(integer x=0;x<3;x=x+1) begin
            assert(occ_q[x] == f_src_count[x]);
            assert(occ_q[x] <= 7);
            assert($onehot0(head_onehot[x]));
        end
        assert(!older_q[f_i][f_i]);
        if(valid_q[f_i]) assert(src_q[f_i]<3);
        if(valid_q[f_i] && valid_q[f_j] && f_i!=f_j)
            assert(older_q[f_i][f_j] != older_q[f_j][f_i]);
        if(valid_q[f_i] && valid_q[f_j] && valid_q[f_k] &&
           older_q[f_i][f_j] && older_q[f_j][f_k])
            assert(older_q[f_i][f_k]);
        if(!valid_q[f_i] || !valid_q[f_j]) assert(!older_q[f_i][f_j]);
        assert($onehot0(select_onehot));
        assert((candidate_mask & current_issue_mask)==0);
        assert($countones(window_mask)<=5);
        if(alloc_fire) begin
            assert(alloc_entry<9);
            assert(!valid_q[alloc_entry] ||
                   (retire_fire && retire_entry==alloc_entry));
        end
        if(issue_valid_q) begin
            assert(issue_entry_q<9);
            assert(valid_q[issue_entry_q] && !issued_q[issue_entry_q]);
            assert(issue_addr_q==addr_q[issue_entry_q][17:6]);
            assert(issue_bank_q==addr_q[issue_entry_q][5:3]);
        end
        if(capture_valid) begin
            assert(capture_entry<9);
            assert(valid_q[capture_entry] && issued_q[capture_entry] &&
                   !done_q[capture_entry]);
            assert(!(retire_fire && retire_entry==capture_entry));
        end
        if(retire_fire) begin
            assert(valid_q[retire_entry] && issued_q[retire_entry] && done_q[retire_entry]);
            assert(rid==id_q[retire_entry]);
            assert(r_port_id==port_q[retire_entry]);
            assert(raddr==addr_q[retire_entry][2:0]);
            assert(rresp==((arresp_q[retire_entry]==3)?2'b11:
                         (rsp_pc_err?2'b01:2'b00)));
        end
        if(f_past_valid && $past(rst_n)) begin
            if($past(alloc_fire) && $past(alloc_entry)==f_i) begin
                assert(valid_q[f_i] && !issued_q[f_i] && !done_q[f_i]);
                assert(addr_q[f_i]==$past(araddr));
                assert(src_q[f_i]==$past(src));
                assert(id_q[f_i]==$past(arid));
                assert(port_q[f_i]==$past(ar_port_id));
                assert(arresp_q[f_i]==$past(arresp));
            end else if($past(retire_fire) && $past(retire_entry)==f_i) begin
                assert(!valid_q[f_i] && !issued_q[f_i] && !done_q[f_i]);
            end else begin
                assert(valid_q[f_i]==$past(valid_q[f_i]));
                assert(issued_q[f_i]==($past(issued_q[f_i]) ||
                       ($past(issue_success) && $past(issue_entry)==f_i)));
                assert(done_q[f_i]==($past(done_q[f_i]) ||
                       ($past(capture_valid) && $past(capture_entry)==f_i)));
                if(valid_q[f_i]) begin
                    assert(addr_q[f_i]==$past(addr_q[f_i]));
                    assert(src_q[f_i]==$past(src_q[f_i]));
                    assert(id_q[f_i]==$past(id_q[f_i]));
                    assert(port_q[f_i]==$past(port_q[f_i]));
                    assert(arresp_q[f_i]==$past(arresp_q[f_i]));
                end
            end
            if(valid_q[f_i] && valid_q[f_j] &&
               $past(valid_q[f_i]) && $past(valid_q[f_j]) &&
               !($past(alloc_fire) &&
                 ($past(alloc_entry)==f_i || $past(alloc_entry)==f_j)))
                assert(older_q[f_i][f_j]==$past(older_q[f_i][f_j]));
            assert(issue_valid_q==$past(select_valid));
            if(issue_valid_q) assert(issue_entry_q==$past(select_entry));
        end
        cover(occ_q[0]==7 && occ_q[1]==0 && occ_q[2]==0 && arready==3'b110);
        cover(occ_q[0]==4 && occ_q[1]==4 && occ_q[2]==0 && arready==3'b100);
        cover($countones(valid_q)==9 && alloc_fire && retire_fire &&
              alloc_entry==retire_entry);
        cover(occ_q[0]==7 && occ_q[1]==1 && occ_q[2]==1 &&
              rvalid==3'b010 && arready==3'b010 && alloc_fire);
    end
`endif
// END CMDBUF NATIVE FORMAL MONITOR
