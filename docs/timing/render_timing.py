from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json, html

OUT = Path(__file__).resolve().parent
FONT = 'C:/Windows/Fonts/msyh.ttc'
BOLD = 'C:/Windows/Fonts/msyhbd.ttc'
W, LEFT, RIGHT, ROW_H = 2000, 350, 1950, 72
INK, MUTED, GRID = '#16324f', '#5d6f82', '#dce5ed'
BLUE, TEAL, PURPLE, RED, ORANGE = '#2468b4', '#07877e', '#7953b3', '#bf3b43', '#b96a10'
BG = '#f3f6fa'

def font(n, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, n)

def width(s, f):
    return f.getlength(str(s))

def wrapped(s, max_w, f):
    lines, cur = [], ''
    for ch in s:
        if ch == '\n':
            lines.append(cur); cur = ''; continue
        if cur and width(cur + ch, f) > max_w:
            lines.append(cur); cur = ch
        else:
            cur += ch
    if cur: lines.append(cur)
    return lines

def text_center(d, xy, s, f, fill=INK):
    x, y = xy
    s = str(s).replace('✓', '+')
    d.text((x-width(s, f)/2, y), s, font=f, fill=fill)

def dashed(d, x1, x2, y, fill=GRID, dash=8):
    x = x1
    while x < x2:
        d.line((x, y, min(x+dash, x2), y), fill=fill, width=2)
        x += dash*2

def row(label, values, kind='bus', color=None):
    return {'label':label, 'values':values, 'kind':kind, 'color':color}

def panel(title, cycles, rows, note=''):
    assert all(len(r['values']) == len(cycles) for r in rows), title
    return {'title':title, 'cycles':cycles, 'rows':rows, 'note':note}

def cyc(a, b): return ['C'+str(i) for i in range(a, b+1)]
def seq(s): return s.split()
def b(s): return list(map(int,s))

def bus_style(v, forced=None):
    s = str(v)
    if '×' in s or '取消' in s or s in ['11','越界']:
        return RED, '#fbe8e8'
    if forced: return forced, '#eaf2fa'
    for char, col, bg in [('A',BLUE,'#e8f1fc'),('B',PURPLE,'#f0ebfa'),('C',TEAL,'#e4f5f2'),('F',ORANGE,'#fff1dc')]:
        if char in s: return col, bg
    if s in ['空拍','无候选','无效']:
        return MUTED, '#edf1f5'
    return BLUE, '#eaf2fa'

def panel_height(p):
    note_lines = wrapped(p['note'], W-110, font(23)) if p['note'] else []
    return 124 + ROW_H*(len(p['rows'])+1) + 40 + 30*len(note_lines)

def draw_panel(d, p, y0):
    h = panel_height(p)
    d.rounded_rectangle((25,y0,W-25,y0+h-12), radius=18, fill='white', outline=GRID, width=2)
    d.text((50,y0+19),p['title'],font=font(29,True),fill=INK)
    n = len(p['cycles']); cw=(RIGHT-LEFT)/n
    top=y0+105
    for j,c in enumerate(p['cycles']):
        x=LEFT+j*cw
        text_center(d,(x+cw/2,y0+66),c,font(24,True),INK)
    bottom=top+ROW_H*(len(p['rows'])+1)
    for j in range(n+1):
        x=LEFT+j*cw
        d.line((x,top-9,x,bottom),fill=GRID,width=2)
    # Rising edges are at column boundaries; the right boundary commits that cycle.
    y=top
    d.text((50,y+15),'clk',font=font(24,True),fill=MUTED)
    hi,lo=y+10,y+43
    for j in range(n):
        x=LEFT+j*cw
        d.line((x,hi,x+cw/2,hi,x+cw/2,lo,x+cw,lo,x+cw,hi),fill=MUTED,width=3)
    for k,r in enumerate(p['rows']):
        y=top+(k+1)*ROW_H
        if k%2==0:
            d.rectangle((LEFT,y-1,RIGHT,y+ROW_H-2),fill='#f8fafc')
            for j in range(n+1):
                x=LEFT+j*cw; d.line((x,y-1,x,y+ROW_H-2),fill=GRID,width=1)
        lf=font(24)
        if width(r['label'],lf)>LEFT-70: lf=font(21)
        d.text((50,y+17),r['label'],font=lf,fill=INK)
        if r['kind']=='bit':
            col=r['color'] or TEAL; hi,lo=y+12,y+48
            prev=None
            for j,v in enumerate(r['values']):
                x=LEFT+j*cw; lev=hi if v else lo
                if v: d.rectangle((x+1,hi, x+cw-1,lo),fill='#e1f3ef')
                if prev is not None and prev!=v:
                    d.line((x,hi,x,lo),fill=col,width=3)
                d.line((x,lev,x+cw,lev),fill=col,width=3)
                text_center(d,(x+cw/2,y+21),str(v),font(20),col if v else MUTED)
                prev=v
        else:
            for j,v in enumerate(r['values']):
                x=LEFT+j*cw
                if v is None or str(v) in ['—','-']:
                    dashed(d,x+8,x+cw-8,y+31,'#c4ced9')
                    continue
                col,fill=bus_style(v,r['color'])
                pts=[(x+3,y+31),(x+12,y+9),(x+cw-12,y+9),(x+cw-3,y+31),(x+cw-12,y+54),(x+12,y+54)]
                d.polygon(pts,fill=fill,outline=col,width=2)
                fs=24
                while fs>15 and width(str(v),font(fs))>cw-26: fs-=1
                text_center(d,(x+cw/2,y+15),str(v),font(fs,True),col)
    yy=bottom+10
    for line in wrapped(p['note'],W-110,font(23)) if p['note'] else []:
        d.text((55,yy),line,font=font(23),fill=MUTED); yy+=30
    return h

manifest=[]
def figure(num,title,panels,notes=(),pending=False,confirmed=''):
    foot=[]
    for note in notes: foot += wrapped(note,W-110,font(23))
    h=150+sum(panel_height(p)+14 for p in panels)+50+len(foot)*32
    im=Image.new('RGB',(W,h),BG);d=ImageDraw.Draw(im)
    d.rectangle((0,0,W,103),fill=INK)
    d.text((45,21),f'{num:02d}  {title}',font=font(37,True),fill='white')
    d.text((48,113),'每列一个周期，右边界上升沿提交；+ 成功，× 失败，虚线表示无对应有效数据。',font=font(22),fill=MUTED)
    if pending:
        tag='待确认方案'
        d.rounded_rectangle((W-250,25,W-35,76),radius=10,fill='#ffddb0')
        text_center(d,(W-142,34),tag,font(24,True),ORANGE)
    elif confirmed:
        tag='已确认 '+confirmed
        d.rounded_rectangle((W-250,25,W-35,76),radius=10,fill='#c9efe3')
        text_center(d,(W-142,34),tag,font(24,True),TEAL)
    y=153
    for p in panels: y+=draw_panel(d,p,y)+14
    for line in foot:
        d.text((50,y+4),line,font=font(23),fill=ORANGE if pending else MUTED);y+=32
    name=f'{num:02d}_timing.png';im.save(OUT/name)
    manifest.append({'num':num,'title':title,'file':name,'pending':pending,'confirmed':confirmed,'width':W,'height':h})

figure(1,'连续正常流水',[panel('A、B、C 均来自 XAU 0；仲裁成功；rready[0] 始终为 1',cyc(1,10),[
 row('AR 接收',seq('A B C — — — — — — —')),
 row('判断级选中',seq('— A B C — — — — — —')),
 row('下游请求',seq('— — A✓ B✓ C✓ — — — — —')),
 row('issue_success',b('0011100000'),'bit'),
 row('内部 capture_valid',b('0000001110'),'bit'),
 row('MEM 有效数据',seq('— — — — — — A B C —')),
 row('R 返回命令',seq('— — — — — — — A B C')),
 row('rvalid[2:0]',seq('000 000 000 000 000 000 000 001 001 001')),
 row('释放 CMDBUF / OTB',seq('— — — — — — — A B C')),
], 'C3 同时接收 C、判断 B、请求 A。A 在 C3 发射成功、C7 捕获返回、C8 响应成功后释放。')],
['已确认：MEM 返回当拍写 OTB，最早下一拍参与 R 仲裁；仍须满足源内保序、rready 和 RR。'],confirmed='无旁路')

figure(2,'乱序发射与单 XAU 保序返回',[panel('A 比 B 老，均属 XAU 0；A 的 Bank 在 C4 才变空闲',cyc(1,11),[
 row('AR 接收',seq('A B — — — — — — — — —')),
 row('A 的 Bank 状态',seq('忙 忙 忙 空闲 空闲 空闲 空闲 空闲 空闲 空闲 空闲')),
 row('判断级选中',seq('— 无候选 B A — — — — — — —')),
 row('下游请求',seq('— — — B✓ A✓ — — — — — —')),
 row('MEM 有效数据',seq('— — — — — — — B A — —')),
 row('XAU 0 响应',seq('— — — — — — — — — A B')),
 row('释放 Entry',seq('— — — — — — — — — A B')),
], 'B 在 C8 完成仍不能越过 A；A 在 C9 完成，最早 C10 返回 A、C11 返回 B（ready 与 RR 允许）。')])

figure(3,'窗口外命令等待成功前馈后进入窗口',[panel('预置未发射年龄顺序 A、B、C、D、E、F；F 始终空闲',['N','N+1','N+2','N+3'],[
 row('判断级窗口',seq('A～E A～E B～F B～E')),
 row('A 的 Bank 状态',seq('忙 空闲 空闲 空闲')),
 row('B～E 的状态',seq('忙 忙 忙 忙')),
 row('F 的 Bank 状态',seq('空闲 空闲 空闲 空闲')),
 row('F 是否属于窗口',b('0010'),'bit'),
 row('判断级选中',seq('无候选 A F 无候选')),
 row('下游请求',seq('— — A✓ F✓')),
], 'N 拍不能越过窗口选择 F；N+2 拍 A 成功，按 6B 当拍前移窗口并选 F；N+3 拍 F 发射。')],
['窗口前移只由成功结果触发；屏蔽请求级命令的重复预选，不等于提前把它移出未发射窗口。'])

figure(4,'双 grant 判定与返回气泡',[panel('示意：N+1 尝试 B 失败，N+2 重判，N+3 重试成功',['N','N+1','N+2','N+3','N+4','N+5','N+6','N+7'],[
 row('下游请求',seq('A B — B — — — —')),
 row('ar_rd_gnt[目标 Bank]',b('11010000'),'bit'),
 row('rw_rd_gnt[目标 Bank]',b('10010000'),'bit'),
 row('issue_success',b('10010000'),'bit'),
 row('内部 capture_valid',b('00001001'),'bit'),
 row('MEM 有效返回',seq('— — — — A — — B')),
], '失败当拍无其他合格候选，N+2 重判 B。N+5 无失败尝试的返回；N+7 才捕获成功重试的 B。')],
['成功条件：|(req & ar_rd_gnt & rw_rd_gnt)。两个 grant 必须命中 req 所在的同一个 Bank bit。'])

figure(5,'失败不取消后续预选：采用 5A',[
 panel('方案 5A：B 继续发送；A 在下一拍按原年龄恢复判断',cyc(2,6),[
  row('判断级选中',seq('A B A C —')),
  row('下游请求',seq('— A× B✓ A✓ C✓')),
  row('issue_success',b('00111'),'bit'),
 ], 'C3：A 正在请求，B 同拍完成判断。A 失败后 C4 重判，C5 重试；B 在 C4 继续发送。'),
],['已确认 5A：A 失败不取消 B，也不在失败当拍重选 A 替换 B。A 下一拍按原年龄恢复候选。',
   '当前请求级命令仍计入待发数；失败时仍占窗口位置，但本拍屏蔽重复预选。'],confirmed='5A')

figure(6,'成功当拍前移窗口：采用 6B',[
 panel('方案 6B：将成功 grant 前馈到本拍窗口与选择逻辑',['N','N+1','N+2'],[
  row('判断级窗口',seq('B～F B～E B～E')),
  row('判断级选中',seq('F 无候选 无候选')),
  row('下游请求',seq('A✓ F✓ —')),
 ], 'N 拍 A 确认成功后立即选 F，N+1 请求 F；代价是增加 grant→窗口→选择的组合路径。'),
],['已确认 6B：成功 grant 前馈到本拍窗口计算。A 失败时不前移，且按 5A 保留后续预选结果。',
   '前提：A～F 按年龄排列；B～E 始终忙，F 始终空闲；成功发射后 Entry 仍保留到 R 握手。'],confirmed='6B')

figure(7,'MEM 单拍返回必须捕获，不受 R ready 影响',[panel('A 属于 XAU 0，arresp=00，C3 发射成功，C7 返回 pc_err=1',cyc(7,9),[
 row('内部 capture_valid',b('100'),'bit'),
 row('MEM 有效数据',seq('D_A — —')),
 row('MEM 有效 pc_err',seq('1 — —')),
 row('rready[2:0]',seq('000 000 001')),
 row('OTB 保存的数据',seq('捕获D_A D_A D_A')),
 row('OTB 保存的 pc_err',seq('捕获1 1 1')),
 row('rvalid[2:0]',seq('000 000 001')),
 row('R 的 rresp',seq('— — 01')),
 row('retire_fire',b('001'),'bit'),
], 'MEM 返回之外的虚线表示无效 / 不关心，不代表数据被强制清零。C9 输出保存值，拍末释放。')])

figure(8,'响应 RR 仅在当拍 ready 的完成队头间选择',[panel('初始 RR 起点 XAU 0；A / B / C 分别为三个 XAU 的已完成队头',['N','N+1','N+2','N+3'],[
 row('RR 起点（拍初）',seq('XAU0 XAU2 XAU1 XAU1')),
 row('rready[2:0]',seq('110 001 000 100')),
 row('rvalid[2:0]',seq('010 001 000 100')),
 row('R 返回命令',seq('B A — C')),
 row('目标 XAU',seq('1 0 — 2')),
 row('retire_fire',b('1101'),'bit'),
 row('RR 起点（拍末）',seq('XAU2 XAU1 XAU1 XAU0')),
], 'N+2 无 ready 通道，不产生 rvalid，也不推进 RR。rvalid & ~rready 必须始终为 0。')])

figure(9,'地址拆分、字段透传与异常优先级',[panel('A：src=2，ID=A5，port=13，地址=12345（十六进制）；arresp=2\'b11',cyc(1,8),[
 row('AR 接收',seq('A — — — — — — —')),
 row('判断级选中',seq('— A — — — — — —')),
 row('req[7:0]',seq('00 00 01 00 00 00 00 00')),
 row('arb_addr[11:0]',seq('— — 48D — — — — —')),
 row('issue_success',b('00100000'),'bit'),
 row('内部 capture_valid',b('00000010'),'bit'),
 row('MEM 有效 pc_err',seq('— — — — — — 1 —')),
 row('rready[2:0]',seq('100 100 100 100 100 100 100 100')),
 row('rvalid[2:0]',seq('000 000 000 000 000 000 000 100')),
 row('rid / port / raddr',seq('— — — — — — — A5/13/5')),
 row('rresp[1:0]',seq('— — — — — — — 11')),
], '目标为 Bank 0 的奇部分，检查 rd_mem_status[1][0]；araddr[17:6]=12\'h48D。')],
['C8 返回 rdata=D_A，rid=8\'hA5，port_id=5\'h13，raddr=3\'b101。arresp=11 优先于 pc_err=1。',
 '正常地址时：pc_err=0 → rresp=00；pc_err=1 → rresp=01。C7 捕获，最早 C8 返回，无同拍旁路。'])

figure(10,'满表同拍释放复用：采用 10B',[
 panel('方案 10B：占用为 (7,1,1)，本拍 XAU0 退休一条并接收新命令',['N','N+1','N+2'],[
  row('used_cnt（拍初）',seq('9 9 9')),
  row('arready[2:0]',seq('111 000 000')),
  row('arvalid',b('100'),'bit'),
  row('AR 接收',seq('新命令 — —')),
  row('R 释放',seq('旧命令 — —')),
  row('used_cnt（拍末）',seq('9 9 9')),
 ], 'R 输出使用旧命令的内容；同一拍末再写入新命令，重新初始化状态与年龄。'),
],['已确认 10B：free_mask = ~valid | retire_mask；同拍接收与释放时，占用数量仍为 9。',
   '新分配初始化优先，清除新命令 issued/done，重新登记年龄；新命令下一拍才进入判断级。'],confirmed='10B')

figure(11,'窗口内全忙：第六条空闲命令仍被阻塞',[
 panel('预置 A～E 均未发射且访问 Bank 0 偶；第六条 F 访问 Bank 1 偶；请求级初始为空',
       ['N','N+1','N+2','N+3','N+4','N+5'],[
  row('rd_mem_status（十六进制）',seq('0001 0001 0001 0001 0001 0001')),
  row('AR 接收',seq('F — — — — —')),
  row('判断级窗口',seq('A～E A～E A～E A～E A～E A～E')),
  row('A～E 的 Bank 状态',seq('忙 忙 忙 忙 忙 忙')),
  row('F 的 Bank 状态',seq('空闲 空闲 空闲 空闲 空闲 空闲')),
  row('判断级选中',seq('无候选 无候选 无候选 无候选 无候选 无候选')),
  row('req[7:0]',seq('00 00 00 00 00 00')),
  row('issue_success',b('000000'),'bit'),
  row('pending_cnt（拍末）',seq('6 6 6 6 6 6')),
 ], 'N 拍末接收 F；N+1 起 F 已驻留，但年龄排第六，仍在窗口外。状态持续不变时，等待持续。'),
],['rd_mem_status=16\'h0001：rd_mem_status[0][0]=1，其余位为 0；Bank 0 偶忙，Bank 1 偶空闲。',
   '先取最老五条待发命令，再判断 Bank 空闲；本例无成功发射，6B 不触发窗口前移。',
   '例如 A～E 属于 XAU0、F 属于 XAU1；后续接收还受各 XAU 保留额度约束，不能由一路占满九项。'])

figure(12,'容量保留：一路占七项后仍允许其他来源接收',[
 panel('每 XAU 保留一项，其余六项共享；例中无 R 退休；占用元组按 (XAU0,XAU1,XAU2)',
       ['N','N+1','N+2','N+3','N+4'],[
  row('占用数（拍初）',seq('6/0/0 7/0/0 7/0/0 7/1/0 7/1/1')),
  row('arready[2:0]',seq('111 110 110 100 000')),
  row('AR 输入来源',seq('XAU0 — XAU1 XAU2 —')),
  row('arvalid',b('10110'),'bit'),
  row('ar_fire',b('10110'),'bit'),
  row('占用数（拍末）',seq('7/0/0 7/0/0 7/1/0 7/1/1 7/1/1')),
 ], 'XAU0 占七项后 ready[0]=0，但 XAU1/2 仍各有一个接收名额；三路占用合计九项后才全零。'),
],['容量实现方案：每 XAU 逻辑保留一项，其余六项共享；物理 entry 仍统一分配，不按固定编号分区。',
   '用户已要求防止容量独占；保留一项是本设计采用的最小保底方案。上游可切换 src，但公平性未定。'])

figure(13,'满表复用仍需保留刚释放来源的最低名额',[
 panel('初始占用 (7,1,1)；N 拍退休 XAU1 唯一命令，N+2 拍退休 XAU0 一条',
       ['N','N+1','N+2'],[
  row('占用数（拍初）',seq('7/1/1 7/1/1 7/1/1')),
  row('R 退休来源',seq('XAU1 — XAU0')),
  row('扣除退休后的占用',seq('7/0/1 7/1/1 6/1/1')),
  row('arready[2:0]',seq('010 000 111')),
  row('AR 接收来源',seq('XAU1 — XAU2')),
  row('arvalid',b('101'),'bit'),
  row('占用数（拍末）',seq('7/1/1 7/1/1 6/1/2')),
 ], 'N 拍可同拍复用，但只有 XAU1 有准入资格；N+2 释放的是共享额度，三路都具备准入资格。'),
],['10B 保留；free_mask 仍考虑当拍退休，arready 还必须逐来源核对保留额度。',
   '同拍只能接收共享 AR 上的一条命令。R 返回旧负载，时钟沿后新命令初始化生效。'])

(OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(OUT/'decisions.json').write_text(json.dumps({
    'confirmed_on':'2026-10-10',
    'selected_scenarios':{
        '5':'5A: failed A does not cancel preselected B; A rejoins next cycle with original age',
        '6':'6B: forward successful grants into the current oldest-five window',
        '10':'10B: allow same-cycle response retirement and AR allocation/reuse'},
    'selection_logic':[
        'pending_mask = valid & ~issued',
        'success_mask = issue_success ? onehot(issue_entry_id) : 0',
        'window_mask = oldest_5(pending_mask & ~success_mask)',
        'candidate_mask = window_mask & bank_idle_mask & ~current_issue_mask'],
    'window_blocking':{
        'scope':'Oldest five not-yet-successfully-issued commands, before filtering bank availability',
        'scenario_11':'If all five window commands remain bank-busy and there is no issue-stage success, an idle-bank sixth command stays outside the window and cannot issue',
        'window_advance':'6B forwards actual successful issue only; allocation, MEM completion and R retirement do not by themselves advance this pending-command window'},
    'allocation_logic':'free_mask = ~valid | retire_mask; allocation initialization wins on reused entry',
    'capacity_policy':{
        'user_requirement':'Prevent one XAU from exhausting entries and denying entry admission to other XAUs',
        'supersedes':'Unrestricted sharing with no per-XAU admission protection',
        'design_choice':'One logical reserved entry per XAU plus six shared entries; nine physical entries remain pooled',
        'policy_origin':'Design recommendation implementing the new user requirement; reserve size not separately specified by user',
        'occupancy':'All accepted commands until their R response retires, including issued and completed commands',
        'invariant':'sum(max(occ[x], 1) for x in XAUs) <= 9',
        'ready':'After subtracting same-cycle retirement: free_after > 0 && (occ_after[x] == 0 || sum(max(occ_after[y]-1,0)) < 6)',
        'upstream_dependency':'User confirmed shared AR may switch src; fairness remains unspecified. Eventual admission needs fairness; cmdbuf_rd guarantees capacity availability'},
    'mem_to_r_timing':{
        'confirmed':True,
        'mem_return_duration_cycles':1,
        'same_cycle_bypass':False,
        'earliest_response_cycle':'MEM capture cycle N + 1',
        'eligibility':'Only registered OTB completion from a previous cycle can enter R arbitration; per-XAU head order, current rready and RR must also permit the response',
        'example':'Successful issue C3 -> MEM capture C7 -> earliest R response C8'},
    'still_unconfirmed':['Shared upstream AR arbitration fairness is unspecified; source switching is confirmed allowed']
},ensure_ascii=False,indent=2),encoding='utf-8')

# A native image overview plus a self-contained local review gallery.
thumb_w=925; margin=50; tile_h=330
ov=Image.new('RGB',(2000,140+((len(manifest)+1)//2)*tile_h+80),BG);d=ImageDraw.Draw(ov)
d.rectangle((0,0,2000,105),fill=INK)
d.text((45,25),f'cmdbuf_rd 时序图 · {len(manifest)} 个场景',font=font(38,True),fill='white')
for k,m in enumerate(manifest):
    x=margin+(k%2)*975; y=130+(k//2)*tile_h
    im=Image.open(OUT/m['file']);im.thumbnail((thumb_w,270))
    ov.paste(im,(x,y))
    d.text((x,y+278),f"{m['num']:02d}  {m['title']}",font=font(23,True),fill=ORANGE if m['pending'] else INK)
ov.save(OUT/'00_overview.png')

cards='\n'.join(f'<section id="s{m["num"]}"><h2>{m["num"]:02d} {html.escape(m["title"])}</h2><a href="{m["file"]}" target="_blank"><img src="{m["file"]}" alt="{html.escape(m["title"])}"></a></section>' for m in manifest)
nav=' '.join(f'<a href="#s{m["num"]}">{m["num"]:02d}</a>' for m in manifest)
doc='''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>cmdbuf_rd 时序图</title><style>body{margin:0;background:#edf2f7;color:#16324f;font-family:"Microsoft YaHei",sans-serif}header{background:#16324f;color:white;padding:24px 5vw}nav{position:sticky;top:0;background:white;padding:14px 5vw;box-shadow:0 2px 8px #0001}nav a{display:inline-block;margin-right:12px;color:#2468b4;font-weight:bold}main{max-width:1700px;margin:auto;padding:20px}section{scroll-margin-top:70px;margin-bottom:40px}h2{font-size:22px}img{width:100%;display:block;border-radius:10px;box-shadow:0 4px 20px #18334f18}p{line-height:1.8}</style><header><h1>cmdbuf_rd 时序图</h1><p>2026-10-10 已确认采用 5A、6B、10B；相应图已更新，绿色徽标表示已确认。图 03 同步采用 6B 的成功当拍窗口前移。<br>每列一个周期，右边界采样提交。点击任意图片查看原尺寸。<br>已确认：MEM 返回只持续一拍，返回当拍写入 OTB；最早下一拍参与 R 仲裁，无同拍旁路。实际响应仍须满足源内保序、当拍 rready 和 RR。</p></header><nav>'''+nav+'</nav><main>'+cards+'</main></html>'
doc=doc.replace('</p></header>', '<br>最新容量规则：禁止 XAU 独占九项；本设计采用每 XAU 一项保底、六项共享，新增图 12 和 13。上游允许切换 src，公平性未定。</p></header>', 1)
doc=doc.replace('<nav>', '<nav><a href="../cmdbuf_rd_design/index.html">详细设计</a><a href="../cmdbuf_rd_fault_catalog/index.html">注错清单</a>', 1)
(OUT/'index.html').write_text(doc,encoding='utf-8')
print(json.dumps({'directory':str(OUT),'figures':len(manifest),'files':[m['file'] for m in manifest]},ensure_ascii=False))
