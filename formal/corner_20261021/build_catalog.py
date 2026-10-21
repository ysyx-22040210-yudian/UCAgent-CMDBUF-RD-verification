#!/usr/bin/env python3
"""Render reviewed Corner cover expressions and their case-to-property index.

Source of truth here is the explicit expression table below plus catalog.json.
No expression is inferred from prose; unmapped cases stop generation.
Generated SV remains plain, labelled, commented native SVA for manual review.
"""
import json,re
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parent.parent
sys.path.insert(0,str(ROOT/'formal/protocol_20261021'))
from property_catalog import properties

CASES=json.loads((ROOT/'docs/testpoints/corner_20261021/catalog.json').read_text(encoding='utf-8'))['cases']
spec={}
def cv(key,expr,bin='MAIN',scope='完整场景的关键采样点；持续正确性由关联 assert 检查。'):
    spec.setdefault(key,[]).append(dict(label='C_CC_'+key.replace('-','_')+'_'+bin,expression=expr,scope=scope))

# AR：无效负载不比较，阻塞请求允许下一拍换来源/负载。
for s in range(3):
    cv('AR-01',f'used==0 && !r_fire && ar_fire && src=={s} && arready==7',f'S{s}')
    cv('AR-03',f'ar_fire && src=={s}',f'S{s}')
for s in range(4): cv('AR-02',f'!h_prev_valid && !arvalid && !h_prev_r && !r_fire && h_prev_n==used && src=={s} && src!=h_prev_src && arready==h_prev_ready',f'S{s}')
cv('AR-04','occ[0]==7 && occ[1]==0 && occ[2]==0 && !r_fire && arvalid && src==0 && !ar_fire && arready==6')
cv('AR-05','h_prev_n==7 && h_prev_valid && !h_prev_a && h_prev_src==0 && h_prev_ready==6 && ar_fire && src==1 && araddr!=h_prev_addr && arid!=h_prev_id && ar_port_id!=h_prev_port')
cv('AR-06','h_same_ar_run>=2 && ar_fire && src==h_prev_src && arid!=h_prev_id && ar_port_id!=h_prev_port')
cv('AR-07',"h_a_history[2:0]==3'b111 && h_src_history==6'b001001 && ar_fire && src==0")
cv('AR-08','used==9 && !r_fire && arready==0 && !arvalid')
cv('AR-11','!h_prev_valid && !arvalid && used>0 && araddr!=h_prev_addr && arid!=h_prev_id && ar_port_id!=h_prev_port')
cv('AR-12','h_prev_a && ar_fire && src==h_prev_src && araddr==h_prev_addr && arid==h_prev_id && ar_port_id==h_prev_port')
cv('AR-13','!h_prev_a && !ar_fire && !h_prev_r && !r_fire && h_prev_n==used && src!=h_prev_src && arready==h_prev_ready && used>0')
cv('AR-14','!h_prev_a && !h_prev_r && !r_fire && used==h_prev_n && arvalid!=h_prev_valid && arready==h_prev_ready && arready!=0')
for s in range(3):
    for b in (0,1): cv('AR-16',f'h_response_matches && m_src[rsp_e]=={s} && m_addr[rsp_e]==18\'h{("3ffff" if b else "00000")} && rid=={255 if b else 0} && r_port_id=={31 if b else 0}',f'S{s}_EXT{b}')
for low in range(8): cv('AR-16',f'h_response_matches && raddr=={low}',f'LOW{low}')
cv('AR-17','ar_fire && r_fire && src==winner && h_response_matches')
cv('AR-18','ar_fire && r_fire && src!=winner && h_response_matches')
cv('AR-19','occ[0]==4 && occ[1]==4 && occ[2]==1 && rvalid==4 && arvalid && src<2 && !ar_fire && arready==4')

# 容量：每源首项保留，其他六项共享。N 由实际握手历史独立维护。
for n in range(7): cv('CAP-01',f'h_total=={n} && !r_fire && arready==7',f'N{n}')
cv('CAP-02','h_prev_occ[0]==6 && h_prev_occ[1]==0 && h_prev_occ[2]==0 && h_prev_a && h_prev_src==0 && !h_prev_r && occ[0]==7 && !r_fire && arready==6')
cv('CAP-03','occ[0]==7 && occ[1]==0 && occ[2]==0 && !r_fire && arvalid && src==0 && !ar_fire && arready==6')
cv('CAP-04','used==7 && ((occ[0]>0)+(occ[1]>0)+(occ[2]>0))>=2 && !r_fire && arready==7')
cv('CAP-05','used==8 && occ[0]>0 && occ[1]>0 && occ[2]==0 && !r_fire && arready==4')
cv('CAP-06','used==8 && occ[0]>0 && occ[1]>0 && occ[2]>0 && !r_fire && arready==7')
cv('CAP-07','used==9 && !r_fire && arready==0 && !arvalid')
cv('CAP-08','used==9 && r_fire && occ[winner]>1 && arready==7')
for s in range(3): cv('CAP-09',f'used==9 && r_fire && winner=={s} && occ[{s}]==1 && arready==(3\'b1<<{s})',f'S{s}')
cv('CAP-10','used==9 && ar_fire && r_fire && src==winner && h_response_matches')
cv('CAP-11','occ[0]==7 && occ[1]==0 && occ[2]==0 && rvalid==1 && ar_fire && src==0 && arready==7')
cv('CAP-12','occ[0]==7 && occ[1]==1 && occ[2]==0 && rvalid==1 && arready==7')
cv('CAP-13','occ[0]==7 && occ[1]==1 && occ[2]==0 && rvalid==2 && arready==6')
cv('CAP-14','h_prev_occ[0]==6 && h_prev_occ[1]==1 && h_prev_occ[2]==1 && h_prev_r && h_prev_rsrc==1 && h_prev_a && h_prev_src==0 && occ[0]==7 && occ[1]==0 && occ[2]==1 && !r_fire && arready==2')
cv('CAP-15','h_prev_occ[0]==7 && h_prev_occ[1]==1 && h_prev_occ[2]==0 && h_prev_r && h_prev_rsrc==1 && !h_prev_a && occ[0]==7 && used==7 && !r_fire && arvalid && src==0 && !ar_fire')
cv('CAP-16','used==1 && r_fire && ar_fire && src!=winner && arready==7')
cv('CAP-17','h_prev_n==1 && h_prev_r && !h_prev_a && used==0 && arready==7')
for mask in range(8): cv('CAP-18',f'arready=={mask} && used>0',f'READY{mask:03b}')
for s in range(3): cv('CAP-19',f'occ[{s}]==7 && used==7 && !r_fire && arready==(3\'b111^(3\'b1<<{s}))',f'S{s}')
for s in range(3):
    cv('CAP-22',f'head_valid[{s}] && !m_done[head[{s}]] && rready[{s}] && !rvalid[{s}]',f'UNDONE{s}')
    cv('CAP-22',f'head_valid[{s}] && m_done[head[{s}]] && !rready[{s}] && !rvalid[{s}]',f'NOTREADY{s}')
cv('CAP-23','used>=7 && issue_fire && !r_fire && !ar_fire && arready!=7')
cv('CAP-24','used>=7 && mem_capture_due && !r_fire && !ar_fire && arready!=7')

# Entry：只验证端口可观察后果；逻辑 token 的复用不证明 DUT 物理清零。
cv('ENT-01','h_response_matches',scope='见证完整 AR→I→M→R；物理两表一一对应仍需结构/内部检查。')
cv('ENT-02','used>0 && waiting>0 && h_quiet_run>=3 && !select_valid && !ar_fire && !r_fire && !issue_fire')
cv('ENT-03','retry_selected && req==last_retry_req && arb_addr==last_retry_addr && req!=0')
cv('ENT-04','(m_live&m_sent&~m_done)!=0 && ar_fire && !r_fire')
cv('ENT-05','h_response_matches && h_done_wait[rsp_e]>=3')
cv('ENT-06','ar_fire && h_hole_reused && h_total_r>0',scope='参考记录在中间空洞重新分配；不限定 DUT 物理槽选择。')
cv('ENT-07','used==9 && ar_fire && r_fire && alloc_e==rsp_e && h_response_matches',scope='满表同拍复用的可观察端口行为；不声称证明原始存储位清零。')
cv('ENT-08','used<9 && used>1 && ar_fire && r_fire && h_response_matches')
cv('ENT-09','h_response_matches && h_clean_reuse[rsp_e] && m_err[rsp_e]==0 && !m_pc[rsp_e] && m_data[rsp_e]==0 && rresp==0')
cv('ENT-12','h_total_a>=20 && h_total_r>=12 && h_ever_full && ar_fire && h_duplicate_id',scope='至少 20 次接收、12 次返回且曾满表，包含重复 ID；有限轨迹不等于无限运行证明。')

# 乱序：覆盖的是 C2 排名/候选与 C3 请求，A_REQ/A_ARB_ADDR 对所有拍检查。
cv('WIN-01','h_a_history[1] && h_prev_n==1 && used==1 && h_selected_prev && issue_fire && h_total_a==1 && h_total_r==0')
cv('WIN-02','h_prev_i && issue_fire && h_a_history[2:1]==2\'b11')
for n in range(5): cv('WIN-03',f'waiting=={n} && !issue_fire && (h_rank_valid>>{n})==0',f'P{n}')
cv('WIN-04',"waiting==5 && !issue_fire && h_rank_idle[4:0]==5'b11111 && select_valid && ranks[select_e]==0")
cv('WIN-05','waiting>=2 && !issue_fire && !h_rank_idle[0] && h_rank_idle[1] && select_valid && ranks[select_e]==1')
cv('WIN-06',"waiting>=5 && !issue_fire && h_rank_idle[4:0]==5'b11010 && select_valid && ranks[select_e]==1")
cv('WIN-07',"waiting>=6 && !issue_fire && h_rank_idle[5:0]==6'b110000 && select_valid && ranks[select_e]==4")
cv('WIN-08','blocked_six && blocked_streak>=3 && req==0 && h_status==h_prev_status')
for n in range(6,10): cv('WIN-09',f'waiting=={n} && blocked_six && blocked_streak>=1 && req==0',f'P{n}')
cv('WIN-10','(m_live&m_sent)!=0 && select_valid && m_age[select_e]>=5 && ranks[select_e]<5')
cv('WIN-11','refill_selected && !nonhead_refill_selected && req==last_refill_req && arb_addr==last_refill_addr && req!=0')
cv('WIN-12','nonhead_refill_selected && req==last_refill_req && arb_addr==last_refill_addr && req!=0')
cv('WIN-13','waiting>=6 && req!=0 && !issue_fire && !h_rank_idle[4:0] && h_rank_idle[5] && !select_valid')
cv('WIN-14','waiting==1 && retry_selected && req==last_retry_req && arb_addr==last_retry_addr && req!=0')
cv('WIN-15','h_failed_none && req==0 && waiting>0')
cv('WIN-16','h_failed_other && req==h_selected_req && arb_addr==h_selected_addr && req!=0')
cv('WIN-17','issue_fire && select_valid && select_e!=m_attempt_e')
cv('WIN-18','ar_fire && select_valid && alloc_e!=select_e && h_rank_valid!=0')
cv('WIN-19','r_fire && blocked_six && !issue_fire && req==0')

# Bank、half、双 grant 全组合；不对 grant 强加 onehot。
for b in range(8):
    cv('ARB-01',f'issue_fire && req==(8\'b1<<{b}) && arb_addr==m_addr[m_attempt_e][17:6]',f'B{b}')
    for h in range(2):
        cv('ARB-02',f'select_valid && m_addr[select_e][5:3]=={b} && m_addr[select_e][6]=={h} && rd_mem_status[{b}]=={1 if h else 2}',f'B{b}H{h}')
        cv('ARB-11',f'req[{b}] && ar_rd_gnt[{b}] && rw_rd_gnt[{b}] && arb_addr[0]=={h} && rd_mem_status[{b}][{h}]',f'B{b}H{h}')
cv('ARB-03','waiting>0 && rd_mem_status[m_addr[m_attempt_e][5:3]]==0 && select_valid','IDLE')
cv('ARB-03','waiting>0 && h_status==16\'hffff && !select_valid','BUSY')
for a in (0,1,4094,4095): cv('ARB-04',f'req!=0 && arb_addr=={a} && arb_addr==m_addr[m_attempt_e][17:6]',f'ADDR{a}')
for ag in range(2):
    for rg in range(2): cv('ARB-05',f'req!=0 && ((req&ar_rd_gnt)!=0)=={ag} && ((req&rw_rd_gnt)!=0)=={rg} && issue_fire=={ag&rg}',f'G{ag}{rg}')
cv('ARB-06','req!=0 && (ar_rd_gnt&rw_rd_gnt&~req)!=0 && !issue_fire')
cv('ARB-07','req!=0 && (req&ar_rd_gnt)!=0 && (req&rw_rd_gnt)==0 && rw_rd_gnt!=0 && !issue_fire')
cv('ARB-08',"req==0 && ar_rd_gnt==8'hff && rw_rd_gnt==8'hff && !issue_fire")
cv('ARB-09',"issue_fire && ar_rd_gnt==8'hff && rw_rd_gnt==8'hff")
cv('ARB-10','h_selected_prev && req==h_selected_req && arb_addr==h_selected_addr && rd_mem_status[m_addr[m_attempt_e][5:3]][arb_addr[0]] && issue_fire')
cv('ARB-13','h_selected_prev && req==h_selected_req && arb_addr==h_selected_addr && h_status!=h_prev_status && !issue_fire')
cv('ARB-14','h_prev_i && issue_fire && req==h_prev_req && arb_addr[0]!=h_prev_arb[0]')

# 组合 pending 与生命周期占用分别检查，不能把 R 当发射扣减。
for a in range(2):
    for i in range(2): cv('CNT-01',f'ar_fire=={a} && issue_fire=={i} && waiting>0 && pending_cnt==waiting+{a}-{i}',f'A{a}I{i}')
cv('CNT-02','waiting==5 && issue_fire && !ar_fire && pending_cnt==4')
cv('CNT-03','waiting==5 && issue_fire && ar_fire && pending_cnt==5')
cv('CNT-04','waiting==5 && !issue_fire && ar_fire && pending_cnt==6')
cv('CNT-05','used==9 && waiting==0 && pending_cnt==0 && !ar_fire && !r_fire && arready==0')
cv('CNT-06','waiting==0 && ar_fire && !issue_fire && pending_cnt==1','EMPTY_A')
cv('CNT-06','waiting==9 && !ar_fire && !issue_fire && pending_cnt==9','FULL')
cv('CNT-07','req!=0 && !issue_fire && !ar_fire && pending_cnt==waiting','FAIL')
cv('CNT-07','mem_capture_due && !issue_fire && !ar_fire && pending_cnt==waiting','MEM')
for a in range(2): cv('CNT-08',f'r_fire && ar_fire=={a} && !issue_fire && pending_cnt==waiting+{a}',f'A{a}')

# MEM：到期由成功历史决定。无 valid/tag，不能从本接口检测环境“实际丢返回”。
cv('MEM-01','h_prev_m && h_response_matches && rsp_e==h_prev_due_slot','NEXT_R')
cv('MEM-02','h_i_history[3:0]==4\'b1000 && mem_capture_due && h_failed_before_success[mem_capture_slot]')
cv('MEM-03',"h_m_history[2:0]==3'b111 && mem_capture_due && mem_rdata!=h_prev_mem && pc_err!=h_prev_pc")
cv('MEM-04',"h_m_history[4:0]==5'b10100 && mem_capture_due")
cv('MEM-05','!mem_capture_due && mem_rdata!=h_prev_mem && pc_err!=h_prev_pc && used>0')
cv('MEM-06','h_response_matches && h_done_wait[rsp_e]>=1 && mem_rdata!=m_data[rsp_e] && pc_err!=m_pc[rsp_e]')
cv('MEM-07','mem_capture_due && h_prev_m && rready==0 && rvalid==0')
cv('MEM-08','ar_fire && mem_capture_due && alloc_e!=mem_capture_slot')
cv('MEM-09','issue_fire && mem_capture_due && m_attempt_e!=mem_capture_slot')
cv('MEM-10','mem_capture_due && h_response_matches && mem_capture_slot!=rsp_e')
cv('MEM-11','mem_capture_due && head_valid[m_src[mem_capture_slot]] && head[m_src[mem_capture_slot]]==mem_capture_slot && rready[m_src[mem_capture_slot]] && !rvalid[m_src[mem_capture_slot]]')
for name,val in [('ZERO',"128'b0"),('ONES',"{128{1'b1}}"),('AA',"{16{8'haa}}"),('55',"{16{8'h55}}")]:
    cv('MEM-12',f'h_response_matches && rdata=={val}',name)
# 128 位均由 A_R_DATA 无条件逐位比较；下面覆盖每一位 walking 1 / walking 0。
for bit in range(128):
    cv('MEM-12',f'h_response_matches && rdata==(128\'b1<<{bit})',f'W1_{bit:03d}')
    cv('MEM-12',f'h_response_matches && rdata==~(128\'b1<<{bit})',f'W0_{bit:03d}')
cv('MEM-13',"h_m_history[2:0]==3'b111 && mem_capture_due && h_pc_history==3'b101 && !pc_err")

# R / RR：按接收 FIFO 头比较五类返回字段，ID 可重复。
cv('RSP-01','eligible==0 && rvalid==0 && used>0')
cv('RSP-02','(m_live&m_done)!=0 && rready==0 && rvalid==0 && h_prev_rready==0 && !h_prev_r')
for s in range(3): cv('RSP-03',f'eligible==(3\'b1<<{s}) && rvalid==(3\'b1<<{s}) && h_response_matches',f'S{s}')
cv('RSP-04','h_rr012_phase==2 && eligible==7 && rvalid==4 && h_response_matches')
for mask in (3,5,6):
    for rr in range(3): cv('RSP-05',f'eligible=={mask} && m_rr=={rr} && h_response_matches',f'M{mask}RR{rr}')
cv('RSP-06','h_prev_r && h_prev_rsrc==2 && m_rr==0 && rvalid[0] && h_response_matches')
cv('RSP-07','h_rr_gap_seen && r_fire && h_response_matches')
cv('RSP-08','h_prev_eligible!=0 && eligible!=0 && rready!=h_prev_rready && rvalid!=0 && (rvalid&~rready)==0 && h_response_matches')
for s in range(3):
    q=f'sources[{s}]'
    cv('RSP-09',f'{q}.order_phase==5 && {q}.source_r && {q}.oldest=={q}.third_token && {q}.head_payload_matches',f'S{s}')
    cv('RSP-10',f'{q}.order_count>=2 && !m_sent[{q}.order_slot[0]] && m_done[{q}.order_slot[1]] && rready[{s}] && !rvalid[{s}]',f'S{s}')
    cv('RSP-11',f'{q}.order_count>=2 && m_id[{q}.order_slot[0]]!=m_id[{q}.order_slot[1]] && m_done[{q}.order_slot[1]] && {q}.source_r && {q}.head_payload_matches',f'S{s}')
    cv('RSP-12',f'{q}.order_count>=2 && m_id[{q}.order_slot[0]]==m_id[{q}.order_slot[1]] && m_data[{q}.order_slot[0]]!=m_data[{q}.order_slot[1]] && m_done[{q}.order_slot[1]] && {q}.source_r && {q}.head_payload_matches',f'S{s}')
    cv('RSP-13',f'head_valid[{s}] && !m_done[head[{s}]] && (rvalid&~(3\'b1<<{s}))!=0 && h_response_matches',f'S{s}')
    cv('RSP-14',f'h_prev_r && h_prev_rsrc=={s} && rvalid[{s}] && h_response_matches',f'S{s}')
    cv('RSP-15',f'{q}.order_count==1 && {q}.source_r && {q}.source_ar && {q}.head_payload_matches',f'S{s}')
    cv('RSP-16',f'eligible[{s}] && {q}.bypass_count==2 && rvalid[{s}] && h_response_matches',f'S{s}')
cv('RSP-17','eligible==7 && h_response_matches && (rvalid==1 || rvalid==2 || rvalid==4)')
cv('RSP-18','rvalid==0 && used>0',scope='无 R 的合法采样点；不 cover 具体无效输出值，也不约束它们。')

for num,err,pc,resp in [('01',0,0,0),('02',3,0,3),('03',0,1,1),('04',3,1,3)]:
    cv('ERR-'+num,f'h_response_matches && m_err[rsp_e]=={err} && m_pc[rsp_e]=={pc} && rresp=={resp}')
cv('ERR-06','h_error_sandwich_phase==2 && h_response_matches && winner==0 && rresp==0')
cv('ERR-07','h_prev_r && r_fire && winner==h_prev_rsrc && m_addr[rsp_e][17:3]==h_prev_raddr_full[17:3] && raddr!=h_prev_raddr_full[2:0] && h_response_matches')
for p in (0,1,15,16,31): cv('ERR-08',f'h_response_matches && r_port_id=={p}',f'P{p}')

cv('CON-01','ar_fire && issue_fire && mem_capture_due && r_fire && h_response_matches')
cv('CON-02','used==9 && ar_fire && issue_fire && mem_capture_due && r_fire && alloc_e==rsp_e && mem_capture_slot!=rsp_e && m_attempt_e!=rsp_e && h_response_matches')
cv('CON-03','h_quiet_run>=3 && !ar_fire && !issue_fire && !mem_capture_due && !r_fire && used>0')
cv('CON-04','used==0 && ar_fire && !issue_fire && !mem_capture_due && !r_fire')
cv('CON-06','h_ar_r_run>=2 && ar_fire && r_fire && h_response_matches')

cv('BIZ-01','h_single_start[6] && h_response_matches','FIRST_R')
cv('BIZ-01','h_ar_r_run>=3 && ar_fire && r_fire && src==winner && (h_ar_sources==1 || h_ar_sources==2 || h_ar_sources==4) && h_response_matches','STEADY4')
cv('BIZ-02','h_total_a>=16 && h_total_r>=8 && h_ar_sources==7 && h_seen_reject && h_seen_partial_ready && ar_fire && h_duplicate_id',scope='有限长混合轨迹，含三源、失败、部分 ready、重复 ID；不声明无界进展。')
cv('BIZ-03','waiting>=3 && h_hotspot && h_reject_run>=2 && select_valid')
cv('BIZ-04','blocked_six && blocked_streak>=6 && req==0',scope='连续至少 7 拍窗口阻塞；永久忙的安全性由 assert 检查，不把有限 cover 当作永久见证。')
cv('BIZ-05','h_reject_run>=6 && req!=0 && !issue_fire',scope='连续至少 7 拍拒绝；不假定后续一定获 grant。')
cv('BIZ-06','h_notready_run[0]>=6 && !rready[0] && (rvalid&6)!=0 && h_response_matches',scope='源 0 连续至少 7 拍阻塞期间其他源响应；不证明无限轨迹最终排空。')
cv('BIZ-09','occ[0]==7 && !m_done[head[0]] && h_other_done && !r_fire && arready[1] && arready[2] && ar_fire && src!=0')
cv('BIZ-10','used==0 && h_was_drained && h_empty_run>=5 && ar_fire && mem_rdata!=h_prev_mem')

# 边界行不伪造“已覆盖”。有端口表达能力的附加见证仍给出。
cv('AR-20','h_prev_valid && !h_prev_a && arvalid && !ar_fire && arready!=0 && src==h_prev_src',scope='只见证连续阻塞选择；共享端口无各源 pending 信号，不能证明上游公平性。')
cv('BIZ-07','h_total_a>=7 && h_ar_sources==1 && arready[1] && arready[2]',scope='有限的不公平选择；未呈现给共享 AR 的请求无法观察。')
cv('BIZ-08','h_was_drained && used==0 && h_total_r>=6 && !arvalid',scope='存在排空轨迹；不添加公平性 assume，不声明所有轨迹有界排空。')
for b in range(8):
    for h in range(2): cv('ENV-06',f'select_valid && m_addr[select_e][5:3]=={b} && m_addr[select_e][6]=={h} && h_status==(16\'hffff^(16\'b1<<{2*b+h}))',f'B{b}H{h}',scope='逐位解码见证；实际 SoC 接线仍需在该 SoC 边界连接检查器。')

# 明确哪些测试点超出仅顶层端口时钟 SVA 的观测范围。
exceptions={
 'AR-09':('negative_contract','关闭 E05 后，用 N_AR_09 cover / V_AR_09 assert 检查环境违规见证。'),
 'AR-10':('negative_contract','关闭 E03 后，用 N_AR_10 cover / V_AR_10 assert 检查环境违规见证。'),
 'ARB-12':('negative_contract','关闭 E06 后，用 N_ARB_12 cover / V_ARB_12 assert 检查环境违规见证。'),
 'ERR-05':('negative_contract','关闭 E04 后，用 N_ERR_05 cover / V_ERR_05 assert 检查环境违规见证。'),
 'MEM-14':('external_oracle_required','MEM 无 valid/tag/独立存储器真值：仅当前顶层信号不能分辨延迟或错误数据；不得伪造 assume/cover。需外部 MEM 参考或注错记录。'),
 'CAP-20':('mutation_required','A_CC_READY 与 A_CC_BUDGET 检查错误接收后果；物理强制 5/4/0 需内部注错。'),
 'CAP-21':('mutation_required','A_CC_READY/A_CC_SRC_LIMIT 检查第八项错误接收；物理强制占用需内部注错。'),
 'ENT-10':('mutation_required','双重分配的丢单/串单由 A_REQ/A_R_*/A_XAU_R_* 检查；物理 alloc 冲突不是端口可观察事件。'),
 'ENT-11':('mutation_required','A_CC_R_NONEMPTY/A_XAU_R_* 检查重复响应；重复 done 若未改变外部行为不保证检出。'),
 'CON-05':('mutation_required','端口数据/顺序断言检查有外部后果的槽别名；无外部后果的内部冲突需白盒断言。'),
 'AR-15':('integration_review','posedge SVA 只检查采样值；边沿之间的组合毛刺/稳定时间需要时序或仿真检查。'),
 'ENV-07':('observability_review','只使用顶层端口，不能证明物理存储数量、原始位清零或不可观察内部事件。'),
 'ENV-08':('assumption_audit','机械核对 assume 只有 E03/E04/E05/E06；环境关系不可替代 A_READY/A_REQ/A_R_*。'),
}

PORT_NAMES=set('arvalid arready araddr src arid ar_port_id arresp rvalid rready rdata rid r_port_id raddr rresp req arb_addr pending_cnt ar_rd_gnt rw_rd_gnt rd_mem_status mem_rdata pc_err ar_fire issue_fire r_fire h_status onehot'.split())
HISTORY_NAMES=set('h_prev_valid h_prev_a h_prev_i h_prev_r h_prev_src h_prev_rsrc h_prev_ready h_prev_rready h_prev_req h_prev_id h_prev_arb h_prev_addr h_prev_port h_prev_mem h_prev_pc h_prev_status h_total h_occ h_budget h_ready h_ar_sources h_total_a h_total_r h_i_history h_a_history h_src_history h_pc_history h_ar_run h_same_ar_run h_r_run h_ar_r_run h_reject_run h_seen_reject h_seen_partial_ready'.split())
def dependency(expr):
    # Ignore numeric literal base/digits, then classify every remaining identifier.
    clean=re.sub(r"\d+'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ]+",'',expr)
    names=set(re.findall(r'\b[A-Za-z_][A-Za-z0-9_]*\b',clean))
    if names<=PORT_NAMES:return 'NO_REF_MODEL_PORTS'
    if names<=PORT_NAMES|HISTORY_NAMES:return 'NO_REF_MODEL_HISTORY'
    return 'REF_MODEL'

def emit():
    missing={c['id'] for c in CASES}-set(spec)-set(exceptions)
    assert not missing,missing
    text=['// 自动整理的可读原生 SVA；定义源为本目录 build_catalog.py 的显式表达式表。',
          '// 测试点与前提来自 docs/testpoints/corner_20261021/catalog.json。',
          '// 不含复位场景、X/Z 场景；disable iff 仅禁用属性，不建立初态。',
          '`include "cmdbuf_rd_corner_history.svh"',
          '`include "cmdbuf_rd_corner_assertions.svh"',
          '`include "cmdbuf_rd_corner_sequences.svh"','']
    rows=[]
    for c in CASES:
        cid=c['id']; bins=spec.get(cid,[])
        text += [f'// ==================== {cid} {c["name"]} ====================',
                 '// 前提：'+c['pre'],'// 操作：'+c['action'],'// 应检查：'+c['expected']]
        if not bins: text += ['// 此行不添加伪覆盖：'+exceptions[cid][1],'']
        for b in bins:
            b['dependency']=dependency(b['expression'])
            text += ['// 覆盖边界：'+b['scope'],
                     '// ['+b['dependency']+'] 场景见证；命中仅证明存在路径，断言单独检验正确性。',
                     b['label']+': cover property (',
                     '    @(posedge clk) disable iff (!rst_n)',
                     '    '+b['expression'],');','']
        related=[s for s in c['properties'].split(',') if s and s!='待专项补充']
        if cid.startswith(('AR-','CAP-','ENT-','CON-','BIZ-')):
            related+=['A_CC_READY','A_CC_TOTAL','A_CC_BUDGET','A_CC_SRC_LIMIT','A_CC_R_NONEMPTY']
        row=dict(c,assertion_or_assumption_labels=sorted(set(related)),cover_bins=bins,
                 coverage_class=exceptions.get(cid,('port_sva',None))[0],
                 limitation=exceptions.get(cid,(None,None))[1],execution='NOT_RUN')
        if cid in ('AR-20','BIZ-07','BIZ-08','ENV-06'):
            row['coverage_class']='bounded_witness_and_boundary';row['limitation']=bins[0]['scope']
        rows.append(row)
    (HERE/'cmdbuf_rd_corner_properties.svh').write_text('\n'.join(text)+'\n',encoding='utf-8')
    (HERE/'case_property_map.json').write_text(json.dumps({'scope':'156 cases; no reset/four-state; top ports only; cover is reachability, not proof.',
        'cases':rows},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'cases':len(rows),'normal_cases_with_cover':sum(bool(r['cover_bins']) for r in rows),
                      'new_cover_bins':sum(len(r['cover_bins']) for r in rows)},ensure_ascii=False))

if __name__=='__main__': emit()
