#!/usr/bin/env python3
"""Generate reviewable, concrete cover goals and a 200-row property map.

Run from a repository copy, or pass --classification. Labels are stable.
The map describes implemented predicates, never claims an executed cover hit.
"""
import argparse
import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Nonempty witnesses; functional correctness is checked by the independent
# scoreboard assertions in the same harness. Complex multi-bin points below
# add bins rather than replacing them with an implication/vacuous trigger.
C = {
'P-CLK': [
 'history[0] && accept',
 'previous_reset && arready==7 && accept',
 'flow_stage==15 && used==0',
 'seen_noise && flow_stage==15'],
'P-AR': [
 'accept', '!arvalid && (success || due || retire)',
 'history[0] && $past(arvalid && src<3 && !arready[src]) && accept && src!=$past(src)',
 'accept && arready==7',
 'used==9 && !retire && arready==0 && !arvalid',
 'retire && m_addr[rsp_e]!=araddr', 'retire && m_id[rsp_e]!=arid',
 'retire && m_port[rsp_e]!=ar_port_id', 'retire && m_err[rsp_e]==3',
 'history[0] && $past(arvalid && src<3 && !arready[src]) && accept && src!=$past(src)',
 None],
'P-R': [
 'retire', 'm_done!=0',
 'retire && ((head_valid & ~rready)!=0)',
 'retire && rid!=arid', 'retire && r_port_id!=ar_port_id', 'retire',
 'retire && rdata[127] && rdata[0]', 'retire',
 'retired_total!=0 && rvalid==0'],
'P-ARB': [
 'req!=0', 'req!=0', 'req!=0',
 'req!=0 && (ar_rd_gnt & rw_rd_gnt)!=0 && !success',
 'history[0] && $past(req!=0 && (req & ar_rd_gnt)!=0 && (req & rw_rd_gnt)==0) && req!=0 && (req & ar_rd_gnt)==0 && (req & rw_rd_gnt)!=0 && !success',
 'req==0 && ar_rd_gnt!=0 && rw_rd_gnt!=0 && m_due==0',
 'waiting>=0', 'history[0]',
 'retired_total!=0 && req==0 && arb_addr==0'],
'P-MEM': [
 'select_valid', 'pending!=0',
 'history[0] && m_attempt && rd_mem_status[m_addr[m_attempt_e][6:3]] && $past(select_valid)',
 'history[0] && $past(due) && retire && rsp_e==$past(due_e) && mem_rdata!=$past(mem_rdata)',
 'due && mem_rdata==0', 'retire'],
'F-ENT': [
 'accept', 'used==9 && (occ[0]>3 || occ[1]>3 || occ[2]>3)',
 'accept', 'accept || success || due || retire',
 'accept && ever_used[alloc_e]', 'retire',
 'success && failures[m_attempt_e]>=2',
 'accept && (m_sent & ~m_done)!=0',
 'retire && done_cycles[rsp_e]>=3',
 'retire && retired_total!=0',
 'retire', 'used>=2 && (accept || success || due || retire)',
 'history[0]', 'retire && failures[rsp_e]>=2'],
'F-CAP': [
 'm_live!=0 && m_done!=0 && (m_sent & ~m_done)!=0 && pending!=0',
 'shared_cost>=0',
 'occ[0]==7 && occ[1]==0 && occ[2]==0 && !retire',
 'occ[0]==4 && occ[1]==4 && occ[2]==0 && !retire',
 'used==9 && !retire && arready==0 && due',
 'accept && occ[src]==0 && shared_cost==6',
 'used==9 && retire && occ[winner]==1',
 'used==9 && retire && occ[winner]>1 && accept',
 'retire && accept && src==winner && occ[src]==7',
 'retire && accept && src!=winner',
 'history[0] && (occ[0]==$past(occ[0]) && occ[1]==$past(occ[1]) && occ[2]==$past(occ[2])) && !retire && !$past(retire) && araddr!=$past(araddr)',
 'quota_cost<=9'],
'F-AGE': [
 'history[0] && $past(arvalid && src<3 && !arready[src]) && accept && src!=$past(src)',
 'success && seen_accept_src==7',
 'success && m_attempt_e!=0 && m_live[0] && m_age[0]>m_age[m_attempt_e]',
 'retire && failures[rsp_e]!=0 && used>=2',
 'used>=3 && retire && accept',
 'used>=3 && retire && accept && alloc_e==rsp_e',
 'retire && accepted_total>=257 && rid==0'],
'F-PIPE': [
 'flow_stage==15',
 'history[0] && m_attempt && $past(select_valid)',
 'accept && m_attempt && select_valid',
 'issue_streak>=4',
 'm_attempt && select_valid && m_attempt_e!=select_e',
 'history[0] && $past(m_attempt && !success && select_valid) && m_attempt && m_attempt_e==$past(select_e)',
 'select_valid && failures[select_e]!=0',
 'history[1] && used==1 && m_attempt && $past(m_attempt && !success,2) && !$past(m_attempt) && m_attempt_e==$past(m_attempt_e,2)',
 'select_valid && failures[select_e]!=0 && seen_busy6',
 'retire && failures[rsp_e]>=3',
 'success && failures[m_attempt_e]!=0',
 'm_attempt'],
'F-WIN': [
 'waiting<5', 'waiting>=6 && (pool & ~window & idle)!=0',
 'select_valid && (m_sent & m_live)!=0',
 'blocked_six', 'busy_streak>=16',
 'select_valid && !$onehot0(candidate)',
 'select_valid && ranks[select_e]>0',
 'candidate!=0',
 'success && select_valid && ranks[select_e]==4 && m_age[m_attempt_e]<m_age[select_e]',
 'm_attempt && !success && waiting>=6 && (pool & ~window & idle)!=0',
 'blocked_six && (due || retire)',
 'accept && !rd_mem_status[araddr[6:3]]',
 'accept && occ[src]==0 && waiting>=5 && (window & idle)==0 && !rd_mem_status[araddr[6:3]]',
 'seen_reuse && select_valid && m_live!=((9\'b1<<used)-1)'],
'F-MEM': [
 'history[3] && due && $past(success,4)',
 'due && seen_out_of_order',
 'm_due==15 && due && success',
 'success_pattern==8\'b10100110',
 'history[3] && $past(m_attempt && !success,4) && !due',
 'due && !arvalid && req==0', 'due && rready==0',
 'history[0] && $past(due) && m_done[$past(due_e)]',
 'due && m_done==0 && rready==7 && !retire',
 'history[0] && $past(due) && retire && rsp_e==$past(due_e)',
 'due && retire && due_e!=rsp_e', 'due'],
'F-DAT': [
 'due && mem_rdata!=0',
 'retire && done_cycles[rsp_e]>=4',
 'm_done==9\'h1ff && rready==0',
 'due && m_done!=0 && rready==0',
 'retire && rdata==0',
 'retire && m_pc[rsp_e]!=pc_err && done_cycles[rsp_e]>=1',
 'retire && seen_out_of_order && m_id[rsp_e]!=arid && m_port[rsp_e]!=ar_port_id',
 'retire || accept'],
'F-RR': [
 'retire && overtaken[rsp_e]', 'retire && overtaken[rsp_e]',
 'retire && head_valid[0] && !m_done[head[0]] && winner!=0',
 'head_valid!=0', 'm_rr<3',
 'eligible==0 && (accept || success || due)',
 'retire && winner!=m_rr',
 'history[0] && retire && $past(retire) && winner==$past(winner)',
 'history[0] && retire && $past(retire) && winner!=$past(winner)',
 'history[1] && eligible==7 && $past(eligible)==7 && $past(eligible,2)==7',
 'history[0] && rready!=$past(rready) && retire',
 'eligible!=0 && retire'],
'F-ERR': [
 'retire && m_err[rsp_e]==0 && !m_pc[rsp_e]',
 'retire && m_err[rsp_e]==0 && m_pc[rsp_e]',
 'retire && m_err[rsp_e]==3 && !m_pc[rsp_e]',
 'retire && m_err[rsp_e]==3 && m_pc[rsp_e]',
 'retire && m_err[rsp_e]==3 && failures[rsp_e]!=0 && overtaken[rsp_e]',
 'retire && rresp!=0 && rdata[127] && rdata[0]'],
'F-CNT': [
 'waiting>=0', 'history[0]',
 '!accept && !success && (m_attempt || select_valid || due || retire)',
 'history[0]', 'used<=9'],
'F-REU': [
 'used==9 && retire && accept && alloc_e==rsp_e',
 'retire && accept && alloc_e==rsp_e && rid!=arid && r_port_id!=ar_port_id && raddr!=araddr[2:0]',
 'history[0] && $past(retire && accept && alloc_e==rsp_e) && m_live[$past(alloc_e)] && !m_sent[$past(alloc_e)] && !m_done[$past(alloc_e)]',
 'retire && reused[rsp_e] && age_cycles[rsp_e]>=6',
 'used<9 && retire && accept && alloc_e!=rsp_e',
 'used==9 && aimr==15 && alloc_e==rsp_e',
 'aimr==15 && due_e!=rsp_e && m_attempt_e!=rsp_e && m_attempt_e!=due_e',
 'accept && due && retire && m_attempt && !success'],
'B-FLOW': [
 'flow_stage==15', 'retired_total>=512 && seen_retire_src==1',
 'retired_total>=512 && seen_retire_src==7 && fullrate_streak>=8',
 'retire && seen_retire_src!=7 && !$onehot0(seen_retire_src)',
 'retire && failures[rsp_e]!=0 && seen_accept_src==7',
 'retire && failures[rsp_e]!=0',
 'target_seen==16\'hffff && retire',
 'used==0 && retired_total>=9 && accept',
 'seen_noise && idle_streak>=64 && accept', None],
'B-BLOCK': [
 'used==9 && waiting==9 && select_valid', 'busy_streak>=16',
 'history[0] && $past(success && select_valid && ranks[select_e]==4 && m_age[m_attempt_e]<m_age[select_e]) && m_attempt && m_attempt_e==$past(select_e)',
 'history[1] && $past(m_attempt && !success && select_valid,2) && $past(m_attempt && select_valid) && $past(m_attempt_e)==$past(select_e,2) && $past(select_e)==$past(m_attempt_e,2) && m_attempt && m_attempt_e==$past(m_attempt_e,2)',
 'retire && failures[rsp_e]>=4',
 'history[0] && m_attempt && rd_mem_status[m_addr[m_attempt_e][6:3]] && $past(select_valid)',
 'busy_streak>=16 && seen_accept_src!=1'],
'B-ORDER': [
 'retire && overtaken[rsp_e]',
 'history[0] && head_valid[0] && !m_done[head[0]] && retire && winner!=0 && $past(retire && winner!=0) && winner!=$past(winner)',
 'history[1] && eligible==7 && $past(eligible)==7 && $past(eligible,2)==7',
 'history[0] && rready!=$past(rready) && retire',
 'm_done==9\'h1ff && rready==0',
 'pc_pattern==6\'b010110 && retire && seen_out_of_order',
 'success_pattern==8\'b10100110',
 'retire && seen_accept_src==7',
 'retire && (m_addr[rsp_e]==0 || m_addr[rsp_e]==18\'h3ffff)',
 'retire && failures[rsp_e]!=0 && done_cycles[rsp_e]>=2'],
'B-CAP': [
 'occ[0]==7 && occ[1]==1 && occ[2]==1',
 'occ[0]==4 && occ[1]==4 && occ[2]==0 && accept && src==2',
 'used==9 && retire && occ[winner]==1',
 'used==9 && retire && occ[winner]==7 && accept',
 'retire && reused[rsp_e] && seen_reuse',
 'aimr==15 && select_valid && used==9 && alloc_e==rsp_e',
 'seen_busy6 && retired_total>=9 && used==0',
 'retired_total>=4096 && used==0 && m_due==0']}

GROUP_ASSERTS = {
'P-CLK':'A_RESET_OUTPUTS A_RESET_EMPTY A_READY A_REQ A_RR_CHOICE',
'P-AR':'A_READY A_PENDING A_REQ A_ARB_ADDR A_R_METADATA A_R_RESP',
'P-R':'A_R_ONEHOT A_R_READY A_RR_CHOICE A_R_METADATA A_R_RESP A_R_DATA A_R_IDLE_ZERO',
'P-ARB':'A_REQ_ONEHOT A_REQ A_ARB_ADDR A_PENDING A_RR_CHOICE',
'P-MEM':'A_REQ A_ARB_ADDR A_RR_CHOICE A_R_DATA A_R_RESP',
'F-ENT':'A_READY A_PENDING A_REQ A_RR_CHOICE A_R_METADATA A_R_DATA',
'F-CAP':'A_READY A_PENDING A_RR_CHOICE',
'F-AGE':'A_REQ A_ARB_ADDR A_RR_CHOICE A_R_METADATA',
'F-PIPE':'A_REQ A_ARB_ADDR A_PENDING A_RR_CHOICE',
'F-WIN':'A_REQ A_ARB_ADDR A_PENDING',
'F-MEM':'A_RR_CHOICE A_R_METADATA A_R_DATA A_R_RESP',
'F-DAT':'A_R_METADATA A_R_DATA A_R_RESP A_RR_CHOICE',
'F-RR':'A_RR_CHOICE A_R_READY A_R_METADATA sources.A_RR_BOUND',
'F-ERR':'A_R_RESP A_R_DATA A_REQ A_RR_CHOICE',
'F-CNT':'A_PENDING A_READY A_RR_CHOICE',
'F-CON':'A_READY A_PENDING A_REQ A_RR_CHOICE A_R_METADATA A_R_DATA A_R_RESP',
'F-REU':'A_READY A_PENDING A_REQ A_ARB_ADDR A_RR_CHOICE A_R_METADATA A_R_DATA A_R_RESP',
'B-FLOW':'A_READY A_REQ A_ARB_ADDR A_RR_CHOICE A_R_METADATA A_R_RESP A_R_DATA',
'B-BLOCK':'A_REQ A_ARB_ADDR A_PENDING A_READY A_RR_CHOICE',
'B-ORDER':'A_RR_CHOICE A_R_METADATA A_R_RESP A_R_DATA sources.A_RR_BOUND',
'B-CAP':'A_READY A_PENDING A_REQ A_RR_CHOICE A_R_METADATA A_R_DATA'}

STRUCTURAL_GAPS = {
'F-ENT-01':'只能验证接收后事务完整、占用一致；不能证明物理 CMDBUF/OTB 同槽原子写入。',
'F-ENT-02':'只能验证共享容量策略；不能证明物理池组织。',
'F-ENT-03':'只能验证合法接收及无事务丢失；无法观察 DUT 分配索引。',
'F-ENT-04':'只能覆盖逻辑事务生命周期；DUT 内部索引范围不可观察。',
'F-ENT-05':'检查新请求不早发、不早回及最终数据；内部初始存储位不可观察。',
'F-ENT-06':'验证抽象生命周期对外效果；不能证明实际状态编码。',
'F-ENT-11':'验证释放容量及后续不受旧事务污染；物理双侧清零不可观察。',
'F-ENT-12':'端到端检查不受其他事务影响；内部存储中间时刻不变不可观察。',
'F-ENT-14':'验证逻辑请求和响应对应；内部捕获次数不可直接观察。',
'F-AGE-03':'逻辑槽复用不影响年龄；无法指定 DUT 实际物理槽编号。',
'F-AGE-05':'以最老选择和保序检查替代功能效果；物理年龄矩阵结构不可观察。',
'F-AGE-06':'复用后按新事务年龄调度；内部矩阵清行清列不可观察。',
'F-PIPE-11':'用成功后返回时序及内容检查提交效果；OTB 提交信号不可观察。',
'F-WIN-14':'检查连续窗口移动和逻辑复用；DUT 物理稀疏槽不可观察。',
'F-MEM-08':'用 N+5 响应资格及后续行为检查完成效果；两个内部 done 同拍不可观察。',
'F-MEM-12':'参考到期记录和响应正确；内部捕获索引不可观察。',
'F-DAT-02':'验证 9 条事务数据独立保存的外部效果；物理存储实现不可观察。',
'F-DAT-03':'比较最终返回数据；无法证明未响应期间所有内部位逐拍不变。',
'F-DAT-04':'比较其他事务最终返回；中间存储写入隔离不可直接观察。',
'F-DAT-08':'用无旧数据泄漏和新事务完整路径替代；空闲数据/pc 位清零不可证明。',
'F-REU-01':'满表同进同出功能可检；实际同一物理槽不可观察。',
'F-REU-02':'旧响应与新请求独立保存可检；物理同槽不可观察。',
'F-REU-03':'新事务生命周期可检；沿后内部状态位不可观察。',
'F-REU-05':'非满同进同出可检；实际不同物理槽不可观察。',
'F-REU-06':'并行事件功能可检；物理复用槽不可观察。',
'F-REU-07':'检查逻辑事务事件一致性；实际内部事件别名不可观察。',
'B-CAP-05':'旧新元数据相反及端到端结果可检；物理同槽不可观察。',
'B-CAP-06':'满表多事件外部效果可检；DUT 同槽与选择级内部事件不可观察。'
}


# These witnesses intentionally cover a structural subscenario. The omitted
# history/cross bins remain explicit work items, not alleged 200/200 coverage.
PARTIAL = {
'P-CLK-01':'数字采样状态；子周期边沿另由仿真或物理时序模型验证。',
'P-ARB-08':'采样更新；物理毛刺不在单时钟模型内。',
'F-AGE-07':'257次接受与ID回零；不枚举全部长序列排列。',
'F-PIPE-09':'当前见证包含失败后重新选择；完整变忙与恢复序列可进一步细化。',
'F-WIN-14':'稀疏槽和复用后选择；未逐一枚举所有连续滑窗历史。',
'B-FLOW-02':'BASE是512笔单源路径；持续理想供给下每拍吞吐由PERF单源任务单列。',
'B-FLOW-03':'BASE长交织及短稳态；持续条件吞吐由PERF轮流三源任务单列。',
'B-FLOW-05':'三源及失败热点结构见证；全序列地址固定交叉需要后续补充。',
'B-FLOW-06':'奇偶目标与失败见证；完整交替忙闲业务序列需进一步细化。',
'B-FLOW-08':'九项后排空重启；1、2、4、5、6笔独立突发序列尚未逐项编码。',
'B-BLOCK-05':'同一身份至少4次失败后退休；未强制按00、10、01、错Bank的顺序。',
'B-BLOCK-07':'持续五项窗口阻塞且出现其他来源；保底准入由F-WIN-13的精确事件补充。',
'B-ORDER-01':'老项被同源年轻项越过后退休；后续年轻项退休可由断言保证安全但本cover未追踪。',
'B-ORDER-03':'三源连续合格3拍；此前ready000积压历史未在同一个bin内强制。',
'B-ORDER-04':'动态ready及8个掩码分别覆盖；未强制特定8拍掩码次序。',
'B-ORDER-05':'九项全部done积压；随后九项全部排空另由DRAIN见证，不是同一cover。',
'B-ORDER-06':'010110捕获pc序列与乱序退休；未强制六次捕获全相邻。',
'B-ORDER-07':'精确成功模式；四拍日历及数据配对另由assert持续核对。',
'B-ORDER-08':'重复/倒序字段基础bins；未将所有条件合并成一个完整复合业务。',
'B-CAP-05':'复用后新事务退休；旧R与新AR字段相反由F-REU-02另见证。',
'B-CAP-07':'有限窗口阻塞后排空见证；一般恢复界另由DRAIN验证。',
'B-CAP-08':'4096笔后排空是可达性目标；随机种子、概率分布仍需仿真。'}

def generate(classification):
    original=json.loads(classification.read_text(encoding='utf8'))
    rows={r['id']:r for r in original['rows']}
    bins={key:[] for key in rows}
    def add(key,expr,suffix='MAIN',profile='BASE'):
        label='C_'+key.replace('-','_')+'_'+suffix
        bins[key].append(dict(label=label,predicate=expr,profile=profile))
    # Replace preliminary structural witnesses with completed sequence monitors.
    upgrades={
      'F-AGE-07':'wrap_completed',
      'F-PIPE-09':'retry_finished && retry_busy && retry_reselected',
      'F-WIN-14':"seen_reuse && shifted_selections>=3 && select_valid && m_live!=((9'b1<<used)-1)",
      'B-FLOW-01':'flow_stage==15 && flow_isolated',
      'B-FLOW-05':'hotspot_retired',
      'B-FLOW-06':'hotspot_retired && half_flip_seen',
      'B-FLOW-08':'burst_restart',
      'B-FLOW-09':'long_idle_finished',
      'B-BLOCK-05':'exact_retry_finished',
      'B-BLOCK-07':'reserved_outside_cycles>=16',
      'B-ORDER-01':'same_source_pair_done',
      'B-ORDER-03':'rr_release_count==3 && rr_release_srcs==7',
      'B-ORDER-04':'ready_sequence_done',
      'B-ORDER-05':'drain9_finished',
      'B-ORDER-06':'pc_run_done && retire && seen_out_of_order',
      'B-ORDER-07':'bubble_drained',
      'B-ORDER-08':'duplicate_completed==7',
      'B-ORDER-10':'completed_error_types==15',
      'B-CAP-05':'opposite_reuse_completed',
    }
    for group, exprs in C.items():
        for n,expr in enumerate(exprs,1):
            key=f'{group}-{n:02}'
            if expr: add(key,upgrades.get(key,expr))
    for n in range(16): add(f'F-CON-{n+1:02}',f'aimr==4\'d{n}')
    add('P-AR-11','bad_src','SRC','NEGATIVE')
    add('P-AR-11','arvalid && src<3 && arresp==1','RESP01','NEGATIVE')
    add('P-AR-11','arvalid && src<3 && arresp==2','RESP10','NEGATIVE')
    add('B-FLOW-10','resumed && seen_retire_src==7','RESET','IDLE_RESET')
    for s in range(3):
        for key in ['P-AR-01','F-ENT-01']: add(key,f'accept && src=={s}',f'SRC{s}')
        for key in ['P-R-01','P-R-04','P-R-05']: add(key,f'retire && winner=={s}',f'SRC{s}')
        add('F-CAP-03',f'occ[{s}]==7 && used==7 && !retire',f'HEAVY{s}')
        add('F-CAP-04',f'occ[{s}]==0 && occ[{(s+1)%3}]==4 && occ[{(s+2)%3}]==4 && accept && src=={s}',f'EMPTY{s}')
        add('B-CAP-01',f'occ[{s}]==7 && used==9',f'HEAVY{s}')
        add('B-CAP-02',f'occ[{s}]==0 && occ[{(s+1)%3}]==4 && occ[{(s+2)%3}]==4 && accept && src=={s}',f'EMPTY{s}')
        for y in range(3):
            if y!=s:add('F-CAP-10',f'retire && winner=={s} && accept && src=={y}',f'R{s}A{y}')
            add('B-CAP-03',f'used==9 && retire && occ[winner]==1 && winner=={s} && arvalid && src=={y}',f'R{s}OFFER{y}')
            add('B-CAP-04',f'used==9 && retire && occ[winner]==7 && winner=={s} && accept && src=={y}',f'R{s}A{y}')
        for bank in range(16):
            add('B-FLOW-01',f'flow_stage==15 && flow_isolated && flow_src=={s} && flow_target=={bank}',f'S{s}T{bank:02}')
        for mask in range(8):add('F-RR-05',f'm_rr=={s} && eligible==3\'d{mask}',f'PTR{s}E{mask}')
    for bit in range(18):
        for v in (0,1):add('P-AR-06',f'retire && m_addr[rsp_e][{bit}]==1\'b{v}',f'BIT{bit:02}_{v}')
    for key,field,width in [('P-AR-07','rid',8),('P-AR-08','r_port_id',5),('P-R-04','rid',8),('P-R-05','r_port_id',5),('P-ARB-02','arb_addr',12),('P-R-07','rdata',128)]:
        for bit in range(width):
            for v in (0,1):add(key,('req!=0' if key=='P-ARB-02' else 'retire')+f' && {field}[{bit}]==1\'b{v}',f'BIT{bit:03}_{v}')
    for bit in range(128):
        add('F-DAT-05',f'retire && rdata==(128\'b1<<{bit})',f'WALK1_{bit:03}')
        add('F-DAT-05',f'retire && rdata==~(128\'b1<<{bit})',f'WALK0_{bit:03}')
    add('F-DAT-05',"retire && rdata==128'hffffffffffffffffffffffffffffffff",'ONES')
    for m in range(8):
        add('P-R-02',f'm_done!=0 && rready=={m}',f'READY{m}')
        add('B-ORDER-04',f'm_done!=0 && rready=={m}',f'READY{m}')
        add('P-R-06',f'retire && raddr=={m}',f'ADDR{m}')
        add('P-ARB-01',f'req==(8\'b1<<{m})',f'BANK{m}')
    for key in ['P-R-08','P-MEM-06','B-ORDER-10']:
        for a in [0,3]:
            for p in [0,1]:add(key,f'retire && m_err[rsp_e]=={a} && m_pc[rsp_e]=={p}',f'ERR{a}PC{p}')
    for a in (0,1):
        for w in (0,1):
            expr=f'req!=0 && ((req & ar_rd_gnt)!=0)==1\'b{a} && ((req & rw_rd_gnt)!=0)==1\'b{w}'
            for key in ['P-ARB-03','F-PIPE-12']:add(key,expr,f'AR{a}RW{w}')
    add('P-ARB-04','success && !$onehot0(ar_rd_gnt) && !$onehot0(rw_rd_gnt)','EXTRA_BITS')
    add('P-ARB-09','req!=0 && arb_addr==0','REAL_ZERO_ADDR')
    for t in range(16):
        for v in (0,1): add('P-MEM-01',f'pending!=0 && rd_mem_status[{t}]=={v} && has_target[{t}]',f'T{t:02}BUSY{v}')
        add('B-FLOW-07',f'retire && m_addr[rsp_e][6:3]=={t}',f'T{t:02}_R')
        for outcome in (0,1):add('B-BLOCK-06',f'history[0] && m_attempt && m_addr[m_attempt_e][6:3]=={t} && rd_mem_status[{t}] && success=={outcome}',f'T{t:02}SUCCESS{outcome}')
    for b in range(8):
        for half in (0,1):
            expr=f'select_valid && m_addr[select_e][6:3]=={b+8*half} && rd_mem_status[{b+8*(1-half)}]'
            add('P-MEM-02',expr,f'B{b}HALF{half}')
    for key in ['P-ARB-07','F-CNT-01']:
        for count in range(10):add(key,f'waiting=={count}',f'PENDING{count}')
    for count in range(5):add('F-WIN-01',f'waiting=={count}',f'COUNT{count}')
    for count in range(7):add('F-CAP-02',f'shared_cost=={count}',f'SHARED{count}')
    for count in (0,1,8,9):
        for key in ['F-ENT-13','F-CNT-05']:add(key,f'used=={count}',f'USED{count}')
    for a in (0,1):
        for ev in (0,1):
            for key in ['P-ARB-08','F-CNT-02']:add(key,f'accept=={a} && success=={ev}',f'A{a}I{ev}')
            add('F-CNT-04',f'accept=={a} && retire=={ev}',f'A{a}R{ev}')
    for a in range(8):
        for b in range(8):
            for c in range(8):
                if max(a,1)+max(b,1)+max(c,1)<=9:
                    add('F-CAP-12',f'occ[0]=={a} && occ[1]=={b} && occ[2]=={c}',f'O{a}{b}{c}')
    for slot in range(9):
        for event,idx in [('accept','alloc_e'),('success','m_attempt_e'),('due','due_e'),('retire','rsp_e')]:
            add('F-ENT-04',f'{event} && {idx}=={slot}',f'{event.upper()}{slot}')
        add('F-MEM-12',f'due && due_e=={slot}',f'SLOT{slot}')
    for key in ['F-ENT-11','F-DAT-08']:
        add(key,'retire && !(accept && alloc_e==rsp_e)','RELEASE')
        add(key,'retire && accept && alloc_e==rsp_e','REUSE')
    add('F-DAT-08','accept && !m_live[alloc_e]','FREE_ALLOC')
    add('F-PIPE-02','history[0] && !$past(select_valid) && !m_attempt','BUBBLE')
    add('P-MEM-05','!due && mem_rdata!=0','NOISE')
    add('P-MEM-05','due && mem_rdata==0 && pc_err','ZERO_PC1')
    add('P-MEM-05','due && mem_rdata==0 && !pc_err','ZERO_PC0')
    add('F-MEM-05','m_attempt && !success && due','FAIL_WITH_OLD_RETURN')
    add('F-WIN-08','candidate==0','ZERO')
    add('F-WIN-08','candidate!=0 && $onehot0(candidate)','ONE')
    add('F-WIN-08','!$onehot0(candidate)','MULTI')
    for key in ['P-AR-07','F-RR-02','B-ORDER-08']:
        add(key,'same_src_same_id','SAME_SOURCE_DUP_ID')
        add(key,'cross_src_same_id','CROSS_SOURCE_DUP_ID')
        add(key,'descending_id','DESCENDING_ID')
    for n in [1,2,4,5,6,9]:add('B-FLOW-08',f'burst_restart && burst_length=={n}',f'BURST{n}')
    # Exact monitor replacements close the earlier short-witness limitations.
    for key in upgrades: PARTIAL.pop(key,None)

    lines=['// Generated by generate_covers.py. Predicates are nonvacuous witnesses.',
           '// See property_map.json for exact coverage limits and profiles.',
           'reg [15:0] has_target;',
           'reg same_src_same_id, cross_src_same_id, descending_id;',
           'integer ci,cj;', 'always @* begin',
           '  has_target=0; same_src_same_id=0; cross_src_same_id=0; descending_id=0;',
           '  for(ci=0;ci<9;ci=ci+1) begin',
           '    if(pending[ci]) has_target[m_addr[ci][6:3]]=1;',
           '    for(cj=0;cj<9;cj=cj+1) if(ci!=cj && m_live[ci] && m_live[cj]) begin',
           '      if(m_id[ci]==m_id[cj] && m_src[ci]==m_src[cj]) same_src_same_id=1;',
           '      if(m_id[ci]==m_id[cj] && m_src[ci]!=m_src[cj]) cross_src_same_id=1;',
           '      if(m_src[ci]==m_src[cj] && m_age[ci]<m_age[cj] && m_id[ci]>m_id[cj]) descending_id=1;',
           '    end', '  end', 'end', '`ifndef TP_NEGATIVE']
    mapped=[]
    for key,row in rows.items():
        group=row['group']; goals=bins[key]
        assert goals,key
        if key not in ['P-AR-11','B-FLOW-10']:
            lines+=['`ifdef TP_COVER_'+group.replace('-','_'),'// '+key+' '+row['name']]
            for goal in goals:lines.append(f"`TP_COVER({goal['label']}, active && ({goal['predicate']}))")
            lines+=['`endif']
        asserts=GROUP_ASSERTS[group].split()
        if key=='P-AR-05':asserts=[]
        if key=='P-AR-11':asserts=['A_NEG_SRC_MONITOR','A_NEG_RESP_MONITOR']
        if key=='B-CAP-07':asserts+=['A_DRAIN_BOUND']
        if key in ['B-FLOW-02','B-FLOW-03']:asserts+=['A_PERF_STEADY']
        mapped.append(dict(testpoint=key,name=row['name'],assertions=asserts,
                           environment='E01 E02 E03 E04 E05' if key not in ['P-AR-11','B-FLOW-10'] else ('E01 E02 E05; NEGATIVE' if key=='P-AR-11' else 'E01 E02_RESET_IDLE_ONLY E03 E04 E05'),
                           cover_bins=goals,original_cover_goal=row['cover_goal'],
                           coverage_scope='partial_scenario' if key in PARTIAL else 'implemented_predicates',
                           limitation=PARTIAL.get(key,''),execution='not_run', port_only=True, observable_scope='functional_rewrite' if key in STRUCTURAL_GAPS else 'port_behavior', structural_gap=STRUCTURAL_GAPS.get(key,''), witness_state='All m_* indices are checker logical slots; due is expected MEM arrival, not observed DUT capture.'))
    lines.append('`endif')
    (HERE/'cmdbuf_rd_port_covers.svh').write_text('\n'.join(lines)+'\n',encoding='utf8')
    result=dict(schema_version=1,classification_sha256=hashlib.sha256(classification.read_bytes()).hexdigest(),
                testpoint_count=len(mapped),cover_bins=sum(len(b) for b in bins.values()),
                partial_scenarios=len(PARTIAL),rows=mapped,
                status='source_mapping_not_execution', port_only=True, structural_gap_count=len(STRUCTURAL_GAPS),
                note='SVA includes shared invariant properties; one testpoint is not one assertion. Short/partial cover predicates are explicitly distinguished from the original broader goal.')
    (HERE/'property_map.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    # Preserve reviewed dependency labels when regenerating the cover source.
    from annotate_model_dependencies import annotate
    annotate(HERE)
    print(json.dumps({k:result[k] for k in ['testpoint_count','cover_bins','partial_scenarios']}))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classification',type=Path,default=HERE.parents[1]/'docs/testpoints/formal_classification.json')
    generate(parser.parse_args().classification)
