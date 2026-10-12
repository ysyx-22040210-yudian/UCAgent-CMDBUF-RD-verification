// BEGIN CMDBUF CLOSURE FORMAL MONITOR

`ifdef FORMAL

    reg [3:0] f_delay_history=0;
    always @(posedge clk)
        if(!rst_n) f_delay_history<=0;
        else f_delay_history<={f_delay_history[2:0],1'b1};
    always @(posedge clk) if(rst_n) begin
        if(f_delay_history[0]) begin
            assert(ret_valid_q[0]==$past(issue_success));
            if(ret_valid_q[0]) assert(ret_entry_q[0]==$past(issue_entry));
        end
        if(f_delay_history[1]) begin
            assert(ret_valid_q[1]==$past(issue_success,2));
            if(ret_valid_q[1]) assert(ret_entry_q[1]==$past(issue_entry,2));
        end
        if(f_delay_history[2]) begin
            assert(ret_valid_q[2]==$past(issue_success,3));
            if(ret_valid_q[2]) assert(ret_entry_q[2]==$past(issue_entry,3));
        end
        if(f_delay_history[3]) begin
            assert(capture_valid==$past(issue_success,4));
            if(capture_valid) assert(capture_entry==$past(issue_entry,4));
        end else assert(!capture_valid);
        cover(capture_valid);
    end
`endif

`ifdef FORMAL_CLOSURE
    for(genvar e=0;e<9;e=e+1) begin
        assign fc_obs_data[e*128+:128]=data_q[e];
    end
    for(genvar k=0;k<4;k=k+1) begin
        assign fc_obs_ret_entry[k*4+:4]=ret_entry_q[k];
    end
    assign fc_obs_pc=pc_err_q;
    assign fc_obs_reserved=reserved_q;
    assign fc_obs_done=done_q;
    assign fc_obs_ret_valid=ret_valid_q;
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
