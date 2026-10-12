// BEGIN CMDBUF CLOSURE FORMAL MONITOR
`ifdef FORMAL_CLOSURE
    // This theorem binds the external request and payload to the complete
    // previous selection, including failed-current-attempt replacement (5A).
    // Selection correctness and accepted-address identity have separate proved
    // suppliers. No selected/bank/ready behavior is assumed here.
    reg pa_history=0;
    wire [17:0] pa_selected_addr=addr_q[select_entry];
    reg pa_valid;
    reg [3:0] pa_entry;
    reg [2:0] pa_bank;
    reg [11:0] pa_addr;
    always @(posedge clk)begin
        pa_history<=1;
        if(!rst_n)begin
            pa_valid<=0;pa_entry<=0;pa_bank<=0;pa_addr<=0;
        end else begin
            pa_valid<=select_valid;
            pa_entry<=select_valid?select_entry:4'b0;
            pa_bank<=select_valid?pa_selected_addr[5:3]:3'b0;
            pa_addr<=select_valid?pa_selected_addr[17:6]:12'b0;
        end
        PIPELINE_ALL: assert(
            (!rst_n && req==0 && arb_addr==0) ||
            (rst_n && pa_history &&
             issue_valid_q==pa_valid && issue_entry==pa_entry &&
             issue_bank_q==pa_bank && issue_addr_q==pa_addr &&
             req==(pa_valid?(8'b1<<pa_bank):8'b0) &&
             arb_addr==(pa_valid?pa_addr:12'b0)));
    end
`endif
// END CMDBUF CLOSURE FORMAL MONITOR
