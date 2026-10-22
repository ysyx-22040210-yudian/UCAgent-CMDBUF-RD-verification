// 自动整理的可读原生 SVA；定义源为本目录 build_catalog.py 的显式表达式表。
// 测试点与前提来自 docs/testpoints/corner_20261021/catalog.json。
// 不含复位场景、X/Z 场景；disable iff 仅禁用属性，不建立初态。
`include "cmdbuf_rd_corner_history.svh"
`include "cmdbuf_rd_corner_assertions.svh"
`include "cmdbuf_rd_corner_sequences.svh"

// ==================== AR-01 空表首次接收 ====================
// 前提：N=(0,0,0)，rst_n=1，无 R
// 操作：arvalid=1，依次覆盖 src=0/1/2
// 应检查：arready=111；仅 src 对应计数加 1；一次只分配一项
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_01_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==0 && !r_fire && ar_fire && src==0 && arready==7
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_01_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==0 && !r_fire && ar_fire && src==1 && arready==7
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_01_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==0 && !r_fire && ar_fire && src==2 && arready==7
);

// ==================== AR-02 无请求时切换 src ====================
// 前提：任一合法占用，无 R
// 操作：arvalid=0；src 在 0/1/2/3 之间切换
// 应检查：不接收命令；占用不变；ready 不应由 src 变化而变化
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_02_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    !h_prev_valid && !arvalid && !h_prev_r && !r_fire && h_prev_n==used && src==0 && src!=h_prev_src && arready==h_prev_ready
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_02_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    !h_prev_valid && !arvalid && !h_prev_r && !r_fire && h_prev_n==used && src==1 && src!=h_prev_src && arready==h_prev_ready
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_02_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    !h_prev_valid && !arvalid && !h_prev_r && !r_fire && h_prev_n==used && src==2 && src!=h_prev_src && arready==h_prev_ready
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_02_S3: cover property (
    @(posedge clk) disable iff (!rst_n)
    !h_prev_valid && !arvalid && !h_prev_r && !r_fire && h_prev_n==used && src==3 && src!=h_prev_src && arready==h_prev_ready
);

// ==================== AR-03 选中可接收来源 ====================
// 前提：arready 非零，所选 src 的位为 1
// 操作：arvalid=1，src=0/1/2
// 应检查：A=1；只采样该拍共享负载并归属 src
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_03_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire && src==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_03_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire && src==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_03_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire && src==2
);

// ==================== AR-04 选中被阻塞来源 ====================
// 前提：例如 N=(7,0,0)，无 R，ready=110
// 操作：arvalid=1，src=0
// 应检查：A=0；不分配、不增加占用、不把请求加入年龄序列
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[0]==7 && occ[1]==0 && occ[2]==0 && !r_fire && arvalid && src==0 && !ar_fire && arready==6
);

// ==================== AR-05 被阻塞后切换来源 ====================
// 前提：N=(7,0,0)，src0 未被接收
// 操作：下一拍换 src1；可同时更换地址、ID 和 port_id
// 应检查：新拍若 ready[1]=1 则只接收新请求；前一拍不形成事务
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_05_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_n==7 && h_prev_valid && !h_prev_a && h_prev_src==0 && h_prev_ready==6 && ar_fire && src==1 && araddr!=h_prev_addr && arid!=h_prev_id && ar_port_id!=h_prev_port
);

// ==================== AR-06 同源连续接收 ====================
// 前提：有容量且每拍所选 ready=1
// 操作：连续数拍 arvalid=1、src 相同，负载每拍变化
// 应检查：每拍独立接收；年龄按握手拍排序；无 valid 下降沿要求
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_same_ar_run>=2 && ar_fire && src==h_prev_src && arid!=h_prev_id && ar_port_id!=h_prev_port
);

// ==================== AR-07 不同源连续切换 ====================
// 前提：有容量
// 操作：src 按 0→2→1→0 切换，每拍实际握手
// 应检查：三路分别计数与保序；共享 AR 每拍仍最多一单
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_07_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_a_history[2:0]==3'b111 && h_src_history==6'b001001 && ar_fire && src==0
);

// ==================== AR-08 全不 ready 时空拍 ====================
// 前提：N=9 且无 R
// 操作：arready=000，环境令 arvalid=0，src 任意
// 应检查：不接收；src 不决定何时恢复 ready；恢复取决于实际 R
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_08_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && !r_fire && arready==0 && !arvalid
);

// ==================== AR-09 全不 ready 仍拉 valid ====================
// 前提：arready=000
// 操作：注入 arvalid=1
// 应检查：违反输入约束 E05；不能作为合法业务反例；单独检查约束监测
// 此行不添加伪覆盖：关闭 E05 后，用 N_AR_09 cover / V_AR_09 assert 检查环境违规见证。

// ==================== AR-10 有效请求 src=3 ====================
// 前提：arvalid=1
// 操作：src=2'b11
// 应检查：违反 E03；不能分配给不存在的第四路；无合法业务承诺
// 此行不添加伪覆盖：关闭 E03 后，用 N_AR_10 cover / V_AR_10 assert 检查环境违规见证。

// ==================== AR-11 AR 无效负载任意变化 ====================
// 前提：arvalid=0
// 操作：地址、arid、port_id、arresp 改变
// 应检查：不采样这些字段；不得改变当前事务内容
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_11_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    !h_prev_valid && !arvalid && used>0 && araddr!=h_prev_addr && arid!=h_prev_id && ar_port_id!=h_prev_port
);

// ==================== AR-12 相同负载重复握手 ====================
// 前提：两次 AR 地址、ID、port_id 完全相同
// 操作：两拍分别 A=1
// 应检查：是两条不同事务；占两项；每条分别发射和响应
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_12_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_a && ar_fire && src==h_prev_src && araddr==h_prev_addr && arid==h_prev_id && ar_port_id==h_prev_port
);

// ==================== AR-13 本拍 src 不直接决定 ready ====================
// 前提：固定 N、R，选择不同合法 src
// 操作：仅切换 src，保持 rready 与完成状态不变
// 应检查：ready 三位保持相同；只有 A 的来源和下一拍占用可变
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_13_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    !h_prev_a && !ar_fire && !h_prev_r && !r_fire && h_prev_n==used && src!=h_prev_src && arready==h_prev_ready && used>0
);

// ==================== AR-14 本拍 valid 不直接决定 ready ====================
// 前提：固定 N 与 R
// 操作：arvalid 在 0/1 间改变，遵守全零 ready 约束
// 应检查：ready 本拍不变；不允许由 A 反推 ready 构成环路
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_14_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    !h_prev_a && !h_prev_r && !r_fire && used==h_prev_n && arvalid!=h_prev_valid && arready==h_prev_ready && arready!=0
);

// ==================== AR-15 非采样瞬间的组合变化 ====================
// 前提：时钟边沿前后分别观察
// 操作：rready 变化使 R 胜者改变，再观察 ready 与 AR 握手
// 应检查：用上升沿稳定值定义 A/R；ready 是组合输出，不要求整拍恒定
// 此行不添加伪覆盖：posedge SVA 只检查采样值；边沿之间的组合毛刺/稳定时间需要时序或仿真检查。

// ==================== AR-16 有效时字段的边界值 ====================
// 前提：每个 src 有容量
// 操作：araddr=0/18'h3ffff，arid=0/255，port_id=0/31，并遍历 raddr 0..7
// 应检查：有效负载位宽不截断；返回所属事务字段；地址越界由 arresp 指示
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_S0_EXT0: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_src[rsp_e]==0 && m_addr[rsp_e]==18'h00000 && rid==0 && r_port_id==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_S0_EXT1: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_src[rsp_e]==0 && m_addr[rsp_e]==18'h3ffff && rid==255 && r_port_id==31
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_S1_EXT0: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_src[rsp_e]==1 && m_addr[rsp_e]==18'h00000 && rid==0 && r_port_id==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_S1_EXT1: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_src[rsp_e]==1 && m_addr[rsp_e]==18'h3ffff && rid==255 && r_port_id==31
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_S2_EXT0: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_src[rsp_e]==2 && m_addr[rsp_e]==18'h00000 && rid==0 && r_port_id==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_S2_EXT1: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_src[rsp_e]==2 && m_addr[rsp_e]==18'h3ffff && rid==255 && r_port_id==31
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_LOW0: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && raddr==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_LOW1: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && raddr==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_LOW2: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && raddr==2
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_LOW3: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && raddr==3
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_LOW4: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && raddr==4
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_LOW5: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && raddr==5
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_LOW6: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && raddr==6
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_16_LOW7: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && raddr==7
);

// ==================== AR-17 AR 与 R 来源相同 ====================
// 前提：该源旧队头可响应，当前有容量或可回收
// 操作：同拍 R_s=1、A_s=1
// 应检查：N_s 不变；旧头弹出，新命令放到该源末尾
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_17_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire && r_fire && src==winner && h_response_matches
);

// ==================== AR-18 AR 与 R 来源不同 ====================
// 前提：源 s 响应，源 t 的 ready[t]=1
// 操作：同拍 R_s=1、A_t=1，s≠t
// 应检查：总 N 不变；N_s 减 1、N_t 加 1；逐源顺序不串扰
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_18_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire && r_fire && src!=winner && h_response_matches
);

// ==================== AR-19 R 已发生但所选源不能接收 ====================
// 前提：例如 (4,4,1) 本拍 R2，ready=100
// 操作：arvalid=1、src0 或 src1
// 应检查：R 仍正常回收，AR 不接收，总占用由 9 降到 8
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_19_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[0]==4 && occ[1]==4 && occ[2]==1 && rvalid==4 && arvalid && src<2 && !ar_fire && arready==4
);

// ==================== AR-20 没有上游公平保证 ====================
// 前提：ready 至少一位有效，某一路持续有需求
// 操作：上游长期只选另一路或被阻塞的 src
// 应检查：DUT 保留容量许可，但不能保证未被送到共享 AR 的请求最终接收
// 覆盖边界：只见证连续阻塞选择；共享端口无各源 pending 信号，不能证明上游公平性。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_AR_20_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_valid && !h_prev_a && arvalid && !ar_fire && arready!=0 && src==h_prev_src
);

// ==================== CAP-01 总量 0 到 6 ====================
// 前提：任意合法分配，N≤6
// 操作：无 R，查询三个 ready
// 应检查：ready=111；所有来源均可再收一项
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_01_N0: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total==0 && !r_fire && arready==7
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_01_N1: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total==1 && !r_fire && arready==7
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_01_N2: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total==2 && !r_fire && arready==7
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_01_N3: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total==3 && !r_fire && arready==7
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_01_N4: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total==4 && !r_fire && arready==7
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_01_N5: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total==5 && !r_fire && arready==7
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_01_N6: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total==6 && !r_fire && arready==7
);

// ==================== CAP-02 单源从 6 到 7 ====================
// 前提：N=(6,0,0)，无 R
// 操作：src0 握手一次
// 应检查：本拍 ready=111；下一拍 (7,0,0)、ready=110
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_02_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_occ[0]==6 && h_prev_occ[1]==0 && h_prev_occ[2]==0 && h_prev_a && h_prev_src==0 && !h_prev_r && occ[0]==7 && !r_fire && arready==6
);

// ==================== CAP-03 单源七项被限制 ====================
// 前提：N=(7,0,0)，无 R
// 操作：持续向 src0 请求
// 应检查：不得接收第 8 项；src1/2 仍各可接收首项
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_03_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[0]==7 && occ[1]==0 && occ[2]==0 && !r_fire && arvalid && src==0 && !ar_fire && arready==6
);

// ==================== CAP-04 总量七项但多源有数据 ====================
// 前提：例如 (6,1,0)、(5,1,1)
// 操作：无 R
// 应检查：ready=111；不能把所有 N=7 都按单源七项处理
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==7 && ((occ[0]>0)+(occ[1]>0)+(occ[2]>0))>=2 && !r_fire && arready==7
);

// ==================== CAP-05 总量八项且一源为空 ====================
// 前提：例如 (7,1,0)、(4,4,0)
// 操作：无 R，各 src 尝试
// 应检查：ready=100；空源的保留首项可接收，已有源不可增长
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_05_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==8 && occ[0]>0 && occ[1]>0 && occ[2]==0 && !r_fire && arready==4
);

// ==================== CAP-06 总量八项且三源非空 ====================
// 前提：例如 (6,1,1)、(3,3,2)
// 操作：无 R
// 应检查：ready=111；任何一源可使用最后一项
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==8 && occ[0]>0 && occ[1]>0 && occ[2]>0 && !r_fire && arready==7
);

// ==================== CAP-07 总量九项无回收 ====================
// 前提：任意合法满载分布，三源均非空
// 操作：R=0
// 应检查：ready=000；arvalid 必须为 0
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_07_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && !r_fire && arready==0 && !arvalid
);

// ==================== CAP-08 满表回收多项源 ====================
// 前提：(7,1,1) 中 R0，或 (4,4,1) 中 R0/R1
// 操作：本拍 R=1
// 应检查：回收后共享额度减少 1，本拍 ready=111
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_08_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && r_fire && occ[winner]>1 && arready==7
);

// ==================== CAP-09 满表回收唯一项源 ====================
// 前提：(4,4,1) 中 R2
// 操作：本拍尝试三种 src
// 应检查：ready=100；仅回收源可重填，不可借走其首项名额
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_09_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && r_fire && winner==0 && occ[0]==1 && arready==(3'b1<<0)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_09_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && r_fire && winner==1 && occ[1]==1 && arready==(3'b1<<1)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_09_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && r_fire && winner==2 && occ[2]==1 && arready==(3'b1<<2)
);

// ==================== CAP-10 满表同源出入保持九项 ====================
// 前提：有效 R 且 AR 选择 ready 源
// 操作：R 与 AR 同拍
// 应检查：N_next=9；满表必须复用刚退役物理项，旧响应仍正确
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_10_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && ar_fire && r_fire && src==winner && h_response_matches
);

// ==================== CAP-11 单源七项回收并重填 ====================
// 前提：N=(7,0,0)，本拍 R0
// 操作：同拍 AR src0
// 应检查：ready=111；N_next=(7,0,0)，下一拍无 R 时回到 110
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_11_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[0]==7 && occ[1]==0 && occ[2]==0 && rvalid==1 && ar_fire && src==0 && arready==7
);

// ==================== CAP-12 八项两源回收多项源 ====================
// 前提：N=(7,1,0)，本拍 R0
// 操作：三种 src 分别尝试
// 应检查：ready=111；释放一个共享名额，可由任一源使用
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_12_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[0]==7 && occ[1]==1 && occ[2]==0 && rvalid==1 && arready==7
);

// ==================== CAP-13 八项两源回收单项源 ====================
// 前提：N=(7,1,0)，本拍 R1
// 操作：三种 src 分别尝试
// 应检查：回收后 (7,0,0)，ready=110；src0 仍不可加项
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_13_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[0]==7 && occ[1]==1 && occ[2]==0 && rvalid==2 && arready==6
);

// ==================== CAP-14 总量不变但 ready 改变 ====================
// 前提：N=(6,1,1)，R1 与 AR0 同拍
// 操作：从 (6,1,1) 变为 (7,0,1)
// 应检查：两拍总量均为 8；下一拍无 R 时 ready 从 111 变 010
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_14_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_occ[0]==6 && h_prev_occ[1]==1 && h_prev_occ[2]==1 && h_prev_r && h_prev_rsrc==1 && h_prev_a && h_prev_src==0 && occ[0]==7 && occ[1]==0 && occ[2]==1 && !r_fire && arready==2
);

// ==================== CAP-15 总量下降但原源仍被挡 ====================
// 前提：N=(7,1,0)，R1，AR0 未接收
// 操作：下一拍继续 src0 请求
// 应检查：总量从 8 降到 7，src0 ready 仍为 0
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_15_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_occ[0]==7 && h_prev_occ[1]==1 && h_prev_occ[2]==0 && h_prev_r && h_prev_rsrc==1 && !h_prev_a && occ[0]==7 && used==7 && !r_fire && arvalid && src==0 && !ar_fire
);

// ==================== CAP-16 最后一项回收后可换源 ====================
// 前提：N=(1,0,0)，R0
// 操作：同拍接收 src1 或 src2
// 应检查：ready=111；旧源归零，新源一项，总量保持 1
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_16_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==1 && r_fire && ar_fire && src!=winner && arready==7
);

// ==================== CAP-17 排空到零 ====================
// 前提：N=1，有效 R，无 AR
// 操作：R 完成后观察下一拍
// 应检查：N_next=0，各源占用全零；释放后 ready=111
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_17_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_n==1 && h_prev_r && !h_prev_a && used==0 && arready==7
);

// ==================== CAP-18 八种 ready 码全部出现 ====================
// 前提：合法 Ni，允许有效 R
// 操作：遍历容量状态与 R 来源
// 应检查：000、001、010、011、100、101、110、111 均有合法容量实例；bit 顺序为 [2:0]
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_18_READY000: cover property (
    @(posedge clk) disable iff (!rst_n)
    arready==0 && used>0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_18_READY001: cover property (
    @(posedge clk) disable iff (!rst_n)
    arready==1 && used>0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_18_READY010: cover property (
    @(posedge clk) disable iff (!rst_n)
    arready==2 && used>0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_18_READY011: cover property (
    @(posedge clk) disable iff (!rst_n)
    arready==3 && used>0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_18_READY100: cover property (
    @(posedge clk) disable iff (!rst_n)
    arready==4 && used>0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_18_READY101: cover property (
    @(posedge clk) disable iff (!rst_n)
    arready==5 && used>0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_18_READY110: cover property (
    @(posedge clk) disable iff (!rst_n)
    arready==6 && used>0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_18_READY111: cover property (
    @(posedge clk) disable iff (!rst_n)
    arready==7 && used>0
);

// ==================== CAP-19 来源对称性 ====================
// 前提：任一合法场景
// 操作：把 0/1/2 的计数、AR 与 R 来源一起置换
// 应检查：ready 置换后一致；容量规则不偏袒编号；R 轮询顺序另受指针影响
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_19_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[0]==7 && used==7 && !r_fire && arready==(3'b111^(3'b1<<0))
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_19_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[1]==7 && used==7 && !r_fire && arready==(3'b111^(3'b1<<1))
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_19_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[2]==7 && used==7 && !r_fire && arready==(3'b111^(3'b1<<2))
);

// ==================== CAP-20 不合法分布 5/4/0 ====================
// 前提：总数 9，各源都不超过 7，但空源无首项余量
// 操作：内部状态强制为 (5,4,0)，或注错让 (4,4,0) 再收 src0
// 应检查：违反 sum(max(Ni,1))≤9；正常 admission 应阻止形成
// 此行不添加伪覆盖：A_CC_READY 与 A_CC_BUDGET 检查错误接收后果；物理强制 5/4/0 需内部注错。

// ==================== CAP-21 不合法单源八项 ====================
// 前提：强制 N=(8,0,0) 或错误接收第八条同源命令
// 操作：检查容量及响应记账
// 应检查：正常协议下不可达；需捕获超额或异常接收
// 此行不添加伪覆盖：A_CC_READY/A_CC_SRC_LIMIT 检查第八项错误接收；物理强制占用需内部注错。

// ==================== CAP-22 非空并不代表可回收 ====================
// 前提：容量表某源 Ni>0，但队头未完成或 rready=0
// 操作：试图选该源作为 R
// 应检查：实际 RTL 不得 R；枚举里的 R 选择仅在队头完成且 ready 时成立
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_22_UNDONE0: cover property (
    @(posedge clk) disable iff (!rst_n)
    head_valid[0] && !m_done[head[0]] && rready[0] && !rvalid[0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_22_NOTREADY0: cover property (
    @(posedge clk) disable iff (!rst_n)
    head_valid[0] && m_done[head[0]] && !rready[0] && !rvalid[0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_22_UNDONE1: cover property (
    @(posedge clk) disable iff (!rst_n)
    head_valid[1] && !m_done[head[1]] && rready[1] && !rvalid[1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_22_NOTREADY1: cover property (
    @(posedge clk) disable iff (!rst_n)
    head_valid[1] && m_done[head[1]] && !rready[1] && !rvalid[1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_22_UNDONE2: cover property (
    @(posedge clk) disable iff (!rst_n)
    head_valid[2] && !m_done[head[2]] && rready[2] && !rvalid[2]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_22_NOTREADY2: cover property (
    @(posedge clk) disable iff (!rst_n)
    head_valid[2] && m_done[head[2]] && !rready[2] && !rvalid[2]
);

// ==================== CAP-23 发射不释放 entry ====================
// 前提：达到容量限制；待发命令仲裁成功
// 操作：无 R，可有 req_success
// 应检查：N 不变，容量不会因 issued 而释放
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_23_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used>=7 && issue_fire && !r_fire && !ar_fire && arready!=7
);

// ==================== CAP-24 MEM 返回不释放 entry ====================
// 前提：达到容量限制；本拍 MEM 返回
// 操作：无 R，允许 pc_err 任意
// 应检查：N 不变；最早下一拍才可能 R 并释放
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CAP_24_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used>=7 && mem_capture_due && !r_fire && !ar_fire && arready!=7
);

// ==================== ENT-01 一次 AR 同时占两表 ====================
// 前提：一次 A=1，有一项可用
// 操作：观察最终响应及内部结构
// 应检查：CMDBUF/OTB 一一对应预留；不能只有一张表分配；端口模型只能查可观察后果
// 覆盖边界：见证完整 AR→I→M→R；物理两表一一对应仍需结构/内部检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_01_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches
);

// ==================== ENT-02 待发项无进展仍保留 ====================
// 前提：Bank 忙，未选中，R 不涉及此项
// 操作：多拍等待
// 应检查：地址/ID/源/port/异常与年龄保持；不因等待覆盖
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_02_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used>0 && waiting>0 && h_quiet_run>=3 && !select_valid && !ar_fire && !r_fire && !issue_fire
);

// ==================== ENT-03 仲裁失败保留年龄 ====================
// 前提：当前 req 对应命令失败
// 操作：后续和新老命令竞争
// 应检查：entry 仍待发，年龄不重置；不重新分配 OTB
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_03_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    retry_selected && req==last_retry_req && arb_addr==last_retry_addr && req!=0
);

// ==================== ENT-04 已发未返回继续占用 ====================
// 前提：I=1 后尚未到 N+4
// 操作：发生其他 AR/R
// 应检查：原项保持 reserved，不参与重发，不可分给新命令
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    (m_live&m_sent&~m_done)!=0 && ar_fire && !r_fire
);

// ==================== ENT-05 已返回未响应继续占用 ====================
// 前提：MEM 已完成，源头阻塞或 rready=0
// 操作：多拍延迟后 R
// 应检查：缓存数据和 pc_err 保持直到该事务实际 R
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_05_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && h_done_wait[rsp_e]>=3
);

// ==================== ENT-06 空闲物理洞再次使用 ====================
// 前提：多项中间某项先 R，其他项存活
// 操作：随后 AR 使用空闲位置
// 应检查：新项年龄为最新，与物理索引大小无关
// 覆盖边界：参考记录在中间空洞重新分配；不限定 DUT 物理槽选择。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire && h_hole_reused && h_total_r>0
);

// ==================== ENT-07 满表同项退役与分配 ====================
// 前提：9 项有效，本拍 R+A
// 操作：同一物理槽交接旧/新事务
// 应检查：旧 R 读旧字段；时钟后新项 valid=1、issued/done=0；数据错误位清理
// 覆盖边界：满表同拍复用的可观察端口行为；不声称证明原始存储位清零。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_07_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && ar_fire && r_fire && alloc_e==rsp_e && h_response_matches
);

// ==================== ENT-08 非满表同拍出入 ====================
// 前提：旧空闲项和本拍退役项都存在
// 操作：R+A
// 应检查：允许实现选择任一合法空闲位置；不能把指定槽号作为外部协议要求
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_08_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used<9 && used>1 && ar_fire && r_fire && h_response_matches
);

// ==================== ENT-09 错误位与数据残留 ====================
// 前提：旧事务 pc_err=1、数据全 1，随后退役
// 操作：同槽新事务正常数据全 0
// 应检查：新 R 为新值及 rresp=00；不能继承旧 done/pc_err
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_09_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && h_clean_reuse[rsp_e] && m_err[rsp_e]==0 && !m_pc[rsp_e] && m_data[rsp_e]==0 && rresp==0
);

// ==================== ENT-10 双重分配 ====================
// 前提：内部强制 alloc 指向尚未退役的有效项
// 操作：继续该项及新项的响应流程
// 应检查：注错应触发结构诊断或丢单/字段断言；不能以模型自检替代物理状态证明
// 此行不添加伪覆盖：双重分配的丢单/串单由 A_REQ/A_R_*/A_XAU_R_* 检查；物理 alloc 冲突不是端口可观察事件。

// ==================== ENT-11 重复完成或重复响应 ====================
// 前提：对同一已完成命令注入重复 done/retire
// 操作：检查 R 计数与逐源队头
// 应检查：每次 AR 只能产生一次 R；不得使占用下溢或重复交付
// 此行不添加伪覆盖：A_CC_R_NONEMPTY/A_XAU_R_* 检查重复响应；重复 done 若未改变外部行为不保证检出。

// ==================== ENT-12 长期槽位复用 ====================
// 前提：多次填满、部分回收，再填满
// 操作：累计事务远多于 9，ID 也重复
// 应检查：年龄关系不受物理槽位和 ID 回绕影响；响应数守恒
// 覆盖边界：至少 20 次接收、12 次返回且曾满表，包含重复 ID；有限轨迹不等于无限运行证明。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENT_12_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total_a>=20 && h_total_r>=12 && h_ever_full && ar_fire && h_duplicate_id
);

// ==================== WIN-01 空表单命令最短路径 ====================
// 前提：空表；Bank 可按协议空闲/变忙；仲裁允许
// 操作：C1 AR，C2 预选，C3 req 并成功
// 应检查：C1/C2 不得提前发射；C3 地址为该命令
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_01_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_a_history[1] && h_prev_n==1 && used==1 && h_selected_prev && issue_fire && h_total_a==1 && h_total_r==0
);

// ==================== WIN-02 连续两条流水 ====================
// 前提：A、B 连续 AR，目标条件允许
// 操作：A 在 C3 req 时同拍预选 B
// 应检查：B 可于 C4 req，不应强制预选空拍
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_02_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_i && issue_fire && h_a_history[2:1]==2'b11
);

// ==================== WIN-03 窗口不足五项 ====================
// 前提：待发数分别 0/1/2/3/4
// 操作：逐项改变 Bank 空闲状态
// 应检查：只在存在的待发项中选；空表无 req；不得读无效槽
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_03_P0: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==0 && !issue_fire && (h_rank_valid>>0)==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_03_P1: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==1 && !issue_fire && (h_rank_valid>>1)==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_03_P2: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==2 && !issue_fire && (h_rank_valid>>2)==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_03_P3: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==3 && !issue_fire && (h_rank_valid>>3)==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_03_P4: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==4 && !issue_fire && (h_rank_valid>>4)==0
);

// ==================== WIN-04 正好五项全部可用 ====================
// 前提：A..E 按年龄排列且目标均空闲
// 操作：C2 选择
// 应检查：发最老 A；跨源也按全局 AR 年龄
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==5 && !issue_fire && h_rank_idle[4:0]==5'b11111 && select_valid && ranks[select_e]==0
);

// ==================== WIN-05 最老忙而次老空闲 ====================
// 前提：窗口 A..E，A 忙，B 空闲
// 操作：C2 选择
// 应检查：选择 B；先按空闲过滤再选最老
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_05_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting>=2 && !issue_fire && !h_rank_idle[0] && h_rank_idle[1] && select_valid && ranks[select_e]==1
);

// ==================== WIN-06 多个非连续候选 ====================
// 前提：窗口 A..E，只有 B/D/E 空闲
// 操作：C2 选择
// 应检查：选择 B；不能跳到 D/E
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting>=5 && !issue_fire && h_rank_idle[4:0]==5'b11010 && select_valid && ranks[select_e]==1
);

// ==================== WIN-07 只有第五项可用 ====================
// 前提：A..D 忙、E 空闲；F 更年轻且也空闲
// 操作：C2 选择
// 应检查：选择 E；窗口上界包含第 5 项
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_07_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting>=6 && !issue_fire && h_rank_idle[5:0]==6'b110000 && select_valid && ranks[select_e]==4
);

// ==================== WIN-08 前五项全忙但第六项空闲 ====================
// 前提：已接收 A..F，A..E 目标忙，F 目标空闲
// 操作：状态保持多拍，未发生成功发射
// 应检查：不下发 F；窗口不因空闲等待而向后滑动
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_08_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    blocked_six && blocked_streak>=3 && req==0 && h_status==h_prev_status
);

// ==================== WIN-09 六到九项窗口仍只取五 ====================
// 前提：已接收 6/7/8/9 项，合法来源分布
// 操作：第 6..9 项目标空闲，前五不可用
// 应检查：这些项都不能越窗；占用多不扩大窗口
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_09_P6: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==6 && blocked_six && blocked_streak>=1 && req==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_09_P7: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==7 && blocked_six && blocked_streak>=1 && req==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_09_P8: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==8 && blocked_six && blocked_streak>=1 && req==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_09_P9: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==9 && blocked_six && blocked_streak>=1 && req==0
);

// ==================== WIN-10 已发项不占待发窗口 ====================
// 前提：若干最老项已 issued，仍保留 entry
// 操作：检查剩余未 issued 命令的排名
// 应检查：取最老五条未成功发射命令，不是最老五条有效项
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_10_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    (m_live&m_sent)!=0 && select_valid && m_age[select_e]>=5 && ranks[select_e]<5
);

// ==================== WIN-11 窗口队头成功后补入 ====================
// 前提：A..E 在窗内，F 在窗外；当前 A req 成功
// 操作：同拍进行下一次预选
// 应检查：新窗 B/C/D/E/F，F 可当拍参与、下一拍 req
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_11_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    refill_selected && !nonhead_refill_selected && req==last_refill_req && arb_addr==last_refill_addr && req!=0
);

// ==================== WIN-12 窗口中间项成功后补入 ====================
// 前提：窗口 A/B/C/D/E，F 在窗外，C 成功
// 操作：当拍更新候选
// 应检查：新窗 A/B/D/E/F；其余相对年龄不变，F 可参与
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_12_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    nonhead_refill_selected && req==last_refill_req && arb_addr==last_refill_addr && req!=0
);

// ==================== WIN-13 仲裁失败窗口不后移 ====================
// 前提：当前窗内命令 req，双 grant 未同位为 1
// 操作：当拍预选及下一拍请求
// 应检查：失败项仍在原年龄位置，第六项不因失败进入
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_13_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting>=6 && req!=0 && !issue_fire && !h_rank_idle[4:0] && h_rank_idle[5] && !select_valid
);

// ==================== WIN-14 单命令失败后连续重试 ====================
// 前提：只有 A 待发，C3 失败且目标在 C3 仍空闲
// 操作：C3 同拍重新选中 A
// 应检查：C4 仍有 A 的 req；不应固定插空拍
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_14_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==1 && retry_selected && req==last_retry_req && arb_addr==last_retry_addr && req!=0
);

// ==================== WIN-15 失败后目标变忙 ====================
// 前提：A 当前失败；C3 status 指示 A 忙
// 操作：当拍没有其他候选
// 应检查：C4 无 req；A 保持待发直到以后空闲
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_15_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_failed_none && req==0 && waiting>0
);

// ==================== WIN-16 失败后改选其他命令 ====================
// 前提：A 当前失败且忙，B 在窗内且空闲
// 操作：C3 预选 B
// 应检查：C4 req=B，A 年龄仍旧；不锁死在 A
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_16_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_failed_other && req==h_selected_req && arb_addr==h_selected_addr && req!=0
);

// ==================== WIN-17 成功项不能再次预选 ====================
// 前提：当前 req=A 成功，A 仍有效且可能状态误解
// 操作：同拍构造多个候选
// 应检查：排除 A；仅其他未成功项参与下一拍
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_17_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && select_valid && select_e!=m_attempt_e
);

// ==================== WIN-18 新 AR 不加入当前预选 ====================
// 前提：本拍 A 接收且另有已存命令可选
// 操作：对新旧命令设置空闲状态
// 应检查：本拍 C2 仅看已寄存命令；新 AR 最早下拍判断、再下拍 req
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_18_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire && select_valid && alloc_e!=select_e && h_rank_valid!=0
);

// ==================== WIN-19 R 回收不使待发窗前移 ====================
// 前提：旧已发项本拍 R，待发五项均忙
// 操作：第六待发项空闲
// 应检查：R 只释放容量；不把第六待发项自动拉入窗口
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_WIN_19_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    r_fire && blocked_six && !issue_fire && req==0
);

// ==================== ARB-01 八个 Bank 编码边界 ====================
// 前提：合法命令在窗口中
// 操作：遍历 araddr[5:3]=0..7
// 应检查：req[bank] 唯一置位；没有 Bank8；地址最低三位不影响 Bank
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_01_B0: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && req==(8'b1<<0) && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_01_B1: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && req==(8'b1<<1) && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_01_B2: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && req==(8'b1<<2) && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_01_B3: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && req==(8'b1<<3) && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_01_B4: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && req==(8'b1<<4) && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_01_B5: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && req==(8'b1<<5) && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_01_B6: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && req==(8'b1<<6) && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_01_B7: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && req==(8'b1<<7) && arb_addr==m_addr[m_attempt_e][17:6]
);

// ==================== ARB-02 奇偶半区独立 ====================
// 前提：固定 bank，status=01 或 10
// 操作：命令 araddr[6] 分别为 0/1
// 应检查：仅对应 half=0 的 bit0、half=1 的 bit1 为 0 时可预选
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B0H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==0 && m_addr[select_e][6]==0 && rd_mem_status[0]==2
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B0H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==0 && m_addr[select_e][6]==1 && rd_mem_status[0]==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B1H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==1 && m_addr[select_e][6]==0 && rd_mem_status[1]==2
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B1H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==1 && m_addr[select_e][6]==1 && rd_mem_status[1]==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B2H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==2 && m_addr[select_e][6]==0 && rd_mem_status[2]==2
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B2H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==2 && m_addr[select_e][6]==1 && rd_mem_status[2]==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B3H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==3 && m_addr[select_e][6]==0 && rd_mem_status[3]==2
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B3H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==3 && m_addr[select_e][6]==1 && rd_mem_status[3]==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B4H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==4 && m_addr[select_e][6]==0 && rd_mem_status[4]==2
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B4H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==4 && m_addr[select_e][6]==1 && rd_mem_status[4]==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B5H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==5 && m_addr[select_e][6]==0 && rd_mem_status[5]==2
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B5H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==5 && m_addr[select_e][6]==1 && rd_mem_status[5]==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B6H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==6 && m_addr[select_e][6]==0 && rd_mem_status[6]==2
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B6H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==6 && m_addr[select_e][6]==1 && rd_mem_status[6]==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B7H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==7 && m_addr[select_e][6]==0 && rd_mem_status[7]==2
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_02_B7H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==7 && m_addr[select_e][6]==1 && rd_mem_status[7]==1
);

// ==================== ARB-03 Bank 两半均空闲/均忙 ====================
// 前提：status[bank]=00 或 11
// 操作：窗内请求同 bank 两种 half
// 应检查：00 两半都可候选；11 两半都排除，仍按年龄择一
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_03_IDLE: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting>0 && rd_mem_status[m_addr[m_attempt_e][5:3]]==0 && select_valid
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_03_BUSY: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting>0 && h_status==16'hffff && !select_valid
);

// ==================== ARB-04 发送地址保留 half ====================
// 前提：araddr[17:6] 边界与相邻变化
// 操作：命令进入 req 拍
// 应检查：arb_addr=araddr[17:6]，12 位；arb_addr[0]=half
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_04_ADDR0: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && arb_addr==0 && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_04_ADDR1: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && arb_addr==1 && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_04_ADDR4094: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && arb_addr==4094 && arb_addr==m_addr[m_attempt_e][17:6]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_04_ADDR4095: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && arb_addr==4095 && arb_addr==m_addr[m_attempt_e][17:6]
);

// ==================== ARB-05 四种双 grant 组合 ====================
// 前提：当前 req 的同一 bit=i
// 操作：(ar_gnt[i],rw_gnt[i])=00/01/10/11
// 应检查：仅 11 成功；其他组合均失败且待发保持
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_05_G00: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && ((req&ar_rd_gnt)!=0)==0 && ((req&rw_rd_gnt)!=0)==0 && issue_fire==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_05_G01: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && ((req&ar_rd_gnt)!=0)==0 && ((req&rw_rd_gnt)!=0)==1 && issue_fire==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_05_G10: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && ((req&ar_rd_gnt)!=0)==1 && ((req&rw_rd_gnt)!=0)==0 && issue_fire==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_05_G11: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && ((req&ar_rd_gnt)!=0)==1 && ((req&rw_rd_gnt)!=0)==1 && issue_fire==1
);

// ==================== ARB-06 grant 出现在非请求 Bank ====================
// 前提：req[i]=1，其他 Bank grant=1
// 操作：请求 bit 双 grant 不同时为 1
// 应检查：不成功；不能把无关 bit 合并为成功
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && (ar_rd_gnt&rw_rd_gnt&~req)!=0 && !issue_fire
);

// ==================== ARB-07 两个 grant 的有效 bit 不同 ====================
// 前提：req[i]=1，ar_gnt[i]=1；rw_gnt[j]=1，j≠i
// 操作：无 requested bit 的双 1
// 应检查：失败；pending 不因该 grant 减 1
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_07_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && (req&ar_rd_gnt)!=0 && (req&rw_rd_gnt)==0 && rw_rd_gnt!=0 && !issue_fire
);

// ==================== ARB-08 req=0 时有 grant ====================
// 前提：当前无下游请求
// 操作：grant 任意组合，包括多 bit=1
// 应检查：本模块 I=0，不启动返回日历；无效 arb_addr 不检查
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_08_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    req==0 && ar_rd_gnt==8'hff && rw_rd_gnt==8'hff && !issue_fire
);

// ==================== ARB-09 多 bit grant 包含请求 bit ====================
// 前提：req onehot，请求 bit 两种 grant 都为 1，其他位可为 1
// 操作：遵守请求 half 必须 busy
// 应检查：仍只成功一条；无额外多发/多返回
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_09_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && ar_rd_gnt==8'hff && rw_rd_gnt==8'hff
);

// ==================== ARB-10 预选空闲，发送拍已忙 ====================
// 前提：C2 status 目标 half=0，命令被选中
// 操作：C3 req 有效且目标 status=1
// 应检查：req 保持；是否成功由双 grant 决定；不以当前 busy 撤销 req
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_10_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_selected_prev && req==h_selected_req && arb_addr==h_selected_addr && rd_mem_status[m_addr[m_attempt_e][5:3]][arb_addr[0]] && issue_fire
);

// ==================== ARB-11 成功当拍目标 busy ====================
// 前提：req[i] 与两个 grant[i] 均为 1
// 操作：检查 status[i][arb_addr[0]]
// 应检查：同拍必须为 1；这是一条环境关系，不是 DUT 要拉的输出
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B0H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[0] && ar_rd_gnt[0] && rw_rd_gnt[0] && arb_addr[0]==0 && rd_mem_status[0][0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B0H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[0] && ar_rd_gnt[0] && rw_rd_gnt[0] && arb_addr[0]==1 && rd_mem_status[0][1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B1H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[1] && ar_rd_gnt[1] && rw_rd_gnt[1] && arb_addr[0]==0 && rd_mem_status[1][0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B1H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[1] && ar_rd_gnt[1] && rw_rd_gnt[1] && arb_addr[0]==1 && rd_mem_status[1][1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B2H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[2] && ar_rd_gnt[2] && rw_rd_gnt[2] && arb_addr[0]==0 && rd_mem_status[2][0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B2H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[2] && ar_rd_gnt[2] && rw_rd_gnt[2] && arb_addr[0]==1 && rd_mem_status[2][1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B3H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[3] && ar_rd_gnt[3] && rw_rd_gnt[3] && arb_addr[0]==0 && rd_mem_status[3][0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B3H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[3] && ar_rd_gnt[3] && rw_rd_gnt[3] && arb_addr[0]==1 && rd_mem_status[3][1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B4H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[4] && ar_rd_gnt[4] && rw_rd_gnt[4] && arb_addr[0]==0 && rd_mem_status[4][0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B4H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[4] && ar_rd_gnt[4] && rw_rd_gnt[4] && arb_addr[0]==1 && rd_mem_status[4][1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B5H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[5] && ar_rd_gnt[5] && rw_rd_gnt[5] && arb_addr[0]==0 && rd_mem_status[5][0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B5H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[5] && ar_rd_gnt[5] && rw_rd_gnt[5] && arb_addr[0]==1 && rd_mem_status[5][1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B6H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[6] && ar_rd_gnt[6] && rw_rd_gnt[6] && arb_addr[0]==0 && rd_mem_status[6][0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B6H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[6] && ar_rd_gnt[6] && rw_rd_gnt[6] && arb_addr[0]==1 && rd_mem_status[6][1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B7H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[7] && ar_rd_gnt[7] && rw_rd_gnt[7] && arb_addr[0]==0 && rd_mem_status[7][0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_PORTS] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_11_B7H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    req[7] && ar_rd_gnt[7] && rw_rd_gnt[7] && arb_addr[0]==1 && rd_mem_status[7][1]
);

// ==================== ARB-12 成功但目标仍空闲 ====================
// 前提：req 位双 grant=1，同时目标 status=0
// 操作：独立负向注入
// 应检查：违反 E06；不能要求正常模型接受该环境并当合法反例
// 此行不添加伪覆盖：关闭 E06 后，用 N_ARB_12 cover / V_ARB_12 assert 检查环境违规见证。

// ==================== ARB-13 其他 Bank 状态变化 ====================
// 前提：固定窗口命令的目标 half 条件
// 操作：无关 Bank/half 状态任意改变
// 应检查：不影响该项是否候选；候选排序只受真正相关项影响
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_13_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_selected_prev && req==h_selected_req && arb_addr==h_selected_addr && h_status!=h_prev_status && !issue_fire
);

// ==================== ARB-14 同 Bank 两 half 连续请求 ====================
// 前提：A 指向 half0，B 指向 half1，A 成功拍只要求其 half busy
// 操作：若 B 的 half 仍空闲则同拍预选 B
// 应检查：B 可下一拍请求；不把一个 half busy 当整个 bank 永久忙
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ARB_14_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_i && issue_fire && req==h_prev_req && arb_addr[0]!=h_prev_arb[0]
);

// ==================== CNT-01 四种 A/I 组合 ====================
// 前提：拍初待发数 P，合法 A/I 条件
// 操作：分别 A,I=00/10/01/11
// 应检查：本拍 pending_cnt=P、P+1、P-1、P；以事件布尔值计算
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_01_A0I0: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire==0 && issue_fire==0 && waiting>0 && pending_cnt==waiting+0-0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_01_A0I1: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire==0 && issue_fire==1 && waiting>0 && pending_cnt==waiting+0-1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_01_A1I0: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire==1 && issue_fire==0 && waiting>0 && pending_cnt==waiting+1-0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_01_A1I1: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire==1 && issue_fire==1 && waiting>0 && pending_cnt==waiting+1-1
);

// ==================== CNT-02 五条只成功一条 ====================
// 前提：P=5，本拍 I=1、A=0
// 操作：查看本拍组合输出
// 应检查：pending_cnt=4；不能等下一拍显示 4
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_02_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==5 && issue_fire && !ar_fire && pending_cnt==4
);

// ==================== CNT-03 五条同拍进一出一 ====================
// 前提：P=5，A=1、I=1
// 操作：查看本拍组合输出
// 应检查：pending_cnt=5；新 AR 当拍计入
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_03_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==5 && issue_fire && ar_fire && pending_cnt==5
);

// ==================== CNT-04 五条只进一条 ====================
// 前提：P=5，A=1、I=0
// 操作：查看本拍组合输出
// 应检查：pending_cnt=6；窗口仍最多 5 条
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==5 && !issue_fire && ar_fire && pending_cnt==6
);

// ==================== CNT-05 满九项但待发为零 ====================
// 前提：9 项均已发射，尚有等待 MEM/R 的项
// 操作：没有新的 AR
// 应检查：pending_cnt=0；不代表 CMDBUF 空或 ready=111
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_05_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && waiting==0 && pending_cnt==0 && !ar_fire && !r_fire && arready==0
);

// ==================== CNT-06 pending 上界与下界 ====================
// 前提：P=0 或 P=9
// 操作：合法事件组合：空时无 I；P=9 时无直接多收
// 应检查：pending 始终 0..9；无 4 位回绕；P=0 接收可为 1
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_06_EMPTY_A: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==0 && ar_fire && !issue_fire && pending_cnt==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_06_FULL: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting==9 && !ar_fire && !issue_fire && pending_cnt==9
);

// ==================== CNT-07 失败与 MEM 不减 pending ====================
// 前提：req 失败，或仅有 MEM 捕获
// 操作：无 AR、无成功发射
// 应检查：pending 保持；失败请求仍待发
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_07_FAIL: cover property (
    @(posedge clk) disable iff (!rst_n)
    req!=0 && !issue_fire && !ar_fire && pending_cnt==waiting
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_07_MEM: cover property (
    @(posedge clk) disable iff (!rst_n)
    mem_capture_due && !issue_fire && !ar_fire && pending_cnt==waiting
);

// ==================== CNT-08 R 仅间接影响 pending ====================
// 前提：旧已发项 R，可能释放容量给新 AR
// 操作：R 无 AR 时 P 不变；R+A 时 P 加 1，另按 I 减 1
// 应检查：不直接从 P 扣 R；新 A 是否成立取决于本拍 ready
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_08_A0: cover property (
    @(posedge clk) disable iff (!rst_n)
    r_fire && ar_fire==0 && !issue_fire && pending_cnt==waiting+0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CNT_08_A1: cover property (
    @(posedge clk) disable iff (!rst_n)
    r_fire && ar_fire==1 && !issue_fire && pending_cnt==waiting+1
);

// ==================== MEM-01 固定四拍返回 ====================
// 前提：命令在 Cn 双 grant 成功
// 操作：Cn+4 提供 mem_rdata 与 pc_err，仅维持一拍
// 应检查：在 Cn+4 捕获到该事务；最早 Cn+5 R；不是从 AR 或预选起算
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_01_NEXT_R: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_m && h_response_matches && rsp_e==h_prev_due_slot
);

// ==================== MEM-02 失败请求不启动日历 ====================
// 前提：req 失败后若干拍再成功
// 操作：在真正成功后第 4 拍返回
// 应检查：失败那拍+4 的数据不得绑定该事务
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_02_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_i_history[3:0]==4'b1000 && mem_capture_due && h_failed_before_success[mem_capture_slot]
);

// ==================== MEM-03 连续成功对应连续捕获 ====================
// 前提：Cn..Cn+3 每拍成功一条
// 操作：四拍后逐拍给不同数据和 pc_err
// 应检查：返回时序与成功顺序一致，逐项分开缓存
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_03_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_m_history[2:0]==3'b111 && mem_capture_due && mem_rdata!=h_prev_mem && pc_err!=h_prev_pc
);

// ==================== MEM-04 带空洞的返回流水 ====================
// 前提：成功序列 1/0/1/0/0/1
// 操作：四拍后在对应位置给数据
// 应检查：捕获掩码同样有空洞；不得把无效拍压缩掉
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_m_history[4:0]==5'b10100 && mem_capture_due
);

// ==================== MEM-05 没有到期命令的数据扰动 ====================
// 前提：返回日历该拍为空
// 操作：mem_rdata/pc_err 任意变化
// 应检查：忽略该拍输入；不产生 done 或 R
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_05_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    !mem_capture_due && mem_rdata!=h_prev_mem && pc_err!=h_prev_pc && used>0
);

// ==================== MEM-06 返回脉冲只有一拍 ====================
// 前提：到期拍给特征数据与 pc_err
// 操作：下一拍立即改变输入总线
// 应检查：OTB 保留到期拍值，晚 R 仍正确
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && h_done_wait[rsp_e]>=1 && mem_rdata!=m_data[rsp_e] && pc_err!=m_pc[rsp_e]
);

// ==================== MEM-07 R 不 ready 期间照常捕获 ====================
// 前提：一个或多个源 rready=0
// 操作：MEM 到期连续返回
// 应检查：仍逐项缓存；R 阻塞不能暂停返回日历
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_07_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    mem_capture_due && h_prev_m && rready==0 && rvalid==0
);

// ==================== MEM-08 新 AR 与 MEM 同拍 ====================
// 前提：A 为新事务，M 为四拍前成功的旧事务
// 操作：两事件同拍，合法槽位互异
// 应检查：新槽预留与旧槽捕获各自完成，N 加 1；不能覆盖旧数据
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_08_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire && mem_capture_due && alloc_e!=mem_capture_slot
);

// ==================== MEM-09 发射成功与旧 MEM 同拍 ====================
// 前提：新 I 与四拍前 I 到期
// 操作：同拍写日历头并读日历尾
// 应检查：两事件均保留，流水连续推进
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_09_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    issue_fire && mem_capture_due && m_attempt_e!=mem_capture_slot
);

// ==================== MEM-10 MEM 与 R 同拍不同命令 ====================
// 前提：已完成 A 正在 R；B 本拍才 MEM
// 操作：同拍捕获 B、退役 A
// 应检查：R 给 A 的旧缓存；B 最早下拍响应；两槽不得相同
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_10_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    mem_capture_due && h_response_matches && mem_capture_slot!=rsp_e
);

// ==================== MEM-11 MEM 不能当拍旁路 R ====================
// 前提：命令首次到期，之前未 done，rready=1
// 操作：到期拍观察 rvalid
// 应检查：本拍不能为该命令产生 R；下一拍才具备资格
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_11_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    mem_capture_due && head_valid[m_src[mem_capture_slot]] && head[m_src[mem_capture_slot]]==mem_capture_slot && rready[m_src[mem_capture_slot]] && !rvalid[m_src[mem_capture_slot]]
);

// ==================== MEM-12 128 位数据全宽特征 ====================
// 前提：多条不同命令返回不同数据
// 操作：全 0、全 1、交替位、walking-1、walking-0、随机；在各字节边界翻转
// 应检查：R 数据与该事务捕获值逐位一致
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_ZERO: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==128'b0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_ONES: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata=={128{1'b1}}
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_AA: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata=={16{8'haa}}
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_55: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata=={16{8'h55}}
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_000: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<0)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_000: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<0)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_001: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<1)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_001: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<1)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_002: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<2)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_002: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<2)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_003: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<3)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_003: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<3)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_004: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<4)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_004: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<4)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_005: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<5)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_005: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<5)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_006: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<6)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_006: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<6)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_007: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<7)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_007: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<7)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_008: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<8)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_008: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<8)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_009: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<9)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_009: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<9)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_010: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<10)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_010: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<10)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_011: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<11)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_011: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<11)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_012: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<12)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_012: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<12)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_013: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<13)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_013: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<13)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_014: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<14)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_014: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<14)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_015: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<15)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_015: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<15)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_016: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<16)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_016: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<16)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_017: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<17)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_017: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<17)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_018: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<18)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_018: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<18)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_019: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<19)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_019: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<19)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_020: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<20)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_020: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<20)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_021: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<21)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_021: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<21)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_022: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<22)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_022: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<22)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_023: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<23)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_023: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<23)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_024: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<24)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_024: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<24)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_025: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<25)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_025: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<25)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_026: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<26)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_026: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<26)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_027: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<27)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_027: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<27)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_028: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<28)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_028: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<28)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_029: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<29)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_029: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<29)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_030: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<30)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_030: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<30)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_031: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<31)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_031: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<31)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_032: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<32)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_032: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<32)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_033: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<33)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_033: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<33)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_034: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<34)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_034: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<34)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_035: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<35)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_035: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<35)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_036: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<36)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_036: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<36)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_037: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<37)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_037: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<37)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_038: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<38)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_038: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<38)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_039: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<39)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_039: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<39)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_040: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<40)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_040: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<40)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_041: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<41)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_041: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<41)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_042: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<42)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_042: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<42)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_043: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<43)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_043: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<43)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_044: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<44)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_044: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<44)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_045: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<45)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_045: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<45)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_046: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<46)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_046: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<46)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_047: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<47)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_047: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<47)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_048: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<48)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_048: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<48)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_049: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<49)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_049: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<49)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_050: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<50)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_050: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<50)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_051: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<51)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_051: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<51)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_052: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<52)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_052: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<52)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_053: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<53)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_053: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<53)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_054: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<54)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_054: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<54)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_055: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<55)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_055: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<55)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_056: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<56)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_056: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<56)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_057: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<57)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_057: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<57)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_058: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<58)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_058: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<58)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_059: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<59)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_059: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<59)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_060: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<60)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_060: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<60)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_061: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<61)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_061: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<61)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_062: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<62)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_062: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<62)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_063: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<63)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_063: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<63)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_064: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<64)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_064: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<64)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_065: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<65)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_065: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<65)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_066: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<66)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_066: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<66)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_067: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<67)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_067: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<67)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_068: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<68)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_068: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<68)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_069: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<69)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_069: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<69)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_070: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<70)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_070: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<70)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_071: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<71)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_071: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<71)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_072: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<72)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_072: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<72)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_073: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<73)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_073: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<73)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_074: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<74)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_074: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<74)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_075: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<75)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_075: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<75)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_076: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<76)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_076: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<76)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_077: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<77)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_077: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<77)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_078: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<78)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_078: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<78)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_079: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<79)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_079: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<79)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_080: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<80)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_080: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<80)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_081: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<81)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_081: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<81)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_082: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<82)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_082: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<82)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_083: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<83)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_083: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<83)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_084: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<84)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_084: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<84)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_085: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<85)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_085: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<85)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_086: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<86)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_086: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<86)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_087: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<87)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_087: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<87)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_088: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<88)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_088: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<88)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_089: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<89)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_089: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<89)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_090: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<90)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_090: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<90)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_091: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<91)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_091: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<91)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_092: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<92)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_092: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<92)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_093: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<93)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_093: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<93)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_094: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<94)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_094: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<94)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_095: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<95)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_095: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<95)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_096: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<96)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_096: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<96)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_097: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<97)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_097: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<97)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_098: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<98)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_098: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<98)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_099: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<99)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_099: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<99)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_100: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<100)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_100: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<100)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_101: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<101)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_101: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<101)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_102: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<102)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_102: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<102)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_103: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<103)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_103: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<103)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_104: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<104)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_104: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<104)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_105: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<105)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_105: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<105)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_106: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<106)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_106: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<106)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_107: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<107)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_107: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<107)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_108: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<108)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_108: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<108)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_109: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<109)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_109: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<109)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_110: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<110)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_110: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<110)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_111: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<111)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_111: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<111)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_112: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<112)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_112: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<112)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_113: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<113)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_113: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<113)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_114: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<114)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_114: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<114)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_115: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<115)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_115: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<115)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_116: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<116)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_116: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<116)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_117: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<117)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_117: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<117)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_118: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<118)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_118: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<118)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_119: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<119)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_119: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<119)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_120: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<120)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_120: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<120)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_121: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<121)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_121: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<121)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_122: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<122)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_122: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<122)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_123: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<123)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_123: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<123)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_124: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<124)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_124: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<124)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_125: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<125)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_125: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<125)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_126: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<126)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_126: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<126)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W1_127: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==(128'b1<<127)
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_12_W0_127: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && rdata==~(128'b1<<127)
);

// ==================== MEM-13 parity 错误交替 ====================
// 前提：连续到期，pc_err=1/0/1/0
// 操作：R 可延迟、跨源交错
// 应检查：pc_err 随对应 entry 保存，不能使用当前总线的错误位
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_MEM_13_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_m_history[2:0]==3'b111 && mem_capture_due && h_pc_history==3'b101 && !pc_err
);

// ==================== MEM-14 MEM 提前/延后/丢返回 ====================
// 前提：已成功事务按协议应在 n+4 返回
// 操作：独立注入 n+3/n+5 或 n+4 给错误数据
// 应检查：无返回 valid/tag，DUT 按 n+4 无条件采样；不能承诺自动识别丢包或重定时
// 此行不添加伪覆盖：MEM 无 valid/tag/独立存储器真值：仅当前顶层信号不能分辨延迟或错误数据；不得伪造 assume/cover。需外部 MEM 参考或注错记录。

// ==================== RSP-01 没有完成的源队头 ====================
// 前提：三路均无可返回队头
// 操作：rready 任意
// 应检查：rvalid=000；无效共享负载不检查；RR 不推进
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_01_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==0 && rvalid==0 && used>0
);

// ==================== RSP-02 完成但 rready 全零 ====================
// 前提：三路可有缓存完成项
// 操作：rready=000 持续多拍
// 应检查：rvalid=000；缓存不变；RR 保持
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_02_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    (m_live&m_done)!=0 && rready==0 && rvalid==0 && h_prev_rready==0 && !h_prev_r
);

// ==================== RSP-03 只有一路候选 ====================
// 前提：其他两路空、未完成或不 ready
// 操作：逐一覆盖候选 0/1/2
// 应检查：立即选择该候选；共享负载属于它，rvalid onehot
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_03_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==(3'b1<<0) && rvalid==(3'b1<<0) && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_03_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==(3'b1<<1) && rvalid==(3'b1<<1) && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_03_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==(3'b1<<2) && rvalid==(3'b1<<2) && h_response_matches
);

// ==================== RSP-04 三路同时候选 ====================
// 前提：当前 RR 指向 0；各路持续可响应
// 操作：连续三个 R 拍
// 应检查：顺序 0→1→2，下一轮回到 0
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_rr012_phase==2 && eligible==7 && rvalid==4 && h_response_matches
);

// ==================== RSP-05 两路候选跳过空缺 ====================
// 前提：分别候选 011/101/110，RR 可处于 0/1/2
// 操作：每拍实际响应
// 应检查：按 RR 起点循环查找第一候选；不是比较谁的全局命令更老
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_05_M3RR0: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==3 && m_rr==0 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_05_M3RR1: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==3 && m_rr==1 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_05_M3RR2: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==3 && m_rr==2 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_05_M5RR0: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==5 && m_rr==0 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_05_M5RR1: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==5 && m_rr==1 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_05_M5RR2: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==5 && m_rr==2 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_05_M6RR0: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==6 && m_rr==0 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_05_M6RR1: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==6 && m_rr==1 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_05_M6RR2: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==6 && m_rr==2 && h_response_matches
);

// ==================== RSP-06 RR 到末尾回绕 ====================
// 前提：RR 指向 2，候选含 2/0
// 操作：源2 实际 R 后继续响应
// 应检查：下次从 0 开始扫描，不产生非法源3
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_r && h_prev_rsrc==2 && m_rr==0 && rvalid[0] && h_response_matches
);

// ==================== RSP-07 无响应的空拍 ====================
// 前提：中途所有候选消失一拍或多拍
// 操作：后续候选恢复
// 应检查：RR 起点维持空拍前值；不因时间流逝旋转
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_07_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_rr_gap_seen && r_fire && h_response_matches
);

// ==================== RSP-08 rready 变化改变当拍候选 ====================
// 前提：某源已完成，另一路也可响应
// 操作：在采样前切换 rready mask
// 应检查：只在 ready=1 源中选；没有 valid 锁住等待的状态
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_08_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_eligible!=0 && eligible!=0 && rready!=h_prev_rready && rvalid!=0 && (rvalid&~rready)==0 && h_response_matches
);

// ==================== RSP-09 同源 3 先发、先完成 ====================
// 前提：同源 AR 顺序为 1/2/3，3 的 bank 先可用
// 操作：3 先成功且 MEM 返回；1/2 尚未 R
// 应检查：源内不能先 R3；最终 R 顺序必须 1→2→3
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_09_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[0].order_phase==5 && sources[0].source_r && sources[0].oldest==sources[0].third_token && sources[0].head_payload_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_09_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[1].order_phase==5 && sources[1].source_r && sources[1].oldest==sources[1].third_token && sources[1].head_payload_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_09_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[2].order_phase==5 && sources[2].source_r && sources[2].oldest==sources[2].third_token && sources[2].head_payload_matches
);

// ==================== RSP-10 同源第二条完成但第一条未发 ====================
// 前提：队头仍待发，次项已完成
// 操作：rready=1
// 应检查：不得 R 次项；先找源队头再检查 done
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_10_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[0].order_count>=2 && !m_sent[sources[0].order_slot[0]] && m_done[sources[0].order_slot[1]] && rready[0] && !rvalid[0]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_10_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[1].order_count>=2 && !m_sent[sources[1].order_slot[0]] && m_done[sources[1].order_slot[1]] && rready[1] && !rvalid[1]
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_10_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[2].order_count>=2 && !m_sent[sources[2].order_slot[0]] && m_done[sources[2].order_slot[1]] && rready[2] && !rvalid[2]
);

// ==================== RSP-11 不同 ID 仍要同源保序 ====================
// 前提：同源命令 ID 各不相同
// 操作：乱序发射与完成
// 应检查：R 按 AR 接收顺序；不是仅同 ID 内保序
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_11_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[0].order_count>=2 && m_id[sources[0].order_slot[0]]!=m_id[sources[0].order_slot[1]] && m_done[sources[0].order_slot[1]] && sources[0].source_r && sources[0].head_payload_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_11_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[1].order_count>=2 && m_id[sources[1].order_slot[0]]!=m_id[sources[1].order_slot[1]] && m_done[sources[1].order_slot[1]] && sources[1].source_r && sources[1].head_payload_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_11_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[2].order_count>=2 && m_id[sources[2].order_slot[0]]!=m_id[sources[2].order_slot[1]] && m_done[sources[2].order_slot[1]] && sources[2].source_r && sources[2].head_payload_matches
);

// ==================== RSP-12 重复 ID 不合并事务 ====================
// 前提：同源或跨源 arid 重复，其他字段/数据不同
// 操作：多条命令乱序完成
// 应检查：每次 R 返回对应源队头的完整记录，不能以 rid 查唯一事务
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_12_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[0].order_count>=2 && m_id[sources[0].order_slot[0]]==m_id[sources[0].order_slot[1]] && m_data[sources[0].order_slot[0]]!=m_data[sources[0].order_slot[1]] && m_done[sources[0].order_slot[1]] && sources[0].source_r && sources[0].head_payload_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_12_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[1].order_count>=2 && m_id[sources[1].order_slot[0]]==m_id[sources[1].order_slot[1]] && m_data[sources[1].order_slot[0]]!=m_data[sources[1].order_slot[1]] && m_done[sources[1].order_slot[1]] && sources[1].source_r && sources[1].head_payload_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_12_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[2].order_count>=2 && m_id[sources[2].order_slot[0]]==m_id[sources[2].order_slot[1]] && m_data[sources[2].order_slot[0]]!=m_data[sources[2].order_slot[1]] && m_done[sources[2].order_slot[1]] && sources[2].source_r && sources[2].head_payload_matches
);

// ==================== RSP-13 一源阻塞其他源仍推进 ====================
// 前提：XAU0 老队头未完成；XAU1/2 有已完成头且 ready
// 操作：多拍 R 选择
// 应检查：可返回 XAU1/2，不要求全局 AR 顺序
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_13_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    head_valid[0] && !m_done[head[0]] && (rvalid&~(3'b1<<0))!=0 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_13_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    head_valid[1] && !m_done[head[1]] && (rvalid&~(3'b1<<1))!=0 && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_13_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    head_valid[2] && !m_done[head[2]] && (rvalid&~(3'b1<<2))!=0 && h_response_matches
);

// ==================== RSP-14 同源队头 R 后立即换头 ====================
// 前提：某源前两条都已完成
// 操作：本拍第一条 R，下一拍第二条仍 ready
// 应检查：第二条进入候选，可按 RR 获胜；元数据与数据同步切换
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_14_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_r && h_prev_rsrc==0 && rvalid[0] && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_14_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_r && h_prev_rsrc==1 && rvalid[1] && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_14_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_r && h_prev_rsrc==2 && rvalid[2] && h_response_matches
);

// ==================== RSP-15 同源唯一旧项 R 与新 AR ====================
// 前提：源队列仅一项且完成，AR 同源接收
// 操作：同拍出入
// 应检查：返回旧项；新项变新队头但未完成，不能下拍凭旧 done 返回
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_15_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[0].order_count==1 && sources[0].source_r && sources[0].source_ar && sources[0].head_payload_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_15_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[1].order_count==1 && sources[1].source_r && sources[1].source_ar && sources[1].head_payload_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_15_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    sources[2].order_count==1 && sources[2].source_r && sources[2].source_ar && sources[2].head_payload_matches
);

// ==================== RSP-16 持续候选的 RR 等待上界 ====================
// 前提：某源队头持续 done、rready 持续 1
// 操作：其他两源也持续候选
// 应检查：至多先服务其他两次 R；最迟第三个连续选择拍轮到该源
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_16_S0: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible[0] && sources[0].bypass_count==2 && rvalid[0] && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_16_S1: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible[1] && sources[1].bypass_count==2 && rvalid[1] && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_16_S2: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible[2] && sources[2].bypass_count==2 && rvalid[2] && h_response_matches
);

// ==================== RSP-17 R 共享负载只归一个源 ====================
// 前提：多个完成队头且 ready
// 操作：同拍观察 rvalid 与共享 rdata/rid/port/raddr/rresp
// 应检查：rvalid 至多一位；所有字段来自同一获胜源的同一队头
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_17_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    eligible==7 && h_response_matches && (rvalid==1 || rvalid==2 || rvalid==4)
);

// ==================== RSP-18 无效 R 负载不约束 ====================
// 前提：rvalid=000
// 操作：共享输出可能保持旧值或为零
// 应检查：只检查 rvalid；不得强制 rdata/rid/raddr/port/rresp 全零
// 覆盖边界：无 R 的合法采样点；不 cover 具体无效输出值，也不约束它们。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_RSP_18_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    rvalid==0 && used>0
);

// ==================== ERR-01 正常响应 ====================
// 前提：arresp=00，MEM pc_err=0
// 操作：命令按任意合法时序完成
// 应检查：rresp=00，其他字段和数据属于原命令
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_01_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_err[rsp_e]==0 && m_pc[rsp_e]==0 && rresp==0
);

// ==================== ERR-02 仅地址越界 ====================
// 前提：arresp=11，pc_err=0
// 操作：仍发射 MEM，再按源内顺序 R
// 应检查：rresp=11；不可绕过发射/四拍捕获提前返回
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_02_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_err[rsp_e]==3 && m_pc[rsp_e]==0 && rresp==3
);

// ==================== ERR-03 仅奇偶异常 ====================
// 前提：arresp=00，pc_err=1
// 操作：捕获后 R
// 应检查：rresp=01；保留返回数据；不丢弃命令
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_03_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_err[rsp_e]==0 && m_pc[rsp_e]==1 && rresp==1
);

// ==================== ERR-04 两个错误同时发生 ====================
// 前提：arresp=11，pc_err=1
// 操作：正常完成并返回
// 应检查：rresp=11；地址越界优先于奇偶异常
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && m_err[rsp_e]==3 && m_pc[rsp_e]==1 && rresp==3
);

// ==================== ERR-05 未定义输入 arresp ====================
// 前提：arvalid=1、arresp=01 或 10
// 操作：独立负向输入
// 应检查：违反 E04；正常环境只允许 00/11；不替 DUT 指定新业务含义
// 此行不添加伪覆盖：关闭 E04 后，用 N_ERR_05 cover / V_ERR_05 assert 检查环境违规见证。

// ==================== ERR-06 错误命令被正常命令夹住 ====================
// 前提：三条同源命令为正常/错误/正常
// 操作：改变发射完成顺序
// 应检查：R 仍按接收顺序，错误只附着于中间命令
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_error_sandwich_phase==2 && h_response_matches && winner==0 && rresp==0
);

// ==================== ERR-07 低地址位与 Bank/行地址分离 ====================
// 前提：命令只改变 araddr[2:0]
// 操作：保持其余字段，分别完成
// 应检查：req 和 arb_addr 不变，raddr 按原三位变化
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_07_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_prev_r && r_fire && winner==h_prev_rsrc && m_addr[rsp_e][17:3]==h_prev_raddr_full[17:3] && raddr!=h_prev_raddr_full[2:0] && h_response_matches
);

// ==================== ERR-08 port_id 直接透传 ====================
// 前提：同源或跨源使用不同 port_id，包括 0 和 31
// 操作：乱序完成且 RR 交错
// 应检查：r_port_id 来自该命令 AR，不由 src、Bank 或 ID 重新编码
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_08_P0: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && r_port_id==0
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_08_P1: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && r_port_id==1
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_08_P15: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && r_port_id==15
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_08_P16: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && r_port_id==16
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ERR_08_P31: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_response_matches && r_port_id==31
);

// ==================== CON-01 四事件全部发生 ====================
// 前提：新 A、当前 I、四拍前的 M、已完成项 R 均合法
// 操作：四事件同拍；A 可复用 R 槽，其他事务互异
// 应检查：N_next=N，P_out=P；M 缓存、R 输出、I 日历与 A 分配全部完成
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CON_01_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    ar_fire && issue_fire && mem_capture_due && r_fire && h_response_matches
);

// ==================== CON-02 满表四事件同拍 ====================
// 前提：N=9，存在一个待发、一个到期、一个已完成头
// 操作：R 释放槽，A 选择合法来源，同时 I/M
// 应检查：同拍复用 R 槽；不得借用 I 或 M 槽；N 保持 9
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CON_02_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==9 && ar_fire && issue_fire && mem_capture_due && r_fire && alloc_e==rsp_e && mem_capture_slot!=rsp_e && m_attempt_e!=rsp_e && h_response_matches
);

// ==================== CON-03 零事件保持 ====================
// 前提：无 A/I/M/R；可有失败 req
// 操作：等待多拍
// 应检查：占用不变；数据与年龄保持；失败项可重选；日历仍按拍移位
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CON_03_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_quiet_run>=3 && !ar_fire && !issue_fire && !mem_capture_due && !r_fire && used>0
);

// ==================== CON-04 同拍新 AR 不能立刻 I/M/R ====================
// 前提：当前只有一个全新接收事务，无旧事务
// 操作：尝试把多个事件解释为同一命令
// 应检查：A→I 至少三阶段，I→M 四拍，M→R 至少下一拍；事件组合需对应历史事务
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CON_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==0 && ar_fire && !issue_fire && !mem_capture_due && !r_fire
);

// ==================== CON-05 物理槽冲突注错 ====================
// 前提：内部把同拍 I/M、M/R、A/M 等指向同一存活事务槽
// 操作：观察双重写入或错误响应
// 应检查：合法历史中这些别名不成立；应由内部断言/注错及端口后果检出
// 此行不添加伪覆盖：端口数据/顺序断言检查有外部后果的槽别名；无外部后果的内部冲突需白盒断言。

// ==================== CON-06 计数不变不等于无动作 ====================
// 前提：同拍 A/R=1，可能 I/M=1
// 操作：连续多拍总 N 恒定
// 应检查：字段、队头、年龄、数据和 RR 均可能变化；需逐事务检查
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_CON_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_ar_r_run>=2 && ar_fire && r_fire && h_response_matches
);

// ==================== BIZ-01 单源持续满速流 ====================
// 前提：同源 ready 时每拍提交；Bank/grant 条件允许最早 I；R ready 持续 1
// 操作：最短 C1 AR→C3 I→C7 M→C8 R，持续填充和回收
// 应检查：首次返回后可同拍接收并稳态 1 AR/拍；这是条件吞吐，不是无条件保证
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_01_FIRST_R: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_single_start[6] && h_response_matches
);

// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_01_STEADY4: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_ar_r_run>=3 && ar_fire && r_fire && src==winner && (h_ar_sources==1 || h_ar_sources==2 || h_ar_sources==4) && h_response_matches
);

// ==================== BIZ-02 三源混合长流 ====================
// 前提：上游选择不同 src，维持合法握手
// 操作：随机 Bank/half、ID 重复、R ready mask 和 grant 失败
// 应检查：长期 AR-R 守恒，各源不超过 7，字段与数据不串单
// 覆盖边界：有限长混合轨迹，含三源、失败、部分 ready、重复 ID；不声明无界进展。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_02_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total_a>=16 && h_total_r>=8 && h_ar_sources==7 && h_seen_reject && h_seen_partial_ready && ar_fire && h_duplicate_id
);

// ==================== BIZ-03 同 Bank 热点竞争 ====================
// 前提：许多命令指向同一 Bank 或 half
// 操作：status 忙闲变化，失败多拍，夹杂其他 Bank 命令
// 应检查：只在窗口内绕过忙项；成功规则与年龄不变；无吞吐下限承诺
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_03_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    waiting>=3 && h_hotspot && h_reject_run>=2 && select_valid
);

// ==================== BIZ-04 前五永久忙 ====================
// 前提：前五待发项始终忙，第六项及以后空闲
// 操作：长时间无成功发射
// 应检查：可以永久不发射；容量耗尽后阻塞合法；无 bank 公平假设不能证明排空
// 覆盖边界：连续至少 7 拍窗口阻塞；永久忙的安全性由 assert 检查，不把有限 cover 当作永久见证。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_04_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    blocked_six && blocked_streak>=6 && req==0
);

// ==================== BIZ-05 仲裁持续拒绝 ====================
// 前提：可用候选每次 req，但双 grant 不成功
// 操作：任意长失败序列
// 应检查：不丢命令、不减 pending，可连续重试或重选；不保证最终成功
// 覆盖边界：连续至少 7 拍拒绝；不假定后续一定获 grant。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_05_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_reject_run>=6 && req!=0 && !issue_fire
);

// ==================== BIZ-06 某源永不 R ready ====================
// 前提：该源占据若干已完成项，其他源继续
// 操作：rready[该源]=0 长期不变
// 应检查：该源项不释放；其他源在容量和窗口许可范围推进；整体不保证排空
// 覆盖边界：源 0 连续至少 7 拍阻塞期间其他源响应；不证明无限轨迹最终排空。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_06_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_notready_run[0]>=6 && !rready[0] && (rvalid&6)!=0 && h_response_matches
);

// ==================== BIZ-07 源切换不公平 ====================
// 前提：三路有业务，但上游长期不选某一路
// 操作：仅观察共享 AR 与 arready
// 应检查：可证明该路首项容量许可；无法证明未呈现请求的服务时间
// 覆盖边界：有限的不公平选择；未呈现给共享 AR 的请求无法观察。
// [NO_REF_MODEL_HISTORY] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_07_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_total_a>=7 && h_ar_sources==1 && arready[1] && arready[2]
);

// ==================== BIZ-08 停止注入后排空 ====================
// 前提：AR 停止；所有待发目标最终可用且获 grant；各源最终 ready
// 操作：继续完整 MEM 返回
// 应检查：在这些服务条件下应逐项排空；若需固定周期界，需给出各条件的有界版本
// 覆盖边界：存在排空轨迹；不添加公平性 assume，不声明所有轨迹有界排空。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_08_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    h_was_drained && used==0 && h_total_r>=6 && !arvalid
);

// ==================== BIZ-09 错序返回叠加容量限制 ====================
// 前提：同源年轻项先完成；老项阻塞；占用达到 7
// 操作：另两路各一项有业务
// 应检查：老项未 R 前该源不再接收；另两源可各保留一项；年轻完成不归还额度
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_09_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    occ[0]==7 && !m_done[head[0]] && h_other_done && !r_fire && arready[1] && arready[2] && ar_fire && src!=0
);

// ==================== BIZ-10 长时间全空后重新启动 ====================
// 前提：事务全部 R，空闲许多拍，MEM 总线仍变化
// 操作：再发送新命令
// 应检查：仅新事务产生 req/R，RR 保持上次实际响应后的指针
// 覆盖边界：完整场景的关键采样点；持续正确性由关联 assert 检查。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_BIZ_10_MAIN: cover property (
    @(posedge clk) disable iff (!rst_n)
    used==0 && h_was_drained && h_empty_run>=5 && ar_fire && mem_rdata!=h_prev_mem
);

// ==================== ENV-06 数组连接方向 ====================
// 前提：上层与模块都使用 bank-major [1:0] status [7:0]
// 操作：对 16 个独立 bank/half 定向置位
// 应检查：一一对应 status[bank][half]；适配器若必须展开需显式定义映射
// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B0H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==0 && m_addr[select_e][6]==0 && h_status==(16'hffff^(16'b1<<0))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B0H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==0 && m_addr[select_e][6]==1 && h_status==(16'hffff^(16'b1<<1))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B1H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==1 && m_addr[select_e][6]==0 && h_status==(16'hffff^(16'b1<<2))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B1H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==1 && m_addr[select_e][6]==1 && h_status==(16'hffff^(16'b1<<3))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B2H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==2 && m_addr[select_e][6]==0 && h_status==(16'hffff^(16'b1<<4))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B2H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==2 && m_addr[select_e][6]==1 && h_status==(16'hffff^(16'b1<<5))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B3H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==3 && m_addr[select_e][6]==0 && h_status==(16'hffff^(16'b1<<6))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B3H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==3 && m_addr[select_e][6]==1 && h_status==(16'hffff^(16'b1<<7))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B4H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==4 && m_addr[select_e][6]==0 && h_status==(16'hffff^(16'b1<<8))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B4H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==4 && m_addr[select_e][6]==1 && h_status==(16'hffff^(16'b1<<9))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B5H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==5 && m_addr[select_e][6]==0 && h_status==(16'hffff^(16'b1<<10))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B5H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==5 && m_addr[select_e][6]==1 && h_status==(16'hffff^(16'b1<<11))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B6H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==6 && m_addr[select_e][6]==0 && h_status==(16'hffff^(16'b1<<12))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B6H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==6 && m_addr[select_e][6]==1 && h_status==(16'hffff^(16'b1<<13))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B7H0: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==7 && m_addr[select_e][6]==0 && h_status==(16'hffff^(16'b1<<14))
);

// 覆盖边界：逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。
// [REF_MODEL] 场景见证；命中仅证明存在路径，断言单独检验正确性。
C_CC_ENV_06_B7H1: cover property (
    @(posedge clk) disable iff (!rst_n)
    select_valid && m_addr[select_e][5:3]==7 && m_addr[select_e][6]==1 && h_status==(16'hffff^(16'b1<<15))
);

// ==================== ENV-07 仅端口可观察的证明边界 ====================
// 前提：仅连接顶层接口运行 SVA
// 操作：检查数据、计数、顺序与后续响应
// 应检查：可查外部行为；不能单凭参考模型自检证明物理 entry 恰有 9 项、OTB 位已清零
// 此行不添加伪覆盖：只使用顶层端口，不能证明物理存储数量、原始位清零或不可观察内部事件。

// ==================== ENV-08 环境约束不能假设 DUT 结果 ====================
// 前提：构建 formal harness
// 操作：检查 E03/E04/E05/E06 及新增 assume
// 应检查：只约束合法输入关系；ready/req/R 正确性应 assert，不能 assume 掉设计错误
// 此行不添加伪覆盖：机械核对 assume 只有 E03/E04/E05/E06；环境关系不可替代 A_READY/A_REQ/A_R_*。

