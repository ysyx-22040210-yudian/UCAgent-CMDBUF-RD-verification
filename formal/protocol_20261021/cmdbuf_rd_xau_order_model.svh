// 此文件在 sources[g] 内引用，每个 XAU 各有一套本地接收 FIFO；不观察 DUT 内部。
// 独立 FIFO：source_ar 入队；只有 source_r 才出队。
// oldest 指向最早接受且尚未返回的命令，与发射/MEM 返回顺序无关。
// 命令3先到 OTB 不能移动队头；同拍出入时，新项追加到剩余项之后。
// order_phase 仅记录 cover：0等待三项，1等待3先发，2等待3先捕获，
// 3等待R1，4等待R2，5等待R3；它不约束 DUT 或环境。

        // 【RR 等待预算】只统计本源持续 eligible 期间，其他源实际完成的响应次数。
        // 本源资格中断或已轮到本源时归零；空闲时钟不计数，最多两次其他响应后必须轮到本源。
        reg [1:0] bypass_count; // 本源持续可响应却被其他源先响应的次数，供 RR 有界公平断言使用。
        always @(posedge clk or negedge rst_n)
            if(!rst_n) bypass_count<=0;
            else if(!eligible[g] || rvalid[g]) bypass_count<=0;
            else if(r_fire) bypass_count<=bypass_count+1'b1;

        // [REF_MODEL] FIFO 只记录 AR 接收顺序，不记录下游发射顺序。
        // 本源 AR 真正握手才入队，本源 R 真正握手才出队；发射/MEM 事件都不出队。
        // 保存的是检查器本地 token，既不是 arid 也不是 DUT 物理 entry 编号。
        // 对各源单独比较队头整组负载，不靠跨源 RR 选择来定义源内顺序。
        // 【独立顺序记录】order_count 是已接受、尚未本源 R 回收的命令数，不是已完成数。
        // order_slot[0] 是队头，其后按 AR 接受先后保存；数组大小为共享上限，合法单源占用最多 7。
        reg [3:0] order_count; // 本源独立接收 FIFO 的有效长度，仅真实 AR/R 握手改变它。
        reg [3:0] order_slot [0:8]; // 本源按 AR 接收先后排列的参考 token；0 为最老未回收项。
        // 入队条件包含所选 arready；仅 arvalid 拉高而没有握手不能加入 FIFO。
        wire source_ar; // 本拍是否真正接收本源 AR，即本源 FIFO 入队事件。
        // 全局 AR 真正握手且 src 指向当前展开来源 g，才让这个来源的接收 FIFO 入队一次。
        assign source_ar = ar_fire && src==g;
        // 出队必须是本源的真实握手；其他源的响应不会改变此 FIFO。
        wire source_r; // 本拍是否真正返回本源 R，即本源 FIFO 出队事件。
        // 只检查来源 g 自己的 R 握手；其他来源返回不会弹出本源 FIFO 的队头。
        assign source_r = rvalid[g] && rready[g];
        // 队头 token 的意义与 ID 无关；只有 oldest_valid 为真时它才指向有效的本源事务。
        // 空队列中的默认 token=0 不能被当作一条真实命令。
        wire [3:0] oldest; // 本源独立 FIFO 队头的参考槽号，与下游发射顺序无关。
        // 固定取接收 FIFO 的第 0 项，按 AR 接收先后决定队头，不按成功发射或 MEM 到达先后选择。
        assign oldest = order_slot[0];
        wire oldest_valid; // 队列非空、token 合法，且该 token 仍是本源有效事务。
        // 同时检查 FIFO 非空、token 在 0..8、对应事务仍有效且来源匹配，避免空队列默认值或陈旧 token 被当成队头。
        assign oldest_valid = order_count!=0 && oldest<9 &&
                            m_live[oldest] && m_src[oldest]==g;
        // 针对同一个 oldest 计算状态，优先级与共享 R 检查一致；不读取当前 MEM pc_err。
        wire [1:0] oldest_resp; // 本源 FIFO 队头的预期错误状态，越界优先于校验异常。
        // 从独立 FIFO 队头保存的 arresp/pc_err 合成响应状态，保持地址越界高于奇偶校验异常的优先级。
        assign oldest_resp = m_err[oldest]==2'b11 ? 2'b11 :
                                (m_pc[oldest] ? 2'b01 : 2'b00);
        // 一次比较五类负载：低地址、ID、port、128 位数据、错误状态，必须全部来自同一个队头。
        // 此信号供 cover 记录正确返回；各字段另有独立 assert，便于从失败标签定位错误字段。
        wire head_payload_matches; // R 的五类负载是否都属于本源 FIFO 队头，供完整业务见证使用。
        // 先确认 FIFO 队头有效，再一次比较 raddr、rid、port_id、128 位数据、rresp 是否全部属于它。
        // 重复 ID 也不会混淆顺序，因为比较对象由 AR 接收 token 决定，并同时核对整组负载。
        assign head_payload_matches = oldest_valid &&
            {raddr,rid,r_port_id,rdata,rresp} ==
            {m_addr[oldest][2:0],m_id[oldest],m_port[oldest],m_data[oldest],oldest_resp};
        integer qi; // 时序移位循环的队列位置，0 为本源接收 FIFO 队头。
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                order_count<=0;
                for(qi=0;qi<9;qi=qi+1) order_slot[qi]<=0;
            end else begin
                // 同拍既入又出时长度不变；只入加一，只出减一；发射成功和 MEM 返回都不改变长度。
                order_count<=order_count+{3'b0,source_ar}-{3'b0,source_r};
                // 旧队头真正返回后才左移剩余项；年轻完成项继续留在原相对位置。
                if(source_r) begin
                    for(qi=0;qi<8;qi=qi+1) order_slot[qi]<=order_slot[qi+1];
                    order_slot[8]<=0;
                end
                // 同时出入时写入下标 order_count-1，也就是左移后剩余队列的末尾。
                // 例如 [A,B,C] 同拍返回 A 并接收 D，下一状态必须是 [B,C,D]。
                // 如果旧队列只有 A，新 D 可复用它的 token，但仍代表新的事务且元数据已重写。
                // 同拍出入时，新事务追加到全部剩余老事务之后。
                if(source_ar && order_count>=source_r &&
                   (order_count-{3'b0,source_r})<9)
                    order_slot[order_count-{3'b0,source_r}]<=alloc_e;
            end
        end

        // [REF_MODEL] 业务见证：接收 1/2/3，3 先发射与捕获，R 再按 1/2/3 返回。
        // 每次返回都比较 token 和整组负载，不能仅用一次 rid 匹配表示保序。
        // 这是找轨迹的监视器，不要求每条输入轨迹都走此场景，也不约束环境。
        // 【覆盖状态机】phase 不是 DUT 状态，也不决定合法响应；assert 仍检查所有业务轨迹。
        // 0 等待至少三条未发射项；1 等待 3 先发；2 等待 3 先捕获；3/4/5 等待 R1/R2/R3。
        // first/second/third_token 在启动见证时固定，后续 FIFO 左移不会改变被跟踪的事务。
        reg [2:0] order_phase; // 0..5 的覆盖跟踪阶段，含义见上方状态转移说明。
        reg [3:0] first_token;  // 覆盖启动时本源第一条命令的参考槽号，等待最先 R 返回。
        reg [3:0] second_token; // 覆盖启动时本源第二条命令的参考槽号，等待第二次 R 返回。
        reg [3:0] third_token;  // 覆盖启动时本源第三条命令的参考槽号，应先发射/捕获、最后 R 返回。
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                order_phase<=0; first_token<=0; second_token<=0; third_token<=0;
            end else begin
                case(order_phase)
                    // 启动条件：FIFO 最老三项都尚未发射，且本拍没有本源出队，避免启动时事务已经切换。
                    0: if(order_count>=3 &&
                          !m_sent[order_slot[0]] && !m_sent[order_slot[1]] &&
                          !m_sent[order_slot[2]] && !source_r) begin
                        first_token<=order_slot[0]; second_token<=order_slot[1];
                        third_token<=order_slot[2]; order_phase<=1;
                    end
                    // 要求 3 在 1/2 仍未成功发射时先成功；若 1/2 先发或已有本源响应，本次见证作废重找。
                    1: begin
                        if(source_r) order_phase<=0;
                        else if(issue_fire && m_attempt_e==third_token &&
                                !m_sent[first_token] && !m_sent[second_token])
                            order_phase<=2;
                        else if(issue_fire && (m_attempt_e==first_token || m_attempt_e==second_token))
                            order_phase<=0;
                    end
                    // 要求 3 的四拍返回到期时 1/2 仍未完成；该到期沿后 m_done[third_token] 才置位。
                    2: begin
                        if(source_r) order_phase<=0;
                        else if(mem_capture_due && mem_capture_slot==third_token &&
                                !m_done[first_token] && !m_done[second_token])
                            order_phase<=3;
                    end
                    // 3/4 阶段分别消费一次真实 R，并核对当前 oldest 是预定的 1/2，且整组负载相符。
                    // 若出现不匹配，监视器回到 0；不能把重启当作通过，端口 assert 会独立报告违规。
                    3: if(source_r)
                        order_phase<=(oldest==first_token && head_payload_matches)?3'd4:3'd0;
                    4: if(source_r)
                        order_phase<=(oldest==second_token && head_payload_matches)?3'd5:3'd0;
                    // R3 到来的当前采样拍，主文件 C_XAU_R_123_AFTER_ISSUE3_FIRST 检查 phase=5 并命中。
                    // 这个沿后才重置 phase，因此不会在 cover 采样前丢失完整返回链的最后一拍。
                    5: if(source_r) order_phase<=0;
                    default: order_phase<=0;
                endcase
            end
        end
