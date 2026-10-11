`default_nettype none
module cmdbuf_rd (
    input  logic clk,
    input  logic rst_n,
    input  logic arvalid,
    output logic [2:0] arready,
    input  logic [17:0] araddr,
    input  logic [1:0] src,
    input  logic [7:0] arid,
    input  logic [4:0] ar_port_id,
    input  logic [1:0] arresp,
    output logic [2:0] rvalid,
    input  logic [2:0] rready,
    output logic [127:0] rdata,
    output logic [7:0] rid,
    output logic [4:0] r_port_id,
    output logic [2:0] raddr,
    output logic [1:0] rresp,
    output logic [7:0] req,
    output logic [11:0] arb_addr,
    output logic [3:0] pending_cnt,
    input  logic [7:0] ar_rd_gnt,
    input  logic [1:0][7:0] rd_mem_status,
    input  logic [127:0] mem_rdata,
    input  logic pc_err,
    input  logic [7:0] rw_rd_gnt
);
    logic alloc_fire, retire_fire, issue_success, capture_valid;
    logic [3:0] alloc_entry, retire_entry, issue_entry, capture_entry, rsp_entry;
    logic [127:0] rsp_data;
    logic rsp_pc_err;

    cmdbuf_rd_cmd u_cmd (
        .clk, .rst_n, .arvalid, .arready, .araddr, .src, .arid,
        .ar_port_id, .arresp, .rvalid, .rready, .rid, .r_port_id,
        .raddr, .rresp, .req, .arb_addr, .pending_cnt, .ar_rd_gnt,
        .rd_mem_status, .rw_rd_gnt, .alloc_fire, .alloc_entry,
        .retire_fire, .retire_entry, .issue_success, .issue_entry,
        .capture_valid, .capture_entry, .rsp_entry, .rsp_pc_err
    );
    cmdbuf_rd_otb u_otb (
        .clk, .rst_n, .alloc_fire, .alloc_entry, .retire_fire,
        .retire_entry, .issue_success, .issue_entry, .capture_valid,
        .capture_entry, .mem_rdata, .pc_err, .rsp_entry, .rsp_data,
        .rsp_pc_err
// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
        ,.fc_obs_data,.fc_obs_pc,.fc_obs_reserved,.fc_obs_done,
        .fc_obs_ret_valid,.fc_obs_ret_entry
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
    );
    assign rdata = (|rvalid) ? rsp_data : 128'b0;
// BEGIN CMDBUF CLOSURE FORMAL MONITOR

`ifdef FORMAL

    // F_EXT: event consistency is asserted, never assumed.
    always @(posedge clk) if (rst_n) begin
        assert(alloc_fire == (arvalid && (src < 3) &&
                             ((src < 3) ? arready[src] : 1'b0)));
        assert(retire_fire == (|(rvalid & rready)));
        assert(issue_success == (|(req & ar_rd_gnt & rw_rd_gnt)));
        assert($onehot0(req));
        assert($onehot0(rvalid));
        assert((rvalid & ~rready) == 0);
        assert(rdata == ((|rvalid) ? rsp_data : 128'b0));
        if (alloc_fire) assert(alloc_entry < 9);
        if (retire_fire) assert(retire_entry < 9);
        if (issue_success) assert(issue_entry < 9);
        if (capture_valid) assert(capture_entry < 9);
    end
    reg [2:0] f_lifecycle = 0;
    reg [3:0] f_life_entry = 0;
    always @(posedge clk) begin
        if (!rst_n) begin f_lifecycle <= 0; f_life_entry <= 0; end
        else begin
            if (f_lifecycle == 0 && alloc_fire) begin
                f_life_entry <= alloc_entry; f_lifecycle <= 1;
            end
            if (f_lifecycle == 1 && issue_success && issue_entry == f_life_entry)
                f_lifecycle <= 2;
            if (f_lifecycle == 2 && capture_valid && capture_entry == f_life_entry)
                f_lifecycle <= 3;
            if (f_lifecycle == 3 && retire_fire && retire_entry == f_life_entry)
                f_lifecycle <= 4;
// auxiliary cover omitted in this cover-only partition:             cover(f_lifecycle == 4);
// auxiliary cover omitted in this cover-only partition:             cover(alloc_fire && issue_success && capture_valid && retire_fire);
        end
    end
`endif
`ifdef FORMAL_CLOSURE
    // Independent data origin oracle uses the TOP input and external handshake.
    // Observation ports are read-only induction witnesses, never assumptions.
    wire fd_accept = arvalid && src<3 && ((src<3)?arready[src]:1'b0);
    wire fd_success = |(req & ar_rd_gnt & rw_rd_gnt);
    wire fd_retire = |(rvalid & rready);
    reg [3:0] fd_history_q=0;
    reg [127:0] fd_data_q[0:8];
    reg [8:0] fd_pc_q;
    always @(posedge clk) begin
        if(!rst_n) begin
            fd_history_q<=0;
            fd_pc_q<=0;
            for(integer e=0;e<9;e=e+1)fd_data_q[e]<=0;
        end else begin
            fd_history_q<={fd_history_q[2:0],1'b1};
            for(integer e=0;e<9;e=e+1) begin
                if((fd_accept && alloc_entry==e) ||
                   (fd_retire && retire_entry==e)) begin
                    fd_data_q[e]<=0;
                    fd_pc_q[e]<=0;
                end else if(fd_history_q[3] && $past(fd_success,4) &&
                            $past(issue_entry,4)==e) begin
                    fd_data_q[e]<=mem_rdata;
                    fd_pc_q[e]<=pc_err;
                end
            end
        end
    end
    always @(posedge clk) if(rst_n) begin
        D_ORIGIN_ACCEPT: assert(alloc_fire==fd_accept);
        D_ORIGIN_SUCCESS: assert(issue_success==fd_success);
        D_ORIGIN_RETIRE: assert(retire_fire==fd_retire);
        if(fd_history_q[3]) begin
            D_ORIGIN_CAPTURE_TIME: assert(capture_valid==$past(fd_success,4));
            if(capture_valid)
                D_ORIGIN_CAPTURE_ID: assert(capture_entry==$past(issue_entry,4));
        end else D_ORIGIN_INITIAL_NO_CAPTURE: assert(!capture_valid);
        for(integer e=0;e<9;e=e+1) begin
            // Every stored bit must keep matching the TOP-source oracle,
            // including while no source is ready and other MEM data arrives.
            assert(fc_obs_data[e*128+:128]==fd_data_q[e]);
            assert(fc_obs_pc[e]==fd_pc_q[e]);
        end
        if(fd_retire) begin
            D_ORIGIN_R_SLOT: assert(rsp_entry<9 && rsp_entry==retire_entry);
            D_ORIGIN_R_DATA: assert(rdata==fd_data_q[rsp_entry]);
            D_ORIGIN_R_PC: assert(rsp_pc_err==fd_pc_q[rsp_entry]);
        end
    end
`endif

`ifdef FORMAL_CLOSURE
    wire [1151:0] fc_obs_data;
    wire [8:0] fc_obs_pc,fc_obs_reserved,fc_obs_done;
    wire [3:0] fc_obs_ret_valid;
    wire [15:0] fc_obs_ret_entry;
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
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
endmodule
`default_nettype wire
