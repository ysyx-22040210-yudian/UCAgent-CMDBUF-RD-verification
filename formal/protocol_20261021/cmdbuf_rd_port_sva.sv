// CMDBUF RD 顶层端口 SVA 阅读入口
// 1 环境假设 -> 2 端口/历史检查 -> 3 发射与 RR -> 4 单 XAU 保序
// -> 5 参考模型自检 -> 6 业务场景覆盖。
// 所有属性显式写出 posedge clk / disable iff (!rst_n)，不检查复位协议。
// |-> 表示同一采样拍；此文件不把本拍义务推迟到下一拍。
// [NO_REF_MODEL_PORTS] 仅本拍端口；[NO_REF_MODEL_HISTORY] 仅端口历史；
// [NO_REF_MODEL_ENV] 环境责任；[REF_MODEL] 依赖事务参考记录；
// [MODEL_SELF_CHECK] 检查器自洽检查，不等于验证 DUT 物理 entry。
// 属性标签保持不变，以便对照测试点、反例和历史结果。
`default_nettype none
// 【采样约定】所有属性在时钟上升沿读取同一拍的采样值；状态用非阻塞赋值在沿后更新。
// 以成功发射的采样拍为 N：N+4 采样并保存 MEM 数据，R 最早在 N+5 的采样拍合法返回。
// 当前用 disable iff 关闭复位期间的属性；参考记录清零与工具初态设置是另一个问题。
// 【责任边界】本模块所有端口均声明为 input，是因为它只观察 DUT 与环境之间的连线。
// 环境 assume 描述已确认契约；DUT assert 检查输出；模型自检不访问 DUT 内部层次。
// 【阅读方法】先看每条触发前提，再看期望结果；生成块中的 g 是来源编号，slots 中 g 是逻辑槽编号。
// cover 表示存在一条满足条件的轨迹，未命中不等于断言失败，命中也不等于无界正确性证明。
module cmdbuf_rd_port_sva (
    // 观测时钟：所有接口义务按此上升沿采样。
    input wire clk,
    // 低有效复位：属性在低电平时禁用；模型寄存器由复位分支建立空状态。
    input wire rst_n,
    // AR 通道：一组命令负载，三位 ready 表示各来源接收资格。
    // 来自上游：共享一条 AR 命令，由 src 指定来源，不是三路独立 arvalid。
    input wire arvalid,
    // 来自 DUT：每位表示该 XAU 当前可接收；可多位同时为 1，握手只看 src 对应位。
    input wire [2:0] arready,
    // 来自上游：完整 18 位地址；[5:3] 选 Bank，[6] 选奇偶，[2:0] 在 R 口透传。
    input wire [17:0] araddr,
    // 来源编码 0/1/2 分别是 XAU0/1/2；3 在有效 AR 时由环境契约排除。
    input wire [1:0] src,
    // 上游事务 ID：8 位原样保存，允许重复，不能以它替代接收 FIFO 的顺序 token。
    input wire [7:0] arid,
    // 上游 5 位 port_id：与同一事务的数据、ID、低地址一起保序返回。
    input wire [4:0] ar_port_id,
    // 上游地址状态：00 正常、11 越界；越界请求仍发 MEM，最终错误优先级最高。
    input wire [1:0] arresp,
    // R 通道：一组共享负载，单源保序，跨源按 RR 选择。
    // rvalid 来自 DUT、rready 来自上游；共享 R 负载由唯一有效的 rvalid 位指定接收者。
    input wire [2:0] rvalid, rready,
    // 来自 DUT：共享 128 位返回数据；无 rvalid 的拍不检查其取值。
    input wire [127:0] rdata,
    // 来自 DUT：应等于本次返回事务在 AR 接受时的 arid。
    input wire [7:0] rid,
    // 来自 DUT：应透传同一次 AR 的 port_id。
    input wire [4:0] r_port_id,
    // 来自 DUT：只返回原 araddr[2:0]，不是完整地址。
    input wire [2:0] raddr,
    // 来自 DUT：00 正常、01 校验异常、11 地址越界；无效拍不比较。
    input wire [1:0] rresp,
    // Arbit 通道：请求和地址已流水一拍；双 grant 才能推进待发窗口。
    // 来自 DUT：八个 Bank 的独热或全零请求；仲裁失败的请求不算成功发射。
    input wire [7:0] req,
    // 来自 DUT：请求事务的 araddr[17:6]；bit0 将奇偶半区送到下游。
    input wire [11:0] arb_addr,
    // 来自 DUT：组合输出的待发数，含本拍新 AR、扣本拍成功发射，不是总占用数。
    input wire [3:0] pending_cnt,
    // 来自 Arbit/MEM：只有同一 req 位的两个 grant 都为 1，本拍才算发射成功。
    input wire [7:0] ar_rd_gnt, rw_rd_gnt,
    // MEM 通道：逐 Bank 半区状态；数据和校验异常只有一组合并返回。
    // 二维状态：rd_mem_status[Bank编号][奇偶位]，0 空闲、1 占用；保持逐 Bank 数组形式。
    input wire [1:0] rd_mem_status [7:0],
    // 来自 MEM：一组合并后的 128 位数据，仅在四拍日历到期的采样沿保存。
    input wire [127:0] mem_rdata,
    // 来自 MEM：与本次返回数据同拍的 1 位校验异常；非到期拍数值不用于该事务。
    input wire pc_err

);

    // 公开端口事件：这些名称只表示本拍实际发生的握手或双 grant 成功。
    // AR 有效但所选来源不 ready 时不分配 entry、不入接收 FIFO，也不占年龄排名。
    // src 的范围保护避免用非法索引访问 arready；它不是新增的环境限制。
    wire ar_fire = arvalid && (src < 3) &&
                   ((src < 3) ? arready[src] : 1'b0);
    // 三个向量先逐位相与，再做归约或；禁止把不同 Bank 的两个 grant 误拼成一次成功。
    wire issue_fire = |(req & ar_rd_gnt & rw_rd_gnt);
    // 真实 R 握手是释放 CMDBUF/OTB 生命周期的事件；MEM 到达只标记完成，不回收。
    wire r_fire = |(rvalid & rready);

    // 参考模型只用已接受 AR、公开 req/grant 和固定返回时延推导事务身份。
    // 其中 expected_* 是独立期望值，不读取 DUT 的选择/完成/entry 等内部信号。
    // 参考状态的更新细节单独存放；阅读属性时不必先展开模型。
    `include "cmdbuf_rd_reference_model.svh"

    // ----------------------------------------------------------------
    // 1. 环境 assume：只描述已对齐的输入契约
    // ----------------------------------------------------------------
    // 【E03_SRC 详解】
    // 检查前提：arvalid 为 1 的当前采样拍，不以 arready 握手为触发条件。
    // 环境义务：2 位 src 只能取 0/1/2；src=3 只允许出现在无效 AR 拍。
    // 分析提示：assume 会排除非法来源的环境轨迹，不能拿它证明 DUT 能处理非法 src。
    // [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 有效 AR 必须来自 XAU0、XAU1 或 XAU2；无效拍不约束 src。
    E03_SRC: assume property (
        @(posedge clk) disable iff (!rst_n)
        (arvalid)
        |-> (src < 2'd3)
    );

    // 【E04_ARRESP 详解】
    // 检查前提：当前拍存在有效 AR；即使尚未握手，输入命令状态也必须合法。
    // 环境义务：只允许 00 正常或 11 地址越界，01/10 不作为合法 AR 状态。
    // 越界请求仍走正常发射、MEM 返回和单源保序流程，不能在本模块提前结束。
    // [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 有效 AR 的上游状态只允许正常 00 或地址越界 11。
    E04_ARRESP: assume property (
        @(posedge clk) disable iff (!rst_n)
        (arvalid)
        |-> (arresp == 2'b00 || arresp == 2'b11)
    );

    // 【E05_ZERO_READY 详解】
    // 检查前提：三位 arready 同时为 0；这是上游已确认的输入输出契约。
    // 环境义务：本拍 arvalid 必须为 0；只要存在 ready 通道，本条就不再限制 arvalid。
    // 本条没有要求 src 指向的位一定 ready；是否真正接收仍由 ar_fire 判断。
    // [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 三个来源都不能接收时，上游不得发送有效 AR。
    E05_ZERO_READY: assume property (
        @(posedge clk) disable iff (!rst_n)
        (arready == 3'b000)
        |-> (!arvalid)
    );

    genvar bank_env;
    generate for (bank_env = 0; bank_env < 8; bank_env = bank_env + 1) begin : status_contract
        wire requested_half_busy = rd_mem_status[bank_env][arb_addr[0]];
        // 【E06_SUCCESS_BUSY 详解】
        // 触发条件：同一个 Bank 位上的 req、ar_rd_gnt、rw_rd_gnt 本拍同时为 1。
        // 环境义务：本拍 rd_mem_status[bank][arb_addr[0]] 必须为 1，表示访问半区占用。
        // arb_addr[0] 是原 araddr[6]；只约束请求命中的半区，不要求另一个半区忙。
        // 注意时序：这是成功当拍义务，不能改成下一拍，也不能据忙状态取消当前 req。
        // 本条不是反向条件：状态忙本身不代表发射成功，任意一个 grant 缺失都不算成功。
        // [NO_REF_MODEL_ENV] [NO_REF_MODEL_PORTS] 本拍该 Bank 双 grant 成功时，被访问的奇偶半区本拍必须报告占用。
        E06_SUCCESS_BUSY: assume property (
            @(posedge clk) disable iff (!rst_n)
            (req[bank_env] && ar_rd_gnt[bank_env] && rw_rd_gnt[bank_env])
            |-> (requested_half_busy)
        );

    end endgenerate

    // ----------------------------------------------------------------
    // 2. 无事务参考模型的 assert：端口合法性与计数递推
    // ----------------------------------------------------------------
    // [NO_REF_MODEL_HISTORY] 只保存上拍公开 pending_cnt，不复制 entry。
    reg [3:0] last_pending;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            last_pending <= 0;
        else
            last_pending <= pending_cnt;
    end

    // 以下无条件断言每拍都检查；后面的蕴含断言只在前件成立时检查后件。
    // onehot0 允许零项，适合空闲拍；不能误写成必须恰好一位为 1。
    // x & (x-1) == 0 与 onehot0 等价，允许无请求的全零值。
    // 【A_REQ_ONEHOT 详解】
    // 检查范围：每个非复位采样拍，无需先出现 grant。
    // 允许 req=0，或八个 Bank 位中仅一个为 1；req 不是三源请求向量。
    // 失败通常表示一个共享地址同时请求多个 Bank，应先看 req 的置位来源。
    // [NO_REF_MODEL_PORTS] 下游每拍最多请求一个 Bank；全零合法。
    A_REQ_ONEHOT: assert property (
        @(posedge clk) disable iff (!rst_n)
        (req & (req-8'd1)) == 0
    );

    // 【A_R_ONEHOT 详解】
    // 检查范围：每个非复位拍；共享数据、ID、地址和状态只能属于一个响应对象。
    // 允许 rvalid=000；非零时最多一位有效。三位 arready 则没有此 onehot 要求。
    // 失败意味着共享 R 负载被同时标记给多个 XAU。
    // [NO_REF_MODEL_PORTS] 共享 R 负载每拍最多发往一个 XAU；全零合法。
    A_R_ONEHOT: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rvalid & (rvalid-3'd1)) == 0
    );

    // 【A_R_READY 详解】
    // 检查范围：三个位逐位比较，rvalid[i]=1 时同拍 rready[i] 必须为 1。
    // 本项目 RR 只在 ready 的来源间选择，不能先拉高 valid 再锁住等待 ready。
    // 它检查本拍资格；RR 是否选了正确来源由 A_RR_CHOICE 进一步检查。
    // [NO_REF_MODEL_PORTS] rvalid 只能在对应 rready 已经为 1 的通道拉高。
    A_R_READY: assert property (
        @(posedge clk) disable iff (!rst_n)
        (rvalid & ~rready) == 0
    );

    // 【A_PENDING_RANGE 详解】
    // 检查范围：每个非复位拍，仅检查公开的 4 位计数口。
    // pending_cnt 只统计尚未成功发射的命令，合法值 0 到 9。
    // 失败可提示减法下溢或重复计数；计数虽然合法但数值不对时要看另外两条计数断言。
    // [NO_REF_MODEL_PORTS] 待发命令数不能超过共享容量 9。
    A_PENDING_RANGE: assert property (
        @(posedge clk) disable iff (!rst_n)
        pending_cnt <= 9
    );

    // 【A_PENDING_RECURRENCE 详解】
    // 检查前提：每个非复位拍；last_pending 只保存上一采样拍的公开输出。
    // 本拍 AR 握手加一，双 grant 成功减一；仲裁失败不减，MEM/R 事件也不直接减。
    // 示例：上拍为 5，本拍成功 1 条且新收 1 条，则本拍仍应输出 5。
    // 失败时先检查计数是否晚一拍，以及是否错误地在 req 或 R 返回时扣减。
    // [NO_REF_MODEL_HISTORY] 本拍计数 = 上拍计数 + 本拍 AR 握手 - 本拍成功发射。
    A_PENDING_RECURRENCE: assert property (
        @(posedge clk) disable iff (!rst_n)
        pending_cnt == (last_pending+{3'b0,ar_fire}-{3'b0,issue_fire})
    );

    // ----------------------------------------------------------------
    // 3. 依赖参考记录的 assert：容量、乱序发射、RR 与有效负载
    // ----------------------------------------------------------------
    // 【A_READY 详解】
    // 检查范围：每个非复位拍，逐位比较三个来源的接收资格。
    // expected_ready 先计入本拍预期 R 回收，再按剩余容量和空源首项预留计算。
    // 例如 7/0/0 时 ready 应保留给另外两源；不能让同一源继续耗尽保留容量。
    // 该属性检查容量策略，不假设上游调度公平，也不保证某源最终一定获得输入机会。
    // [REF_MODEL] arready 必须符合容量预留规则，并计入本拍 R 回收。
    A_READY: assert property (
        @(posedge clk) disable iff (!rst_n)
        arready == expected_ready
    );

    // 【A_PENDING 详解】
    // 检查范围：每个非复位拍，使用事务表中尚未发射的条目数 waiting 作为基数。
    // 期望值组合计入本拍 ar_fire 和 issue_fire，不等下一拍寄存输出。
    // 已发射但仍等 MEM/R 的事务继续占 entry，却不再属于 waiting。
    // 它与 A_PENDING_RECURRENCE 采用不同依据，便于发现模型基数或接口计数时点不一致。
    // [REF_MODEL] 待发数含本拍新 AR，扣除本拍双 grant 成功；仲裁失败不扣除。
    A_PENDING: assert property (
        @(posedge clk) disable iff (!rst_n)
        pending_cnt == (waiting+(ar_fire?1:0)-(issue_fire?1:0))
    );

    // 【A_REQ 详解】
    // 检查范围：每拍同时检查有请求和无请求；无候选时必须 req=0。
    // m_attempt 是上一拍预选结果，选择依据为五项窗口内空闲半区的最老命令。
    // 当拍 Bank 已变忙仍可保留当前 req，真正成功与否只由同 Bank 的双 grant 决定。
    // 失败时沿反例回看上一拍 window、candidate、selected，而不只看当前状态。
    // [REF_MODEL] 当前 req 必须对应上一拍窗口内选出的最老可发命令。
    A_REQ: assert property (
        @(posedge clk) disable iff (!rst_n)
        req == expected_req
    );

    // 【A_ARB_ADDR 详解】
    // 检查前提：当前 req 非零；req=0 时地址负载按约定不关心。
    // 期望地址属于当前流水请求，内容为保存的 araddr[17:6]，共 12 位。
    // bit0 同时携带奇偶半区选择；不能误用旧的 [17:7] 或当前新输入 araddr。
    // [REF_MODEL] req 有效时检查完整下游地址 araddr[17:6]；无效时不检查负载。
    A_ARB_ADDR: assert property (
        @(posedge clk) disable iff (!rst_n)
        (req != 8'b0)
        |-> (arb_addr == expected_addr)
    );

    // 【A_RR_CHOICE 详解】
    // 检查范围：每拍比较完整 rvalid 向量，包含应当响应却没有响应的情况。
    // 先找各 XAU 最老未返回事务，再判断已完成和 ready，最后从 RR 起点扫描。
    // 不能先过滤出所有已完成项再选源内最老，否则年轻项可能越过尚未完成的老命令。
    // 失败时先区分资格计算错误、源内越序和 RR 指针推进错误。
    // [REF_MODEL] 只在 ready 且最老队头已完成的来源间按 RR 选择。
    A_RR_CHOICE: assert property (
        @(posedge clk) disable iff (!rst_n)
        rvalid == expected_rvalid
    );

    // 【A_R_METADATA 详解】
    // 检查前提：本拍发生真实 R 握手；无有效响应的负载不比较。
    // rid、r_port_id、raddr 必须同时来自模型所选的同一个 rsp_e。
    // raddr 仅检查原地址低三位，不存在额外的 18 位完整 R 地址口。
    // 该共享出口检查与下面逐源 FIFO 检查互补，不能用三个字段分别各自找到匹配项代替。
    // [REF_MODEL] R 握手时，ID、port_id、地址低三位必须属于同一预期事务。
    A_R_METADATA: assert property (
        @(posedge clk) disable iff (!rst_n)
        (r_fire)
        |-> ((rid == m_id[rsp_e] && r_port_id == m_port[rsp_e] && raddr == m_addr[rsp_e][2:0]))
    );

    // 【A_R_RESP 详解】
    // 检查前提：真实 R 握手，状态必须对应 rsp_e 保存的上游状态和 MEM pc_err。
    // 优先级：原 arresp=11 则返回 11；否则 pc_err=1 返回 01；否则返回 00。
    // 地址越界与校验错同时存在时必须为 11，不能被较晚捕获的校验错覆盖。
    // [REF_MODEL] R 错误状态来自预期事务；地址越界优先于奇偶校验异常。
    A_R_RESP: assert property (
        @(posedge clk) disable iff (!rst_n)
        (r_fire)
        |-> (rresp == expected_resp)
    );

    // 【A_R_DATA 详解】
    // 检查前提：真实 R 握手；期望值来自该事务成功发射 N 拍后 N+4 的 MEM 采样。
    // MEM 只有一组数据且只保持一拍，因此比较的是已保存数据，不是当前 mem_rdata。
    // 失败时应核对发射事务归属、四拍返回日历，以及数据等待期间是否被后续返回覆盖。
    // [REF_MODEL] R 数据必须等于预期事务在成功发射后第 4 拍捕获的数据。
    A_R_DATA: assert property (
        @(posedge clk) disable iff (!rst_n)
        (r_fire)
        |-> (rdata == m_data[rsp_e])
    );

    // ----------------------------------------------------------------
    // 4. 单 XAU 顺序：AR 接收 FIFO 的队头必须先返回
    // ----------------------------------------------------------------
    genvar g, h;
    generate for (g = 0; g < 3; g = g + 1) begin : sources
        // 本地状态只记录该源接收顺序以及 cover 进度。
        `include "cmdbuf_rd_xau_order_model.svh"

        // 【A_RR_BOUND 详解】
        // 检查前提：该源本拍仍具备响应资格，并已经在持续具备资格期间被其他响应越过两次。
        // 三源 RR 此时必须给该源 rvalid；bypass_count 仅在实际发生其他 R 时递增。
        // 该源不 ready 或队头尚未完成时资格断开，不累计无条件等待时钟数。
        // [REF_MODEL] 该源持续可响应且已被另外两次响应越过时，本拍必须轮到它。
        A_RR_BOUND: assert property (
            @(posedge clk) disable iff (!rst_n)
            (eligible[g] && bypass_count >= 2)
            |-> (rvalid[g])
        );

        // 【A_XAU_R_HAS_PENDING 详解】
        // 检查前提：rvalid[g] 为 1；队头由该 XAU 的 AR 实际握手顺序确定。
        // 期望 FIFO 非空、token 合法、对应事务仍有效且来源为 g。
        // 失败提示凭空响应、重复响应或来源串线；此处不把 arid 当事务唯一编号。
        // [REF_MODEL] 该 XAU 的 rvalid 有效时，必须存在已接受但尚未返回的最老事务。
        A_XAU_R_HAS_PENDING: assert property (
            @(posedge clk) disable iff (!rst_n)
            (rvalid[g])
            |-> (oldest_valid)
        );

        // 【A_XAU_R_HEAD_COMPLETE 详解】
        // 检查前提：该源 rvalid 为 1，必须响应独立接收 FIFO 的 oldest。
        // 队头既要已成功发射，也要已捕获 MEM；只取得 grant 还不足以返回 R。
        // 即使命令 3 数据已经返回，只要命令 1 尚未完成，本条仍禁止借命令 3 提前响应。
        // [REF_MODEL] 只允许响应已成功发射且已捕获 MEM 数据的 FIFO 队头。
        A_XAU_R_HEAD_COMPLETE: assert property (
            @(posedge clk) disable iff (!rst_n)
            (rvalid[g])
            |-> ((oldest_valid && m_sent[oldest] && m_done[oldest]))
        );

        // 【A_XAU_R_NO_EARLY_BYPASS 详解】
        // 检查前提：该源有合法队头，但队头的 MEM 数据尚未捕获。
        // 期望该源 rvalid 为 0；不要求其他 XAU 停止响应，也不要求下游停止发射。
        // 这是明确的队头阻塞规则：年轻项完成不改变 AR 接收 FIFO 的出队条件。
        // [REF_MODEL] 队头未完成时，年轻命令即使已完成，也不能让该源提前响应。
        A_XAU_R_NO_EARLY_BYPASS: assert property (
            @(posedge clk) disable iff (!rst_n)
            (oldest_valid && !m_done[oldest])
            |-> (!rvalid[g])
        );

        // 【A_XAU_R_ADDR_ORDER 详解】
        // 检查前提：该源有有效 R，先确认 oldest 有效，再比较地址低三位。
        // 期望值来自最早接受且尚未返回的命令，不来自最早发射或最早完成的命令。
        // 地址低位相同的不同命令仍要靠 ID、port、数据和状态的配套断言继续区分。
        // [REF_MODEL] 有效 R 的 raddr 必须等于该源接收 FIFO 队头的 araddr[2:0]。
        A_XAU_R_ADDR_ORDER: assert property (
            @(posedge clk) disable iff (!rst_n)
            (rvalid[g])
            |-> ((oldest_valid && raddr == m_addr[oldest][2:0]))
        );

        // 【A_XAU_R_ID_ORDER 详解】
        // 检查前提：该源有有效 R，rid 必须等于 oldest 在 AR 接受时保存的 arid。
        // 允许同源多个未完成命令使用相同 ID；保序要求也跨不同 ID 生效。
        // ID 只作为透传负载检查，不能用 ID 大小或 ID 唯一性替代接收顺序。
        // [REF_MODEL] 有效 R 的 rid 必须属于队头；不按 ID 数值排序，也不要求 ID 唯一。
        A_XAU_R_ID_ORDER: assert property (
            @(posedge clk) disable iff (!rst_n)
            (rvalid[g])
            |-> ((oldest_valid && rid == m_id[oldest]))
        );

        // 【A_XAU_R_PORT_ORDER 详解】
        // 检查前提：该源有有效 R；比较原 AR 的 5 位 port_id。
        // 必须与数据、ID、地址指向相同队头，不允许 port_id 取自当前 AR 或年轻事务。
        // port_id 重复是合法情况，不负责作为事务唯一标识。
        // [REF_MODEL] 有效 R 的 port_id 必须透传同一个队头命令的 port_id。
        A_XAU_R_PORT_ORDER: assert property (
            @(posedge clk) disable iff (!rst_n)
            (rvalid[g])
            |-> ((oldest_valid && r_port_id == m_port[oldest]))
        );

        // 【A_XAU_R_DATA_ORDER 详解】
        // 检查前提：该源有有效 R；比较 oldest 对应的完整 128 位捕获记录。
        // 命令 3 即使先到 OTB，也只能等命令 1、2 各自 R 成功后再返回自己的数据。
        // 即使三条命令 ID、port、地址低位都相同，只要数据不同，错用年轻项数据仍能检出。
        // [REF_MODEL] 有效 R 的 128 位数据必须来自同一个队头事务的 MEM 捕获记录。
        A_XAU_R_DATA_ORDER: assert property (
            @(posedge clk) disable iff (!rst_n)
            (rvalid[g])
            |-> ((oldest_valid && rdata == m_data[oldest]))
        );

        // 【A_XAU_R_RESP_ORDER 详解】
        // 检查前提：该源有有效 R；状态必须由 oldest 的 arresp 与捕获 pc_err 形成。
        // 先比对越界 11，再比对校验异常 01；错误状态也必须按命令顺序归属。
        // 不能出现 ID/数据属于命令 1，但错误状态来自先完成的命令 3 的拼接响应。
        // [REF_MODEL] 有效 R 的错误状态必须由同一个队头事务的 arresp 和 pc_err 形成。
        A_XAU_R_RESP_ORDER: assert property (
            @(posedge clk) disable iff (!rst_n)
            (rvalid[g])
            |-> ((oldest_valid && rresp == oldest_resp))
        );

        // 下列两项是 FIFO 与事务表互相核对，不是 DUT 存储探针。
        // 【M_XAU_FIFO_COUNT 详解】
        // 检查范围：每拍核对两个独立记录：接收 FIFO 长度与事务表该源有效占用数。
        // 长度最多 7 是已对齐的容量策略；这里检查模型记录，外部 ready 正确性由 A_READY 检查。
        // 失败先查同拍出入、重复出队或复用逻辑槽时是否遗漏更新，不能直接归结为 DUT 物理槽损坏。
        // [MODEL_SELF_CHECK] 独立接收 FIFO 的长度必须与事务表该源占用数一致，且不超过 7。
        M_XAU_FIFO_COUNT: assert property (
            @(posedge clk) disable iff (!rst_n)
            order_count == occ[g] && order_count <= 7
        );

        // 【M_XAU_FIFO_HEAD 详解】
        // 检查范围：FIFO 是否为空必须与年龄模型的 head_valid 一致；非空时两个队头 token 相同。
        // FIFO 靠接收/返回事件维护，head 靠事务表年龄计算，二者不以发射顺序建队。
        // 这是检查器交叉自检；应与 A_XAU_R_* 的实际端口负载检查一起分析。
        // [MODEL_SELF_CHECK] 独立 FIFO 队头必须与事务表按年龄计算的最老事务一致。
        M_XAU_FIFO_HEAD: assert property (
            @(posedge clk) disable iff (!rst_n)
            (order_count != 0) == head_valid[g] &&
            (order_count == 0 || (oldest_valid &&
            oldest == head[g]))
        );

        // cover 的 && 是同拍条件共现；不能改成蕴含后靠空真命中。
        // 【C_XAU_EARLY_THIRD_BLOCKED 详解】
        // 命中前提：监视器已经见到 3 先发射并先捕获，且 1 仍未完成。
        // 还要求 ready[g]=1 和 rvalid[g]=0，用来见证等待确实由源内顺序引起。
        // 只证明这种等待状态可达；所有轨迹均不能越序的义务由 assert 承担。
        // [REF_MODEL] 命令 3 先捕获，命令 1 未完成；即使 ready=1，该源仍无响应。
        C_XAU_EARLY_THIRD_BLOCKED: cover property (
            @(posedge clk) disable iff (!rst_n)
            order_phase == 3 && m_done[third_token] && !m_done[first_token] && rready[g] && !rvalid[g]
        );

        // 【C_XAU_R_123_AFTER_ISSUE3_FIRST 详解】
        // 监视器跨拍跟踪三个 token：AR 顺序为 1/2/3，3 早于 1/2 成功发射及捕获。
        // 进入本命中拍前已经核对 R1、R2；本拍核对 R3 的 token 和整组负载。
        // 这是完整返回链的可达见证，不是只检查本拍 ID 排序。
        // [REF_MODEL] 完整见证：3 先发射及捕获，但 R 按 1、2、3 返回对应整组负载。
        C_XAU_R_123_AFTER_ISSUE3_FIRST: cover property (
            @(posedge clk) disable iff (!rst_n)
            order_phase == 5 && source_r && oldest == third_token && head_payload_matches
        );

        // 【C_XAU_OTHER_SOURCE_PROGRESS 详解】
        // 命中时当前源的命令 3 已完成而命令 1 未完成，同时另一个来源有有效 R。
        // 用于见证某源队头阻塞不会强制所有来源一起停住。
        // 该表达式本身不逐字段检查另一个响应，其合法性由配套 DUT assert 和原生仿真核对。
        // [REF_MODEL] 该源因旧命令未完成而等待时，另一个 XAU 仍能返回。
        C_XAU_OTHER_SOURCE_PROGRESS: cover property (
            @(posedge clk) disable iff (!rst_n)
            order_phase == 3 && m_done[third_token] && !m_done[first_token] && (|(rvalid & ~(3'b1<<g)))
        );

        // 【C_XAU_SAME_CYCLE_POP_PUSH 详解】
        // 命中时同一源 source_ar 与 source_r 同拍成立，且返回负载属于旧队头。
        // 用于见证同拍收发路径；队列下一状态的长度、队头一致性另由模型自检检查。
        // 新项应放在剩余老项之后，不能因为复用刚释放的 token 而插到队首。
        // [REF_MODEL] 同一个 XAU 同拍返回旧命令、接受新命令。
        C_XAU_SAME_CYCLE_POP_PUSH: cover property (
            @(posedge clk) disable iff (!rst_n)
            source_ar && source_r && order_count>0 && head_payload_matches
        );

        // 【C_XAU_REPEAT_ID_HEAD_R 详解】
        // 命中时至少两条同源命令 ID 相同，较年轻的第二项已完成，且本拍返回旧队头负载。
        // 不要求这两项的 port、地址或数据也相同；全元数据重复场景另有定向用例。
        // 该覆盖用于排除只能依赖唯一 ID 才能工作的验证盲点。
        // [REF_MODEL] 队列中 ID 重复且年轻项已完成时，响应仍匹配最老队头。
        C_XAU_REPEAT_ID_HEAD_R: cover property (
            @(posedge clk) disable iff (!rst_n)
            order_count >= 2 &&
            m_id[order_slot[0]] == m_id[order_slot[1]] &&
            m_done[order_slot[1]] &&
            source_r &&
            head_payload_matches
        );

    end endgenerate

    // ----------------------------------------------------------------
    // 5. 模型自检 assert：检验参考记录的一致性
    // ----------------------------------------------------------------
    // 【M_ALLOC 详解】
    // 检查前提：公开 AR 口已经真正握手，本地事务表必须能找到可写逻辑槽。
    // 允许使用本拍预期 R 刚释放的槽；alloc_e 只属于检查器，不要求与 DUT 编号相同。
    // 失败先查 ready 预测和回收计算，不应添加 assume 强行禁止满载同拍收发。
    // [MODEL_SELF_CHECK] 模型接收 AR 时必须找到合法逻辑槽；不检查 DUT 物理分配编号。
    M_ALLOC: assert property (
        @(posedge clk) disable iff (!rst_n)
        (ar_fire)
        |-> ((free_found && alloc_e<9))
    );

    // 【M_RETIRE 详解】
    // 检查前提：真实 R 握手，模型也应当允许一次响应。
    // rsp_e 必须合法、有效、已发射并完成；它用于避免错误地从模型删除不存在的事务。
    // 若失败，结合 A_RR_CHOICE 和各源 FIFO 检查定位输出错误或模型归属错误。
    // [MODEL_SELF_CHECK] 实际 R 握手必须对应模型的合法、已发射、已完成事务。
    M_RETIRE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (r_fire)
        |-> ((model_retire && rsp_e<9 && m_live[rsp_e] && m_sent[rsp_e] && m_done[rsp_e]))
    );

    // 【M_SUCCESS 详解】
    // 检查前提：真实 req 与两个 grant 在同一 Bank 位同时有效。
    // 模型请求流水项必须存在，且指向尚未成功发射的有效事务。
    // 失败可提示重复发射或请求预测脱节；不能把 req 非零本身当作成功。
    // [MODEL_SELF_CHECK] 实际发射成功必须对应模型当前请求中的未发射事务。
    M_SUCCESS: assert property (
        @(posedge clk) disable iff (!rst_n)
        (issue_fire)
        |-> ((m_attempt && m_attempt_e<9 && m_live[m_attempt_e] && !m_sent[m_attempt_e]))
    );

    // 【M_DUE 详解】
    // 检查前提：四拍返回日历的到期位有效；此时没有独立的 MEM valid 端口。
    // 对应逻辑槽必须仍有效、已成功发射、尚未捕获，防止提前释放或重复捕获。
    // 这条核对返回归属与生命周期，不把任意非到期拍的 MEM 数据当作有效返回。
    // [MODEL_SELF_CHECK] 返回日历到期必须对应仍在途且尚未捕获的事务。
    M_DUE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (mem_capture_due)
        |-> ((mem_capture_slot<9 &&
              m_live[mem_capture_slot] &&
              m_sent[mem_capture_slot] &&
              !m_done[mem_capture_slot]))
    );

    // 【M_NO_BYPASS 详解】
    // 检查前提：本拍有 MEM 捕获且有真实 R 握手，二者允许属于不同事务。
    // 要求到期事务与响应事务不同，体现 MEM 捕获后最快下一采样拍才可返回 R。
    // 本条对模型选定的 rsp_e 作归属自检；实际响应选择仍要看 A_RR_CHOICE。
    // [MODEL_SELF_CHECK] 本拍刚捕获 MEM 的事务不得在同拍 R 返回，最快下一拍。
    M_NO_BYPASS: assert property (
        @(posedge clk) disable iff (!rst_n)
        (mem_capture_due && r_fire)
        |-> (mem_capture_slot != rsp_e)
    );

    // 【M_STATE 详解】
    // 检查范围：每拍位集合关系；已完成项必须已发射，已发射项必须仍有效。
    // 成功发射和 MEM 返回都不会清 m_live，只有 R 回收才结束生命周期。
    // 失败先查同拍更新优先级或状态提前清除，不能把模型位当成 DUT 内部探针。
    // [MODEL_SELF_CHECK] 模型完成集合是已发射集合的子集；已发射集合是有效集合的子集。
    M_STATE: assert property (
        @(posedge clk) disable iff (!rst_n)
        ((m_sent & ~m_live) == 0 && (m_done & ~m_sent) == 0)
    );

    // 【M_RANGE 详解】
    // 检查范围：每拍核对模型计数的基本大小关系。
    // waiting 不含已成功发射项；used 包含所有已接受但还未 R 回收项。
    // 它检查模型基础一致性，不能代替公开 pending_cnt 和 arready 的 DUT 断言。
    // [MODEL_SELF_CHECK] 模型待发数不超过占用数，占用数不超过 9。
    M_RANGE: assert property (
        @(posedge clk) disable iff (!rst_n)
        (waiting >= 0 && waiting <= used && used <= 9)
    );

    // 【M_QUOTA 详解】
    // 检查范围：共享使用量不超过 6，加上三源首项预留后的预算不超过 9。
    // shared_cost=sum(max(occ[x]-1,0))；quota_cost=sum(max(occ[x],1))。
    // 这比只限制单源最多 7 项更完整，也能表达 4/4/0 时需给最后空源留一项。
    // [MODEL_SELF_CHECK] 模型的共享池与空源保留预算均不得超限。
    M_QUOTA: assert property (
        @(posedge clk) disable iff (!rst_n)
        (shared_cost <= 6 && quota_cost <= 9)
    );

    // 【M_ATTEMPT 详解】
    // 检查前提：本拍模型持有上一拍预选好的请求。
    // 该请求必须指向有效且未成功发射的槽；等待仲裁失败的命令仍符合条件。
    // 成功当拍允许参与下一拍预选的集合改变，但当前流水事务编号不能混淆。
    // [MODEL_SELF_CHECK] 模型请求流水项必须指向合法、有效、未成功发射的事务。
    M_ATTEMPT: assert property (
        @(posedge clk) disable iff (!rst_n)
        (m_attempt)
        |-> ((m_attempt_e<9 && m_live[m_attempt_e] && !m_sent[m_attempt_e]))
    );

    generate for (g = 0; g < 9; g = g + 1) begin : slots
        // 逐槽统计返回日历四级有效 token；只在对应有效位为 1 时计算该级。
        // 该统计不要求读 DUT 内部 OTB，日历由公开的成功发射事件建立。
        wire [3:0] calendar_count =
            {3'b0, (m_due[0] && m_due_e[0] == g)} +
            {3'b0, (m_due[1] && m_due_e[1] == g)} +
            {3'b0, (m_due[2] && m_due_e[2] == g)} +
            {3'b0, (m_due[3] && m_due_e[3] == g)};
        // 【M_AGE_RANGE 详解】
        // 检查前提：第 g 个逻辑槽有效，年龄排名应在 0 到 used-1。
        // 年龄按 AR 接受建立，只在较老事务 R 回收后压缩。
        // 发射成功或失败不改变未返回事务之间的相对新老关系。
        // [MODEL_SELF_CHECK] 每个有效逻辑槽的年龄排名必须落在当前有效事务范围内。
        M_AGE_RANGE: assert property (
            @(posedge clk) disable iff (!rst_n)
            (m_live[g])
            |-> (m_age[g]<used)
        );

        // 【M_CALENDAR 详解】
        // 检查范围：逐逻辑槽统计四级返回日历中指向它的有效项个数。
        // 有效、已发射、未完成的槽应恰有 1 项；其他槽应为 0 项。
        // 可发现返回 token 丢失、重复登记或 MEM 捕获后日历未正确移出等模型问题。
        // [MODEL_SELF_CHECK] 每个已发射未完成事务在 4 拍返回日历中恰好有一项。
        M_CALENDAR: assert property (
            @(posedge clk) disable iff (!rst_n)
            calendar_count == {3'b0,(m_live[g] && m_sent[g] && !m_done[g])}
        );

        for (h = 0; h < 9; h = h + 1) begin : pairs
            if (g != h) begin : distinct
                // 【M_AGE_UNIQUE 详解】
                // 检查前提：两个不同逻辑槽都有效；年龄排名不能相同。
                // 年龄唯一才能明确选最老候选、源内队头及窗口第六项。
                // 无效槽可保存相同初值，因此不能把本条改成对所有槽无条件不等。
                // [MODEL_SELF_CHECK] 任意两个不同的有效逻辑槽不得使用相同年龄排名。
                M_AGE_UNIQUE: assert property (
                    @(posedge clk) disable iff (!rst_n)
                    (m_live[g] && m_live[h])
                    |-> (m_age[g] != m_age[h])
                );

            end
        end
    end endgenerate

    // ----------------------------------------------------------------
    // 6. cover：要求业务事件真实发生，不对输入增加 assume
    // ----------------------------------------------------------------
    // 【C_RETRY_NEXT_CYCLE 详解】
    // retry_selected 记住上一拍仲裁失败但同拍又选中同一 token 的事件。
    // 本拍还需有非零 req，且 Bank 与地址都等于保存值，才算见到连续重试。
    // 它见证失败后可以紧接下一拍请求，不额外假设下一次仲裁必定成功。
    // [REF_MODEL] 仲裁失败后本拍重选同一命令，下一拍继续发出该请求。
    C_RETRY_NEXT_CYCLE: cover property (
        @(posedge clk) disable iff (!rst_n)
        retry_selected && req == last_retry_req && arb_addr == last_retry_addr && req != 0
    );

    // 【C_FAILURE_SELECT_OTHER 详解】
    // 当前请求存在但未成功，且它对应半区现在忙；窗口内另一个空闲候选被选中。
    // 命中拍处于预选阶段，下一拍对外 req 的正确性由 A_REQ/A_ARB_ADDR 检查。
    // 失败项保留年龄，不因本次改选其他命令而移到队尾。
    // [REF_MODEL] 当前请求失败且对应半区忙，本拍选中窗口内另一条命令。
    C_FAILURE_SELECT_OTHER: cover property (
        @(posedge clk) disable iff (!rst_n)
        m_attempt && !issue_fire && !idle[m_attempt_e] && select_valid && select_e != m_attempt_e
    );

    // 【C_REFILL_NEXT_CYCLE 详解】
    // refill_selected 记录上一拍成功并预选到原排名 5，即第六条待发命令。
    // 本拍 req/地址必须等于该补入命令，体现成功当拍即补窗的 6B 行为。
    // 这里检查预选后的下一拍请求，不要求该新请求也在本拍取得 grant。
    // [REF_MODEL] 成功当拍补入原第 6 条命令，下一拍请求它。
    C_REFILL_NEXT_CYCLE: cover property (
        @(posedge clk) disable iff (!rst_n)
        refill_selected && req == last_refill_req && arb_addr == last_refill_addr
    );

    // 【C_NONHEAD_REFILL 详解】
    // 与 C_REFILL_NEXT_CYCLE 相同，但额外要求前一拍成功项不是窗口最老队头。
    // 例如 A/B/C/D/E 中 C 成功，剩余顺序应为 A/B/D/E/F，且 F 可当拍预选。
    // 未成功的 A/B/D/E 保持相对年龄，不允许整体跳过它们或重排。
    // [REF_MODEL] 窗口非队头成功后，原第 6 条同拍补入并于下一拍请求。
    C_NONHEAD_REFILL: cover property (
        @(posedge clk) disable iff (!rst_n)
        nonhead_refill_selected && req == last_refill_req && arb_addr == last_refill_addr
    );

    // 【C_BLOCKED_SIX 详解】
    // 当前五项窗口无空闲候选，窗口外至少有一项匹配空闲状态，且没有已流水请求。
    // blocked_streak 还要求该状态持续多个采样拍，见证第六项不能越窗发射。
    // 这条 cover 不证明所有受阻轨迹都正确；发射输出的普遍约束由 A_REQ 检查。
    // [REF_MODEL] 窗口五条均不匹配、窗口外第六条匹配，连续等待仍不能越窗发射。
    C_BLOCKED_SIX: cover property (
        @(posedge clk) disable iff (!rst_n)
        blocked_six && blocked_streak >= 3
    );

    // 【C_PENDING5_DEC 详解】
    // 拍初模型有 5 条未发射命令，本拍无 AR 握手但成功发射一条。
    // 命中要求本拍 pending_cnt 已变为 4，不能保持 5 等到下一拍。
    // [REF_MODEL] 原待发 5 条，本拍只成功发射一条，pending_cnt 本拍为 4。
    C_PENDING5_DEC: cover property (
        @(posedge clk) disable iff (!rst_n)
        waiting == 5 && !ar_fire && issue_fire && pending_cnt == 4
    );

    // 【C_PENDING5_BOTH 详解】
    // 拍初模型有 5 条待发，本拍同时接收新 AR 并成功发射旧命令。
    // 加一减一相抵，本拍 pending_cnt=5；这里同收同发指 AR/下游发射两事件。
    // [REF_MODEL] 原待发 5 条，本拍同收同发，pending_cnt 本拍仍为 5。
    C_PENDING5_BOTH: cover property (
        @(posedge clk) disable iff (!rst_n)
        waiting == 5 && ar_fire && issue_fire && pending_cnt == 5
    );

    // 【C_PENDING5_ADD 详解】
    // 拍初模型有 5 条待发，本拍只接收新 AR，没有成功发射。
    // 本拍必须输出 6；req 仲裁失败也属于没有成功发射。
    // [REF_MODEL] 原待发 5 条，本拍只接收一条，pending_cnt 本拍为 6。
    C_PENDING5_ADD: cover property (
        @(posedge clk) disable iff (!rst_n)
        waiting == 5 && ar_fire && !issue_fire && pending_cnt == 6
    );

    // 【C_FULL_REUSE 详解】
    // 拍初九项均占用，本拍同时发生 R 回收和 AR 接收。
    // 用于见证满载仍能利用本拍释放的容量；不要求两条事务来自同一 XAU。
    // 检查器可以重用同一逻辑槽，但本条不要求 DUT 使用特定物理槽。
    // [REF_MODEL] 9 项满占用时，同拍 R 回收并接收新 AR。
    C_FULL_REUSE: cover property (
        @(posedge clk) disable iff (!rst_n)
        used == 9 && ar_fire && r_fire
    );

    // 【C_ALL_FOUR_EVENTS 详解】
    // 同一采样拍四事件均为 1，通常分别属于不同生命周期阶段的命令。
    // AR 新入、旧命令发射、四拍前命令捕获、已完成命令 R 返回可以并行。
    // 它不表示同一条命令在一拍内完成四个阶段。
    // [REF_MODEL] 同拍发生 AR 接收、成功发射、MEM 捕获和 R 返回。
    C_ALL_FOUR_EVENTS: cover property (
        @(posedge clk) disable iff (!rst_n)
        ar_fire && issue_fire && mem_capture_due && r_fire
    );

    // 【C_CAPACITY700 详解】
    // 当前占用分别为 7/0/0，且本拍没有 R 回收，排除回收放宽接收资格的影响。
    // arready=6 即二进制 110：XAU0 不可再收，XAU1/XAU2 仍可各用首项。
    // 只见证 ready 容量保护，不假设上游一定调度到这两个来源。
    // [REF_MODEL] 占用为 7/0/0 时，仍允许其余两个 XAU 各接收第一条命令。
    C_CAPACITY700: cover property (
        @(posedge clk) disable iff (!rst_n)
        occ[0] == 7 && occ[1] == 0 && occ[2] == 0 && !r_fire && arready == 6
    );

    // 【C_CAPACITY440 详解】
    // 当前占用分别为 4/4/0，本拍没有 R 回收，共享预算已用满。
    // arready=4 即二进制 100：最后一个空源仍能接收，其余两源暂不可继续扩占。
    // 用于覆盖只设单源上限却未给第三源留容量的实现缺陷。
    // [REF_MODEL] 占用为 4/4/0 时，最后空源仍可接收，已有两个源暂不可接收。
    C_CAPACITY440: cover property (
        @(posedge clk) disable iff (!rst_n)
        occ[0] == 4 && occ[1] == 4 && occ[2] == 0 && !r_fire && arready == 4
    );

    // 【C_RETURN_ERROR_PRIORITY 详解】
    // 命中时响应事务原 arresp=11 且捕获到 pc_err=1，R 仍返回 11。
    // 这里使用保存的 m_pc 而非当前 pc_err，避免把其他事务的 MEM 状态混入响应。
    // [REF_MODEL] 同一事务越界与校验异常同时存在，最终响应越界 11。
    C_RETURN_ERROR_PRIORITY: cover property (
        @(posedge clk) disable iff (!rst_n)
        r_fire && m_err[rsp_e] == 3 && m_pc[rsp_e] && rresp == 3
    );

    // 【C_READY_MASK_RR 详解】
    // 至少一个队头具备响应资格，且 rready 不是三源全开，同时确有 R 返回。
    // 用于见证 RR 能跳过不 ready 的通道，不要求固定是哪一个来源被跳过。
    // [REF_MODEL] 部分通道不 ready 时，RR 仍能选出可响应来源。
    C_READY_MASK_RR: cover property (
        @(posedge clk) disable iff (!rst_n)
        eligible != 0 && rready != 7 && r_fire
    );

    // 【C_FOUR_SUCCESS 详解】
    // issue_streak 记录前面连续成功发射的次数，遇到任意未成功拍即归零。
    // 本拍再次 issue_fire 且之前至少连续三拍成功，见证至少四拍连续成功吞吐。
    // 只依赖端口事件历史，不需要命令/数据参考队列；饱和计数还允许更长连续序列。
    // [NO_REF_MODEL_HISTORY] 连续四拍成功发射，仅使用成功发射事件历史。
    C_FOUR_SUCCESS: cover property (
        @(posedge clk) disable iff (!rst_n)
        issue_streak >= 3 && issue_fire
    );

    // 下面 8×2 的 generate 是全部物理 Bank 半区组合；与前面的三源 generate 不是同一个维度。
    genvar cb, ch;
    generate for (cb = 0; cb < 8; cb = cb + 1) begin : bank_covers
        for (ch = 0; ch < 2; ch = ch + 1) begin : half_covers
            wire this_half_busy = rd_mem_status[cb][ch];
            // 【C_SUCCESS_BUSY_TARGET 详解】
            // 按八个 Bank 和两个半区展开，共 16 个覆盖实例。
            // 需真实请求和同 Bank 双 grant 成功，并确认 arb_addr[0] 选中该半区。
            // 用于避免 E06 约束只在无请求时空真成立；本条要求对应目标实际出现过成功事件。
            // [NO_REF_MODEL_PORTS] 逐 Bank、逐奇偶半区命中成功发射且状态报告占用。
            C_SUCCESS_BUSY_TARGET: cover property (
                @(posedge clk) disable iff (!rst_n)
                req[cb] && ar_rd_gnt[cb] && rw_rd_gnt[cb] && arb_addr[0] == ch && this_half_busy
            );

        end
    end endgenerate
    // Corner 专项是可选扩展；正常工程不开宏时仍使用原属性集合。
    // 打开 formal/corner_20261021/native.f 后，追加逐测试点见证及独立 AR/R 容量记账。
`ifdef CMDBUF_CORNER_SUITE
    `include "cmdbuf_rd_corner_properties.svh"
`endif
endmodule
`default_nettype wire
