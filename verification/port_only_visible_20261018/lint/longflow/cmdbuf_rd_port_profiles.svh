// Additional input contracts are opt-in and must be reported separately.
`ifdef TP_PERF
    reg [9:0] perf_cycles;
    reg [1:0] offer_src;
    always @(posedge clk) begin
        if(!rst_n) begin perf_cycles<=0; offer_src<=0; end
        else begin
            if(perf_cycles!=1023) perf_cycles<=perf_cycles+1'b1;
            offer_src<=(offer_src==2)?2'd0:offer_src+2'd1;
        end
    end
    /* [NO_REF_MODEL_PORTS] */`TP_ASSUME(PERF_BANKS, !active || rd_mem_status==0) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSUME(PERF_READY, !active || rready==3'b111) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSUME(PERF_GRANT_AR, !active || ar_rd_gnt==8'hff) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSUME(PERF_GRANT_RW, !active || rw_rd_gnt==8'hff) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSUME(PERF_OFFER, !active || arvalid==(|arready)) // [NO_REF_MODEL_PORTS]
`ifdef TP_PERF_SINGLE
    /* [NO_REF_MODEL_PORTS] */`TP_ASSUME(PERF_SOURCE, !active || src==`TP_PERF_SINGLE) // [NO_REF_MODEL_PORTS]
`else
    /* [NO_REF_MODEL_HISTORY] */`TP_ASSUME(PERF_SOURCE, !active || src==offer_src) // [NO_REF_MODEL_HISTORY]
`endif
    // The DUT's acceptance, request, capture and response remain assertions.
    /* [NO_REF_MODEL_HISTORY] */`TP_ASSERT(A_PERF_STEADY, !active || perf_cycles<8 || aimr==4'b1111) // [NO_REF_MODEL_HISTORY]
    /* [NO_REF_MODEL_HISTORY] */`TP_COVER(C_PERF_512, active && retired_total>=512 && fullrate_streak>=8) // [NO_REF_MODEL_HISTORY]
`endif

`ifdef TP_DRAIN
    // An arbitrary marker permits any legal prefix, including full/backlogged
    // states. Do not assume the DUT is nonempty or already completes anything.
    (* anyseq *) reg drain_start;
    reg draining;
    reg [6:0] drain_cycles;
    always @(posedge clk) begin
        if(!rst_n) begin draining<=0; drain_cycles<=0; end
        else begin
            if(drain_start) draining<=1;
            if(draining && drain_cycles!=127) drain_cycles<=drain_cycles+1'b1;
        end
    end
    /* [NO_REF_MODEL_ENV] */`TP_ASSUME(DRAIN_NO_NEW_AR, !active || !draining || !arvalid) // [NO_REF_MODEL_ENV]
    /* [NO_REF_MODEL_ENV] */`TP_ASSUME(DRAIN_BANKS, !active || !draining || rd_mem_status==0) // [NO_REF_MODEL_ENV]
    /* [NO_REF_MODEL_ENV] */`TP_ASSUME(DRAIN_READY, !active || !draining || rready==7) // [NO_REF_MODEL_ENV]
    /* [NO_REF_MODEL_ENV] */`TP_ASSUME(DRAIN_AR_GRANT, !active || !draining || ar_rd_gnt==255) // [NO_REF_MODEL_ENV]
    /* [NO_REF_MODEL_ENV] */`TP_ASSUME(DRAIN_RW_GRANT, !active || !draining || rw_rd_gnt==255) // [NO_REF_MODEL_ENV]
    // Conservative bound: <=2 cycles to first issue + <=9 issue slots +
    // 4-cycle return + <=9 response slots = <=24; allow 4 boundary cycles.
    // This is a property to verify, not an assumed progress fact.
    `TP_ASSERT(A_DRAIN_BOUND, !active || !draining || drain_cycles<28 || (used==0 && m_due==0 && !m_attempt)) // [REF_MODEL]
    `TP_COVER(C_DRAIN_RECOVER, active && draining && drain_cycles>=28 && accepted_total>=9 && used==0 && m_due==0) // [REF_MODEL]
`endif

`ifdef TP_IDLE_RESET
    reg reset_seen = 1'b0;
    reg resumed = 1'b0;
    always @(posedge clk) begin
        if(started && !rst_n) reset_seen<=1;
        if(reset_seen && rst_n) resumed<=1;
    end
    `TP_COVER(C_B_FLOW_10_RESET, active && resumed && seen_retire_src==7) // [REF_MODEL]
`endif

`ifdef TP_NEGATIVE
    // This profile disables DUT functional assertions: illegal-input recovery
    // has not been specified. Only the interface violation monitor is tested.
    /* [NO_REF_MODEL_PORTS] */`TP_ASSERT(A_NEG_SRC_MONITOR, !active || bad_src==(arvalid && src==3)) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_ASSERT(A_NEG_RESP_MONITOR, !active || bad_arresp==(arvalid && arresp!=0 && arresp!=3)) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_COVER(C_P_AR_11_SRC, active && bad_src) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_COVER(C_P_AR_11_RESP01, active && arvalid && src<3 && arresp==1) // [NO_REF_MODEL_PORTS]
    /* [NO_REF_MODEL_PORTS] */`TP_COVER(C_P_AR_11_RESP10, active && arvalid && src<3 && arresp==2) // [NO_REF_MODEL_PORTS]
`endif
