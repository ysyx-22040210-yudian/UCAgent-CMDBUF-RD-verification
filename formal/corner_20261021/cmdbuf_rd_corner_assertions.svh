// 这一组新增断言不需要事务参考模型。
// 只用顶层实际 AR/R 握手构成 N_s，独立于 m_live/m_age/m_done 等参考记录。
// 与原 A_READY 并行：原检查按预期 R 计算，新检查按实际 R 计算，不能互相替代。

    // [NO_REF_MODEL_HISTORY] AR 累计接收减 R 累计返回：全局最多仍在途 9 条。
    A_CC_TOTAL: assert property (
        @(posedge clk) disable iff (!rst_n)
        h_total<=9
    );
    // 例如 5/4/0 虽然总数是 9，仍侵占第三源的首项预留。
    // [NO_REF_MODEL_HISTORY] 空来源按 1 项保留计算，三源总预算不得超过 9。
    A_CC_BUDGET: assert property (
        @(posedge clk) disable iff (!rst_n)
        h_budget<=9
    );
    // 本拍 R 先从 N_s 中扣除，再计算 ready；本拍 src/arvalid 不参与 ready 计算。
    // full+R 不应平白插空拍，但释放单项源时也不能把其首项借给其他源。
    // [NO_REF_MODEL_HISTORY] 三位 ready 必须等于按实际 AR/R 历史及本拍 R 计算的接收许可。
    A_CC_READY: assert property (
        @(posedge clk) disable iff (!rst_n)
        arready==h_ready
    );
    genvar cs;
    generate for(cs=0;cs<3;cs=cs+1) begin: corner_source
        // [NO_REF_MODEL_HISTORY] 任一 XAU 尚未返回的命令不能超过 7 条。
        A_CC_SRC_LIMIT: assert property (
            @(posedge clk) disable iff (!rst_n)
            h_occ[cs]<=7
        );
        // rvalid 已由 A_R_READY 要求 ready 为 1；此处另检查不能凭空或重复返回。
        // 本拍新 AR 不能为本拍的 R 提供队列项，所以比较拍初 N_s，不加入本拍 AR。
        // [NO_REF_MODEL_HISTORY] 只要该源 rvalid 有效，就必须有之前接受而尚未返回的命令。
        A_CC_R_NONEMPTY: assert property (
            @(posedge clk) disable iff (!rst_n)
            rvalid[cs] |-> (h_occ[cs]!=0)
        );
    end endgenerate

    // 两条显式流水检查让失败重选、成功补窗等场景更容易定位到 C2/C3。
    // C2 的所有候选、先过滤空闲再按年龄选择都保存在 h_selected_* 中。
    // 不读取本拍 status 来撤销上拍已预选出的请求。
    // [REF_MODEL] 上一拍 C2 有选择，本拍必须按该选择发 req 和地址。
    A_CC_C2_TO_C3: assert property (
        @(posedge clk) disable iff (!rst_n)
        h_selected_prev |-> (req==h_selected_req && arb_addr==h_selected_addr)
    );
    // 无请求时故意不比较 arb_addr。
    // [REF_MODEL] 上一拍没有 C2 选择，本拍不得凭空发起请求。
    A_CC_NO_C2_NO_REQ: assert property (
        @(posedge clk) disable iff (!rst_n)
        (!h_selected_prev) |-> (req==0)
    );
