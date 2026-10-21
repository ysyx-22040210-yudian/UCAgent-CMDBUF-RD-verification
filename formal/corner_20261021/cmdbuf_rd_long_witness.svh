// ENT-12 长循环的独立见证输入。仅用于 run_guided.py，不在 native.f / 正常证明中启用。
// 目的：先填满并暂停 R，再连续收发，尽快构造重复 ID 和超过 9 次槽位复用的合法轨迹。
// 这些 assume 是有意选取一个输入序列，不是设计规格，也不得合入正常环境 E03..E06。
// 该作业只证明所选见证存在；正常 assert 的 BMC/归纳结果另行报告。
    reg [5:0] witness_cycle;
    always @(posedge clk or negedge rst_n)
        if(!rst_n)witness_cycle<=0;
        else if(witness_cycle!=63)witness_cycle<=witness_cycle+1'b1;

    // [NO_REF_MODEL_ENV] [NO_REF_MODEL_HISTORY] 先接收九拍，20 拍后继续注入；全零 ready 时保持合法空拍。
    W_LONG_AR: assume property (
        @(posedge clk) disable iff (!rst_n)
        arvalid==(((witness_cycle<9)||(witness_cycle>=20&&witness_cycle<45))&&(arready!=0))
    );
    // [NO_REF_MODEL_ENV] [NO_REF_MODEL_HISTORY] 三源循环、重复 ID、固定 port；地址遍历 Bank/half。
    W_LONG_PAYLOAD: assume property (
        @(posedge clk) disable iff (!rst_n)
        src==(witness_cycle%3) && arid==8'h5a && ar_port_id==0 && arresp==0 &&
        araddr=={11'b0,witness_cycle[3],witness_cycle[2:0],3'b0}
    );
    // [NO_REF_MODEL_ENV] [NO_REF_MODEL_HISTORY] 前 20 拍不回收，随后三源均 ready；每个实际请求允许获双 grant。
    W_LONG_SERVICE: assume property (
        @(posedge clk) disable iff (!rst_n)
        rready==((witness_cycle<20)?3'b000:3'b111) && ar_rd_gnt==8'hff && rw_rd_gnt==8'hff
    );
    genvar wb;
    generate for(wb=0;wb<8;wb=wb+1)begin: witness_banks
        // [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 请求命中的 half 同拍 busy，其他 half 空闲；与正常 E06 一致。
        W_LONG_STATUS: assume property (
            @(posedge clk) disable iff (!rst_n)
            rd_mem_status[wb][0]==(req[wb]&&!arb_addr[0]) &&
            rd_mem_status[wb][1]==(req[wb]&&arb_addr[0])
        );
    end endgenerate
