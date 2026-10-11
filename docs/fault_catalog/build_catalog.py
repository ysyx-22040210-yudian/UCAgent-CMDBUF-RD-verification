from pathlib import Path
import html
import json
import shutil

OUT = Path(__file__).resolve().parent
TIMING = OUT.parent / 'cmdbuf_rd_timing'
cases = []


def case(number, title, group, baseline, mutations, stimulus, checks, figures, origins, kind='功能'):
    cases.append(dict(
        id=f'FI{number:03d}', title=title, group=group,
        status='待实施', kind=kind, baseline=baseline,
        mutation_variants=mutations if isinstance(mutations, list) else [mutations],
        minimal_stimulus=stimulus,
        checks=checks if isinstance(checks, list) else [checks],
        timing_figures=figures, origins=origins,
    ))


case(1, '共享 AR 的接收与源归属', '接口与字段',
     'AR 只有一组 arvalid、地址和元数据，每拍最多接收一条；合法 src 为 0～2，接收事件为 arvalid && arready[src]。',
     ['把三个 arready 当作三路同时接收许可，为一次 AR 分配多个 entry。', '使用错误的 src 位或忽略目标 arready 判定握手。'],
     '连续三拍分别输入 src=0、2、1，各带不同地址和 ID；按实际 arready[src] 记录握手。',
     ['每个实际握手只产生一次分配，归属保存为当拍 src。', '容量保留策略使 arready 可以为 110、100 或 010，必须检查目标位，不能用 |arready 替代。三位同时为 1 也只接收一条。'],
     [1, 9], ['后续 AR 接口澄清'])
case(2, 'Arbit 地址保留奇偶位', '接口与字段',
     'Arbit 地址为 12 bit，内容为 araddr[17:6]，其中最低位就是 araddr[6]。',
     ['沿用 11-bit araddr[17:7]。', '错取 [16:5] 或丢掉 bit 6。', '地址取自实时 AR 或另一条命令，与 req 指向的命令不一致。'],
     '发送两条仅 araddr[6] 不同的命令，Bank 编号相同、两个 half 均空闲；再改变 bit 17 检查最高位；发射期间继续输入其他地址。',
     'req 的 Bank bit 应相同，arb_addr[0] 应不同；逐位比较 arb_addr 与该请求级命令保存地址的 [17:6]。无需新增 bank_half 外部端口。',
     [9], ['H02', '地址由 [17:7] 修正为 [17:6]'])
case(3, '八个 Bank 的编号解码', '接口与字段',
     'Bank 编号为 araddr[5:3]，范围 0～7；req 为对应 Bank 的 8-bit one-hot 或全零。',
     ['将 Bank 编号取成 [6:4]。', 'Bank bit 左右反转或偏移一位。', '沿用 bank0～8 的九 Bank 解释。'],
     '分别覆盖 Bank 0 和 Bank 7，再覆盖所有中间 Bank；两个 half 各测一次。',
     '有请求时 req == (8\'b1 << saved_araddr[5:3])，且 $onehot0(req)；编号由地址决定而不是物理 entry 下标。',
     [9], ['Bank 0～7 修正'])
case(4, 'rd_mem_status 维度与空闲极性', '接口与字段',
     'rd_mem_status 为 [1:0][7:0]；[0][bank] 偶、[1][bank] 奇；0 空闲、1 忙。',
     ['按 [bank][half] 或旧端口布局索引。', '交换奇偶 half。', '把 1 判为空闲。'],
     '使用非对称状态：只令 rd_mem_status[0][1]=1，再只令 [1][6]=1；分别提交对应地址及相邻空闲地址。',
     'bank_idle = !rd_mem_status[saved_araddr[6]][saved_araddr[5:3]]；非对称模式必须能区分转置、half 交换与极性翻转。',
     [3, 9, 11], ['rd_mem_status 端口修正', 'H02'])
case(5, '共享 R 负载与唯一接收对象', '接口与字段',
     'R 共享一组 128-bit 数据及 rid、port_id、raddr、rresp，通过 rvalid[2:0] 指示唯一接收 XAU。',
     ['同拍对多个 XAU 拉高 valid。', 'valid 选中 XAU1，但负载 mux 取 XAU0。'],
     '至少两个 XAU 同时有完成队头且 ready=1，给各命令不同的全部元数据与数据。',
     ['$onehot0(rvalid)。', '所有共享 R 字段必须属于唯一获选命令；不能只核对 rdata 而漏掉 rid、port_id、raddr、rresp。'],
     [8, 9], ['H03'])
case(6, '单组 MEM 返回接口', '接口与字段',
     'MEM 返回是合并后的一组 128-bit 数据和一位 pc_err；cmdbuf_rd 不接收每 Bank 独立的返回负载。',
     ['按 Bank 或 half 再错误选择一组不存在的返回总线。', '只存储或返回 128-bit 数据的一部分。', '将 pc_err 当作多位状态。'],
     '从不同 Bank 发射，按成功发射 +4 拍驱动共享返回；数据高低 64 bit 使用不同且非零的图案。',
     '按内部返回标记写入对应 OTB，正常响应逐位比较 128-bit 数据；pc_err 仅按一位保存和判错。',
     [1, 7, 9], ['H04', '数据口 128 bit 与 pc_err 1 bit'])
case(7, '事务元数据完整保存与透传', '接口与字段',
     'rid=原 arid[7:0]，R port_id=原 AR port_id[4:0]，raddr=原 araddr[2:0]；都从命令保存值读取。',
     ['漏存 ID 或 port_id。', '位宽截断或 raddr 切片错误。', '响应使用实时 AR 输入而非保存字段。'],
     '使用 ID=8\'hA5、port_id=5\'h13、araddr=18\'h12345；响应前持续输入不同元数据。',
     '该命令返回 rid=A5、port_id=13、raddr=3\'b101，且不受后续 AR 改变影响。',
     [9], ['arid/rid 8 bit', 'port_id 5 bit', 'raddr 透传低 3 bit'])

case(8, '共享池防止单个 XAU 独占容量', '容量与生命周期',
     '最新要求禁止一路占满并挡住其他来源。本设计采用每 XAU 保留一项、其余六项共享；单路最多七项，物理槽位仍统一分配。',
     ['沿用无保护的全局共享，允许单 XAU 占九项。', '有保留空位却将所有 arready 同时压低。'],
     '不允许退休，仅由 XAU0 接收七条；然后检查 XAU1 和 XAU2 的接收资格，并在上游调度给出相应 src 时各接收一条。',
     '占用为 (7,0,0) 时 arready=110；(7,1,0) 时为 100；(7,1,1) 时为 000。不能用单路占满九项作为正常容量测试。',
     [12], ['H06 新要求覆盖旧无配额结论', '防止 XAU 容量独占'])
case(9, 'CMDBUF 与 OTB 原子分配和一一对应', '容量与生命周期',
     '每次 AR 接收同时保留一个 CMDBUF 项和对应 OTB 项，整个生命周期绑定同一命令。',
     ['只分配 CMDBUF，等 MEM 返回时才申请 OTB。', '两边独立选空位而丢失对应关系。'],
     '并发发生新接收、旧命令返回、另一命令 R 退休，覆盖表尾与复用槽位。',
     '每条有效命令始终具有唯一对应的 CMDBUF 与 OTB 存储；返回时已有位置，不受当拍容量影响。物理编号是否相同属于实现方式，必须保持可验证的一一映射。',
     [1, 7, 10], ['H06', '接收时申请 OTB'])
case(10, '窗口排除已成功发射但未退休命令', '窗口与选择',
     '窗口是最老五条未成功发射命令，而不是最老五条未释放命令。',
     '已发射或已完成、尚未 R 返回的命令继续占乱序窗口名额。',
     '较老的五条已成功发射且仍驻留，较新待发命令的 Bank 空闲。',
     '较新待发命令必须进入待发窗口；不能被已成功发射项阻挡。',
     [1, 3, 6], ['H01'])
case(11, '五项全部阻塞时不得越窗选择第六项', '窗口与选择',
     '先取最老五条待发命令，再在窗口中筛空闲 Bank；窗口不因空命中或等待时间而自动滑动。',
     ['先筛全九项的空闲 Bank，再取最老。', '五项均忙时滑动窗口或扩大到六项。', '超时后强行发射 F。'],
     'A～F 按年龄排列，请求级为空；A～E 均访问 Bank0 偶，F 访问 Bank1 偶；rd_mem_status 恒为 16\'h0001。',
     ['F 必须一直留在窗口外；无其他请求级成功时，req=0。', '这是正确的窗口阻塞，不得以 F 未最终返回判定 DUT 错误。若继续接收且无退休，容量达到九项后背压。'],
     [11], ['H01', '最新第六条命令场景'])
case(12, '窗口内选择最老可用命令', '窗口与选择',
     '从窗口内满足 Bank 空闲且未被当前请求级占用的命令中选接收年龄最老的一条。',
     ['只看全局队头，队头忙则停止。', '按物理 entry 下标、ID 数值或 Bank 编号优先。'],
     '窗口内 A 忙，B、C 空闲，A 比 B 老、B 比 C 老；通过槽位复用让 B 的物理编号大于 C，ID 使用非单调值。',
     '应选择 B；更改 entry 位置或外部 ID 不改变接收年龄优先级。',
     [2, 3], ['最老匹配选择规则', 'ID 与接收年龄区分'])
case(13, '接收判断请求的三拍路径', '请求流水与仲裁',
     '最早 C1 接收、C2 判断、C3 请求下游；当拍 grant 决定 C3 是否成功。',
     ['新 AR 直接进入当拍选择。', '选择结果同拍组合发 req。'],
     '空表、目标 Bank 空闲、下游始终允许成功，C1 输入唯一命令 A。',
     'C1/C2 不得为 A 发 req；正常无阻塞流水在 C3 发 req，不能把 C3 尝试等同于无条件成功。',
     [1, 9], ['固定三 cycle 要求'])
case(14, '不同命令之间的流水重叠', '请求流水与仲裁',
     '请求 A 的同拍可判断 B、接收 C；无阻塞时每拍可成功发射一条。',
     '将接收、判断、请求做成整机串行状态机，或等待上一命令 MEM 返回才处理下一条。',
     'C1/C2/C3 连续接收 A/B/C，相关 Bank 空闲且每次双 grant 成功。',
     '应能形成 C3/C4/C5 连续请求；记录多余气泡，即使最终数据都正确也要报告吞吐偏离。',
     [1], ['跨命令流水要求'], '吞吐与时序')
case(15, '5A 仲裁失败保留下一条预选', '请求流水与仲裁',
     'C3 请求 A 失败而同拍选中 B 时，C4 仍请求 B；A 在 C4 重新参加判断。',
     ['A 失败冲刷 B。', 'A 在失败当拍重选并替换 B。'],
     'A、B、C 均可匹配；C3 只让 A 的请求失败，其他请求成功。',
     '请求序列为 C3 A失败、C4 B、C5 A重试；A 的恢复不得取消已选 B。',
     [5], ['用户选择 5A'])
case(16, '失败重试保留原年龄', '请求流水与仲裁',
     '失败命令重新成为候选，但相对接收年龄不变。',
     ['重试时把 A 插到队尾。', '更新 A 的年龄为当前时间。'],
     'A 比 B、C 老，A 失败时 B 已预选；下一拍 B 请求，A/C 都可用。',
     '判断级应先重新选 A 而不是 C；已预选 B 仍按 5A 发送。',
     [5], ['失败后新老相对属性不变'])
case(17, '屏蔽当前请求级命令的重复预选', '窗口与选择',
     '当前请求级命令不能在同拍再次被判断级选中。',
     '候选掩码漏掉 current_issue_entry 排除项。',
     'A 正在请求且仍为最老可用项，让本次请求失败以避免 issued 成功前馈掩盖错误；记录下一拍 req，随后重试成功。',
     '失败当拍不能再选 A，最早下一拍才重判；同一命令最多成功发射一次，不得生成重复返回标记。',
     [5], ['5A 流水占用语义'])
case(18, '6B 成功当拍前移窗口', '窗口与选择',
     'A 当拍成功时，把成功信息前馈给本拍窗口计算；第六条 F 可以当拍进入窗口并被选中。',
     '只等下一拍 issued 寄存器更新才前移窗口。',
     'A 正在请求，A～F 为最老六条待发命令；B～E 忙、F 空闲；A 在 N 拍成功。',
     'N 拍选 F，N+1 发 F；等到 N+1 才选 F 会产生额外一拍气泡。',
     [3, 6], ['用户选择 6B'], '吞吐与时序')
case(19, '请求失败不能提前腾出窗口名额', '窗口与选择',
     '未成功的当前请求级命令仍计入最老五条窗口；排除重复选择不等于将其从待发窗口移除。',
     ['不论 grant 成败，在构窗之前移除请求级命令。', '预选就置 issued。'],
     'A 正在请求且失败；A～F 按年龄排列，B～E 忙、F 空闲。',
     '失败当拍不得选 F；应先构 A～E 窗口，再屏蔽 A 的重复预选。',
     [5, 6, 11], ['5A 与 6B 组合语义'])
case(20, '目标 Bank 双 grant 同拍成功', '请求流水与仲裁',
     'issue_success = |(req & ar_rd_gnt & rw_rd_gnt)，三者必须命中同一个 Bank bit。',
     ['两个 grant 用 OR。', '分别归约两个 grant 后再 AND。', '记住上一拍的一个 grant 与本拍另一个拼成成功。'],
     'req[0]=1；分别覆盖目标 grant=00、01、10、11，两个 grant 分居 Bank0/Bank1，以及两个 grant 分在相邻周期。',
     '只有同拍目标位 11 成功；其余情况均不置 issued、不减少待发数、不生成返回标记。',
     [4], ['双 grant 成功定义'])
case(21, '无请求时 grant 不得制造成功', '请求流水与仲裁',
     '成功事件受本模块当前有效 req 限定；无 req 时不会产生本模块的成功命令。',
     '成功逻辑只看两个 grant 向量，忽略 req。',
     'req=0 时驱动 grant 非零。若集成环境明确保证此时 grant 必为零，则改为内部组合逻辑变异检查，不把违反环境保证的激励当正常用例。',
     '不得出现 issued 改变、待发数减少或 +4 拍虚假捕获。',
     [4], ['双 grant 成功定义'])
case(22, '待发计数统计全部未成功命令', '容量与生命周期',
     'pending_cnt 为 4 bit、范围 0～9；接收 +1，成功发射 −1；预选、失败、MEM 返回和 R 退休不直接改变待发数。',
     ['计数封顶为窗口大小 5。', '预选或 req 就减计数。', '已发射驻留项仍计入待发。'],
     '先积累六条未发射命令，再分别制造预选、失败、成功，以及同拍接收与成功。',
     'pending_next=pending+ar_fire-issue_success；同拍接收与成功净变化为零，六条待发时值为 6。计数采样统一为时钟沿前或沿后。',
     [1, 4, 11], ['Arbit 待发指示口定义'])
case(23, '命令保留到 R 返回', '容量与生命周期',
     '成功发射后及 MEM 完成后，命令仍占 CMDBUF 和 OTB；真正 R 返回才退休。',
     ['发射成功即清 CMDBUF。', 'MEM 返回即释放 CMDBUF 或 OTB。'],
     'A 发射成功并收到 MEM 数据，但令所属 XAU 的 rready=0，延后多拍才允许返回。',
     '等待期间 A 两侧存储均保持有效归属；不能把它的槽位当空位接收新命令。',
     [7, 10], ['完整命令生命周期'])
case(24, 'MEM 完成同时通知 CMDBUF', '容量与生命周期',
     'MEM 返回写 OTB 时，CMDBUF 同时感知对应命令完成；具体完成标志命名和编码由实现决定。',
     ['只写 OTB 而丢失 CMDBUF 完成通知。', '通知错误的 entry。'],
     '乱序成功发射两条不同命令，按 +4 拍顺序返回，响应先暂缓。',
     '内部监视对应命令的完成事件或等价状态变化。仅看最终 R 波形可能区分不了此变异，需要内部观测点。',
     [1, 7], ['MEM 返回也被 CMDBUF 感知'], '内部一致性')
case(25, '固定四拍从成功接收起算', 'MEM 返回与捕获',
     '成功发射与 MEM 接收同拍；在 C3 成功则 C7 捕获该命令返回。',
     ['从 AR 或预选拍开始计时。', '延迟写成 3 或 5 拍。', '在 Arbit 与 MEM 之间再虚构一拍。'],
     '唯一命令 C3 成功，C7 提供唯一有效图案；C6/C8 总线使用不同无关值。',
     '仅 C7 对该 entry 发生有效捕获；时间以统一采样沿计，不把包含首尾的五列误认为延迟五拍。',
     [1, 4, 9], ['H05'])
case(26, '失败请求不启动返回计时', 'MEM 返回与捕获',
     '返回标记只由成功发射产生，失败尝试没有对应 MEM 返回。',
     '每次 req 或预选均压入四拍标记流水。',
     'A 在 N 拍失败、N+2 拍重试成功；MEM 只在 N+6 返回 A。',
     'N+4 不得因失败尝试而捕获或置完成，N+6 才捕获一次。',
     [4], ['双 grant 与固定四拍关系'])
case(27, '返回标记每拍前进且保留空泡', 'MEM 返回与捕获',
     '固定延迟流水每个时钟推进，空泡也推进，不受新请求、表满或 R ready 控制。',
     ['只在有成功发射时推进。', '表满或 rready=0 时暂停计时。', '将空泡压缩掉。'],
     'C3 A 成功、C4/C5 无成功、C6 B 成功；期间安排表满或全部 R 不 ready。',
     'C7 捕获 A，C10 捕获 B；C8/C9 不得挤入 B 的完成标记。',
     [4, 7], ['固定四拍及单拍返回'])
case(28, 'MEM 单拍返回必须立即捕获', 'MEM 返回与捕获',
     '返回数据和 pc_err 只保证一个 cycle 有效；该拍写入 OTB，与 R 是否 ready 无关。',
     ['只在 rready=1 时写入。', '晚一拍再读 MEM 数据。', '响应直接读取届时的实时 MEM 总线。'],
     'C7 返回 A，C7/C8 rready=000，C9 允许目标通道响应；C8 起 MEM 总线改变。',
     'C9 响应使用 C7 保存的内容；正常 rresp=00 的子例精确比较数据，错误子例至少比较错误状态，错误时 rdata 语义见 U05。',
     [7], ['MEM 返回只持续一拍'])
case(29, 'pc_err 与零数据不能充当有效信号', 'MEM 返回与捕获',
     '捕获有效性来自成功发射延迟四拍的标记；pc_err=0 和全零数据也可能是合法返回。',
     ['pc_err=1 才捕获。', 'rdata 非零才置完成。'],
     '成功命令返回 128\'b0 且 pc_err=0；目标 XAU 队首并 ready。',
     '命令必须正常完成，并在后续允许响应时返回零数据和 rresp=00。',
     [7, 9], ['pc_err 仅为一位奇偶校验异常'])
case(30, '返回标记绑定原命令', 'MEM 返回与捕获',
     '每个成功发射事件保存可定位原 CMDBUF/OTB 命令的内部标识，四拍后数据及错误写回该命令。',
     ['使用当前请求级下标或当前 AR 下标。', '按接收 FIFO 次序而非实际发射次序匹配。', '直接把外部 arid 当物理槽号。'],
     '同 XAU 的较新 B 先于 A 发射；返回期间继续接收 C/D，并给各正常返回不同数据图案。',
     'B 的返回写 B、A 的返回写 A；最终 R 仍 A 后 B，不能将交换的数据掩盖为正确顺序。',
     [2, 7], ['乱序发射与 OTB 对应关系'])
case(31, 'MEM 捕获当拍禁止该命令 R 旁路', 'R 返回与保序',
     'C7 捕获 A，A 最早 C8 才能向 R 返回；该限制针对 A，不禁止 C7 返回其他此前已完成命令。',
     '用本拍 capture_valid 或 MEM 数据组合直通 R 仲裁和负载。',
     'A 为唯一未返回命令，位于所属 XAU 队首，rready 始终为 1，C7 MEM 返回。',
     ['C7 不得返回 A；C8 可具备响应资格，覆盖最早下一拍路径。', '不能把 C8 必然返回作为所有场景的断言；前序命令、ready 和 RR 可使响应延后。额外固定响应级是否允许不由本条单独裁定。'],
     [1, 7, 9], ['用户确认 MEM 最早下一 cycle 返回 R'])
case(32, '同 XAU 按接收年龄保序', 'R 返回与保序',
     '同一 XAU 的 R 按 AR 接收顺序返回，跨 arid 也保序；ID 是透传标签，不能当年龄。',
     ['按完成顺序返回。', '仅同 ID 保序。', '按 ID 数值升序返回。'],
     '同 XAU 先接收 A(id=A5)、后接收 B(id=03)，但使 B 先完成；另用反向 ID 配置重复该年龄关系。',
     'A 未返回前不能返回 B；基准队列以握手次序建模，不以 ID 排序。重复 ID 的合法性尚未明确，基础用例使用不同 ID。',
     [2], ['单 XAU 保序', 'arid/rid 补充'])
case(33, '不同 XAU 不施加全局返回顺序', 'R 返回与保序',
     '每个 XAU 独立维护最老未返回命令；某通道队头未完成不妨碍另一通道完成队头参加 RR。',
     '只允许全局最老未返回命令响应。',
     '较老 A 属于 XAU0 且未完成；较新 B 属于 XAU1 已完成，rready[1]=1。',
     'B 是合格 RR 候选；不能因 A 阻塞而禁止 XAU1 响应。若有其他合格通道，按 RR 决定获选者。',
     [8], ['按单 XAU 保序并 RR 返回'])
case(34, 'RR 只选 ready 的完成队头', 'R 返回与保序',
     '通道候选 = 该 XAU 最老未返回命令已完成 && rready[src]；rvalid 只在对应 ready=1 时拉高。',
     ['先选不 ready 通道并锁定共享 R。', 'valid 先拉高再等 ready。', '同通道跳过未完成队头，选较新的完成项。'],
     'XAU0 有完成队头但不 ready，XAU1 队头完成且 ready；另测 XAU0 队头未完成、第二条已完成。',
     ['(rvalid & ~rready)==0。', '第一子例应服务 XAU1；第二子例 XAU0 不得因后项已完成而成为候选。'],
     [7, 8], ['H07', 'ready 门控 rvalid 约束'])
case(35, 'RR 推进与空闲保持', 'R 返回与保序',
     '已确认合格通道间采用 RR；图 08 的参考模型约定沿固定环在服务后推进、无响应时保持后续优先级。精确环方向与空闲推进策略见 U06。',
     ['以固定优先级替代 RR，持续压制其他合格通道。', '每拍推进并改变后续可见服务顺序；此变异按图 08 参考模型判定前需确认 U06。', '按错误的获选通道推进，造成合格通道被跳过或长期偏置。'],
     '先观察一次已知响应建立指针，再让三个 XAU 持续具有 ready 的完成队头；中间插入全无候选拍。',
     '持续三个合格通道时检查轮转服务而非固定优先级。图 08 按 XAU0→1→2 及空闲保持绘制，精确序列检查需先确认 U06；比较可见服务顺序，不仅凭内部指针编码变化判错。',
     [8], ['H07', 'RR 返回规则'])
case(36, '地址越界命令仍访问 MEM', '错误状态',
     'arresp=2\'b11 的请求仍缓存、参与窗口、仲裁及 MEM 返回，最终返回地址越界状态。',
     ['接收后本地立即完成越界响应。', '丢弃越界命令，不发送 MEM。'],
     '输入 arresp=11、目标 Bank 空闲的命令，允许双 grant，按 +4 拍返回。',
     '应有正常下游请求和返回捕获；R 不得绕过 MEM 生命周期提前返回，最终 rresp=11。错误响应数据内容见 U05。',
     [9], ['用户确认越界仍发 MEM'])
case(37, '越界异常优先于奇偶异常', '错误状态',
     'arresp=11 时 rresp=11；否则已定义的 arresp=00 下，pc_err=1 返回 01，pc_err=0 返回 00。',
     ['pc_err 覆盖越界状态。', '用位运算拼接成未定义编码。', '忽略任一错误来源。'],
     '覆盖 (arresp,pc_err)=(00,0)、(00,1)、(11,0)、(11,1)。',
     '期望 rresp 分别为 00、01、11、11。不为 arresp=01/10 自行定义结果。',
     [9], ['错误优先级最终确认'])
case(38, 'pc_err 与所属 OTB 命令一起保存', '错误状态',
     '每条命令保存其返回拍的 pc_err，R 使用该保存状态。',
     ['使用实时 pc_err。', '所有 entry 共用一个最后错误寄存器。', '只清数据不清复用项的错误归属。'],
     'A 返回 pc_err=1 后暂缓响应，B 随后返回 pc_err=0；两条 arresp 都为 00。',
     'A 的 rresp=01、B 的 rresp=00，响应时实时 MEM pc_err 的变化不影响结果。',
     [7, 9, 10], ['OTB 保存 pc_err'])
case(39, '10B 满表同拍退休与接收', '容量与生命周期',
     '九项全占用时，当拍 R 退休可使符合来源保留额度的新 AR 同拍接收；不能无条件对三个来源都拉高 ready。',
     'free 判断只看拍初 valid，不包含当拍 retire，导致额外停一拍。',
     '占用为 (7,1,1)，XAU0 当拍退休一条，释放一个共享额度；上游按目标 ready 发送新命令。另测 XAU1 唯一命令退休，参见 FI047。',
     '应允许该拍接收；used_next=9+1-1=9。若变异错误压低 ready，应记录服务机会丢失，不能强行违反 arready=000 时 arvalid=0 的环境约束。',
     [10], ['用户选择 10B'], '吞吐与时序')
case(40, '同槽复用保留旧响应并初始化新命令', '容量与生命周期',
     '复用拍 R 输出旧命令；时钟沿后新分配有效，初始化优先于退休清除，具有新元数据、最年轻年龄、未发射未完成状态。',
     ['新写入提前覆盖旧 R 负载。', '退休清除覆盖新 valid。', '沿用旧 issued、done、pc_err 有效归属或年龄。'],
     '10B 满表复用同一逻辑槽，旧 A 与新 B 的 src、地址、ID、port 和错误情况均不同。',
     '当拍只返回 A；随后 B 仍有效且须经历自己的发射和捕获；B 不得凭旧完成状态直接响应，也不能继承 A 的年龄。',
     [10], ['10B 同拍事件优先级'])
case(41, 'R 退休同时清除两侧归属', '容量与生命周期',
     '实际 R 返回后，旧命令从 CMDBUF 和 OTB 同时移除，旧数据不再有效；同拍新分配仍按 10B 生效。',
     ['只清 CMDBUF 或只清 OTB。', '清错 entry。', '退休后旧命令再次参加 R。'],
     '两个不同命令驻留，只返回其中一条；分别覆盖无复用和同拍复用。',
     '只有获选命令的旧归属失效，每次 AR 接收最多有一次 R 返回；另一命令保持。物理数据寄存器是否必须写零见 U04，不以残留无效位判错。',
     [1, 10], ['用户定义完整生命周期'])
case(42, '复用新命令仍遵守三拍路径', '请求流水与仲裁',
     '10B 释放复用只提前资源可用性，不让新 AR 越过输入寄存；新命令下一拍才判断。',
     '将退休槽位的新 AR 组合直送当拍判断级。',
     'N 拍满表退休 A 并接收 B，B 的目标 Bank 空闲；保持后续 grant 可用。',
     'B 最早 N+1 判断、N+2 请求；不得在 N 或 N+1 提前发 B。',
     [1, 10], ['10B 与固定三拍组合'])

case(43, '两个 XAU 联合占用仍为第三路保留名额', '容量隔离',
     '每个零占用 XAU 都保留一个物理空位；sum(max(occ[x],1))<=9。只设单路上限七项不足。',
     '仅检查每路 occ<=7，允许到达 (4,5,0)。',
     '无退休，将占用推进至 (4,4,0)，分别尝试再接收 XAU0/1，并检查 XAU2 首条请求。',
     '在 (4,4,0) 时 arready=100；只能由 XAU2 使用最后一项，禁止进入 (5,4,0) 或 (4,5,0)。',
     [12], ['每 XAU 一项逻辑保留方案'])
case(44, '占用额度统计到真正 R 退休', '容量隔离',
     'occ[x] 统计该来源全部已接收且未退休命令，覆盖未发射、已发射及已完成状态。',
     ['使用 pending_cnt 代替总占用。', '在发射成功或 MEM 完成时归还额度。'],
     'XAU0 占七项后，让部分命令发射或返回 MEM，但保持 rready[0]=0。',
     'occ[0] 仍为七；没有 R 退休时不能重新给 XAU0 准入，也不能侵占 XAU1/2 的保底空位。',
     [7, 12], ['容量保留与完整生命周期'])
case(45, '逐来源 ready 判定', '容量隔离',
     'arready 每位表示该 XAU 的准入资格，实际接收只认 arready[src]。',
     ['将有物理空位广播成 ready=111。', '用 arvalid && |arready 接收。'],
     '占用为 (7,0,0)，ready 应为 110；输入 src=0、arvalid=1 时不握手。该刺激满足 ready 非全零的既有约束；再切换 src=1 并发送。',
     '不得为被禁止的 XAU0 分配 entry；切换到 XAU1 后可接收。上游已确认允许切换，但尚不保证公平性。',
     [12], ['共享 AR 与容量隔离'])
case(46, '空闲来源的保底项不可借出', '容量隔离',
     '其他来源暂时无请求时也不借出其最后一个保底名额，否则长期不退休时无法回收。',
     '根据当前 src 或短期未观察到其他来源请求，允许一路借满九项。',
     '只有 XAU0 长时间请求且不退休，稍后 XAU1 才开始请求。',
     'XAU0 在七项处停止准入；XAU1 首条请求无需等待 XAU0 退休即可拥有 entry。',
     [12], ['最小保底方案'])
case(47, '满表退休最后一项只恢复该来源保底', '容量隔离',
     '满表 (7,1,1) 中 XAU1 唯一命令退休后，扣除退休占用为 (7,0,1)，仅 XAU1 可使用空位。',
     '发现 retire 就令 ready=111，允许其他来源抢走刚恢复的保底。',
     '在该满表分布下退休 XAU1，并分别观察或尝试 src=0、1、2。',
     '该拍 arready=010；XAU1 可按 10B 同拍复用，其他来源不能抢占。',
     [13], ['10B 与容量保留组合'])
case(48, '同拍退休接收的每来源计数合成', '容量隔离',
     '先扣除当拍退休再算准入，最终 occ_next[x]=occ[x]-retire[x]+accept[x]；同源两个事件净值为零。',
     ['用 if/else 丢失其中一个事件。', '退休与接收属于不同 src 时却更新同一计数。', 'ready 反过来依赖本拍新分配，形成自依赖。'],
     '分别覆盖 (7,1,1) 下 XAU1 退休并接收 XAU1，以及 XAU0 退休并接收 XAU2。',
     '结果依次为 (7,1,1) 和 (6,1,2)；总占用均九，保留不变量保持。退休只由已有命令的 R 响应决定。',
     [10, 13], ['每来源计数与 10B'])
case(49, '容量保护不改变五项发射窗口', '容量隔离',
     '为其他 XAU 保留的命令可进入池，但仍必须遵守最老五条未成功发射窗口。入口可用不等于下游一定有进展。',
     ['因为新命令使用保底项就允许其越过五项窗口。', '将跨 XAU 公平当作发射窗口的额外绕过条件。'],
     'XAU0 的 A～E 占最老五条且 Bank 均忙；XAU1 的 F 经保底接收且 Bank 空闲，状态保持。',
     'XAU1 可以完成 AR 接收，但 F 仍不能越窗发射；不得把这一正常窗口等待判为容量独占错误。',
     [11, 12], ['容量隔离与既有窗口规则'])

history = [
    dict(id='H01', topic='乱序窗口范围', earlier='最老五条未成功发射，还是最老五条未释放。', final='最老五条未成功发射；先定窗口再匹配 Bank。', cases=[10, 11, 12, 18, 19]),
    dict(id='H02', topic='奇偶 Bank 信息如何下传', earlier='原 11-bit [17:7] 丢失 bit 6，曾提出额外 bank_half。', final='地址改为 12-bit araddr[17:6]，最低位携带奇偶信息。', cases=[2, 3, 4]),
    dict(id='H03', topic='R 负载是否共享', earlier='共享一组，还是每个 XAU 一组。', final='共享一组；rvalid[2:0] 选择接收对象。', cases=[5, 7]),
    dict(id='H04', topic='MEM 返回几组', earlier='合并一组、按八个 Bank，或按十六个 half 分组。', final='合并后单组 128-bit 数据及一位 pc_err。', cases=[6, 28, 29, 30]),
    dict(id='H05', topic='固定四拍起算点', earlier='双 grant 成功是否等同于 MEM 同拍接收，中间是否还有流水级。', final='成功与 MEM 接收同拍，成功后四拍捕获。', cases=[20, 25, 26, 27]),
    dict(id='H06', topic='OTB 容量与分配', earlier='原先确认九项共享、一一对应、无配额；最新要求禁止 XAU 独占容量。', final='九项物理池仍共享；本设计采用每 XAU 一项保底、六项共享额度，覆盖原无准入保护结论。', cases=[8, 9, 23, 39, 40, 41, 43, 44, 45, 46, 47, 48, 49]),
    dict(id='H07', topic='RR 遇到反压', earlier='先选再锁住，还是只在 ready 通道间选。', final='只在当前 ready 且完成队头可返回的通道中 RR；rvalid 不等待 ready。', cases=[5, 32, 33, 34, 35]),
]

unresolved = [
    dict(id='U01', topic='复位协议', detail='复位极性、同步或异步、途中未完成请求与四拍返回标记的处置均未定义。不能要求自行选定的恢复行为。'),
    dict(id='U02', topic='非法输入编码', detail='src=3、arresp=01/10 的处理未定义；基础环境限定 src 为 0～2、arresp 为 00/11。'),
    dict(id='U03', topic='重复 ID 与唯一性', detail='重复 arid、跨 XAU 相同 ID 及 port_id 约束未明确；基准不以 ID 作为唯一键，基础激励可采用不同且非单调 ID。'),
    dict(id='U04', topic='清除是否要求物理写零', detail='已确认退休后移除命令及数据有效归属；是否要求 128-bit 存储内容实际清零尚未区分。暂不据无效存储残值判错。'),
    dict(id='U05', topic='错误响应的数据内容', detail='rresp 的优先级已确认；越界或 pc_err=1 时 rdata 是否仍透传捕获值、强制清零或不关心，尚无独立明确约束。正常响应精确比数据，错误响应先判状态及归属。'),
    dict(id='U06', topic='RR 精确推进规则', detail='合格通道间 RR 已确认；图 08 的 0→1→2、服务后推进和空闲保持属于参考模型约定，初始起点及精确序列尚未单独确认。可先检查轮转与合法候选；以空闲后首个获选者判错前需确认策略，内部指针编码变化本身不构成错误。'),
    dict(id='U07', topic='判断后 Bank 状态变化', detail='若判断拍空闲、请求拍转忙，是否再次检查状态并撤销 req 未独立对齐。双 grant 是成功的最终判据；状态变化子例不先设定撤销策略。'),
    dict(id='U08', topic='无效输出与进展时限', detail='req/rvalid 无效拍的 payload 值、grant 和 ready 的公平性、最长等待上限未定义。场景 11、永久不 ready 或长期仲裁失败均不能无条件要求最终响应。'),
    dict(id='U09', topic='共享 AR 上游公平性', detail='用户已确认目标 ready=0 时可以切换 src，但公平性未定。cmdbuf_rd 保证保留空位和对应 ready，不能强迫上游选择另一来源；最终一定接收仍需公平调度前提。'),
]

rules = [
    '一个 cycle 内最多接收一条共享 AR、发射一条下游读请求、返回一条共享 R；三个动作可作用于不同命令。',
    '地址 18 bit；arid/rid 各 8 bit；port_id 各 5 bit；R raddr 为保存地址低 3 bit。',
    'Bank=araddr[5:3]、half=araddr[6]；状态接口 [1:0][7:0]，0 表示空闲；Arbit 地址为 [17:6] 共 12 bit。',
    'CMDBUF 和 OTB 各九项共享、一一对应；接收分配、R 退休释放；成功发射及 MEM 完成不释放。最新要求禁止一路容量独占；本设计用每 XAU 一项保底和六项共享额度实现。',
    '最老五条未成功发射命令构窗；成功项以 6B 当拍前馈移出窗口；当前请求项不能重复预选。',
    '采用 5A、6B、10B。其错误替代行为分别是取消已预选 B、成功后晚一拍前移窗口、满表释放后晚一拍才允许新接收。',
    'MEM 返回为单组 128-bit 数据及一位 pc_err；从双 grant 成功拍起固定 +4 拍，仅有效一拍，必须及时捕获。',
    'MEM 捕获的该条命令最早下一 cycle 参与 R 返回；同 XAU 保序，跨 XAU 在 ready 的完成队头间 RR。',
    'arresp=11 仍访问 MEM；rresp 优先级为地址越界 11，其次 pc_err 对应 01，正常 00。',
    '截图七项均已有后续结论，其中 H06 已被最新防独占要求修订；U01～U09 列出尚不能建立完整错误判据的边界。具体一项保底是设计选择，并非用户指定的配额数字。',
]

timing_summaries = [
    ('连续正常流水', 'C1 接收、C2 判断、C3 请求；不同命令重叠，C3 成功则 C7 捕获、最早 C8 返回。', [13, 14, 25, 31]),
    ('乱序发射与单 XAU 保序', '较新命令可以先完成，但不能越过同 XAU 更老的未返回命令。', [12, 30, 32]),
    ('窗口外命令进入时机', '第六条等待；只有窗口内成功发射触发 6B 当拍前移，才可补入。', [11, 18, 19]),
    ('双 grant 与返回气泡', '目标 Bank 两个 grant 同拍为 1 才成功，失败不产生返回标记，四拍日历保留气泡。', [20, 25, 26, 27]),
    ('已选择 5A', 'A 失败不冲刷同拍选中的 B；B 下一拍发送，A 下一拍按原年龄重新判断。', [15, 16, 17]),
    ('已选择 6B', '成功信息前馈本拍窗口；不能等下一拍才补入第六条。失败则不前移。', [18, 19]),
    ('MEM 单拍返回与 R 等待', '返回当拍必须保存数据及错误，不受 rready 影响；之后等合格响应机会。', [28, 29, 38]),
    ('响应 RR', '只在 ready 且完成队头可返回的 XAU 中轮询；图 08 参考模型的环方向与空闲保持判据见 U06。', [5, 33, 34, 35]),
    ('字段透传与错误', '12-bit 下游地址、保存字段透传、越界仍访 MEM、越界优先于 parity。', [2, 4, 7, 36, 37]),
    ('已选择 10B', '满表允许同拍 R 退休及 AR 接收；当拍输出旧负载，沿后新分配初始化生效。', [39, 40, 41, 42]),
    ('固定窗口全部阻塞', 'A～E 均忙、F 空闲且状态不变时 F 仍不能发射；这是合法等待，越窗发射才是错误。', [11, 22]),
    ('入口容量保留', '单路占七项后保留其他两路首条接收名额；九项物理池统一分配。', [8, 43, 44, 45, 46, 49]),
    ('满表保底复用', '释放某来源唯一项时，只为该来源恢复接收资格；释放共享额度时各路均可竞争。', [39, 47, 48]),
]
timing_scenarios = [dict(figure=n, title=title, baseline=baseline, cases=refs, path=f'../cmdbuf_rd_timing/{n:02d}_timing.png')
                    for n, (title, baseline, refs) in enumerate(timing_summaries, 1)]

semantics = [
    '所有周期沿用图集约定：每列一个周期，右边界采样提交。例如 C3 成功、C7 捕获、最早 C8 返回。',
    'arready==000 时 arvalid==0 是上游环境约束。注错基准驱动器应遵守；违反它的协议负向激励需另定义 DUT 预期。',
    '容量保护要求按来源产生 arready，三位可以不同且不要求 one-hot；真正接收看 arready[src]。',
    '接口名 arb_addr、ar_port_id、r_port_id 等仅用于区分通道，最终 RTL 命名尚未绑定。',
    '窗口公式、free_mask 和内部 entry 标记是等价行为参考，不强制使用年龄矩阵、特定位编码或某种队列结构。',
    '每次只植入一个 mutation_variants 子项，并先在无注错基准上通过同一激励。这里记录的是待实施注错计划，不是已执行 RTL 或已测出的缺陷。',
    '吞吐类变异可能不产生错误数据，需检查请求间隔、窗口前馈和接收机会；内部一致性类还需可观测内部完成及分配事件。',
]

scoreboard = [
    '每次合法 AR 握手分配单调递增的测试序号 accept_seq，保存 src、地址、ID、port、arresp；以 accept_seq 标识命令，而不是以外部 ID 标识。',
    '为每个 XAU 保存接收序列及全部未退休占用 occ；共享池保存占用和待发集合，检查 sum(max(occ[x],1))<=9；根据年龄与窗口规则算判断候选，再寄存供下一拍请求。',
    '从当前有效 req 与两组目标位 grant 判成功；成功事件携带命令序号进入固定四拍日历，空拍仍推进。失败只恢复候选资格，不改原年龄。',
    'MEM 模型只在日历指定拍提供有效数据和 pc_err；无有效返回拍可主动改变总线，以暴露晚采样及实时总线误用。',
    'R 期望只能查看本拍开始前已捕获的完成集合；MEM 本拍捕获的命令在下一拍才可用。R 按每 XAU 队头及 ready、RR 选择。',
    '按同拍原子事件更新状态：旧 R payload 来自旧命令；退休释放、新接收分配可复用同槽；新分配元数据及年龄覆盖旧归属清除。',
    '数量不变量：used_next=used+ar_fire-retire_fire；pending_next=pending+ar_fire-issue_success；pending<=used<=9。退休的命令必已成功发射。',
    '一次成功发射对应一次 +4 捕获，一次接收最多对应一次退休。若环境允许永久阻塞，只检查安全性与有条件的进展，不设置无条件超时故障。',
]

golden_logic = '''bank_id = saved_araddr[5:3]
half = saved_araddr[6]
bank_idle = !rd_mem_status[half][bank_id]
issue_success = |(req & ar_rd_gnt & rw_rd_gnt)
pending_mask = valid & ~issued
success_mask = issue_success ? onehot(current_issue_entry) : 0
window_mask = oldest_5(pending_mask & ~success_mask)
candidate_mask = window_mask & bank_idle_mask & ~current_issue_mask
select = oldest(candidate_mask)

free_mask = ~valid | retire_mask
occ_after[x] = occ[x] - retire_for_xau[x]
free_after = 9 - sum(occ_after)
shared_after = sum(max(occ_after[x] - 1, 0))
arready[x] = (free_after > 0) && ((occ_after[x] == 0) || (shared_after < 6))
ar_fire = arvalid && src_is_0_to_2 && arready[src]
occ_next[x] = occ_after[x] + (ar_fire && src == x)
r_candidate[xau] = oldest_unretired_done_before_this_cycle[xau] && rready[xau]
retire_fire = |(rvalid & rready)
'''

data = dict(
    schema_version='1.0', title='cmdbuf_rd 历史对齐与注错清单', updated_on='2026-10-10',
    purpose='将历史歧义和时序分歧转成可复用的 RTL 注错计划；保留最终规则、错误变体、触发条件和检查点。',
    execution_status='仅整理计划，未修改 DUT RTL，未执行注错或仿真',
    sources=[
        dict(id='S01', description='用户截图中的七项历史未对齐问题', path='historical_unaligned.png'),
        dict(id='S02', description='用户在本对话中的后续确认与接口修正'),
        dict(id='S03', description='已整理的十三张时序示意图', path='../cmdbuf_rd_timing/index.html'),
        dict(id='S04', description='当前已选择的时序规则', path='../cmdbuf_rd_timing/decisions.json'),
    ],
    baseline_rules=rules, interpretation_notes=semantics,
    historical_seven=history, timing_scenarios=timing_scenarios, golden_logic=golden_logic,
    capacity_policy=dict(user_requirement='禁止 XAU 容量独占导致其他来源无法接收', design_choice='每 XAU 逻辑保留一项，其余六项共享；物理不分区', origin='针对最新要求的设计方案，保底数字不是用户独立指定', invariant='sum(max(occ[x],1))<=9', upstream='可以切换 src，公平性未定', note='入口容量保护不等于上游调度公平或五项发射窗口的前进保证'),
    cases=cases, unresolved=unresolved, reference_model_steps=scoreboard,
)

assert len(cases) == 49
assert len({c['id'] for c in cases}) == len(cases)
assert all(c['baseline'] and c['mutation_variants'] and c['minimal_stimulus'] and c['checks'] for c in cases)
assert all(1 <= n <= len(cases) for h in history for n in h['cases'])
assert all((TIMING / f'{n:02d}_timing.png').exists() for c in cases for n in c['timing_figures'])

screenshot = Path('C:/Users/1/AppData/Local/Temp/codex-clipboard-86147ab1-da71-4904-9f95-1b062df4f1cc.png')
if screenshot.exists() and not (OUT/'historical_unaligned.png').exists():
    shutil.copyfile(screenshot, OUT/'historical_unaligned.png')

(OUT/'fault_cases.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')

def ids(nums):
    return '、'.join(f'FI{n:03d}' for n in nums)

md = [f'# {data["title"]}', '', data['purpose'], '',
      f'版本日期 2026-10-10。包含七项历史问题、{len(cases)} 组注错点、{len(timing_scenarios)} 张时序图索引，以及 {len(unresolved)} 项暂不作为强制判据的边界。', '',
      '**容量规则已修订：禁止单个 XAU 独占九项。实现采用每 XAU 保留一项、六项共享，原 FI008 的单路占满测试已被替换。**', '',
      '[容量隔离设计与准入公式](capacity_policy.md) · [容量模型检查结果](capacity_policy_check.json)', '',
      '**场景 11 的固定窗口阻塞是正确行为。注错对象是“允许第六条越窗发射”，而不是“第六条持续等待”。**', '',
      '## 最终基准', '']
md += [f'- {r}' for r in rules] + ['', '## 原截图七项与最终结论', '',
       '| 编号 | 历史问题 | 最终规则 | 注错编号 |', '| --- | --- | --- | --- |']
md += [f'| {h["id"]} | {h["topic"]}：{h["earlier"]} | {h["final"]} | {ids(h["cases"])} |' for h in history]
md += ['', '[原始截图](historical_unaligned.png)', '', '## 时序场景对照', '',
       '| 图 | 场景 | 当前行为 | 注错编号 |', '| --- | --- | --- | --- |']
md += [f'| [图 {s["figure"]:02d}]({s["path"]}) | {s["title"]} | {s["baseline"]} | {ids(s["cases"])} |' for s in timing_scenarios]
md += ['', '## 周期约定与判错边界', '']
md += [f'- {s}' for s in semantics]
md += ['', '## 行为参考逻辑', '', '以下为伪代码，需要按最终 RTL 的状态与采样时刻绑定，不能直接视为可编译 SVA。', '', '```text', golden_logic.rstrip(), '```', '', '## 注错目录', '',
       '| 编号 | 注错主题 | 类别 | 对应图 |', '| --- | --- | --- | --- |']
md += [f'| {c["id"]} | {c["title"]} | {c["group"]}／{c["kind"]} | {", ".join(f"{n:02d}" for n in c["timing_figures"])} |' for c in cases]
md += ['', '## 注错用例', '']
for c in cases:
    md += [f'### {c["id"]} {c["title"]}', '', f'正确行为：{c["baseline"]}', '', '错误变体（每次独立植入一项）：', '']
    md += [f'- {v}' for v in c['mutation_variants']]
    md += ['', f'最小触发：{c["minimal_stimulus"]}', '', '检查点：', '']
    md += [f'- {v}' for v in c['checks']]
    refs = '、'.join(f'[图 {n:02d}](../cmdbuf_rd_timing/{n:02d}_timing.png)' for n in c['timing_figures'])
    md += ['', f'关联：{refs}。依据：{"；".join(c["origins"])}。类型：{c["kind"]}。状态：待实施。', '']
md += ['## 暂不作为强制判据的边界', '', '| 编号 | 主题 | 判据限制 |', '| --- | --- | --- |']
md += [f'| {u["id"]} | {u["topic"]} | {u["detail"]} |' for u in unresolved]
md += ['', '## 后续基准模型与注错记录', '']
md += [f'{n}. {s}' for n, s in enumerate(scoreboard, 1)]
md += ['', '实施记录建议字段：case_id、mutation_index、RTL 版本、修改位置、触发种子、是否真正激活变异、首个分歧周期、命中的检查器、结果与波形路径。', '',
       '若变异未被触发、没有可观测影响或缺少环境前提，应分别记为未激活、等价候选或环境约束不足，不能直接记成验证通过。', '',
       '[机器可读用例](fault_cases.json) · [时序图集](../cmdbuf_rd_timing/index.html) · [详细设计方案](../cmdbuf_rd_design/index.html)', '',
       '当前为注错设计资料；尚未实施 DUT 变异或运行 RTL 验证。', '']
(OUT/'cmdbuf_rd_fault_catalog.md').write_text('\n'.join(md), encoding='utf-8')

def esc(value):
    return html.escape(str(value))

def bullets(values):
    return '<ul>' + ''.join(f'<li>{esc(v)}</li>' for v in values) + '</ul>'

def table(headers, rows):
    return '<div class="table-wrap"><table><thead><tr>' + ''.join(f'<th>{esc(h)}</th>' for h in headers) + '</tr></thead><tbody>' + ''.join('<tr>' + ''.join(f'<td>{esc(c)}</td>' for c in row) + '</tr>' for row in rows) + '</tbody></table></div>'

groups = list(dict.fromkeys(c['group'] for c in cases))
cards = []
for c in cases:
    refs = ' '.join(f'<a href="../cmdbuf_rd_timing/{n:02d}_timing.png" target="_blank">图 {n:02d}</a>' for n in c['timing_figures'])
    search = esc(' '.join([c['id'], c['title'], c['group'], c['baseline'], *c['mutation_variants'], *c['origins']]))
    cards.append(f'''<article class="case" id="{c['id']}" data-group="{esc(c['group'])}" data-search="{search}">
<h3><span>{c['id']}</span> {esc(c['title'])}</h3><p class="meta">{esc(c['group'])} · {esc(c['kind'])} · 待实施</p>
<p><strong>正确行为</strong> {esc(c['baseline'])}</p><div class="mutations"><strong>错误变体</strong>{bullets(c['mutation_variants'])}</div>
<p><strong>最小触发</strong> {esc(c['minimal_stimulus'])}</p><strong>检查点</strong>{bullets(c['checks'])}
<p class="meta">{refs} · 依据：{esc('；'.join(c['origins']))}</p></article>''')

history_table = table(['编号', '历史问题', '最终规则', '注错编号'], [[h['id'], h['topic']+'：'+h['earlier'], h['final'], ids(h['cases'])] for h in history])
timing_table = table(['图', '场景', '当前行为', '注错编号'], [[f'{s["figure"]:02d}', s['title'], s['baseline'], ids(s['cases'])] for s in timing_scenarios])
pending_table = table(['编号', '主题', '判据限制'], [[u['id'], u['topic'], u['detail']] for u in unresolved])
options = ''.join(f'<option value="{esc(g)}">{esc(g)}</option>' for g in groups)
steps = '<ol>' + ''.join(f'<li>{esc(s)}</li>' for s in scoreboard) + '</ol>'
doc = '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>cmdbuf_rd 历史对齐与注错清单</title>
<style>body{margin:0;background:#eef2f7;color:#19334d;font:16px/1.8 "Microsoft YaHei",sans-serif}header{padding:28px max(24px,calc((100vw - 1200px)/2));background:#19334d;color:white}header a{color:#c4e7ff}h1{font-size:30px;margin:0}main{max-width:1200px;margin:auto;padding:24px}h2{margin-top:36px}h3{margin:0;font-size:21px}h3 span{color:#176bb0}.lead,.case,details{background:white;border:1px solid #d7e0e8;border-radius:10px;padding:22px;margin-bottom:20px}.callout{padding:16px 20px;background:#fff4d9;border-left:5px solid #bd8100}.meta{color:#586d80;font-size:14px}.mutations{background:#fff4f1;padding:12px 18px;border-radius:7px}ul,ol{padding-left:24px}li{margin:6px 0}a{color:#176bb0}pre{overflow:auto;background:#19334d;color:#e3f1fb;border-radius:8px;padding:20px}.table-wrap{overflow:auto}table{border-collapse:collapse;width:100%;background:white}th,td{padding:12px;border:1px solid #d7e0e8;text-align:left;vertical-align:top}th{background:#e2ebf4}td:first-child{white-space:nowrap}#filters{position:sticky;top:0;z-index:1;background:#eef2f7;padding:12px 0;display:flex;gap:12px;align-items:center;flex-wrap:wrap}input,select{font:inherit;border:1px solid #b5c5d4;border-radius:6px;padding:8px;max-width:100%}input{flex:1;min-width:180px}article{scroll-margin-top:95px}summary{cursor:pointer;font-weight:bold}footer{padding:24px;color:#586d80}img{max-width:100%}</style></head><body>
<header><h1>cmdbuf_rd 历史对齐与注错清单</h1><p>七项历史问题 · 49 组注错点 · 十三张时序图 · 2026-10-10</p><a href="../cmdbuf_rd_design/index.html">详细设计</a>　<a href="cmdbuf_rd_fault_catalog.md">Markdown 文档</a>　<a href="fault_cases.json">JSON 用例数据</a>　<a href="../cmdbuf_rd_timing/index.html">时序图集</a></header><main>
<p class="callout"><strong>最新容量修订：</strong>禁止一个 XAU 独占全部九项。本设计采用每 XAU 保留一项、六项共享；上游已确认可切换 src，公平性未定。FI008 已替换，新增 FI043～FI049。<br><a href="capacity_policy.md">容量隔离设计与准入公式</a> · <a href="capacity_policy_check.json">容量模型检查结果</a></p>
<p class="callout"><strong>场景 11 的窗口阻塞是正确行为。</strong>第六条命令对应 Bank 空闲，也不能越过最老五条窗口。可植入的错误是越窗发射、无命中时自动滑窗或超时扩窗。</p>
<section class="lead"><h2>最终基准</h2>''' + bullets(rules) + '''</section>
<h2>原截图七项与最终结论</h2>''' + history_table + '''<p><a href="historical_unaligned.png" target="_blank">查看原始截图</a></p>
<h2>时序场景对照</h2>''' + timing_table + '''
<details><summary>周期约定与判错边界</summary>''' + bullets(semantics) + '''</details>
<details><summary>行为参考逻辑</summary><p>伪代码，需要绑定最终 RTL 的状态与采样时刻。</p><pre>''' + esc(golden_logic) + '''</pre></details>
<h2>注错用例</h2><div id="filters"><input id="search" type="search" placeholder="搜索编号、主题、5A、6B、10B…" aria-label="搜索用例"><select id="group" aria-label="用例类别"><option value="">全部类别</option>''' + options + '''</select><span id="count">49 / 49 组</span></div>
<div id="cases">''' + '\n'.join(cards) + '''</div><p id="empty" hidden>没有匹配的用例。</p>
<h2>暂不作为强制判据的边界</h2>''' + pending_table + '''
<h2>后续基准模型</h2>''' + steps + '''
<p>实施时记录 case_id、mutation_index、RTL 版本、修改位置、种子、是否激活、首个分歧周期、检查器、结果和波形。未触发或无可观测影响的变异需单列，不能直接当成验证通过。</p>
</main><footer>当前为注错设计资料；尚未实施 DUT 变异或运行 RTL 验证。</footer>
<script>const cards=[...document.querySelectorAll('.case')],q=document.querySelector('#search'),g=document.querySelector('#group');function filter(){let count=0;const term=q.value.trim().toLowerCase();for(const c of cards){const show=(!g.value||c.dataset.group===g.value)&&(!term||c.dataset.search.toLowerCase().includes(term));c.hidden=!show;if(show)count++;}document.querySelector('#count').textContent=count+' / '+cards.length+' 组';document.querySelector('#empty').hidden=count!==0;}q.addEventListener('input',filter);g.addEventListener('change',filter);</script></body></html>'''
(OUT/'index.html').write_text(doc, encoding='utf-8')
print(json.dumps(dict(cases=len(cases), history=len(history), unresolved=len(unresolved), files=['cmdbuf_rd_fault_catalog.md', 'fault_cases.json', 'index.html', 'historical_unaligned.png']), ensure_ascii=False))
