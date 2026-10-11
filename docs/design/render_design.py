from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import html
import json
import math
import re

OUT = Path(__file__).resolve().parent
FONT = 'C:/Windows/Fonts/msyh.ttc'
BOLD = 'C:/Windows/Fonts/msyhbd.ttc'
INK = '#173550'
MUTED = '#506c82'
BLUE = '#216eb1'
TEAL = '#087f79'
ORANGE = '#a86e0b'


def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)


im = Image.new('RGB', (2100, 1290), '#eef3f8')
d = ImageDraw.Draw(im)
d.rectangle((0, 0, 2100, 108), fill=INK)
d.text((44, 24), 'cmdbuf_rd 架构与关键事件', font=font(40, True), fill='white')
d.text((46, 128), '九项配对存储 · 五项乱序窗口 · 三拍请求 · 成功后四拍捕获 · 每源保底准入', font=font(26), fill=MUTED)


def box(rect, title, lines, color=BLUE):
    x1, y1, x2, y2 = rect
    d.rounded_rectangle(rect, radius=16, fill='white', outline=color, width=3)
    d.rounded_rectangle((x1, y1, x2, y1 + 61), radius=15, fill=color)
    d.rectangle((x1 + 2, y1 + 30, x2 - 2, y1 + 61), fill=color)
    d.text((x1 + 22, y1 + 12), title, font=font(27, True), fill='white')
    for k, line in enumerate(lines):
        size = 24
        while font(size).getlength(line) > x2 - x1 - 44 and size > 19:
            size -= 1
        assert font(size).getlength(line) <= x2 - x1 - 44, line
        d.text((x1 + 22, y1 + 76 + k * 34), line, font=font(size), fill=INK)


def arrow(points, color=BLUE, label=None, label_pos=None):
    d.line(points, fill=color, width=4, joint='curve')
    p0, p1 = points[-2], points[-1]
    angle = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
    tri = [p1, (p1[0] - 15 * math.cos(angle - .46), p1[1] - 15 * math.sin(angle - .46)),
           (p1[0] - 15 * math.cos(angle + .46), p1[1] - 15 * math.sin(angle + .46))]
    d.polygon(tri, fill=color)
    if label:
        assert label_pos
        f = font(22)
        x, y = label_pos
        w = f.getlength(label)
        d.rectangle((x - 5, y - 2, x + w + 6, y + 30), fill='#eef3f8')
        d.text((x, y), label, font=f, fill=color)


box((45, 205, 355, 425), '上游共享 AR', ['来自 XAU 0 / 1 / 2', '一组 valid + payload', '三个来源 ready', '每拍最多接收一条'])
box((485, 205, 1160, 450), 'CMDBUF  九项命令与公共归属状态',
    ['AR 接收：保存地址、src、ID、port、arresp', 'valid / issued / mem_done + 九项年龄关系', '每 XAU 保留一项，其余六项共享', '仅 R 退休归还额度；物理槽位统一分配'])
box((1340, 205, 2020, 425), 'S1  五项窗口与最老命中选择',
    ['最老五条未成功发射命令', '输入 rd_mem_status[half][bank]', '先定窗口，再筛空闲，选最老', '成功当拍前移；屏蔽请求级重复预选'])
box((1340, 540, 2020, 760), 'S2  请求级寄存器',
    ['保存 entry_id / bank / araddr[17:6]', '输出 req[7:0] 与 12-bit 地址', '目标 Bank 同拍双 grant 才成功', '失败不冲刷下一条预选；保留原年龄'])
box((815, 540, 1160, 760), '四级返回标记',
    ['valid + entry_id', '每拍推进，含空泡', '只登记成功发射', '四拍后定点捕获'], TEAL)
box((1340, 875, 2020, 1115), '下游 Arbit 与 MEM Bank',
    ['八个 Bank，每个 Bank 区分奇 / 偶', '一次成功发射等于同拍 MEM 接收', '成功后四拍返回单组 128-bit 数据', 'pc_err 一位；返回仅持续一个 cycle'], TEAL)
box((485, 875, 1160, 1115), 'OTB  九项数据与公共响应控制',
    ['接收时预留 entry，按返回标记写数据和 pc_err', '完成状态同步给 CMDBUF；捕获当拍不能返回', '每 XAU 最老未退休命令完成后才可参加 RR', '只选 ready 通道；R 返回后清除配对 entry'], TEAL)
box((45, 875, 355, 1115), '上游共享 R', ['共享 128-bit payload', '最多一个 rvalid 为 1', '同 XAU 按接收序', '跨 XAU 合格者 RR'], TEAL)

arrow([(355, 285), (485, 285)], label='AR', label_pos=(400, 249))
arrow([(485, 383), (355, 383)], color=ORANGE, label='ready', label_pos=(390, 393))
arrow([(1160, 310), (1340, 310)], label='待发 + 年龄', label_pos=(1180, 270))
arrow([(1550, 425), (1550, 540)], label='选中后寄存', label_pos=(1398, 465))
arrow([(1340, 643), (1160, 643)], color=TEAL, label='成功 + entry', label_pos=(1175, 605))
arrow([(985, 760), (985, 875)], color=TEAL, label='+4 捕获位置', label_pos=(1009, 807))
arrow([(1550, 760), (1550, 875)], label='req / 地址', label_pos=(1364, 801))
arrow([(1840, 875), (1840, 760)], color=ORANGE, label='双 grant', label_pos=(1871, 805))
arrow([(1340, 989), (1160, 989)], color=TEAL, label='data / pc_err', label_pos=(1176, 1030))
arrow([(485, 993), (355, 993)], color=TEAL, label='R', label_pos=(407, 956))
arrow([(355, 1070), (485, 1070)], color=ORANGE, label='rready', label_pos=(378, 1081))
arrow([(640, 450), (640, 875)], label='分配并预留', label_pos=(504, 661))
arrow([(755, 875), (755, 450)], color=ORANGE, label='完成 / 退休', label_pos=(500, 724))
arrow([(1840, 540), (1840, 425)], color=ORANGE, label='成功前馈', label_pos=(1870, 465))
arrow([(2020, 970), (2060, 970), (2060, 180), (1825, 180), (1825, 205)],
      color=ORANGE, label='rd_mem_status', label_pos=(1850, 147))

d.rounded_rectangle((45, 1174, 2020, 1251), radius=10, fill='#fff2d8')
d.text((67, 1195), '关键约束：5A 失败保留后续预选；6B 成功前馈到本拍窗口；10B 退休与准入前馈，但逐来源保留额度。',
       font=font(25, True), fill=ORANGE)
im.save(OUT/'architecture.png')

# Render the controlled Markdown subset used by the design document.
source = (OUT/'cmdbuf_rd_design.md').read_text(encoding='utf-8')


def inline(s):
    tokens = []
    def token(value):
        tokens.append(value)
        return f'\x00{len(tokens)-1}\x00'
    s = re.sub(r'`([^`]+)`', lambda m: token('<code>' + html.escape(m.group(1)) + '</code>'), s)
    s = re.sub(r'!\[([^\]]*)\]\(([^)]+)\)', lambda m: token('<a href="' + html.escape(m.group(2), quote=True) + '"><img src="' + html.escape(m.group(2), quote=True) + '" alt="' + html.escape(m.group(1), quote=True) + '"></a>'), s)
    s = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', lambda m: token('<a href="' + html.escape(m.group(2), quote=True) + '">' + html.escape(m.group(1)) + '</a>'), s)
    s = html.escape(s)
    s = re.sub(r'\*\*([^*]+)\*\*', r'<strong>\1</strong>', s)
    return re.sub(r'\x00(\d+)\x00', lambda m: tokens[int(m.group(1))], s)


lines = source.splitlines()
parts = []
toc = []
i = 0
section_count = 0
while i < len(lines):
    line = lines[i]
    if not line.strip():
        i += 1
        continue
    if line.startswith('```'):
        code = []
        i += 1
        while i < len(lines) and not lines[i].startswith('```'):
            code.append(lines[i]); i += 1
        assert i < len(lines), 'Unterminated code block'
        parts.append('<pre><code>' + html.escape('\n'.join(code)) + '</code></pre>')
        i += 1
        continue
    heading = re.match(r'^(#{1,6}) (.+)$', line)
    if heading:
        level, text = len(heading.group(1)), heading.group(2)
        if level == 1:
            i += 1
            continue
        if level == 2:
            section_count += 1
            anchor = f'section-{section_count}'
            toc.append((anchor, text))
            parts.append(f'<h2 id="{anchor}">{inline(text)}</h2>')
        else:
            parts.append(f'<h{level}>{inline(text)}</h{level}>')
        i += 1
        continue
    if line.startswith('|'):
        rows = []
        while i < len(lines) and lines[i].startswith('|'):
            cells = [v.strip() for v in lines[i].strip().strip('|').split('|')]
            if not all(re.fullmatch(r':?-+:?', v) for v in cells):
                rows.append(cells)
            i += 1
        assert all(len(r) == len(rows[0]) for r in rows), 'Unequal table columns'
        out = '<div class="table"><table><thead><tr>' + ''.join('<th>'+inline(v)+'</th>' for v in rows[0]) + '</tr></thead><tbody>'
        out += ''.join('<tr>' + ''.join('<td>'+inline(v)+'</td>' for v in row) + '</tr>' for row in rows[1:])
        parts.append(out + '</tbody></table></div>')
        continue
    if line.startswith('- '):
        items = []
        while i < len(lines) and lines[i].startswith('- '):
            items.append('<li>' + inline(lines[i][2:]) + '</li>'); i += 1
        parts.append('<ul>' + ''.join(items) + '</ul>')
        continue
    para = [line]
    i += 1
    while i < len(lines) and lines[i].strip() and not re.match(r'^(#{1,6} |```|\||- )', lines[i]):
        para.append(lines[i]); i += 1
    parts.append('<p>' + inline(' '.join(para)) + '</p>')

nav = ''.join(f'<a href="#{anchor}">{html.escape(title)}</a>' for anchor, title in toc)
doc = '''<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>cmdbuf_rd 详细 RTL 设计方案</title><style>
*{box-sizing:border-box}body{margin:0;background:#eef3f8;color:#173550;font:16px/1.85 "Microsoft YaHei",sans-serif}header{background:#173550;color:white;padding:28px 36px}h1{font-size:30px;margin:0}header a{color:#cae8ff}header p{margin:9px 0}.layout{display:grid;grid-template-columns:270px minmax(0,1fr);max-width:1640px;margin:auto}nav{position:sticky;top:0;align-self:start;max-height:100vh;overflow:auto;padding:22px 16px}nav a{display:block;font-size:14px;padding:5px 8px;text-decoration:none;border-radius:5px}nav a:hover{background:#dce8f4}main{background:white;padding:22px 38px 48px;min-width:0}h2{font-size:25px;border-bottom:2px solid #dce8f4;padding-bottom:8px;margin-top:42px;scroll-margin-top:20px}h3{font-size:20px;margin-top:27px}a{color:#176caf}p{margin:15px 0}code{font-family:Consolas,monospace;background:#edf3f7;padding:1px 4px;border-radius:3px}pre{background:#173550;color:#e4f4ff;padding:20px;border-radius:8px;overflow:auto;font:14px/1.65 Consolas,monospace}pre code{background:none;padding:0}table{border-collapse:collapse;width:100%;font-size:15px}th,td{border:1px solid #cedbe7;padding:10px 12px;vertical-align:top;text-align:left}th{background:#e8f0f7}.table{overflow:auto;margin:20px 0}img{max-width:100%;height:auto;border:1px solid #dce8f4;border-radius:10px}li{margin:8px 0}footer{padding:25px 36px;color:#506c82}@media(max-width:950px){.layout{display:block}nav{position:static;max-height:260px;padding:12px 20px}main{padding:18px 20px}h1{font-size:25px}}@media print{nav,header a{display:none}.layout{display:block}body{background:white}main{padding:0}pre{white-space:pre-wrap}h2,h3{break-after:avoid}tr,img{break-inside:avoid}}
</style></head><body><header><h1>cmdbuf_rd 详细 RTL 设计方案</h1><p>2026-10-10 · 九项配对存储 · 五项窗口 · 5A / 6B / 10B · 每来源容量保留</p><a href="cmdbuf_rd_design.md">Markdown 源文档</a>　<a href="../cmdbuf_rd_timing/index.html">十三个时序场景</a>　<a href="../cmdbuf_rd_fault_catalog/index.html">注错清单</a></header><div class="layout"><nav>'''+nav+'</nav><main>'+''.join(parts)+'''</main></div><footer>设计文档及规格示意；尚未交付可综合 RTL 或完整 RTL 验证结果。</footer></body></html>'''
(OUT/'index.html').write_text(doc, encoding='utf-8')
print(json.dumps(dict(sections=section_count, characters=len(source), files=['cmdbuf_rd_design.md', 'index.html', 'architecture.png']), ensure_ascii=False))
