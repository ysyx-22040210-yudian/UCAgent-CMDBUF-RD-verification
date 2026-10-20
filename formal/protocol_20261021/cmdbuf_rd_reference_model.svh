// 【事务参考模型说明】
// 此文件在主检查模块内部引用，不是另一个 DUT；所有记录均为验证侧逻辑状态。
// 参考模型只读顶层端口，不读 DUT entry、窗口、选择结果或 done 标记。
// m_live/m_sent/m_done = 已接收 / 已成功发射 / 已捕获 MEM。
// m_age = 全局接收年龄排名；0 最老。m_* 不是 DUT 层次路径。
// m_due/m_due_e = 固定 4 拍返回日历；m_attempt/m_attempt_e = 请求流水项。
// head/eligible = 各源最老事务 / 已完成且 ready；m_rr = 下次 RR 起点。
// pending -> pool -> window -> candidate -> selected 是预选组合计算。
// 成功当拍从 pool 扣除、补入原第 6 项；失败不扣除，可立即重选。

    // 生命周期：AR 接受 -> 有效待发 -> 双 grant 后已发射 -> MEM 捕获后完成 -> R 回收。
    // m_live：接收至 R 返回期间保持 1；m_sent：成功后保持 1，使其退出待发窗口。
    // m_done：四拍后捕获数据时置 1；m_pc：与该次数据一起保存的 pc_err。
    // 这四个位向量下标都是本地逻辑槽，不能据此推断 DUT 内部物理编号或清零实现。
    reg [8:0] m_live, m_sent, m_done, m_pc;
    // 四级有效位管线只接受 issue_fire；每次成功至多一条，所以到期拍最多捕获一组数据。
    // 配套 m_due_e 携带逻辑 token，解决不同 XAU、不同 Bank 的返回归属问题。
    reg [3:0] m_due;
    // 年龄用连续排名表示：0 最老，新接收项放到末尾；不复制 DUT 的成对年龄矩阵。
    // 模型槽选最低可用编号仅为存储方便，同一条事务在 DUT 中可以使用不同物理编号。
    // 以下元数据在 AR 真正接受时一次保存，直到该事务 R 回收才允许覆盖。
    // m_err 保存 AR 越界状态，m_pc 保存 MEM 校验状态，二者优先级在响应时合成。
    reg [17:0] m_addr [0:8];
    reg [1:0] m_src [0:8], m_err [0:8];
    reg [7:0] m_id [0:8];
    reg [4:0] m_port [0:8];
    // m_age 是全局未返回事务的接收排名；发射乱序不会改变这个相对年龄。
    reg [3:0] m_age [0:8];
    // 每个逻辑槽保存完整返回数据；年轻事务可先捕获，并在这里等待老事务 R 完成。
    reg [127:0] m_data [0:8];
    // 下次 RR 扫描的起点：复位为 0；响应成功后设为 winner 的下一来源，循环 0/1/2。
    reg [1:0] m_rr;
    // 当前对外请求的预测流水：上一拍 selected 在沿后成为 m_attempt/m_attempt_e。
    // 同拍预选与当前仲裁并行，不会因为当前失败而强制插入一拍气泡。
    reg m_attempt;
    reg [3:0] m_attempt_e;
    reg [3:0] m_due_e [0:3];
    wire mem_capture_due = m_due[3];
    wire [3:0] mem_capture_slot = m_due_e[3];
    // 组合集合含义：pending=当前所有待发；pool=扣本拍成功后的待发；window=pool 最老五项。
    // idle=各命令对应半区是否空闲；candidate=window 与 idle 交集；selected=其中最老一项。
    reg [8:0] pending, pool, window, idle, candidate, selected;
    reg [3:0] select_e;
    wire select_valid = |selected;
    // head[x] 先从来源 x 的全部有效未返回项中找最老，随后才检查完成状态。
    // 先过滤 done 再找头会把年轻完成项错误地当作队头，从而破坏单 XAU 保序。
    reg [3:0] head [0:2];
    reg [2:0] head_valid, eligible, expected_rvalid;
    // model_retire 表示本模型预测应发生响应；r_fire 表示 DUT 实际公开握手。
    // 期望 RR/回收用 model_retire 推进；二者若不同会由断言报错，避免错误输出带偏期望记录。
    reg model_retire;
    reg [1:0] winner;
    reg [3:0] rsp_e, alloc_e;
    reg free_found;
    reg [2:0] expected_ready;
    // used 统计全部占用，waiting 只统计未成功发射项，occ[x] 统计各源全部占用。
    // 每源至少预留首项，其余共用 6 项；共享消耗是各源超出第一项的部分之和。
    integer used, waiting, shared_cost, quota_cost;
    integer occ [0:2];
    integer after_occ [0:2];
    integer used_after, shared_after;
    integer ranks [0:8];
    integer best_age, scan;
    integer i, j, x, off;

    always @* begin
        // 1. 统计当前占用以及预留预算。
        used = 0; waiting = 0; shared_cost = 0; quota_cost = 0;
        for (x=0; x<3; x=x+1) occ[x] = 0;
        for (i=0; i<9; i=i+1) begin
            if (m_live[i]) begin
                used = used+1;
                if (!m_sent[i]) waiting = waiting+1;
                if (m_src[i]<3) occ[m_src[i]] = occ[m_src[i]]+1;
            end
        end
        // 容量预算：有命令的源按实际占用计算，空源仍计入 1 项预留。
        // 例如 7/0/0 总占用 7 但预算已满；4/4/0 总占用 8 也必须给第三源保留最后一项。
        for (x=0; x<3; x=x+1) begin
            if (occ[x]>0) shared_cost = shared_cost+occ[x]-1;
            quota_cost = quota_cost+((occ[x]>0)?occ[x]:1);
        end
        // 【单源顺序】此处只决定每源最老事务，完成早晚不参与挑选队头。
        // eligible[x] 才把队头完成与 rready[x] 结合，交给后续跨源 RR。
        // 找最老有效队头后，才读取 done 与 ready。
        head_valid = 0; eligible = 0;
        for (x=0; x<3; x=x+1) begin
            head[x] = 0; best_age = 9;
            for (i=0; i<9; i=i+1)
                if (m_live[i] && m_src[i]==x && m_age[i]<best_age) begin
                    head_valid[x]=1; head[x]=i; best_age=m_age[i];
                end
            if (head_valid[x]) eligible[x] = m_done[head[x]] && rready[x];
        end
        // 【跨源选择】按 m_rr、m_rr+1、m_rr+2 顺序取第一个 eligible，最多置一位 expected_rvalid。
        // 某源队头被阻塞不妨碍其他源；没有候选时不响应，顺序状态不推进。
        // 2. 从 RR 起点扫描，最多选择一个可响应队头。
        expected_rvalid=0; winner=0; rsp_e=0; scan=0;
        for (off=0; off<3; off=off+1) begin
            scan=m_rr+off; if(scan>=3) scan=scan-3;
            if (expected_rvalid==0 && eligible[scan]) begin
                expected_rvalid[scan]=1; winner=scan; rsp_e=head[scan];
            end
        end
        if(!rst_n) expected_rvalid=0;
        model_retire = |expected_rvalid;
        // 【同拍回收再接收】after_occ 是本拍预期 R 返回后的占用，允许 AR 使用当拍腾出的容量。
        // 对非空源新增一条需要共享余量；对空源新增首条使用已预留容量。
        // 3. 先计入本拍 R 回收，再计算各源 AR ready 与逻辑分配槽。
        used_after=0; shared_after=0;
        for(x=0;x<3;x=x+1) begin
            after_occ[x]=occ[x]-((model_retire && winner==x)?1:0);
            used_after=used_after+after_occ[x];
            if(after_occ[x]>0) shared_after=shared_after+after_occ[x]-1;
        end
        expected_ready=0;
        for(x=0;x<3;x=x+1)
            expected_ready[x]=rst_n && used_after<9 &&
                               (after_occ[x]==0 || shared_after<6);
        // alloc_e 在本地事务表选择首个空槽，或选本拍回收的 rsp_e，实现满载同拍复用。
        // 这里不要求新命令与返回命令同源，仍以各源 expected_ready 判定接收资格。
        alloc_e=0; free_found=0;
        for(i=0;i<9;i=i+1)
            if(!free_found && (!m_live[i] || (model_retire && rsp_e==i))) begin
                free_found=1; alloc_e=i;
            end
        // 【五项窗口】窗口只含尚未成功发射的最老五项，而不是最老五项未释放 entry。
        // AR 新输入先保存，下一阶段才进入预选；不能绕过 C1 接收/C2 判断/C3 请求的流水。
        // 4. 只从最老五条未成功发射命令中筛选空闲半区，再选最老。
        pending=m_live & ~m_sent;
        pool=pending;
        // 成功后把当前请求从 pool 扣掉，同一拍重新计算排名，因此原第六条可立即补入预选。
        // 例：A/B/C/D/E 中 C 成功，下一预选窗口是 A/B/D/E/F。
        // 没有选中或仲裁失败时不扣条目，不允许通过轮换窗口绕过受阻的最老五项。
        // 6B：只在本拍成功时从候选排名池移除当前请求。
        if(issue_fire && m_attempt_e<9) pool[m_attempt_e]=0;
        window=0; idle=0; candidate=0; selected=0; select_e=0;
        for(i=0;i<9;i=i+1) begin
            ranks[i]=0;
            for(j=0;j<9;j=j+1)
                if(pool[j] && m_age[j]<m_age[i]) ranks[i]=ranks[i]+1;
            window[i]=pool[i] && ranks[i]<5;
            // 物理映射固定：保存地址 [5:3] 是 Bank 0..7，地址 [6] 是该 Bank 的奇偶半区。
            // 先用状态找全部空闲候选，再按 m_age 找最老；不能只看全局队头空闲与否。
            idle[i]=!rd_mem_status[m_addr[i][5:3]][m_addr[i][6]];
            // 失败项保留年龄；若仍命中空闲状态，本拍可再次被选中。
            candidate[i]=window[i] && idle[i];
        end
        // 最多九条事务的合法年龄是 0..8，9 作为未找到候选的哨兵。
        // 只在 candidate 集合内比较 m_age，不让窗口外的空闲命令插队。
        best_age=9;
        for(i=0;i<9;i=i+1)
            if(candidate[i] && m_age[i]<best_age) begin
                best_age=m_age[i]; select_e=i;
            end
        if(best_age<9) selected[select_e]=1;
    end

    integer e,k;
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

    // 预期 req/地址取自请求流水 token，不取自当前预选命令或当前 AR 输入。
    // 无请求时模型给地址默认值仅为计算方便，A_ARB_ADDR 明确不检查无效地址。
    wire [7:0] expected_req=(rst_n && m_attempt)?(8'b1<<m_addr[m_attempt_e][5:3]):8'd0;
    wire [11:0] expected_addr=(rst_n && m_attempt)?m_addr[m_attempt_e][17:6]:12'd0;
    // 错误优先级只用响应事务保存的信息：AR 越界 11 优先，其次 MEM 校验 01，否则正常 00。
    wire [1:0] expected_resp=(m_err[rsp_e]==2'b11)?2'b11:(m_pc[rsp_e]?2'b01:2'b00);


    // [REF_MODEL] 以下状态只用于记录覆盖见证，不增加输入约束。
    // cover 在 E06 环境契约下寻找业务见证，不能替代 assert。
    // 下列寄存器是 cover 的历史记录，不用于约束输入，也不决定 DUT 应产生的行为。
    // retry_selected 记住失败重选；refill_selected 记住原第六条补入；nonhead 再限定成功项非队头。
    reg retry_selected, refill_selected, nonhead_refill_selected;
    reg [11:0] last_retry_addr, last_refill_addr;
    reg [7:0] last_retry_req, last_refill_req;
    reg [2:0] blocked_streak;
    // 此计数器仅依赖 issue_fire 历史，供 NO_REF_MODEL_HISTORY 覆盖使用；不依赖事务表。
    reg [3:0] issue_streak;
    integer selected_old_rank;
    integer c;
    always @* begin
        // 用成功扣减之前的 pending 计算选中项旧排名：5 表示原第六条，而非新窗口内排名。
        selected_old_rank=0;
        for(c=0;c<9;c=c+1)
            if(pending[c] && m_age[c]<m_age[select_e]) selected_old_rank=selected_old_rank+1;
    end
    // 要求窗口完全不匹配、窗口外至少一项空闲且当前没有已发出的流水请求。
    // 这样记录的是五项窗口被阻塞的状态，而非把上一拍已预选请求误认为窗口越界。
    wire blocked_six=waiting>=6 && (window & idle)==0 && (pool & ~window & idle)!=0 && !m_attempt;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            retry_selected<=0;refill_selected<=0;nonhead_refill_selected<=0;
            last_retry_addr<=0;last_refill_addr<=0;last_retry_req<=0;last_refill_req<=0;
            blocked_streak<=0;issue_streak<=0;
        end else begin
            // 这里保存的是本拍事件，下一拍 cover 才能把实际 req/地址与保存 token 的地址对应起来。
            retry_selected<=m_attempt && !issue_fire && select_valid && select_e==m_attempt_e;
            refill_selected<=issue_fire && select_valid && selected_old_rank==5;
            nonhead_refill_selected<=issue_fire && select_valid && selected_old_rank==5 && ranks[m_attempt_e]!=0;
            last_retry_addr<=expected_addr;last_retry_req<=expected_req;
            last_refill_addr<=m_addr[select_e][17:6];
            last_refill_req<=8'b1<<m_addr[select_e][5:3];
            // blocked_streak 计连续受阻拍，issue_streak 计连续成功拍；条件中断即清零。
            // 采用饱和计数仅为避免长序列回绕，不表示对业务时长增加了限制。
            if(blocked_six) begin if(blocked_streak!=7)blocked_streak<=blocked_streak+1'b1;end
            else blocked_streak<=0;
            if(issue_fire) begin if(issue_streak!=15)issue_streak<=issue_streak+1'b1;end
            else issue_streak<=0;
        end
    end
