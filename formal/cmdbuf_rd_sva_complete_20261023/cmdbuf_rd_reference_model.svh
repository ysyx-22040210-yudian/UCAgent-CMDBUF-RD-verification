// 事务参考模型：只读取检查器顶层端口，不读取 DUT 内部 entry 或状态。
// 先看本文件的组合数据流，再看“时序更新”：AR 记录 -> 预选 -> 请求 -> 四拍 MEM -> R 回收。
// 组合逻辑全部使用 assign；generate 只在编译时展开接线，不增加时钟周期。
// *_prefix[k] 表示扫描前 k 项的组合结果，绝不是第 k 拍寄存器。
// m_* 是跨拍保存的参考状态；其余 wire 是由当前状态/端口计算的本拍结果。
// 验证范围沿用正常运行的二值输入，不新增复位协议或四态用例。

    // 1. 跨拍事务表：逻辑槽编号只供检查器识别事务，与 DUT 物理 entry 无关。
    reg [8:0] m_live;                // 每槽已接受且尚未 R 回收的有效位。
    reg [8:0] m_sent;                // 每槽已双 grant 成功发射的标志，成功后退出待发窗口。
    reg [8:0] m_done;                // 每槽已在四拍到期沿保存 MEM 数据的标志。
    reg [8:0] m_pc;                  // 每槽随 MEM 数据保存的奇偶校验异常。
    reg [17:0] m_addr [0:8];         // AR 接受时的完整地址，包含 Bank、half 和 R 低地址。
    reg [1:0] m_src [0:8];           // 每槽所属 XAU，合法有效事务取 0/1/2。
    reg [1:0] m_err [0:8];           // 每槽 AR 地址状态，11 的优先级高于 m_pc。
    reg [7:0] m_id [0:8];            // 每槽原始 arid，允许不同事务使用相同 ID。
    reg [4:0] m_port [0:8];          // 每槽原始 ar_port_id，随响应原样返回。
    reg [3:0] m_age [0:8];           // 有效未返回事务的全局接收排名，0 最老；发射不改年龄。
    reg [127:0] m_data [0:8];        // 每槽完整 MEM 返回数据，等到该源队头可返回才使用。
    reg [1:0] m_rr;                  // 跨源响应 RR 起点，响应后指向 winner 的下一来源。
    reg m_attempt;                   // 上拍 C2 是否选中命令，即本拍 C3 应有请求。
    reg [3:0] m_attempt_e;           // 本拍 C3 请求的参考事务槽号，仅在 m_attempt 时有效。
    reg [3:0] m_due;                 // 成功发射的四级有效日历，第 3 级表示本拍 MEM 到期。
    reg [3:0] m_due_e [0:3];         // 与四级有效日历同行的事务槽号。
    wire mem_capture_due;           // 本拍是否需要捕获唯一一组 MEM 数据/pc_err。
    wire [3:0] mem_capture_slot;     // 本拍到期的事务槽号，仅在 mem_capture_due 时使用。
    // 第 3 级有效位为 1，表示四拍前已有一次成功发射，本拍必须接住 MEM 的单拍返回。
    assign mem_capture_due = m_due[3];
    // 从有效位对应的同一级取槽号，保证本拍数据写回那一次成功发射的事务。
    assign mem_capture_slot = m_due_e[3];

    // 2. 占用统计：used 是 AR-R 的生命周期占用；waiting 仅含尚未成功发射的命令。
    // 计数保留原 integer 的 32 位有符号宽度，避免改写时引入减法截断或符号变化。
    wire signed [31:0] used;                // 当前九槽中 m_live 的总数。
    wire signed [31:0] waiting;             // 当前 m_live 且未 m_sent 的总数。
    wire signed [31:0] occ [0:2];           // 各 XAU 的全部未回收事务数。
    wire signed [31:0] shared_cost;         // 三源超出首项的总占用，正常不超过共享预算 6。
    wire signed [31:0] quota_cost;          // 非空源用实际占用，空源计 1 项预留的总预算。
    wire signed [31:0] used_prefix [0:9];   // 扫描前 k 个逻辑槽的有效项累计数。
    wire signed [31:0] wait_prefix [0:9];   // 扫描前 k 个逻辑槽的待发项累计数。
    wire signed [31:0] shared_part [0:2];   // 每源占用中超过首项的部分，空源为 0。
    wire signed [31:0] quota_part [0:2];    // 每源的占用/首项预留预算，至少为 1。
    genvar mi;                              // 编译展开用的逻辑槽索引 0..8。
    genvar mx;                              // 编译展开用的 XAU 索引 0..2。
    genvar mj;                              // 编译展开用的年龄比较对象索引 0..8。
    genvar mo;                              // 编译展开用的 RR 扫描偏移 0..2。
    // 扫描任何槽之前，已累计的有效事务数为 0；这是组合链起点，不是计数器清零。
    assign used_prefix[0] = 0;
    // 待发计数也从 0 开始，与全部有效事务的计数分别累计。
    assign wait_prefix[0] = 0;
    generate for (mi=0; mi<9; mi=mi+1) begin : count_slots
        // 前 mi 项的累计数，加上当前槽 mi 的有效位；已发射、已完成但未 R 回收的项仍计入占用。
        assign used_prefix[mi+1] = used_prefix[mi] + (m_live[mi] ? 32'sd1 : 32'sd0);
        // 只有有效且尚未成功发射的当前项才加 1；已成功项继续占 entry，但不再算待发命令。
        assign wait_prefix[mi+1] = wait_prefix[mi] +
                                  ((m_live[mi] && !m_sent[mi]) ? 32'sd1 : 32'sd0);
    end endgenerate
    // 读扫描完槽 0..8 的末端结果，得到本拍全部尚未回收的事务数。
    assign used = used_prefix[9];
    // 读待发累计链末端，得到拍初待发数；本拍 AR/发射的增减另由 pending_cnt 属性检查。
    assign waiting = wait_prefix[9];
    generate for (mx=0; mx<3; mx=mx+1) begin : count_sources
        wire signed [31:0] occ_prefix [0:9]; // 当前 XAU 扫描前 k 个槽的累计占用，分源独立展开。
        // 每个来源 mx 有独立累计链；尚未扫描任何槽时，该来源的占用计数为 0。
        assign occ_prefix[0] = 0;
        for (mi=0; mi<9; mi=mi+1) begin : slots
            // 当前槽必须同时满足“有效”和“来源等于 mx”才加 1，其他来源不影响这条累计链。
            assign occ_prefix[mi+1] = occ_prefix[mi] +
                ((m_live[mi] && m_src[mi]==mx) ? 32'sd1 : 32'sd0);
        end
        // 九个槽都检查完后，末端数值就是来源 mx 的 AR 已接受、R 未回收条数。
        assign occ[mx] = occ_prefix[9];
        // 每源第一项由预留容量承担，第二项起才消耗六项共享容量；空源的共享消耗取 0。
        assign shared_part[mx] = occ[mx]>0 ? occ[mx]-1 : 0;
        // 非空来源按实际条数计费，空来源仍占 1 个预留名额，避免其他来源挤掉它的首项。
        assign quota_part[mx] = occ[mx]>0 ? occ[mx] : 1;
    end endgenerate
    // 合计三源超出各自首项的条数，用于检查六项共享容量是否被超用。
    assign shared_cost = shared_part[0]+shared_part[1]+shared_part[2];
    // 合计实际占用与空源预留，得到含公平性预留的总预算；它可能大于 used。
    assign quota_cost = quota_part[0]+quota_part[1]+quota_part[2];

    // 3. 单源队头：先找该源最老有效事务，再检查 done/ready，不能跳过尚未完成的队头。
    // 前缀扫描用“严格更老”更新，年龄相同则保留较小槽号；9 是无候选的年龄哨兵。
    wire [3:0] head [0:2];                  // 每源最老有效事务的槽号；无队头时默认 0。
    wire [2:0] head_valid;                  // 每源是否存在年龄小于 9 的有效队头。
    wire [2:0] eligible;                    // 每源队头有效、已完成且该源 rready 为 1。
    // 阅读扫描下标：prefix[mi] 已考虑槽 0..mi-1；prefix[mi+1] 再把槽 mi 纳入。
    // 例如扫描到槽 2 时，若它比槽 0/1 中最老者更老，就同时更新年龄和槽号；否则两者均保留。
    // generate/for 展开的是同一拍的接线，mi 是扫描位置，不是时钟拍号。
    generate for (mx=0; mx<3; mx=mx+1) begin : source_heads
        wire [3:0] head_age_prefix [0:9];  // 当前 XAU 扫描前 k 个槽得到的最小年龄，无项为 9。
        wire [3:0] head_slot_prefix [0:9]; // 与当前 XAU 最小年龄对应的参考槽号。
        wire head_found_prefix [0:9];     // 当前 XAU 在前 k 个槽中是否已找到队头。
        wire head_take [0:8];             // 当前槽是否比已找到的本源队头更老。
        // 合法年龄为 0..8，取 9 表示尚未找到队头；第一个合法候选一定比这个初值更老。
        assign head_age_prefix[0] = 4'd9;
        // 尚无候选时先放槽号 0；是否存在真实队头由 head_found_prefix 判定，不能只看这个槽号。
        assign head_slot_prefix[0] = 4'd0;
        // 扫描起点还没检查任何事务，因此“已经找到本源队头”的标志为 0。
        assign head_found_prefix[0] = 1'b0;
        for (mi=0; mi<9; mi=mi+1) begin : slots
            // 当前槽有效、属于来源 mx，且年龄小于此前找到的最小年龄，才替换队头。
            // 这里不检查 m_done：年轻命令即使先完成，也不能绕过尚未完成的老命令。
            assign head_take[mi] = m_live[mi] && m_src[mi]==mx && m_age[mi]<head_age_prefix[mi];
            // 如果当前槽更老，就把最小年龄更新为 m_age[mi]；否则沿用前 mi 项的最小年龄。
            // 下标 mi+1 表示把槽 mi 也纳入扫描结果，全部仍是本拍组合计算。
            assign head_age_prefix[mi+1] = head_take[mi] ? m_age[mi] : head_age_prefix[mi];
            // 年龄更新时，队头槽号也必须同步改为 mi；未替换时保留原队头槽号。
            // 4'(mi) 把展开索引转成 4 位槽号，足以表示 0..8，并不增加流水级。
            assign head_slot_prefix[mi+1] = head_take[mi] ? 4'(mi) : head_slot_prefix[mi];
            // 此前已经找到候选，或当前槽首次满足条件，均表示本源存在队头；后续不匹配的槽不能清掉它。
            assign head_found_prefix[mi+1] = head_found_prefix[mi] || head_take[mi];
        end
        // 取扫描九个槽后的槽号作为来源 mx 的最老事务；只有 head_valid[mx] 为 1 时它才有效。
        assign head[mx] = head_slot_prefix[9];
        // 末端找到标志说明本源确有有效事务；空来源不会因默认槽号为 0 而误参加 RR。
        assign head_valid[mx] = head_found_prefix[9];
        // 先确定本源队头，再要求该队头已经保存 MEM 数据且上游本拍 ready，才授予 RR 候选资格。
        // 例如命令 3 已完成而队头命令 1 未完成，本项仍为 0，必须继续等待命令 1。
        assign eligible[mx] = head_valid[mx] && m_done[head[mx]] && rready[mx];
    end endgenerate

    // 4. 跨源 RR：按起点、下一源、再下一源扫描，遇到首个 eligible 后停止选择。
    // 所有级都在同一拍组合计算；m_rr 才是跨拍保存的轮询位置。
    wire [2:0] expected_rvalid;             // 本拍预期的独热响应对象，无候选或复位时为 0。
    wire [1:0] winner;                      // 预期响应对象的 XAU 编号，仅在 model_retire 时使用。
    wire [3:0] rsp_e;                       // winner 队头对应的参考槽号。
    wire model_retire;                      // 预期本拍有 R 响应，用于模型回收；r_fire 是真实握手。
    wire signed [31:0] rr_scan [0:2];       // 每个 RR 扫描位置对应的来源编号，回绕到 0..2。
    wire [2:0] rr_valid_prefix [0:3];       // 前 k 个 RR 位置已选择的独热响应，初始为 0。
    wire [1:0] rr_winner_prefix [0:3];      // 前 k 个 RR 位置选中的来源编号。
    wire [3:0] rr_slot_prefix [0:3];        // 前 k 个 RR 位置选中的队头槽号。
    wire rr_take [0:2];                     // 尚未选中任何源且当前 RR 位置具备响应资格。
    // RR 扫描开始时还没有选中来源，独热响应向量从全 0 起步。
    assign rr_valid_prefix[0] = 0;
    // 尚未选中时默认来源号为 0；是否真的选中由响应有效向量判断。
    assign rr_winner_prefix[0] = 0;
    // 尚未选中时默认参考槽号为 0，不把它作为有效响应使用。
    assign rr_slot_prefix[0] = 0;
    generate for (mo=0; mo<3; mo=mo+1) begin : response_rr
        // 在 RR 起点上加扫描偏移，达到 3 就减 3 回绕；例如起点 2 的检查顺序为 2、0、1。
        assign rr_scan[mo] = (m_rr+mo>=3) ? m_rr+mo-3 : m_rr+mo;
        // 只有此前还没选中任何来源，并且当前来源 eligible，才能在这个扫描位置选中它。
        assign rr_take[mo] = rr_valid_prefix[mo]==0 && eligible[rr_scan[mo]];
        // 首次命中时置对应来源的一位；已经选中则原样传递，保证后面的候选不能覆盖先命中者。
        assign rr_valid_prefix[mo+1] = rr_take[mo] ? (3'b001 << rr_scan[mo]) : rr_valid_prefix[mo];
        // 与有效向量同时记录命中来源的编号；没有新命中就继续传递已有胜者。
        assign rr_winner_prefix[mo+1] = rr_take[mo] ? rr_scan[mo][1:0] : rr_winner_prefix[mo];
        // 记录同一胜者的本源队头槽号；响应负载随后按这个槽取，避免来源与数据错配。
        assign rr_slot_prefix[mo+1] = rr_take[mo] ? head[rr_scan[mo]] : rr_slot_prefix[mo];
    end endgenerate
    // 扫描三个位置后取最终独热向量；复位期间输出计算值为 0，属性仍按 disable iff 禁用。
    assign expected_rvalid = rst_n ? rr_valid_prefix[3] : 3'b000;
    // 末端保存的来源编号就是本拍 RR 胜者，仅在 model_retire 为 1 时参与回收和指针推进。
    assign winner = rr_winner_prefix[3];
    // 末端保存的队头槽号用于读取本拍响应负载，以及决定本拍要回收哪一条参考事务。
    assign rsp_e = rr_slot_prefix[3];
    // 预期响应向量任意一位有效，就预测本拍回收一次；eligible 已要求对应 rready 为 1。
    assign model_retire = |expected_rvalid;

    // 5. AR 准入：先扣本拍预期 R，再检查物理总量及三源首项预留，支持满载同拍进出。
    // 7/0/0 与 4/4/0 都已耗尽共享预算；空来源仍可以使用自己的首项预留。
    wire signed [31:0] after_occ [0:2];      // 各源扣除本拍预期响应后的占用。
    wire signed [31:0] used_after;           // 三源扣本拍预期 R 后的总占用。
    wire signed [31:0] shared_after;         // 扣本拍预期 R 后共用六项的已使用量。
    wire signed [31:0] after_shared_part [0:2]; // 各源扣 R 后超过首项的占用。
    wire [2:0] expected_ready;               // 每源本拍是否有资格接受一条 AR，允许多位为 1。
    generate for (mx=0; mx<3; mx=mx+1) begin : admission
        // 只有本拍预期 R 属于来源 mx 时，该源占用才减 1；其他来源保持原值。
        // 后续 ready 用减过 R 的占用计算，因此可以接收与回收同拍的新 AR。
        assign after_occ[mx] = occ[mx] - ((model_retire && winner==mx) ? 1 : 0);
        // 先扣 R，再重新扣除该源首项预留；用于判断本拍响应释放了多少共享容量。
        assign after_shared_part[mx] = after_occ[mx]>0 ? after_occ[mx]-1 : 0;
        // 必须有物理空位；空来源可用自己的首项预留，非空来源还须有六项共享预算的余量。
        // 三位分别计算，可同时为 1；实际只接收 src 选择且完成握手的一条命令。
        assign expected_ready[mx] = rst_n && used_after<9 &&
                                    (after_occ[mx]==0 || shared_after<6);
    end endgenerate
    // 合计三源扣除本拍预期 R 后的占用，表示本拍 AR 分配之前实际需要保留的项数。
    assign used_after = after_occ[0]+after_occ[1]+after_occ[2];
    // 合计扣 R 后的共享消耗；由它决定非空来源本拍能否再增加一项。
    assign shared_after = after_shared_part[0]+after_shared_part[1]+after_shared_part[2];

    // 6. 逻辑槽分配：选最小可用槽号；本拍被 R 回收的槽同样可供新 AR 复用。
    // 这是参考表的存储策略，不要求 DUT 采用相同物理槽号。
    wire [3:0] alloc_e;                      // 本拍新 AR 将写入的参考槽号。
    wire free_found;                         // 是否存在空槽或本拍可回收槽。
    wire alloc_free [0:8];                   // 每个逻辑槽是否可供本拍新 AR 使用。
    wire alloc_found_prefix [0:9];          // 扫描前 k 个槽是否已经找到可用槽。
    wire [3:0] alloc_slot_prefix [0:9];      // 扫描前 k 个槽找到的首个可用槽号。
    // 分配扫描起点还没找到可用槽，允许后面第一个可用槽成为分配结果。
    assign alloc_found_prefix[0] = 0;
    // 未找到可用槽时槽号默认 0；分配是否合法需同时检查 free_found。
    assign alloc_slot_prefix[0] = 0;
    generate for (mi=0; mi<9; mi=mi+1) begin : allocation
        // 原本无效的槽可分配，本拍预期 R 要回收的槽也可立即复用；已发射但未回收的槽仍不可用。
        assign alloc_free[mi] = !m_live[mi] || (model_retire && rsp_e==mi);
        // 一旦前面或当前发现可用槽，就保持“已找到”，防止后面的可用槽改写最先选中的结果。
        assign alloc_found_prefix[mi+1] = alloc_found_prefix[mi] || alloc_free[mi];
        // 仅“此前没找到、当前可用”时取当前槽号；否则继续传递先前选中的最小可用槽号。
        assign alloc_slot_prefix[mi+1] = (!alloc_found_prefix[mi] && alloc_free[mi]) ?
                                         4'(mi) : alloc_slot_prefix[mi];
    end endgenerate
    // 取九槽扫描末端的分配槽号，供本拍 ar_fire 时写入新事务。
    assign alloc_e = alloc_slot_prefix[9];
    // 末端标志说明是否真正存在可用槽；它与 alloc_e 配合，防止把默认槽号当空槽。
    assign free_found = alloc_found_prefix[9];

    // 7. 五项窗口：pending 是拍初待发集；pool 只扣本拍成功项，失败项仍保留原年龄。
    // ranks[i] 是 pool 中比 i 更老的项数，排名 0..4 才入窗；C1 新 AR 不在本拍 pool 内。
    // 成功 C 后 A/B/C/D/E -> A/B/D/E/F，F 在成功当拍就参与下一条 C2 预选。
    wire [8:0] pending;                      // 所有有效且未成功发射的事务位图。
    wire [8:0] pool;                         // pending 扣除本拍双 grant 成功事务后的位图。
    wire [8:0] window;                       // pool 中最老五项位图，不受空闲状态影响成员资格。
    wire [8:0] idle;                         // 各事务地址对应 Bank/half 的本拍空闲状态。
    wire [8:0] candidate;                    // window 与 idle 的交集，最老选择只比较此集合。
    wire signed [31:0] ranks [0:8];          // 每项在 pool 内的年龄排名，供窗口与 cover 使用。
    // 有效位与未成功发射位相与，得到所有待发事务；MEM 返回和 R ready 不参与这个集合的定义。
    assign pending = m_live & ~m_sent;
    generate for (mi=0; mi<9; mi=mi+1) begin : issue_window
        wire signed [31:0] rank_prefix [0:9]; // 对当前槽 mi，前 k 个槽中比它更老的 pool 项数。
        // 只移除本拍双 grant 成功的请求项；仲裁失败时不移除，使原命令仍能在本拍被重新选中。
        assign pool[mi] = pending[mi] && !(issue_fire && m_attempt_e==mi);
        // 计算当前槽 mi 的年龄排名前，较老待发事务数从 0 开始累计。
        assign rank_prefix[0] = 0;
        for (mj=0; mj<9; mj=mj+1) begin : compare_age
            // 比较槽 mj 必须仍在 pool 且年龄严格小于 mi 才加 1；无效、已发射或更年轻的槽不计入。
            assign rank_prefix[mj+1] = rank_prefix[mj] +
                ((pool[mj] && m_age[mj]<m_age[mi]) ? 32'sd1 : 32'sd0);
        end
        // 扫描全部九槽后，累计值就是 pool 中比 mi 更老的条数；对仍在 pool 的项，这就是从 0 起算的排名。
        assign ranks[mi] = rank_prefix[9];
        // 当前项仍在 pool，且前面最多只有四条更老命令，才属于五项窗口；Bank 空闲不能改变入窗资格。
        assign window[mi] = pool[mi] && ranks[mi]<5;
        // 地址 [5:3] 选择 Bank 0..7，[6] 选择奇偶半区；对应状态位为 0 才得到 idle=1。
        assign idle[mi] = !rd_mem_status[m_addr[mi][5:3]][m_addr[mi][6]];
        // 只有“已在五项窗口内”并且“本拍目标半区空闲”的交集才可竞争；窗外第六条空闲也不能越窗。
        assign candidate[mi] = window[mi] && idle[mi];
    end endgenerate

    // 8. 最老命中选择：先得到全部空闲候选，再扫描最小年龄；不从窗口外借命令。
    // selected 经下面的时序寄存成为下一拍 m_attempt；本拍仲裁与下一拍预选可并行。
    wire [8:0] selected;                    // 本拍 C2 选中项的独热位图，无候选时为 0。
    wire [3:0] select_e;                    // 本拍 C2 选中的参考槽号，无候选时默认 0。
    wire select_valid;                      // 本拍 C2 是否选中，供下一拍请求流水记录使用。
    wire [3:0] select_age_prefix [0:9];     // 前 k 个候选得到的最小年龄，无项时为 9。
    wire [3:0] select_slot_prefix [0:9];    // 与该最小年龄相对应的参考槽号。
    wire select_take [0:8];                 // 当前槽是候选且年龄严格小于前缀最小年龄。
    // 用合法年龄上界之外的 9 表示尚无选中项，后续扫描寻找候选中的最小年龄。
    assign select_age_prefix[0] = 4'd9;
    // 初始槽号为 0，仅作无候选时的默认值；select_valid 决定它能否生成下一拍请求。
    assign select_slot_prefix[0] = 0;
    generate for (mi=0; mi<9; mi=mi+1) begin : issue_oldest
        // 当前槽必须已经通过窗口与空闲过滤，且比此前最老候选更老，才能替换预选结果。
        assign select_take[mi] = candidate[mi] && m_age[mi]<select_age_prefix[mi];
        // 命中更老候选时更新最小年龄，未命中则保持已有结果；后来的年轻候选不会抢占它。
        assign select_age_prefix[mi+1] = select_take[mi] ? m_age[mi] : select_age_prefix[mi];
        // 与年龄更新同步记录当前 4 位槽号，否则保留此前选中槽，保证选中年龄与事务身份一致。
        assign select_slot_prefix[mi+1] = select_take[mi] ? 4'(mi) : select_slot_prefix[mi];
    end endgenerate
    // 末端槽号给出本拍 C2 预选结果；下面的时序逻辑会在时钟沿把它送入 C3 请求流水。
    assign select_e = select_slot_prefix[9];
    // 末端年龄小于 9 说明确有候选，才将槽号译成九位独热向量；全无候选时输出全 0。
    assign selected = (select_age_prefix[9]<9) ? (9'b1 << select_e) : 9'd0;
    // 对独热向量做归约或，表示本拍是否预选到一条命令，决定下一拍 m_attempt 是否有效。
    assign select_valid = |selected;

    // 9. 时序更新：在采样沿保存事务、请求流水和 MEM 日历，跨拍状态不能用 assign 代替。
    integer e; // 时序循环的参考槽索引，用于九项事务表的同步更新。
    integer k; // 时序循环的日历级索引，用于四拍返回 token 的移位。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            m_live<=0; m_sent<=0; m_done<=0; m_pc<=0; m_rr<=0;
            m_attempt<=0; m_attempt_e<=0; m_due<=0;
            for(k=0;k<4;k=k+1) m_due_e[k]<=0;
            for(e=0;e<9;e=e+1) begin
                m_addr[e]<=0; m_src[e]<=0; m_err[e]<=0; m_id[e]<=0;
                m_port[e]<=0; m_age[e]<=0; m_data[e]<=0;
            end
        end else begin
            // N 拍成功发射 -> N+4 拍捕获；done 在捕获沿后更新，R 最早 N+5。
            // 采样编号示例：N 成功写入第 0 级；N+4 采样前第 3 级到期，捕获本拍 MEM 负载。
            // 没有 MEM valid 口，所以只依赖这条固定时延日历；非到期拍的数据不能更新事务。
            m_due<={m_due[2:0],issue_fire};
            m_due_e[0]<=issue_fire?m_attempt_e:4'd0;
            for(k=1;k<4;k=k+1) m_due_e[k]<=m_due[k-1]?m_due_e[k-1]:4'd0;
            // 本拍计算的 selected 在沿后更新请求流水，对应下一采样拍观察到的 req/arb_addr。
            // 若当前失败但仍为最老空闲候选，它可同拍再次选中，于下一拍继续请求。
            m_attempt<=select_valid;
            m_attempt_e<=select_valid?select_e:4'd0;
            // 按本模型合法响应推进 RR；没有预期响应时保持，不按空转时钟轮换。
            if(model_retire) m_rr<=(winner==2)?2'd0:winner+2'd1;
            for(e=0;e<9;e=e+1) begin
                // 更新优先级：新 AR 写入 > 该槽旧事务回收 > 原事务状态推进。
                // 复用时清除旧数据、完成/发射/校验状态，并写入新的来源、ID、port 和地址。
                // 新命令年龄是回收后的末尾；若先清旧槽再忽略新写入，会造成同拍收发丢命令。
                // 同拍回收并复用同一逻辑槽时，新事务写入优先。
                if(ar_fire && alloc_e==e) begin
                    m_live[e]<=1; m_sent[e]<=0; m_done[e]<=0; m_pc[e]<=0;
                    m_addr[e]<=araddr; m_src[e]<=src; m_err[e]<=arresp;
                    m_id[e]<=arid; m_port[e]<=ar_port_id;
                    m_age[e]<=used-(model_retire?1:0); m_data[e]<=0;
                // 仅 R 生命周期完成才清除有效位；发射成功和 MEM 捕获都不能走回收分支。
                end else if(model_retire && rsp_e==e) begin
                    m_live[e]<=0; m_sent[e]<=0; m_done[e]<=0; m_pc[e]<=0;
                    m_addr[e]<=0; m_src[e]<=0; m_err[e]<=0; m_id[e]<=0;
                    m_port[e]<=0; m_age[e]<=0; m_data[e]<=0;
                end else begin
                    // 只把比被回收事务更年轻的排名减一；其他未返回命令的相对顺序不变。
                    if(model_retire && m_live[e] && m_age[e]>m_age[rsp_e])
                        m_age[e]<=m_age[e]-1'b1;
                    // 成功发射后保持 m_live=1，只把 m_sent 置 1，使该项以后不再参加五项待发窗口。
                    if(issue_fire && m_attempt_e==e) m_sent[e]<=1;
                    // 数据与 pc_err 在同一个到期沿一起保存，同时置 done。
                    // 沿上的 SVA 仍观察更新前的 done，因此该事务最早在下一采样拍才有 R 资格。
                    if(mem_capture_due && mem_capture_slot==e) begin
                        m_done[e]<=1; m_data[e]<=mem_rdata; m_pc[e]<=pc_err;
                    end
                end
            end
        end
    end

    // 10. 本拍端口期望：req/地址取自 C3 流水，错误状态取自本拍 R 队头。
    // 预期 req/地址取自请求流水 token，不取自当前预选命令或当前 AR 输入。
    // 无请求时模型给地址默认值仅为计算方便，A_ARB_ADDR 明确不检查无效地址。
    // expected_req：按 C3 事务地址 [5:3] 解码的预期 Bank 请求。
    wire [7:0] expected_req;
    // 仅 C3 请求流水有效时，根据那条事务地址的 Bank 位译成八位独热 req；不用本拍 C2 新选中项。
    assign expected_req = (rst_n && m_attempt)?(8'b1<<m_addr[m_attempt_e][5:3]):8'd0;
    // expected_addr：同一 C3 事务地址 [17:6]，无 req 时不作为断言比较对象。
    wire [11:0] expected_addr;
    // 从同一 C3 事务取地址 [17:6]，低位保留奇偶半区选择；无请求时的默认值不参加有效负载检查。
    assign expected_addr = (rst_n && m_attempt)?m_addr[m_attempt_e][17:6]:12'd0;
    // 错误优先级只用响应事务保存的信息：AR 越界 11 优先，其次 MEM 校验 01，否则正常 00。
    // expected_resp：本拍 R 事务的预期状态，地址越界优先于奇偶校验异常。
    wire [1:0] expected_resp;
    // 只合成本拍 R 事务保存的状态：AR 越界返回 11，否则 pc_err 返回 01，否则返回 00。
    assign expected_resp = (m_err[rsp_e]==2'b11)?2'b11:(m_pc[rsp_e]?2'b01:2'b00);


    // 11. 覆盖历史：以下寄存器只记录见证进度，不驱动期望输出，也不增加环境约束。
    reg retry_selected;                 // 上拍失败事务在同拍 C2 被再次选中。
    reg refill_selected;                // 上拍成功后原第六条在同拍 C2 补入并选中。
    reg nonhead_refill_selected;         // 在 refill_selected 基础上，成功事务原来不是最老项。
    reg [11:0] last_retry_addr;          // 上拍失败请求地址，供本拍重试一致性 cover 比较。
    reg [11:0] last_refill_addr;         // 上拍补窗选中事务的下游地址。
    reg [7:0] last_retry_req;            // 上拍失败请求的 Bank 独热位图。
    reg [7:0] last_refill_req;           // 上拍补窗事务的 Bank 独热位图。
    reg [2:0] blocked_streak;            // 连续五项窗口受阻的拍数，饱和于 7。
    reg [3:0] issue_streak;              // 仅由端口成功事件累计的连续发射拍数，饱和于 15。
    wire signed [31:0] selected_old_rank; // 本拍选中项在扣成功之前 pending 集合中的排名。
    wire signed [31:0] old_rank_prefix [0:9]; // 扫描前 k 槽中比 select_e 更老的 pending 项数。
    genvar mc;                          // 编译展开用的旧窗口排名比较索引。
    // 用旧 pending 排名而非新 pool 排名识别“原第六条”：selected_old_rank==5。
    // 重新统计预选项在旧 pending 中的排名，起点较老条数为 0。
    assign old_rank_prefix[0] = 0;
    generate for (mc=0; mc<9; mc=mc+1) begin : previous_window_rank
        // 按尚未扣掉本拍成功项的 pending 计数，才能识别新选中项原先是否排在第六条。
        assign old_rank_prefix[mc+1] = old_rank_prefix[mc] +
            ((pending[mc] && m_age[mc]<m_age[select_e]) ? 32'sd1 : 32'sd0);
    end endgenerate
    // 九槽扫描末端若为 5，表示本拍预选项原先是第六条；与 issue_fire 联合见证成功当拍补窗。
    assign selected_old_rank = old_rank_prefix[9];
    // 要求窗口完全不匹配、窗口外至少一项空闲且当前没有已发出的流水请求。
    // 这样记录的是五项窗口被阻塞的状态，而非把上一拍已预选请求误认为窗口越界。
    // blocked_six：五项均不匹配、窗外有空闲项、且没有上拍遗留的请求流水。
    wire blocked_six;
    // 要求至少六条待发、五项窗口全忙、窗外有空闲项，并且没有前拍遗留请求。
    // 这些条件共同隔离“第六条虽匹配却不能越过受阻窗口”的场景，避免把已在 C3 的请求误判为越窗。
    assign blocked_six = waiting>=6 && (window & idle)==0 && (pool & ~window & idle)!=0 && !m_attempt;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            retry_selected<=0;refill_selected<=0;nonhead_refill_selected<=0;
            last_retry_addr<=0;last_refill_addr<=0;last_retry_req<=0;last_refill_req<=0;
            blocked_streak<=0;issue_streak<=0;
        end else begin
            // 这里保存的是本拍事件，下一拍 cover 才能把实际 req/地址与保存 token 的地址对应起来。
            // 当前失败项在同拍 C2 又被选中时置位，下一拍可检查重试没有人为插入气泡。
            retry_selected<=m_attempt && !issue_fire && select_valid && select_e==m_attempt_e;
            // 本拍确有成功，且预选项旧排名为 5，表示原第六条在成功当拍补入并被选中。
            refill_selected<=issue_fire && select_valid && selected_old_rank==5;
            // 再要求成功项之前仍有更老待发项，用于区分窗口非队头成功后的补位场景。
            nonhead_refill_selected<=issue_fire && select_valid && selected_old_rank==5 && ranks[m_attempt_e]!=0;
            // 保存当前 C3 请求的负载，下一拍与重试请求比较；不保存本拍刚选出的另一条命令。
            last_retry_addr<=expected_addr;last_retry_req<=expected_req;
            // 补窗场景则记录本拍 C2 新选中事务，供下一拍检查是否真的从 C3 发出。
            last_refill_addr<=m_addr[select_e][17:6];
            // 从同一新选中事务译出 Bank 请求，和上面的地址保持配对。
            last_refill_req<=8'b1<<m_addr[select_e][5:3];
            // blocked_streak 计连续受阻拍，issue_streak 计连续成功拍；条件中断即清零。
            // 采用饱和计数仅为避免长序列回绕，不表示对业务时长增加了限制。
            if(blocked_six) begin if(blocked_streak!=7)blocked_streak<=blocked_streak+1'b1;end
            else blocked_streak<=0;
            if(issue_fire) begin if(issue_streak!=15)issue_streak<=issue_streak+1'b1;end
            else issue_streak<=0;
        end
    end
