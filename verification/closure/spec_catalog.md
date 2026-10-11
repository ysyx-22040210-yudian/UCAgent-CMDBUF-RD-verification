# cmdbuf_rd 完整正式功能与检测点目录

版本：20261011.1。15 FG / 35 FC / 177 CK：5 项环境约束、107 项安全义务、65 项业务可达见证。**这是一份规格和义务目录，本轮全部验证状态 pending，不是通过报告。**

每个 CK 的稳定 ID、R01–R18、FI001–FI049、期望行为、证明义务和旧证据引用都保存在同名 JSON。native_binding 仍需绑定本轮真实运行的唯一编译属性、源码 hash 和受信证据；不存在恒真占位属性。环境 Assume 的正文是真实输入约束，其 guard=1 仅表示无附加门控。

## 使用边界

仅初始采样复位：首采样 rst_n=0，此后恒为1。无运行中带在途事务复位证明。

不假设上游源公平、bank 最终空闲、grant 最终成功或 rready 最终为1；不承诺无条件最终响应。

每个 CK 定义一个判定关系；向量相等、任意源/任意entry量化属于一个关系，多个时序场景单列 cover。环境和cover均不计安全证明通过。

采用逻辑保底一项/源与六项共享：sum(max(occ[x],1))<=9。不是固定3/3/3分区，也不能仅靠每源<=7。重复ID、精确RR方向/初值、错误数据透传、物理清零和选择后status变化等采用实现行为在合同表单列。

## 需求映射

| 需求 | 名称 | 环境 / 安全 / cover 数 |
| --- | --- | --- |
| R01 | 共享接口与合法握手 | 2 / 6 / 4 |
| R02 | ID/port/address元数据 | 0 / 12 / 3 |
| R03 | 9项配对分配 | 0 / 11 / 1 |
| R04 | 来源保底与10B准入 | 0 / 13 / 8 |
| R05 | pending与生命周期 | 0 / 13 / 0 |
| R06 | 最老5项窗口 | 0 / 9 / 5 |
| R07 | bank/half解码和最老候选 | 0 / 7 / 18 |
| R08 | 三周期流水及去重 | 0 / 12 / 4 |
| R09 | 双grant和5A | 0 / 9 / 9 |
| R10 | 6B成功前馈 | 0 / 1 / 1 |
| R11 | 成功后固定4拍 | 0 / 8 / 3 |
| R12 | MEM单拍捕获及完成同步 | 0 / 15 / 5 |
| R13 | 禁止同拍MEM到R旁路 | 0 / 3 / 2 |
| R14 | 单源保序与ready内RR | 0 / 15 / 11 |
| R15 | 返回归属及错误优先级 | 1 / 17 / 5 |
| R16 | 退休清除和同拍复用 | 0 / 15 / 6 |
| R17 | 初始复位及集成边界 | 2 / 9 / 0 |
| R18 | 约束、cover和故障对照 | 5 / 0 / 65 |

同一 CK 可关联多个需求；不能累加本表当独立属性总数。

## 正式 FG → FC → CK 分解

### FG-API 环境与证明域

#### FC-ENV-RESET 初始复位假设

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-ENV-RESET-FIRST | environment<br>R17,R18<br>— | 首个采样时钟 rst_n=0。<br>义务：环境假设 init_sample -> !rst_n；不得以复位永久有效令安全性质空洞。 | WRAPPER；本轮pending |
| CK-ENV-RESET-RELEASE | environment<br>R17,R18<br>— | 首采样之后 rst_n=1。<br>义务：环境假设 !init_sample -> rst_n；与运行中复位未定义边界一并披露。 | WRAPPER；本轮pending |

#### FC-ENV-LEGAL 合法请求与输入约束

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-ENV-SRC | environment<br>R01,R18<br>FI001 | arvalid=1 时 src 仅取0、1、2。<br>义务：只约束有valid的src；无valid时src保持任意。 | WRAPPER；本轮pending |
| CK-ENV-ARRESP | environment<br>R15,R18<br>FI036,FI037 | arvalid=1 时 arresp 仅取00或11。<br>义务：不限制pc_err；不得把arresp=11排除。 | WRAPPER；本轮pending |
| CK-ENV-READY | environment<br>R01,R18<br>FI001,FI039,FI045 | 实际 arready=000 时 arvalid=0。<br>义务：按DUT实际ready约束，ready部分为1时不强制src所指位为1；ready正确性另行assert。 | WRAPPER；本轮pending |

### FG-AR AR 接收与元数据

#### FC-AR-HANDSHAKE 共享接收

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-AR-ACCEPT | safety<br>R01<br>FI001,FI045 | 每拍接收事件严格等于 arvalid && src<3 && arready[src]。<br>义务：用外部接口握手与分配事件等价；禁止把 &#124;arready 当目标ready。 | W_ALLOC, O_ACCEPT；本轮pending |
| CK-AR-SINGLE | safety<br>R01,R03<br>FI001,FI009 | 一次共享AR握手恰好创建一条新事务。<br>义务：独立接收序号/总live计数每次仅+1；其余已有身份不受影响。 | O_COUNT, O_IDENTITIES, O_VALID；本轮pending |
| CK-AR-NOACCEPT | safety<br>R01,R03<br>FI001,FI045 | 没有目标源握手时不得新增事务。<br>义务：按外部AR与R净事件追踪live集合；当非目标ready为1而目标ready=0时也不分配。 | O_ACCEPT, O_VALID；本轮pending |

#### FC-AR-METADATA 接受时保存并保持元数据

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-AR-ADDR-SAVE | safety<br>R02<br>FI002,FI007 | 接收的完整18位地址保存到本次事务直到退休。<br>义务：按接受序号保存任意araddr；后续实时AR变更不得修改活事务地址。 | L_ADDR, O_LIVE_META；本轮pending |
| CK-AR-SRC-SAVE | safety<br>R01,R02<br>FI001,FI007 | 每条事务始终归属于接收时的src。<br>义务：独立接受模型保存src并逐活事务比较；不能用当前src标记历史事务。 | L_SRC, O_LIVE_META；本轮pending |
| CK-AR-ID-SAVE | safety<br>R02<br>FI007,FI032 | arid全部8位原样保存，与年龄排序无关。<br>义务：任意8位、重复或非单调arid均不约束；活事务ID等于其接受值。 | L_ID, O_LIVE_META；本轮pending |
| CK-AR-PORT-SAVE | safety<br>R02<br>FI007 | port_id全部5位原样保存。<br>义务：任意5位port逐事务保存并保持。 | L_PORT, O_LIVE_META；本轮pending |
| CK-AR-RESP-SAVE | safety<br>R02,R15<br>FI007,FI036,FI037 | arresp原样保存为各事务的地址状态。<br>义务：保存接收时的00或11，不能被后续请求覆盖。 | L_ARRESP, O_LIVE_META；本轮pending |

### FG-LIFE CMDBUF/OTB 配对与生命周期

#### FC-LIFE-ALLOC 原子配对分配

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-LIFE-PAIR | safety<br>R03<br>FI009,FI023 | 每个已接收未退休事务独占一组同索引CMDBUF/OTB资源。<br>义务：建立独立live身份映射；OTB存储及返回token必须绑定同一身份，不能只证明两个内部event相等。 | O_VALID, O_IDENTITIES, O_ALLOC_OWNER, D_STORE；需加强：须补全身份/配对的合并义务；旧局部transition不单独证明配对整个生命周期。；本轮pending |
| CK-LIFE-ALLOC-FREE | safety<br>R03,R16<br>FI009,FI040 | 分配只使用当前空闲项或当拍退休的同一项。<br>义务：任意alloc_entry必须非live，唯一例外为当前外部R退休身份。 | O_ALLOC_OWNER；本轮pending |
| CK-LIFE-RANGE | safety<br>R03<br>FI003,FI009 | 所有分配、发射、捕获、退休entry索引处于0至8。<br>义务：分别对实际事件断言索引有效，不能以输入assume约束内部索引。 | W_RANGE；本轮pending |
| CK-LIFE-NEW-STATE | safety<br>R03,R05<br>FI009,FI040 | 新事务状态初始化为valid=1、issued=0、done=0。<br>义务：AR握手后一拍比较新身份状态；同拍旧项退休不得覆盖新状态。 | L_NEW；本轮pending |
| CK-LIFE-COUNT | safety<br>R03,R05<br>FI009,FI023,FI041 | live总数等于累计接收数减累计退休数，始终0至9。<br>义务：独立队列计数与有效集合一一对应；发射、捕获不改变live总数。 | O_COUNT, O_IDENTITIES, O_VALID；本轮pending |

#### FC-LIFE-STATE 已发/完成状态与留存

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-LIFE-ISSUED | safety<br>R05,R09<br>FI010,FI019,FI020,FI021,FI023 | issued只能由该事务实际双grant成功置位。<br>义务：逐事务issued等于独立握手历史，失败、选择和杂散grant不得置位。 | O_ISSUED, L_ISSUED；本轮pending |
| CK-LIFE-DONE | safety<br>R05,R12<br>FI024,FI028,FI029 | done在该事务固定到期MEM捕获时置位并保持。<br>义务：逐事务done由独立成功+4日历推进，比较CMDBUFdone；不得以内部capture作为唯一期望来源。 | O_DONE, O_CAPTURE；本轮pending |
| CK-LIFE-HOLD | safety<br>R03,R05<br>FI023,FI041 | 从接收至R退休，发射成功或MEM返回均不能释放所有权。<br>义务：独立live集合只随AR/R变化，包含pending、inflight、done三类。 | O_VALID；本轮pending |
| CK-LIFE-NODUP-ISSUE | safety<br>R05,R08<br>FI010,FI017,FI023 | 一条事务至多成功发射一次。<br>义务：身份在成功后至退休不得再次产生成功；重复ID仍按不同接受身份区分。 | O_ISSUED, O_ISSUE_PENDING；本轮pending |
| CK-LIFE-NODUP-R | safety<br>R05,R16<br>FI023,FI041 | 每次R只退休一条已接收且已完成的活事务；同一身份不重复返回。<br>义务：外部R源/身份映射到独立队列并删除，不能用DUTretire内部事件驱动唯一期望。 | O_RVALID, O_RETIRE, O_RETIRE_ID；本轮pending |

#### FC-LIFE-PENDING 待发命令数

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-PENDING-EXACT | safety<br>R05<br>FI022,FI044 | pending_cnt等于全部有效且未成功发射命令数，范围0至9。<br>义务：独立live/issued历史全九项计数，不受五项窗口限制。 | O_PENDING；本轮pending |
| CK-PENDING-UPDATE | safety<br>R05<br>FI021,FI022 | 相邻拍pending更新为旧值+当拍AR接收-当拍发射成功。<br>义务：覆盖两事件同时发生和均不发生；选择、失败、捕获及R本身不得额外改变。 | O_PENDING；本轮pending |

### FG-CAPACITY 共享容量与来源保底

#### FC-CAPACITY-ACCOUNT 按来源统计全部未退休事务

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CAP-OCC | safety<br>R04,R05<br>FI044,FI048 | occ[x]等于来源x全部已接收未退休事务数。<br>义务：独立接受/退休计数，pending/inflight/done都占容量。 | O_OCC, Q_OCC；本轮pending |
| CK-CAP-RESERVE | safety<br>R04<br>FI008,FI043,FI046 | 所有可达状态满足sum(max(occ[x],1))<=9。<br>义务：证明三源全局保底不变量；仅每源<=7不足以排除(4,5,0)。 | Q_RESERVE；本轮pending |
| CK-CAP-MAX7 | safety<br>R04<br>FI008,FI046 | 每个XAU的未退休占用不超过7。<br>义务：三源任意选择断言occ<=7，不能限制上游只送某源。 | Q_MAX7, O_RESERVE；本轮pending |
| CK-CAP-EMPTY-CAN-ACCEPT | safety<br>R04<br>FI008,FI043,FI046 | 合法状态下零占用来源在无退休时具有至少一项准入资源。<br>义务：occ[x]=0 -> arready[x]=1，前提仅rst_n与已证保底不变量，不假设公平选择src。 | Q_READY, O_READY；本轮pending |

#### FC-CAPACITY-READY 退休后准入计算与10B

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CAP-READY-FORMULA | safety<br>R04<br>FI008,FI039,FI043,FI045,FI046,FI047 | ready[x]按当拍退休后的空位和共享额度逐源精确计算。<br>义务：occ_after=occ-retire_src；free_after=9-sum(occ_after)；shared_after=sum(max(occ_after-1,0))；ready[x]=rst_n&&free_after>0&&(occ_after[x]==0&#124;&#124;shared_after<6)。 | Q_READY, O_READY；本轮pending |
| CK-CAP-700 | safety<br>R04<br>FI008,FI046 | 无退休且占用(7,0,0)时arready=110，源置换同理。<br>义务：证明源对称的7项单源保底响应，禁止借用其他源保留项。 | Q_READY；本轮pending |
| CK-CAP-440 | safety<br>R04<br>FI043,FI045 | 无退休且占用(4,4,0)时arready=100，源置换同理。<br>义务：两个活跃源不得消耗第三个空源的一项保留资源。 | Q_READY；本轮pending |
| CK-CAP-711-UNIQUE | safety<br>R04,R16<br>FI039,FI047 | (7,1,1)中源1唯一项当拍退休时arready=010。<br>义务：必须保留新空源的保底槽，不能因有物理空位广播111；源置换同理。 | Q_READY；本轮pending |
| CK-CAP-711-SHARED | safety<br>R04,R16<br>FI039,FI048 | (7,1,1)中源0共享项退休时arready=111。<br>义务：当拍归还共享额度可由任意源利用，保底策略不得制造额外气泡。 | Q_READY；本轮pending |
| CK-CAP-NET-UPDATE | safety<br>R04,R16<br>FI040,FI048 | 每源占用同拍按+accept_src-retire_src合并更新。<br>义务：同源进出净零、异源各自加减；优先级if/else不能丢失任一事件。 | O_OCC；本轮pending |
| CK-CAP-NONBLOCK-COMB | safety<br>R04<br>FI045,FI048 | arready只依赖已登记状态和当拍R退休，不依赖arvalid决定自身。<br>义务：用组合依赖静态审查或双实例同状态不同arvalid证明ready相等；本项不得以有约束的单迹恒真替代。 | 缺失：须新增；采用实现选择；本轮pending |

### FG-WINDOW 最老五项窗口与bank匹配

#### FC-WINDOW-RANK 窗口年龄与成员资格

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-WIN-AGE | safety<br>R06<br>FI012,FI016,FI032,FI040 | 年龄严格按实际AR接受先后排列；重试不改年龄，复用新项最年轻。<br>义务：独立接受FIFO位置定义年龄，不从RTLolder矩阵计算期望。 | O_AGE；本轮pending |
| CK-WIN-MEMBERS | safety<br>R06<br>FI010,FI011,FI019,FI049 | 窗口恰为当前最老5条未成功发射命令，少于5时全部入窗。<br>义务：独立顺序模型排除已issued，当前失败请求仍占名额；当前成功按6B处理。 | O_WINDOW；本轮pending |
| CK-WIN-ISSUED-EXCLUDE | safety<br>R05,R06<br>FI010,FI023 | 已成功发射但尚未退休的项不占乱序窗口名额。<br>义务：issued保持live但不参与pending排名；禁止使用最老5条未释放项。 | O_WINDOW；本轮pending |
| CK-WIN-SIXTH-BLOCK | safety<br>R06<br>FI011,FI049 | 前5条均不匹配时，即使第6条匹配也不得被选择。<br>义务：在稳定或变化status下均断言select只来自窗口；不因超时、源保底准入或空闲bank滑动窗口。 | O_WINDOW, O_CANDIDATES, O_SELECT；本轮pending |
| CK-WIN-6B | safety<br>R06,R10<br>FI018 | 当前发射成功当拍即剔除该命令参与窗口排名。<br>义务：独立rank_pool=pending & ~successmask；之前第6条可当拍进入判断、下一拍req。 | O_WINDOW, O_SELECT；本轮pending |

#### FC-WINDOW-MATCH bank/half解码与最老选择

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-WIN-BANK | safety<br>R07<br>FI003,FI004 | bank由保存地址[5:3]选择0至7。<br>义务：对任意地址验证bank编号与req位置，不能混用entry编号。 | L_BANK, O_REQ；本轮pending |
| CK-WIN-HALF | safety<br>R07<br>FI002,FI004 | half由保存地址[6]选择status[half][bank]，0表示空闲。<br>义务：对packed[1:0][7:0]全部16个位置进行通用断言和逐位cover，禁止维度转置或极性反转。 | O_CANDIDATES；本轮pending |
| CK-WIN-CANDIDATES | safety<br>R06,R07,R08<br>FI004,FI012,FI017,FI019 | 候选集合为窗内、目标half空闲且不是当前请求身份的命令。<br>义务：独立候选集合逐位相等；仅当前成功可在排名前删除，失败仍占窗口。 | O_CANDIDATES；本轮pending |
| CK-WIN-OLDEST-MATCH | safety<br>R06,R07<br>FI012,FI016 | 有候选时选择其中按接受顺序最老的一条；无候选不选择。<br>义务：独立FIFO按年龄扫描候选，不以ID、物理槽、bank或src优先。 | O_SELECT；本轮pending |
| CK-WIN-STATUS-REQUEST | safety<br>R07,R08<br>FI004,FI013,FI017 | 判断拍选中的命令在请求拍不因status改变而取消或换命令。<br>义务：select寄存进入req；请求拍是否成功只由当拍对应双grant决定。 | L_PIPE, O_REQ；采用实现选择；本轮pending |

### FG-ISSUE 三拍流水、双grant与重试

#### FC-ISSUE-PIPE 前向流水边界

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-PIPE-SELECT-NEXT | safety<br>R08<br>FI013,FI014,FI017 | 判断所得valid/entry在恰好下一拍成为请求级。<br>义务：完整比较issue_valid/identity与上一拍独立select；无选择则下一拍请求为空。 | L_PIPE, O_ISSUE；本轮pending |
| CK-PIPE-ACCEPT-NOBYPASS | safety<br>R08<br>FI013,FI042 | 刚接受的请求不得在同拍参与选择或直接发req。<br>义务：新接受身份最早下一拍判断、再下一拍请求；同拍复用亦同。 | O_REQ, O_SELECT；本轮pending |
| CK-PIPE-OVERLAP | safety<br>R08<br>FI014 | 请求A与判断B可同拍发生，前级输入也可同时接受C。<br>义务：每拍独立计算nextselect，不因当前issue_valid统一暂停选择。 | O_SELECT, O_ISSUE；本轮pending |
| CK-PIPE-CURRENT-EXCLUDE | safety<br>R08,R09<br>FI015,FI017,FI019 | 当前正尝试下发的同一命令不能同时再次被选中。<br>义务：candidate不含currentmask，无论当拍grant成功或失败。 | O_CANDIDATES；本轮pending |
| CK-PIPE-REQ-ONEHOT | safety<br>R01,R08<br>FI003,FI014,FI017 | req始终onehot0，每拍最多请求一个bank。<br>义务：对外部8位req断言onehot0。 | W_REQ；本轮pending |
| CK-PIPE-REQ-ADDR | safety<br>R02,R07,R08<br>FI002,FI003,FI007 | 有效req的12位Arbit地址严格等于该事务接受地址[17:6]。<br>义务：按独立请求身份取完整保存地址，包括bit6；不能使用实时AR或11位[17:7]。 | O_ARB_ADDR, L_PIPE；本轮pending |

#### FC-ISSUE-GRANT 同拍同bank双grant

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-GRANT-EXACT | safety<br>R09<br>FI020,FI021 | 成功严格等于|(req & ar_rd_gnt & rw_rd_gnt)。<br>义务：同bank、同周期两个grant都有效才成功；无请求、错误bank、跨拍grant均失败。 | W_SUCCESS, O_SUCCESS；本轮pending |
| CK-GRANT-FAIL-STATE | safety<br>R05,R09<br>FI016,FI019,FI020,FI026 | 失败尝试不改变该事务的issued、pending资格和原始年龄。<br>义务：按身份比较失败前后独立未发状态；允许并行其他事务的AR/R影响总状态。 | O_ISSUED, O_AGE；本轮pending |
| CK-GRANT-NOSTRAY-TOKEN | safety<br>R09,R11<br>FI021,FI026 | 无实际成功就不能为该尝试创建MEM返回token。<br>义务：独立每成功事件生成一个+4事件，单grant或无req不入日历。 | T_DELAY, O_CAPTURE；本轮pending |

#### FC-ISSUE-5A 5A失败与后续预选并行

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-RETRY-5A-B | safety<br>R08,R09<br>FI015 | A请求失败时，同拍已选B仍在下一拍发req。<br>义务：条件A失败且B选择成立，下一拍req身份必须为B，不能A抢占或整级flush。 | L_PIPE, O_ISSUE；本轮pending |
| CK-RETRY-5A-A | safety<br>R06,R09<br>FI015,FI016,FI019 | A失败后保持原龄，下一判断拍按正常窗口规则重新参与。<br>义务：不得无条件立即重发A；若A此时最老匹配且不在当前请求级，应被重新选中。 | O_AGE, O_SELECT；本轮pending |
| CK-RETRY-ONCE-TOKEN | safety<br>R09,R11<br>FI017,FI025,FI026 | 多次失败后首次成功只生成一次该身份的返回事件。<br>义务：独立成功历史至退休最多一次，失败次数不改变4拍基准。 | O_ISSUED, O_CAPTURE；本轮pending |

### FG-MEM 返回日历与完成时序

#### FC-MEM-CALENDAR 成功后固定四拍

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-MEM-EXACT4 | safety<br>R11<br>FI025,FI026,FI027 | 每个成功发射在恰好4个cycle后产生捕获，且无其他捕获。<br>义务：建立由外部成功事件启动的独立四拍历史/倒计时，capture_valid与due等价；禁止3拍、5拍或按接受/选择计时。 | T_DELAY, O_CAPTURE；本轮pending |
| CK-MEM-IDENTITY | safety<br>R11,R12<br>FI006,FI024,FI030 | 到期捕获身份等于4拍前成功发射身份。<br>义务：按独立请求队列身份延迟，不使用当前entry、接受顺序或ID作为唯一索引。 | T_ID, O_CAPTURE_ID；本轮pending |
| CK-MEM-CALENDAR-BUBBLES | safety<br>R11<br>FI026,FI027 | 日历每周期推进，空泡保持空泡，不受新请求、占满或rready影响。<br>义务：对任意间断成功序列逐周期检查到期集合，不能仅在success时移位。 | T_DELAY；本轮pending |
| CK-MEM-UNIQUE | safety<br>R11,R12<br>FI006,FI025,FI027 | 单组MEM每拍至多有一个到期身份。<br>义务：由单成功/拍和固定时延推出独立due_count<=1；不能以assume限制DUT返回。 | O_DUE；本轮pending |
| CK-MEM-NO-EARLY | safety<br>R11,R17<br>FI025,FI026 | 初始复位释放后尚未达到首个成功+4时不得捕获。<br>义务：有界历史有效位不足4时禁止伪token；全空闲与全失败同样不捕获。 | T_DELAY；本轮pending |

#### FC-MEM-COMPLETE 单拍返回与CMDBUF同步

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-MEM-DONE-SYNC | safety<br>R12<br>FI024,FI028 | 一次合法到期捕获同时使对应CMDBUF项完成。<br>义务：独立due后下一状态done=1，其他未到期项done不变；不能仅检查OTB存了数据。 | O_DONE, L_DONE；本轮pending |
| CK-MEM-NO-R-BYPASS | safety<br>R13<br>FI031 | 刚在当拍捕获的事务不能在同拍从R返回。<br>义务：R仅选择周期开始已有done的队头；capture身份与当拍retire身份不同。 | O_NO_BYPASS, O_RVALID；本轮pending |
| CK-MEM-NEXT-R-ELIGIBLE | safety<br>R13,R14<br>FI031 | 捕获后的下一拍，该事务在满足同源队头/ready/RR时可被正常选择。<br>义务：精确R获选关系必须包含上一拍完成；不要求其无条件下一拍返回。 | O_DONE, O_RVALID；本轮pending |
| CK-MEM-CONCURRENT-OLD-R | safety<br>R12,R13<br>FI031 | 捕获A不阻止另一已完成事务B在同拍正常R返回。<br>义务：R精确选择不因capture_valid统一拉低；A/B身份必须不同。 | O_RVALID；本轮pending |

### FG-DATA OTB数据与奇偶错误

#### FC-DATA-CAPTURE 全宽单拍采样

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-DATA-CAPTURE128 | safety<br>R12<br>FI006,FI028,FI029 | 到期拍的MEM全部128位写入且仅写入该事务OTB项。<br>义务：任意128位MEM数据，无值约束；每位均须验证，不以低字节、校验和或相同pattern代替。 | D_STORE；本轮pending |
| CK-DATA-PCERR-CAPTURE | safety<br>R12,R15<br>FI006,FI028,FI038 | pc_err在数据同拍按事务保存。<br>义务：任意pc_err单拍值；与独立due身份配对，不能留为实时组合输入。 | D_ERR；本轮pending |
| CK-DATA-CAPTURE-NOREADY | safety<br>R12<br>FI028 | rready=000也必须在到期拍完成数据和pc_err捕获。<br>义务：不允许R反压令MEM单拍数据丢失；错误位与128位数据均检查。 | D_STORE, D_ERR；本轮pending |
| CK-DATA-VALID-NOTVALUE | safety<br>R12<br>FI029 | 数据全0且pc_err=0同样是有效返回。<br>义务：capture只由成功+4日历决定，不能从数据/错误位推断有效。 | O_CAPTURE, D_STORE；本轮pending |

#### FC-DATA-RETENTION 保持、选路与外部数据归属

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-DATA-HOLD128 | safety<br>R12,R15<br>FI028,FI030 | 捕获后至退休期间128位数据不受后续MEM总线变化影响。<br>义务：任意entry若无alloc/retire/自身capture，则全宽保持；全局顺序另证。 | D_HOLD；本轮pending |
| CK-DATA-PCERR-HOLD | safety<br>R12,R15<br>FI038 | 每条事务的pc_err在捕获后保持至退休。<br>义务：非本项capture及后续其他事务pc_err不得覆盖本项。 | D_ERR_HOLD；本轮pending |
| CK-DATA-R-ROUTE | safety<br>R15<br>FI005,FI006,FI030 | 共享R的128位数据等于本次获选事务保存的数据。<br>义务：连接外部rvalid获选身份→rsp_entry→OTB全128位；必须与独立R身份闭合。 | W_DATA, D_RDATA, O_RETIRE_ID；本轮pending |
| CK-DATA-ENDTOEND128 | safety<br>R03,R11,R12,R14,R15<br>FI006,FI028,FI030,FI032,FI040 | 任意R响应全128位等于该事务实际成功+4拍时的MEM数据。<br>义务：独立接受身份、发射日历、采样data及退休四段完整闭合；局部存储/选路PASS不能独自充当本性质。 | O_RETIRE_ID, T_ID, D_STORE, D_HOLD, W_DATA；需加强：旧证明只有局部128位存储/选路PASS，独立order组TIMEOUT；需同次全局联合证明或受信逐lemma组合。；本轮pending |
| CK-DATA-ENDTOEND-ERR | safety<br>R12,R15<br>FI030,FI037,FI038 | 响应使用的奇偶错误属于该事务成功+4拍采样值。<br>义务：独立pc_err历史或已证日历+存储+R身份组合，禁止只把DUT rsp_pc_err当期望来源。 | O_RETIRE_ID, T_ID, D_ERR, D_ERR_HOLD；需加强：旧order模型rresp使用DUT rsp_pc_err，需独立采样历史或日历/存储/选择组合证明。；本轮pending |

### FG-RESPONSE 单源队头与ready内RR

#### FC-RESPONSE-HEAD 单XAU接受顺序

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-R-HEAD | safety<br>R14<br>FI032,FI034 | 每个来源只允许最早接收且未退休的事务成为其R候选。<br>义务：独立每源接受队列取头，不按发射顺序、完成顺序或ID排序。 | O_RVALID, O_RETIRE_ID；本轮pending |
| CK-R-HEAD-DONE | safety<br>R14<br>FI032,FI034 | 同源队头未完成时，已完成的年轻事务不能越过队头。<br>义务：源资格=head_valid && head_done && ready；年龄由独立接受序号。 | O_RVALID；本轮pending |
| CK-R-CROSS-SRC | safety<br>R14<br>FI033 | 某源队头未完成不能阻塞其他已完成且ready的来源。<br>义务：全局R选择在三个源各自队头中做精确RR，不采用全局FIFO头阻塞。 | O_RVALID；本轮pending |
| CK-R-ID-INDEPENDENT | safety<br>R02,R14<br>FI007,FI032 | 不同ID、非单调ID和重复ID均按同源接收先后返回。<br>义务：输入不约束ID唯一/递增；身份使用独立接受序号而非arid。 | O_RVALID, O_RMETA；采用实现选择；本轮pending |

#### FC-RESPONSE-RR RR精确选择

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-R-ONEHOT | safety<br>R01,R14<br>FI005,FI034 | rvalid[2:0]始终onehot0。<br>义务：单共享负载每拍最多授予一个来源。 | W_RONEHOT；本轮pending |
| CK-R-READY | safety<br>R14<br>FI034 | rvalid只可置位rready=1的来源。<br>义务：断言(rvalid & ~rready)==0；不采用反压锁定型valid。 | W_RREADY；本轮pending |
| CK-R-RR-WINNER | safety<br>R14<br>FI033,FI034,FI035 | 有资格来源时，从当前指针起按0→1→2环形顺序选首个。<br>义务：完整rvalid等于独立head/done/ready/RR计算；不能只证明onehot和ready。 | O_RVALID；采用实现选择；本轮pending |
| CK-R-RR-ADVANCE | safety<br>R14<br>FI035 | 一次实际R退休后指针移到获选来源的下一来源。<br>义务：参考指针由独立R事件更新，非按请求、MEM捕获或任何非退休事件推进。 | O_RRPTR；采用实现选择；本轮pending |
| CK-R-RR-HOLD | safety<br>R14<br>FI034,FI035 | 没有R退休时RR指针保持。<br>义务：包括rready=000、有数据但头未完成、三个源均空三种情形。 | O_RRPTR；采用实现选择；本轮pending |
| CK-R-EXACT-ELIGIBILITY | safety<br>R14<br>FI033,FI034 | 存在已完成且ready的源队头时当拍必须产生一个R；否则rvalid=0。<br>义务：精确获选而非单向合法性，防止永远rvalid=0空洞实现。 | O_RVALID；本轮pending |

### FG-RMETA R负载与错误码

#### FC-RMETA-FIELDS 同一获选事务的共享负载

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-R-ID | safety<br>R02,R15<br>FI005,FI007,FI032 | rid等于本次R事务接受时的8位arid。<br>义务：按独立R身份比对全8位，重复ID不能掩盖port/地址/数据错配。 | O_RMETA；本轮pending |
| CK-R-PORT | safety<br>R02,R15<br>FI005,FI007 | r_port_id等于本次R事务接受时的5位port_id。<br>义务：按同一独立获选身份比对全5位。 | O_RMETA；本轮pending |
| CK-R-ADDR | safety<br>R02,R15<br>FI005,FI007 | raddr等于本次R事务接受时araddr[2:0]。<br>义务：按独立获选身份比对3位低地址；不使用下游12位地址推导。 | O_RMETA；本轮pending |

#### FC-RMETA-ERROR 错误优先级与越界正常流转

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-RESP-ADDRERR | safety<br>R15<br>FI036,FI037 | arresp=11时最终rresp=11，与pc_err无关。<br>义务：分别保留pc_err=0/1两个cover；安全性质不屏蔽pc_err=1。 | O_RMETA；本轮pending |
| CK-RESP-PARITY | safety<br>R15<br>FI037,FI038 | arresp=00且本事务捕获pc_err=1时rresp=01。<br>义务：使用该事务历史pc_err；不能使用实时MEMpc_err。 | O_RMETA, D_ERR；本轮pending |
| CK-RESP-NORMAL | safety<br>R15<br>FI037 | arresp=00且本事务捕获pc_err=0时rresp=00。<br>义务：按同一事务的保存字段组合，无其他响应码。 | O_RMETA, D_ERR；本轮pending |
| CK-RESP-OOB-ISSUE | safety<br>R07,R09,R15<br>FI036 | 越界请求与普通请求同样参加选择、发射与MEM返回。<br>义务：选择、成功及到期规则不按arresp=11旁路/丢弃；不得本地提前置done。 | O_SELECT, O_SUCCESS, O_DONE；本轮pending |
| CK-RESP-ERROR-DATA | safety<br>R12,R15<br>FI006,FI028,FI037 | 错误响应的数据仍为该事务捕获的128位MEM数据。<br>义务：实现采用错误数据透传；与错误状态码分别验证，不把数据自动清零视为等价。 | W_DATA, D_RDATA, O_RETIRE_ID；采用实现选择；本轮pending |

### FG-REUSE 退休、清除与同拍复用

#### FC-REUSE-RETIRE 退休事件和清除

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-RETIRE-EXACT | safety<br>R16<br>FI005,FI041 | 退休事件严格等于外部rvalid与rready握手。<br>义务：内部retire必须与外部握手等价；不能以内部retire作为外部正确性的假设。 | W_RETIRE, O_RETIRE；本轮pending |
| CK-RETIRE-IDENTITY | safety<br>R14,R16<br>FI030,FI041 | 退休身份和OTB读出身份都等于独立R获选身份。<br>义务：retire_entry/rsp_entry绑定同一独立队头；其他entry不得一并释放。 | O_RETIRE_ID；本轮pending |
| CK-RETIRE-CLEAR-STATE | safety<br>R16<br>FI023,FI041 | 单独退休后对应CMDBUF valid/issued/done清零。<br>义务：若没有该槽新分配，下一状态全清；别的活事务保持。 | L_CLEAR, O_VALID；本轮pending |
| CK-RETIRE-CLEAR-DATA | safety<br>R16<br>FI028,FI038,FI041 | 退休且未复用的OTB数据128位与pc_err清零。<br>义务：明确验证物理清零这一采用实现；零值不能作为valid判据。 | D_CLEAR, D_ERR_CLEAR；采用实现选择；本轮pending |

#### FC-REUSE-10B 当拍释放当拍重新准入

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-REUSE-FULL-ACCEPT | safety<br>R04,R16<br>FI039,FI047,FI048 | 满9项时有R退休可立即按来源额度准入新AR。<br>义务：arready用退休后占用；有合法AR时不得固定推迟至下一拍。 | O_READY, O_ACCEPT, Q_READY；本轮pending |
| CK-REUSE-OLD-R | safety<br>R15,R16<br>FI007,FI038,FI040 | 同槽复用当拍对外R仍对应旧事务数据、ID、port、raddr和rresp。<br>义务：边沿前R取旧身份，不能被实时新AR覆盖；逐负载已有原子CK均适用。 | O_RETIRE_ID, O_RMETA, W_DATA；本轮pending |
| CK-REUSE-NEW-WINS | safety<br>R03,R16<br>FI040,FI041 | 同槽退休+接收后，新事务有效状态和元数据初始化优先。<br>义务：边沿后valid=1且issued/done=0、字段为新AR；不能退休清除覆盖新分配。 | L_NEW, L_ADDR, L_SRC, L_ID, L_PORT, L_ARRESP；本轮pending |
| CK-REUSE-NEW-OTB | safety<br>R12,R16<br>FI038,FI040 | 同槽复用后新OTB数据和pc_err初始化为0，旧返回不可污染。<br>义务：验证128位data和pcerr重置；新的合法捕获由新success+4唯一确定。 | D_CLEAR, D_ERR_CLEAR；本轮pending |
| CK-REUSE-YOUNGEST | safety<br>R06,R16<br>FI016,FI040 | 复用物理entry的新事务在所有此前活事务之后。<br>义务：独立接受FIFO追加末尾，禁止沿用旧age/旧ID身份。 | O_AGE；本轮pending |
| CK-REUSE-NEW-PIPELINE | safety<br>R08,R16<br>FI013,FI042 | 复用新事务仍须经历接受、判断、请求三个cycle。<br>义务：旧slot索引不能令新命令绕过判断寄存或继承旧issue token。 | O_REQ, O_SELECT, O_CAPTURE；本轮pending |

### FG-RESET 初始复位与无效输出

#### FC-RESET-INITIAL 初始复位结果

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-RESET-EMPTY | safety<br>R03,R17<br>— | 首个有效工作状态无活事务、已发项和完成项。<br>义务：在初始复位释放后检查独立live集合为空；不把运行中复位假装已验证。 | O_VALID, O_ISSUED, O_DONE；本轮pending |
| CK-RESET-REQ | safety<br>R08,R17<br>— | 初始复位期间及无历史选择时req=0。<br>义务：检查流水valid清零，不产生伪请求。 | G_RESET_REQ；本轮pending |
| CK-RESET-R | safety<br>R14,R17<br>— | 初始复位期间rvalid=000，无虚假R退休。<br>义务：复位后未有完成事务前R仍为零。 | G_RESET_R, O_RVALID；本轮pending |
| CK-RESET-PENDING | safety<br>R05,R17<br>— | 复位后pending_cnt=0。<br>义务：全部9项未发数初值为零。 | G_RESET_PENDING, O_PENDING；本轮pending |
| CK-RESET-READY | safety<br>R04,R17<br>— | 复位期间arready=000，释放且空表时arready=111。<br>义务：区分复位门控与首个工作态准入。 | G_RESET_AR, G_RESET_READY, Q_READY；本轮pending |
| CK-RESET-RR | safety<br>R14,R17<br>— | 初始RR指针为源0。<br>义务：与0→1→2实施选择一致；属于采用实现，不宣称原始需求定义所有RR细节。 | O_RRPTR；采用实现选择；本轮pending |

#### FC-RESET-IDLE 无效负载约定

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-IDLE-ARB | safety<br>R02,R17<br>— | req=0时arb_addr=0。<br>义务：只声明采用的无效输出清零约定，不将其作为成功/有效判断条件。 | G_IDLE_ADDR；采用实现选择；本轮pending |
| CK-IDLE-RPAYLOAD | safety<br>R02,R15,R17<br>— | rvalid=000时rdata/rid/r_port_id/raddr/rresp全部为0。<br>义务：向量零化为一个总线空闲关系；有效负载功能仍由各事务CK证明。 | G_IDLE_R, W_DATA；采用实现选择；本轮pending |

### FG-COVER-TRANSACTION 接口、流水和错误可达性

#### FC-COVER-API 逐来源与拒绝后恢复

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CV-AR0 | cover<br>R01,R18<br>FI001 | 可达源0一次合法AR接收。<br>义务：cover真实外部握手且src=0；不是仅arvalid。 | G_COVER_AR0；本轮pending |
| CK-CV-AR1 | cover<br>R01,R18<br>FI001 | 可达源1一次合法AR接收。<br>义务：cover真实外部握手且src=1。 | G_COVER_AR1；本轮pending |
| CK-CV-AR2 | cover<br>R01,R18<br>FI001 | 可达源2一次合法AR接收。<br>义务：cover真实外部握手且src=2。 | G_COVER_AR2；本轮pending |
| CK-CV-R0 | cover<br>R14,R18<br>FI005 | 可达源0一次合法R退休。<br>义务：cover外部rvalid[0]&&rready[0]。 | G_COVER_R0；本轮pending |
| CK-CV-R1 | cover<br>R14,R18<br>FI005 | 可达源1一次合法R退休。<br>义务：cover外部rvalid[1]&&rready[1]。 | G_COVER_R1；本轮pending |
| CK-CV-R2 | cover<br>R14,R18<br>FI005 | 可达源2一次合法R退休。<br>义务：cover外部rvalid[2]&&rready[2]。 | G_COVER_R2；本轮pending |
| CK-CV-UNREADY-SRC | cover<br>R01,R04,R18<br>FI001,FI045 | 部分arready有效但valid指向未ready来源，未接收；之后切src成功接收。<br>义务：记录拒绝与后续另一src握手，输入始终满足全零ready时valid为0。 | 缺失：须新增；本轮pending |

#### FC-COVER-PIPELINE 三拍、并行、重试

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CV-MIN3 | cover<br>R08,R18<br>FI013,FI042 | 某身份C1接受、C2判断、C3请求成功。<br>义务：cover同一接受身份连续三拍关系，不能三个无关事务事件拼接。 | 缺失：须新增；本轮pending |
| CK-CV-PIPE-ALL | cover<br>R08,R11,R12,R16,R18<br>FI014,FI027,FI031,FI048 | 同拍出现接受、判断、成功、MEM捕获和R退休。<br>义务：五个合法阶段边界同时成立，各自身份按年龄和日历合法。 | C_ALL_EVENTS；本轮pending |
| CK-CV-ISSUE-CONSECUTIVE | cover<br>R08,R18<br>FI014 | 相邻周期发射两条不同事务成功。<br>义务：cover连续success且独立身份不同，避免同条重发充当吞吐。 | 缺失：须新增；本轮pending |
| CK-CV-5A-B | cover<br>R09,R18<br>FI015 | A失败同拍选B，下一拍B请求。<br>义务：追踪A/B身份，B不能被失败A抢占。 | C_5A_B；本轮pending |
| CK-CV-5A-A | cover<br>R09,R18<br>FI015,FI016 | A失败后的下一判断拍重新选A，并再下一拍A请求。<br>义务：原旧cover只见重新选择；本点补齐直到A再次req的身份链。 | C_5A_A；需加强：旧cover止于重新选择A，新义务包含下一拍请求A。；本轮pending |
| CK-CV-RETRY-TO-R | cover<br>R09,R11,R16,R18<br>FI015,FI016,FI026 | 同一身份至少失败一次，随后成功、捕获、最终R退休。<br>义务：失败身份必须与最后退休一致，不能任意其他事务退休代替。 | C_RETRY_R；本轮pending |
| CK-CV-AR-ONLY-GRANT | cover<br>R09,R18<br>FI020 | 有req且仅目标ar_rd_gnt=1，失败。<br>义务：显式失败cover，不约束全局grant onehot。 | G_COVER_ARONLY；本轮pending |
| CK-CV-RW-ONLY-GRANT | cover<br>R09,R18<br>FI020 | 有req且仅目标rw_rd_gnt=1，失败。<br>义务：显式单边读冲裁失败cover。 | G_COVER_RWONLY；本轮pending |
| CK-CV-WRONG-GRANT | cover<br>R09,R18<br>FI020,FI021 | 非请求bank的两个grant同时为1仍失败。<br>义务：目标grant未双有效，同时另一bank双有效。 | G_COVER_WRONGBANK；本轮pending |
| CK-CV-STAGGER-GRANT | cover<br>R09,R18<br>FI020 | 同一失败尝试中两grant分开出现在不同时钟，不能合成成功。<br>义务：追踪相邻尝试/源身份并证明每次单边时都未成功；合法重试另行cover。 | 缺失：须新增；本轮pending |
| CK-CV-STRAY-GRANT | cover<br>R09,R18<br>FI021 | req=0时出现双grant，无成功及对应token。<br>义务：见证杂散grant后4拍无由该grant产生的捕获；可允许其他旧合法token到期。 | 缺失：须新增；本轮pending |

#### FC-COVER-ERROR 错误组合与数据值

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CV-ERR00 | cover<br>R15,R18<br>FI037 | arresp=00、采样pc_err=0，最终rresp=00。<br>义务：同一事务从接受/采样到R，禁止只cover当拍组合输入。 | 缺失：须新增；本轮pending |
| CK-CV-ERR01 | cover<br>R15,R18<br>FI037,FI038 | arresp=00、采样pc_err=1，最终rresp=01。<br>义务：同一事务错误历史跟踪直到R。 | 缺失：须新增；本轮pending |
| CK-CV-ERR10 | cover<br>R15,R18<br>FI036,FI037 | arresp=11、采样pc_err=0，仍发MEM并最终rresp=11。<br>义务：同一事务已真实发射且+4捕获后R。 | 缺失：须新增；本轮pending |
| CK-CV-ERR11 | cover<br>R15,R18<br>FI036,FI037,FI038 | arresp=11、采样pc_err=1，最终rresp=11。<br>义务：同一事务同时两种异常证明地址优先场景可达。 | 缺失：须新增；本轮pending |
| CK-CV-ZERO-DATA | cover<br>R12,R18<br>FI029 | 到期采样全0数据且pc_err=0后最终正常R。<br>义务：旧局部cover只到capture；本点要求对应事务最终R，不能被值零误判无效。 | C_ZERO_DATA；需加强：旧cover仅在采样时见零数据，新义务需对应身份走到R。；本轮pending |
| CK-CV-UPPER-DATA | cover<br>R12,R15,R18<br>FI006,FI028 | 一条事务高64位和低64位不同且高位非零，R完整透传。<br>义务：cover区分高半部截断；128位安全证明仍需任意向量。 | 缺失：须新增；本轮pending |

### FG-COVER-BOUNDARY 窗口、资源、响应边界可达性

#### FC-COVER-WINDOW 窗口与ID身份

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CV-SIXTH-BLOCKED | cover<br>R06,R18<br>FI011 | 前5条不能匹配、第6条可匹配，status连续至少2拍不变且无请求级干扰，持续不发。<br>义务：cover至少6pending、当前及前拍无请求、全部窗内不匹配、第6空闲；安全CK保证任意延续长度仍不越窗。 | C_SIXTH；本轮pending |
| CK-CV-6B | cover<br>R06,R10,R18<br>FI018 | 成功A当拍前馈使原第6条B进入判断。<br>义务：记录B不在未前馈基础窗口、A成功且B被选，下一拍发B。 | C_6B；需加强：旧cover止于原第6项被选择，新义务还要求下一拍请求身份相同。；本轮pending |
| CK-CV-FAIL-KEEPS-WINDOW | cover<br>R06,R09,R18<br>FI019 | A失败仍占窗口，原第6条虽空闲也不能提前进入。<br>义务：见证失败与5条排名同时成立；不能把失败当成功剔除。 | 缺失：须新增；本轮pending |
| CK-CV-QUOTA-NO-ESCAPE | cover<br>R04,R06,R18<br>FI049 | 源0的5条老命令均忙，源1保底接收第6条空闲命令仍不发。<br>义务：同时覆盖接收资源独立和严格5项窗口阻塞。 | 缺失：须新增；本轮pending |
| CK-CV-OUT-OF-ORDER | cover<br>R06,R07,R18<br>FI012,FI030 | 较年轻命令在更老pending命令前成功发射。<br>义务：cover确有更老未发身份，不仅不同物理slot。 | C_OOO；本轮pending |
| CK-CV-DUPLICATE-ID | cover<br>R02,R14,R18<br>FI007,FI032 | 同源两条同时live且arid相同，元数据/数据不同，依接受顺序R返回。<br>义务：跟踪两条独立序号并直至两次响应，禁止ID唯一assume。 | 缺失：须新增；本轮pending |
| CK-CV-NONMONOTONIC-ID | cover<br>R02,R14,R18<br>FI007,FI032 | 同源后接收ID数值较小的事务仍后返回。<br>义务：至少两条live、ID逆序且两者R先后可观察。 | 缺失：须新增；本轮pending |
| CK-CV-CROSS-SRC-ID | cover<br>R02,R14,R18<br>FI007,FI032,FI033 | 不同来源同ID并存且都能正确返回。<br>义务：来源/port/地址区分事务，不只按ID匹配。 | 缺失：须新增；本轮pending |
| CK-CV-STATUS-FLIP | cover<br>R07,R08,R18<br>FI004,FI013 | 判断拍目标half空闲，请求拍变忙，但双grant成功。<br>义务：同一身份记录status翻转，仍保持请求并成功。 | 缺失：须新增；本轮pending |

#### FC-COVER-CAPACITY 保底与满表复用

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CV-CAP700 | cover<br>R04,R18<br>FI008,FI046 | 达到(7,0,0)且无退休，arready=110。<br>义务：包含ready值，旧cover只有占用状态不足以单独覆盖完整点。 | C_700；需加强：旧cover仅占用700，新义务同时要求无退休与ready110。；本轮pending |
| CK-CV-CAP440 | cover<br>R04,R18<br>FI043,FI045 | 达到(4,4,0)且无退休，arready=100。<br>义务：禁止把非法(4,5,0)设为cover目标；该状态应不可达。 | C_440；需加强：旧cover仅占用440，新义务同时要求无退休与ready100。；本轮pending |
| CK-CV-CAP711 | cover<br>R04,R18<br>FI008,FI043 | 达到(7,1,1)且无退休，arready=000、arvalid=0。<br>义务：满9项见证不得违反全零ready输入限制。 | 缺失：须新增；本轮pending |
| CK-CV-UNIQUE-REFILL | cover<br>R04,R16,R18<br>FI039,FI047 | 满表(7,1,1)源1唯一项退休，ready=010并接收源1。<br>义务：合法同拍10B见证。 | C_UNIQUE_REFILL；本轮pending |
| CK-CV-SHARED-REFILL | cover<br>R04,R16,R18<br>FI039,FI048 | 满表源0共享项退休，ready=111并接收另一源。<br>义务：同拍退休与接收来源不同，下一占用如(6,1,2)。 | 缺失：须新增；本轮pending |
| CK-CV-SAME-SRC-NETZERO | cover<br>R04,R16,R18<br>FI040,FI048 | 单源7项时同拍退休一项且接收同源新项，占用仍7。<br>义务：比较前后占用及新旧接受身份，不以计数没变掩盖丢请求。 | C_SEVEN_REFILL；本轮pending |
| CK-CV-FULL-SLOT-REUSE | cover<br>R03,R16,R18<br>FI039,FI040,FI041 | 满表时同一物理槽退休+新分配，随后新事务独立完成。<br>义务：旧cover只到当拍reuse；本点补新身份正常路径至R。 | C_FULL_REUSE；需加强：旧cover只到同槽复用当拍，新义务需新事务后续完整退休。；本轮pending |

#### FC-COVER-MEM 数据捕获与R边界

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CV-CAPTURE-NOREADY | cover<br>R12,R18<br>FI028 | MEM到期单拍返回时rready=000，之后同身份数据正确返回。<br>义务：捕获后MEM任意变化、后续ready释放；不得用ready约束保障不丢失。 | 缺失：须新增；本轮pending |
| CK-CV-CALENDAR-BUBBLE | cover<br>R11,R18<br>FI026,FI027 | 两个成功之间至少一个空泡，相应到期序列也保留空泡。<br>义务：逐成功身份与+4时钟关系，不把发射序号当时间。 | 缺失：须新增；本轮pending |
| CK-CV-MEM-NEXT-R | cover<br>R13,R18<br>FI031 | 某身份在MEM捕获后恰好下一拍R返回。<br>义务：capture身份与下一拍retire身份相同，上一拍不得已返回。 | C_NEXT_R；本轮pending |
| CK-CV-MEM-OTHER-R | cover<br>R12,R13,R18<br>FI031 | 捕获A的同一拍返回之前已完成B。<br>义务：两个不同身份，A最早后续拍R。 | 缺失：须新增；本轮pending |

#### FC-COVER-RR 保序和轮询见证

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CV-YOUNGER-DONE | cover<br>R14,R18<br>FI032,FI034 | 同源年轻事务已完成但老队头尚未完成，年轻事务不R。<br>义务：跟踪至少两条同源不同接受身份。 | C_YOUNGER_DONE；本轮pending |
| CK-CV-REORDER-TO-ORDER | cover<br>R14,R18<br>FI030,FI032 | 同源B晚接受先完成，最终A先R、B再R。<br>义务：必须同一A/B对完成完整重排恢复；旧RETIRE_AFTER_REORDER仅任意退休不足。 | C_REORDER_R；需加强：旧cover见过乱序后任意退休不足，必须同一A/B对恢复为A先B后。；本轮pending |
| CK-CV-CROSS-SRC-PROGRESS | cover<br>R14,R18<br>FI033 | 源0队头未完成时源1完成队头R成功。<br>义务：局部有限见证，不声称无条件最终公平。 | 缺失：须新增；本轮pending |
| CK-CV-RR-ROTATE | cover<br>R14,R18<br>FI035 | 三源队头均完成且ready时连续三次服务按0→1→2环序。<br>义务：固定起始指针或记录实际起始源，三次均有资格；旧ALL_READY单次见证不足。 | C_RR_ALL；需加强：旧cover只一次三个源均有资格，不等于连续三次轮转。；本轮pending |
| CK-CV-RR-MASKS | cover<br>R14,R18<br>FI034,FI035 | 有完成数据时ready依次110、001、000、100，观察跳过、空拍和恢复。<br>义务：四拍连续见证，模型RR保持/推进正确；不是四个无关单拍cover。 | 缺失：须新增；本轮pending |

### FG-COVER-DECODE 16个bank/half精确可达性

#### FC-COVER-EVEN 偶half的8个bank

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CV-H0-B0 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[0][0]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[0]、arb_addr[0]=0以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H0-B1 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[0][1]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[1]、arb_addr[0]=0以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H0-B2 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[0][2]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[2]、arb_addr[0]=0以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H0-B3 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[0][3]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[3]、arb_addr[0]=0以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H0-B4 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[0][4]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[4]、arb_addr[0]=0以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H0-B5 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[0][5]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[5]、arb_addr[0]=0以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H0-B6 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[0][6]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[6]、arb_addr[0]=0以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H0-B7 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[0][7]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[7]、arb_addr[0]=0以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |

#### FC-COVER-ODD 奇half的8个bank

| 稳定 CK | 类型 / 需求 / 故障 | 期望行为和应有证据 | 现有属性关系 |
| --- | --- | --- | --- |
| CK-CV-H1-B0 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[1][0]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[0]、arb_addr[0]=1以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H1-B1 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[1][1]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[1]、arb_addr[0]=1以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H1-B2 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[1][2]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[2]、arb_addr[0]=1以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H1-B3 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[1][3]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[3]、arb_addr[0]=1以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H1-B4 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[1][4]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[4]、arb_addr[0]=1以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H1-B5 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[1][5]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[5]、arb_addr[0]=1以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H1-B6 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[1][6]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[6]、arb_addr[0]=1以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |
| CK-CV-H1-B7 | cover<br>R07,R18<br>FI002,FI003,FI004 | 只有status[1][7]=0、其余15位=1时，对应half/bank事务可被选中并成功发射。<br>义务：记录该事务判断拍的唯一空闲模式和下一拍正确req[7]、arb_addr[0]=1以及同bank双grant；每个组合独立见证。 | 缺失：须新增；本轮pending |

## 49 类故障逐项映射

下表每类至少对应一个安全义务。原始注错变体、最小激励、检查意图和时序图编号完整保留在 JSON；这里没有声称变异已运行。

| 故障 | 名称 | 安全 CK | cover CK |
| --- | --- | --- | --- |
| FI001 | 共享 AR 的接收与源归属 | CK-AR-ACCEPT, CK-AR-SINGLE, CK-AR-NOACCEPT, CK-AR-SRC-SAVE | CK-CV-AR0, CK-CV-AR1, CK-CV-AR2, CK-CV-UNREADY-SRC |
| FI002 | Arbit 地址保留奇偶位 | CK-AR-ADDR-SAVE, CK-WIN-HALF, CK-PIPE-REQ-ADDR | CK-CV-H0-B0, CK-CV-H0-B1, CK-CV-H0-B2, CK-CV-H0-B3, CK-CV-H0-B4, CK-CV-H0-B5, CK-CV-H0-B6, CK-CV-H0-B7, CK-CV-H1-B0, CK-CV-H1-B1, CK-CV-H1-B2, CK-CV-H1-B3, CK-CV-H1-B4, CK-CV-H1-B5, CK-CV-H1-B6, CK-CV-H1-B7 |
| FI003 | 八个 Bank 的编号解码 | CK-LIFE-RANGE, CK-WIN-BANK, CK-PIPE-REQ-ONEHOT, CK-PIPE-REQ-ADDR | CK-CV-H0-B0, CK-CV-H0-B1, CK-CV-H0-B2, CK-CV-H0-B3, CK-CV-H0-B4, CK-CV-H0-B5, CK-CV-H0-B6, CK-CV-H0-B7, CK-CV-H1-B0, CK-CV-H1-B1, CK-CV-H1-B2, CK-CV-H1-B3, CK-CV-H1-B4, CK-CV-H1-B5, CK-CV-H1-B6, CK-CV-H1-B7 |
| FI004 | rd_mem_status 维度与空闲极性 | CK-WIN-BANK, CK-WIN-HALF, CK-WIN-CANDIDATES, CK-WIN-STATUS-REQUEST | CK-CV-STATUS-FLIP, CK-CV-H0-B0, CK-CV-H0-B1, CK-CV-H0-B2, CK-CV-H0-B3, CK-CV-H0-B4, CK-CV-H0-B5, CK-CV-H0-B6, CK-CV-H0-B7, CK-CV-H1-B0, CK-CV-H1-B1, CK-CV-H1-B2, CK-CV-H1-B3, CK-CV-H1-B4, CK-CV-H1-B5, CK-CV-H1-B6, CK-CV-H1-B7 |
| FI005 | 共享 R 负载与唯一接收对象 | CK-DATA-R-ROUTE, CK-R-ONEHOT, CK-R-ID, CK-R-PORT, CK-R-ADDR, CK-RETIRE-EXACT | CK-CV-R0, CK-CV-R1, CK-CV-R2 |
| FI006 | 单组 MEM 返回接口 | CK-MEM-IDENTITY, CK-MEM-UNIQUE, CK-DATA-CAPTURE128, CK-DATA-PCERR-CAPTURE, CK-DATA-R-ROUTE, CK-DATA-ENDTOEND128, CK-RESP-ERROR-DATA | CK-CV-UPPER-DATA |
| FI007 | 事务元数据完整保存与透传 | CK-AR-ADDR-SAVE, CK-AR-SRC-SAVE, CK-AR-ID-SAVE, CK-AR-PORT-SAVE, CK-AR-RESP-SAVE, CK-PIPE-REQ-ADDR, CK-R-ID-INDEPENDENT, CK-R-ID, CK-R-PORT, CK-R-ADDR, CK-REUSE-OLD-R | CK-CV-DUPLICATE-ID, CK-CV-NONMONOTONIC-ID, CK-CV-CROSS-SRC-ID |
| FI008 | 共享池防止单个 XAU 独占容量 | CK-CAP-RESERVE, CK-CAP-MAX7, CK-CAP-EMPTY-CAN-ACCEPT, CK-CAP-READY-FORMULA, CK-CAP-700 | CK-CV-CAP700, CK-CV-CAP711 |
| FI009 | CMDBUF 与 OTB 原子分配和一一对应 | CK-AR-SINGLE, CK-LIFE-PAIR, CK-LIFE-ALLOC-FREE, CK-LIFE-RANGE, CK-LIFE-NEW-STATE, CK-LIFE-COUNT | 由相关序列cover及guard见证补查 |
| FI010 | 窗口排除已成功发射但未退休命令 | CK-LIFE-ISSUED, CK-LIFE-NODUP-ISSUE, CK-WIN-MEMBERS, CK-WIN-ISSUED-EXCLUDE | 由相关序列cover及guard见证补查 |
| FI011 | 五项全部阻塞时不得越窗选择第六项 | CK-WIN-MEMBERS, CK-WIN-SIXTH-BLOCK | CK-CV-SIXTH-BLOCKED |
| FI012 | 窗口内选择最老可用命令 | CK-WIN-AGE, CK-WIN-CANDIDATES, CK-WIN-OLDEST-MATCH | CK-CV-OUT-OF-ORDER |
| FI013 | 接收判断请求的三拍路径 | CK-WIN-STATUS-REQUEST, CK-PIPE-SELECT-NEXT, CK-PIPE-ACCEPT-NOBYPASS, CK-REUSE-NEW-PIPELINE | CK-CV-MIN3, CK-CV-STATUS-FLIP |
| FI014 | 不同命令之间的流水重叠 | CK-PIPE-SELECT-NEXT, CK-PIPE-OVERLAP, CK-PIPE-REQ-ONEHOT | CK-CV-PIPE-ALL, CK-CV-ISSUE-CONSECUTIVE |
| FI015 | 5A 仲裁失败保留下一条预选 | CK-PIPE-CURRENT-EXCLUDE, CK-RETRY-5A-B, CK-RETRY-5A-A | CK-CV-5A-B, CK-CV-5A-A, CK-CV-RETRY-TO-R |
| FI016 | 失败重试保留原年龄 | CK-WIN-AGE, CK-WIN-OLDEST-MATCH, CK-GRANT-FAIL-STATE, CK-RETRY-5A-A, CK-REUSE-YOUNGEST | CK-CV-5A-A, CK-CV-RETRY-TO-R |
| FI017 | 屏蔽当前请求级命令的重复预选 | CK-LIFE-NODUP-ISSUE, CK-WIN-CANDIDATES, CK-WIN-STATUS-REQUEST, CK-PIPE-SELECT-NEXT, CK-PIPE-CURRENT-EXCLUDE, CK-PIPE-REQ-ONEHOT, CK-RETRY-ONCE-TOKEN | 由相关序列cover及guard见证补查 |
| FI018 | 6B 成功当拍前移窗口 | CK-WIN-6B | CK-CV-6B |
| FI019 | 请求失败不能提前腾出窗口名额 | CK-LIFE-ISSUED, CK-WIN-MEMBERS, CK-WIN-CANDIDATES, CK-PIPE-CURRENT-EXCLUDE, CK-GRANT-FAIL-STATE, CK-RETRY-5A-A | CK-CV-FAIL-KEEPS-WINDOW |
| FI020 | 目标 Bank 双 grant 同拍成功 | CK-LIFE-ISSUED, CK-GRANT-EXACT, CK-GRANT-FAIL-STATE | CK-CV-AR-ONLY-GRANT, CK-CV-RW-ONLY-GRANT, CK-CV-WRONG-GRANT, CK-CV-STAGGER-GRANT |
| FI021 | 无请求时 grant 不得制造成功 | CK-LIFE-ISSUED, CK-PENDING-UPDATE, CK-GRANT-EXACT, CK-GRANT-NOSTRAY-TOKEN | CK-CV-WRONG-GRANT, CK-CV-STRAY-GRANT |
| FI022 | 待发计数统计全部未成功命令 | CK-PENDING-EXACT, CK-PENDING-UPDATE | 由相关序列cover及guard见证补查 |
| FI023 | 命令保留到 R 返回 | CK-LIFE-PAIR, CK-LIFE-COUNT, CK-LIFE-ISSUED, CK-LIFE-HOLD, CK-LIFE-NODUP-ISSUE, CK-LIFE-NODUP-R, CK-WIN-ISSUED-EXCLUDE, CK-RETIRE-CLEAR-STATE | 由相关序列cover及guard见证补查 |
| FI024 | MEM 完成同时通知 CMDBUF | CK-LIFE-DONE, CK-MEM-IDENTITY, CK-MEM-DONE-SYNC | 由相关序列cover及guard见证补查 |
| FI025 | 固定四拍从成功接收起算 | CK-RETRY-ONCE-TOKEN, CK-MEM-EXACT4, CK-MEM-UNIQUE, CK-MEM-NO-EARLY | 由相关序列cover及guard见证补查 |
| FI026 | 失败请求不启动返回计时 | CK-GRANT-FAIL-STATE, CK-GRANT-NOSTRAY-TOKEN, CK-RETRY-ONCE-TOKEN, CK-MEM-EXACT4, CK-MEM-CALENDAR-BUBBLES, CK-MEM-NO-EARLY | CK-CV-RETRY-TO-R, CK-CV-CALENDAR-BUBBLE |
| FI027 | 返回标记每拍前进且保留空泡 | CK-MEM-EXACT4, CK-MEM-CALENDAR-BUBBLES, CK-MEM-UNIQUE | CK-CV-PIPE-ALL, CK-CV-CALENDAR-BUBBLE |
| FI028 | MEM 单拍返回必须立即捕获 | CK-LIFE-DONE, CK-MEM-DONE-SYNC, CK-DATA-CAPTURE128, CK-DATA-PCERR-CAPTURE, CK-DATA-CAPTURE-NOREADY, CK-DATA-HOLD128, CK-DATA-ENDTOEND128, CK-RESP-ERROR-DATA, CK-RETIRE-CLEAR-DATA | CK-CV-UPPER-DATA, CK-CV-CAPTURE-NOREADY |
| FI029 | pc_err 与零数据不能充当有效信号 | CK-LIFE-DONE, CK-DATA-CAPTURE128, CK-DATA-VALID-NOTVALUE | CK-CV-ZERO-DATA |
| FI030 | 返回标记绑定原命令 | CK-MEM-IDENTITY, CK-DATA-HOLD128, CK-DATA-R-ROUTE, CK-DATA-ENDTOEND128, CK-DATA-ENDTOEND-ERR, CK-RETIRE-IDENTITY | CK-CV-OUT-OF-ORDER, CK-CV-REORDER-TO-ORDER |
| FI031 | MEM 捕获当拍禁止该命令 R 旁路 | CK-MEM-NO-R-BYPASS, CK-MEM-NEXT-R-ELIGIBLE, CK-MEM-CONCURRENT-OLD-R | CK-CV-PIPE-ALL, CK-CV-MEM-NEXT-R, CK-CV-MEM-OTHER-R |
| FI032 | 同 XAU 按接收年龄保序 | CK-AR-ID-SAVE, CK-WIN-AGE, CK-DATA-ENDTOEND128, CK-R-HEAD, CK-R-HEAD-DONE, CK-R-ID-INDEPENDENT, CK-R-ID | CK-CV-DUPLICATE-ID, CK-CV-NONMONOTONIC-ID, CK-CV-CROSS-SRC-ID, CK-CV-YOUNGER-DONE, CK-CV-REORDER-TO-ORDER |
| FI033 | 不同 XAU 不施加全局返回顺序 | CK-R-CROSS-SRC, CK-R-RR-WINNER, CK-R-EXACT-ELIGIBILITY | CK-CV-CROSS-SRC-ID, CK-CV-CROSS-SRC-PROGRESS |
| FI034 | RR 只选 ready 的完成队头 | CK-R-HEAD, CK-R-HEAD-DONE, CK-R-ONEHOT, CK-R-READY, CK-R-RR-WINNER, CK-R-RR-HOLD, CK-R-EXACT-ELIGIBILITY | CK-CV-YOUNGER-DONE, CK-CV-RR-MASKS |
| FI035 | RR 推进与空闲保持 | CK-R-RR-WINNER, CK-R-RR-ADVANCE, CK-R-RR-HOLD | CK-CV-RR-ROTATE, CK-CV-RR-MASKS |
| FI036 | 地址越界命令仍访问 MEM | CK-AR-RESP-SAVE, CK-RESP-ADDRERR, CK-RESP-OOB-ISSUE | CK-CV-ERR10, CK-CV-ERR11 |
| FI037 | 越界异常优先于奇偶异常 | CK-AR-RESP-SAVE, CK-DATA-ENDTOEND-ERR, CK-RESP-ADDRERR, CK-RESP-PARITY, CK-RESP-NORMAL, CK-RESP-ERROR-DATA | CK-CV-ERR00, CK-CV-ERR01, CK-CV-ERR10, CK-CV-ERR11 |
| FI038 | pc_err 与所属 OTB 命令一起保存 | CK-DATA-PCERR-CAPTURE, CK-DATA-PCERR-HOLD, CK-DATA-ENDTOEND-ERR, CK-RESP-PARITY, CK-RETIRE-CLEAR-DATA, CK-REUSE-OLD-R, CK-REUSE-NEW-OTB | CK-CV-ERR01, CK-CV-ERR11 |
| FI039 | 10B 满表同拍退休与接收 | CK-CAP-READY-FORMULA, CK-CAP-711-UNIQUE, CK-CAP-711-SHARED, CK-REUSE-FULL-ACCEPT | CK-CV-UNIQUE-REFILL, CK-CV-SHARED-REFILL, CK-CV-FULL-SLOT-REUSE |
| FI040 | 同槽复用保留旧响应并初始化新命令 | CK-LIFE-ALLOC-FREE, CK-LIFE-NEW-STATE, CK-CAP-NET-UPDATE, CK-WIN-AGE, CK-DATA-ENDTOEND128, CK-REUSE-OLD-R, CK-REUSE-NEW-WINS, CK-REUSE-NEW-OTB, CK-REUSE-YOUNGEST | CK-CV-SAME-SRC-NETZERO, CK-CV-FULL-SLOT-REUSE |
| FI041 | R 退休同时清除两侧归属 | CK-LIFE-COUNT, CK-LIFE-HOLD, CK-LIFE-NODUP-R, CK-RETIRE-EXACT, CK-RETIRE-IDENTITY, CK-RETIRE-CLEAR-STATE, CK-RETIRE-CLEAR-DATA, CK-REUSE-NEW-WINS | CK-CV-FULL-SLOT-REUSE |
| FI042 | 复用新命令仍遵守三拍路径 | CK-PIPE-ACCEPT-NOBYPASS, CK-REUSE-NEW-PIPELINE | CK-CV-MIN3 |
| FI043 | 两个 XAU 联合占用仍为第三路保留名额 | CK-CAP-RESERVE, CK-CAP-EMPTY-CAN-ACCEPT, CK-CAP-READY-FORMULA, CK-CAP-440 | CK-CV-CAP440, CK-CV-CAP711 |
| FI044 | 占用额度统计到真正 R 退休 | CK-PENDING-EXACT, CK-CAP-OCC | 由相关序列cover及guard见证补查 |
| FI045 | 逐来源 ready 判定 | CK-AR-ACCEPT, CK-AR-NOACCEPT, CK-CAP-READY-FORMULA, CK-CAP-440, CK-CAP-NONBLOCK-COMB | CK-CV-UNREADY-SRC, CK-CV-CAP440 |
| FI046 | 空闲来源的保底项不可借出 | CK-CAP-RESERVE, CK-CAP-MAX7, CK-CAP-EMPTY-CAN-ACCEPT, CK-CAP-READY-FORMULA, CK-CAP-700 | CK-CV-CAP700 |
| FI047 | 满表退休最后一项只恢复该来源保底 | CK-CAP-READY-FORMULA, CK-CAP-711-UNIQUE, CK-REUSE-FULL-ACCEPT | CK-CV-UNIQUE-REFILL |
| FI048 | 同拍退休接收的每来源计数合成 | CK-CAP-OCC, CK-CAP-711-SHARED, CK-CAP-NET-UPDATE, CK-CAP-NONBLOCK-COMB, CK-REUSE-FULL-ACCEPT | CK-CV-PIPE-ALL, CK-CV-SHARED-REFILL, CK-CV-SAME-SRC-NETZERO |
| FI049 | 容量保护不改变五项发射窗口 | CK-WIN-MEMBERS, CK-WIN-SIXTH-BLOCK | CK-CV-QUOTA-NO-ESCAPE |

## 合同与未证明范围

- **CT-RESET**（R17；U01）：采用低有效异步复位实现；本轮formal仅首采样复位后永久释放。 边界：运行中带未完成MEM返回时复位冲刷/跨时钟域/复位去使能硬件时序未定义，不能声称已证明。
- **CT-ILLEGAL**（R01,R15,R18；U02）：有valid时src=3、arresp=01/10在输入域外；无valid元数据可任意。 边界：非法编码行为没有强行定义成DUT bug，合法域证据不覆盖非法协议输入。
- **CT-ID**（R02,R14；U03）：现有实现及本轮验证域允许同源/跨源重复ID、非单调ID；不添加ID唯一性assume。 边界：原故障目录U03曾未定，此为采用的实现兼容行为，不改写用户原始确认历史。
- **CT-CLEAR**（R16；U04）：采用退休/新分配时OTB数据和pc_err物理清零，并单列安全义务。 边界：原用户要求清除可能仅指逻辑失效，物理清零是采用实现选择。
- **CT-ERROR-DATA**（R12,R15；U05）：采用错误响应也透传已捕获数据；地址错误优先级高于pc_err为已确认要求。 边界：错误响应的数据内容规范不冒充原始用户明确要求。
- **CT-RR**（R14；U06）：采用初始指针0、0→1→2、实际R服务后推进、空闲保持。 边界：不能仅从用户说RR就声称其已指定所有方向和初值细节。
- **CT-STATUS**（R07,R08,R09；U07）：采用判断拍采样选择，req拍status变化不撤销；req拍对应双grant决定成功。 边界：不假设status稳定至请求周期，不用assume隐藏该边界。
- **CT-IDLE**（R02,R17；U08）：采用无效req/R负载清零，功能有效性仍只看事件及有效位。 边界：无效负载零值不证明交易正确，也不得从零数据推导未返回。
- **CT-FAIRNESS**（R04,R06,R14,R18；U08,U09）：上游允许切src，但未定义公平性；grant、status、rready均无最终服务假设。 边界：仅保证资源准入保底和精确有限步行为，不声称每请求必最终被输入/发射/返回；前5项永忙可合法永久阻塞后续第6项。
- **CT-FIXED-CONFIG**（R01,R03,R17；implementation_scope）：固定9项、3源、单时钟、128位MEM返回、固定4拍；无burst/rlast/MEMvalid。 边界：不证明MEM阵列内容正确性、数据与地址的内存语义、CDC、STA、参数化所有配置或复位模拟电气时序。
- **CT-FORMAL-STATUS**（R18；verification_method）：safety需要prove；cover是可达见证；Assume是域声明；compile、BMC未发现反例、timeout不能升级为prove PASS。 边界：49故障类的映射不等于49变异已经执行或全部被检出。

## 旧证据使用规则

旧 native 的 wiring/local_transition/calendar_delay/data_transition 曾有局部 prove 结果；order、capacity、structure 存在未决运行。各旧属性的精确源码位置、hash、run_id、compiled_property_id、原始 status 和证据路径在 JSON evidence_registry 中保留。它们是可复核的候选或组合依赖，不能自动作为本轮对应 CK PASS。

全128位端到端数据需要接受身份、独立发射顺序、+4返回日历、保存及R选择一起闭合。仅证明 OTB 每次保存输入，不足以证明对外数据归属；仅用 DUT rsp_pc_err 计算期望，也必须另有独立错误采样/归属证明。

原始 cover 若只记录一次占用、一次重新选择、见过乱序后任意退休，本轮增强为规定身份和前后序列；这些点标记 needs_strengthening。65个业务cover和工具自动guard witness分别统计，cover命中不替代安全证明。

## 本目录结构审查

已检查：177 个 CK ID 唯一；全部18需求有映射；49/49故障类至少有安全CK；每个FG包含多个FC；所有proof_status均pending；没有将合同边界当作成功属性。未运行求解，未改冻结证据、RTL或工具。
