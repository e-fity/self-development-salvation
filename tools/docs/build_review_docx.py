# -*- coding: utf-8 -*-
"""生成《游戏需求文档 v0.1 评审与扩展建议》DOCX"""
import os
from docx import Document
from docx.shared import Pt, Cm, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

FONT_CN = "微软雅黑"
FONT_EN = "Segoe UI"
MONO = "Consolas"
BODY_PT = 10.5
DARK = RGBColor(0x1A, 0x1A, 0x1A)
ACCENT = RGBColor(0x1F, 0x3A, 0x5F)
GRAY = RGBColor(0x59, 0x59, 0x59)
CODE_FILL = "F2F4F7"

doc = Document()

# ---------- 页面 ----------
sec = doc.sections[0]
sec.page_width = Cm(21.0)
sec.page_height = Cm(29.7)
sec.left_margin = Cm(2.4)
sec.right_margin = Cm(2.4)
sec.top_margin = Cm(2.2)
sec.bottom_margin = Cm(2.2)
TEXT_W = 16.2

# ---------- 默认样式 ----------
normal = doc.styles["Normal"]
normal.font.name = FONT_EN
normal.font.size = Pt(BODY_PT)
normal.font.color.rgb = DARK
normal.element.rPr.rFonts.set(qn("w:eastAsia"), FONT_CN)
normal.paragraph_format.space_after = Pt(4)
normal.paragraph_format.line_spacing = 1.35


def set_cn(run, size=None, bold=None, color=None, cn=FONT_CN):
    run.font.name = FONT_EN
    run.font.element.rPr.rFonts.set(qn("w:eastAsia"), cn)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if color is not None:
        run.font.color.rgb = color


def rich(p, chunks, size=BODY_PT, color=DARK):
    """chunks: list of (text, bold)"""
    for text, bold in chunks:
        r = p.add_run(text)
        set_cn(r, size, bold, color)


def para(text=None, size=BODY_PT, bold=False, color=DARK, align=None,
         space_before=0, space_after=4, indent=None, keep=False):
    p = doc.add_paragraph()
    if text:
        r = p.add_run(text)
        set_cn(r, size, bold, color)
    if align is not None:
        p.alignment = align
    pf = p.paragraph_format
    pf.space_before = Pt(space_before)
    pf.space_after = Pt(space_after)
    if indent is not None:
        pf.left_indent = Cm(indent)
    if keep:
        pf.keep_with_next = True
    return p


def heading(text, level=1):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.keep_with_next = True
    pf.keep_together = True
    if level == 1:
        pf.space_before = Pt(18)
        pf.space_after = Pt(8)
        r = p.add_run(text)
        set_cn(r, 15, True, ACCENT)
        pPr = p._p.get_or_add_pPr()
        pbdr = OxmlElement("w:pBdr")
        bottom = OxmlElement("w:bottom")
        bottom.set(qn("w:val"), "single")
        bottom.set(qn("w:sz"), "6")
        bottom.set(qn("w:space"), "4")
        bottom.set(qn("w:color"), "B4C2D6")
        pbdr.append(bottom)
        pPr.append(pbdr)
    elif level == 2:
        pf.space_before = Pt(12)
        pf.space_after = Pt(4)
        r = p.add_run(text)
        set_cn(r, 12, True, ACCENT)
    else:
        pf.space_before = Pt(8)
        pf.space_after = Pt(3)
        r = p.add_run(text)
        set_cn(r, 11, True, DARK)
    return p


def bullet(text= None, chunks=None, size=BODY_PT, level=0):
    p = doc.add_paragraph(style="List Bullet")
    pf = p.paragraph_format
    pf.left_indent = Cm(0.75 + 0.6 * level)
    pf.space_after = Pt(3)
    pf.line_spacing = 1.3
    if chunks:
        rich(p, chunks, size)
    else:
        r = p.add_run(text)
        set_cn(r, size)
    return p


def shade_cell(cell, hexcolor):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hexcolor)
    tcPr.append(shd)


def row_cant_split(row):
    trPr = row._tr.get_or_add_trPr()
    el = OxmlElement("w:cantSplit")
    el.set(qn("w:val"), "true")
    # cantSplit 必须排在 trHeight/tblHeader 之前
    first = None
    for child in trPr:
        if child.tag in (qn("w:trHeight"), qn("w:tblHeader"), qn("w:tblCellSpacing")):
            first = child
            break
    if first is not None:
        first.addprevious(el)
    else:
        trPr.append(el)


def keep_row_with_next(row):
    for cell in row.cells:
        for p in cell.paragraphs:
            p.paragraph_format.keep_with_next = True
            p.paragraph_format.keep_together = True


def set_col_widths(table, widths_cm):
    for row in table.rows:
        for i, w in enumerate(widths_cm):
            row.cells[i].width = Cm(w)


def table(headers, rows, widths, font_size=9.5, header_fill="1F3A5F", zebra=True):
    assert abs(sum(widths) - TEXT_W) < 0.6, f"widths sum {sum(widths)}"
    t = doc.add_table(rows=1, cols=len(headers))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    hdr = t.rows[0]
    for i, h in enumerate(headers):
        c = hdr.cells[i]
        c.text = ""
        p = c.paragraphs[0]
        p.paragraph_format.space_after = Pt(2)
        p.paragraph_format.space_before = Pt(2)
        r = p.add_run(h)
        set_cn(r, font_size, True, RGBColor(0xFF, 0xFF, 0xFF))
        shade_cell(c, header_fill)
    row_cant_split(hdr)
    trPr = hdr._tr.get_or_add_trPr()
    th = OxmlElement("w:tblHeader")
    th.set(qn("w:val"), "true")
    trPr.append(th)
    for ri, row in enumerate(rows):
        cells = t.add_row().cells
        for i, val in enumerate(row):
            cells[i].text = ""
            p = cells[i].paragraphs[0]
            p.paragraph_format.space_after = Pt(2)
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.line_spacing = 1.2
            r = p.add_run(str(val))
            set_cn(r, font_size, False, DARK)
            if zebra and ri % 2 == 1:
                shade_cell(cells[i], "F4F6F9")
    for row in t.rows:
        row_cant_split(row)
    # 只把表头与前两行绑在一起，避免表头孤零零留在页底；
    # 其余行允许跨页（行本身不会断开），比整表硬挤到下一页更省版面
    for row in list(t.rows)[:2]:
        keep_row_with_next(row)
    set_col_widths(t, widths)
    sp = doc.add_paragraph()
    sp.paragraph_format.space_after = Pt(2)
    sp.paragraph_format.line_spacing = 1.0
    return t


def callout(label, text, fill="FFF4E5", border="E0A458"):
    t = doc.add_table(rows=1, cols=1)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    c = t.rows[0].cells[0]
    shade_cell(c, fill)
    c.text = ""
    p = c.paragraphs[0]
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.line_spacing = 1.3
    r1 = p.add_run(label + "  ")
    set_cn(r1, 9.5, True, RGBColor(0x8A, 0x4B, 0x00))
    r2 = p.add_run(text)
    set_cn(r2, 9.5, False, DARK)
    tcPr = c._tc.get_or_add_tcPr()
    borders = OxmlElement("w:tcBorders")
    for edge in ("top", "left", "bottom", "right"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), "8")
        el.set(qn("w:color"), border)
        borders.append(el)
    tcPr.append(borders)
    c.width = Cm(TEXT_W)
    sp = doc.add_paragraph()
    sp.paragraph_format.space_after = Pt(2)
    sp.paragraph_format.line_spacing = 1.0


def code_block(lines):
    t = doc.add_table(rows=1, cols=1)
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    c = t.rows[0].cells[0]
    shade_cell(c, CODE_FILL)
    c.text = ""
    first = True
    for line in lines:
        p = c.paragraphs[0] if first else c.add_paragraph()
        first = False
        pf = p.paragraph_format
        pf.space_before = Pt(0)
        pf.space_after = Pt(0)
        pf.line_spacing = 1.0
        pf.left_indent = Cm(0.15)
        r = p.add_run(line if line else " ")
        r.font.name = MONO
        r.font.element.rPr.rFonts.set(qn("w:eastAsia"), MONO)
        r.font.element.rPr.rFonts.set(qn("w:ascii"), MONO)
        r.font.element.rPr.rFonts.set(qn("w:hAnsi"), MONO)
        r.font.size = Pt(8)
        r.font.color.rgb = RGBColor(0x24, 0x29, 0x2F)
    # 内边距
    tcPr = c._tc.get_or_add_tcPr()
    mar = OxmlElement("w:tcMar")
    for edge, v in (("top", "80"), ("bottom", "80"), ("left", "120"), ("right", "80")):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:w"), v)
        el.set(qn("w:type"), "dxa")
        mar.append(el)
    tcPr.append(mar)
    c.width = Cm(TEXT_W)
    sp = doc.add_paragraph()
    sp.paragraph_format.space_after = Pt(2)
    sp.paragraph_format.line_spacing = 1.0


# =========================================================
# 封面
# =========================================================
for _ in range(3):
    doc.add_paragraph()

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.paragraph_format.space_after = Pt(6)
r = p.add_run("《自我开发——拯救》")
set_cn(r, 24, True, ACCENT)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.paragraph_format.space_after = Pt(2)
r = p.add_run("游戏需求文档 v0.1 · 评审与扩展建议")
set_cn(r, 16, True, DARK)

p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.paragraph_format.space_after = Pt(30)
r = p.add_run("Self-Development: Salvation — PRD Review")
set_cn(r, 11, False, GRAY)

for line in [
    "评审对象：“D:\\lc\\ainiang\\游戏需求文档.docx”（v0.1 · 竖切片版，2026-11-04）",
    "评审日期：2026-11-04",
    "结论：框架可用，但「规则 / 数值 / 验收」三层尚未闭环，P0 项不补会直接返工。",
]:
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(6)
    r = p.add_run(line)
    set_cn(r, 9.5, False, GRAY)

doc.add_page_break()

# =========================================================
# 0. 一句话结论
# =========================================================
heading("0. 一句话结论", 1)
para("v0.1 把「做什么」写清楚了：一个角色、一关、三种小怪、一个 Boss、一套爽快感关键词。"
     "问题在于「做到什么程度算对」——伤害公式、帧数、AI 参数、评价规则、资源尺寸、验收指标，这些全部缺席。"
     "现在的文档更像一份立项说明，而不是一个人能照着做的施工图。", space_after=8)

p = para(space_after=10)
rich(p, [
    ("文档里最要命的不是缺内容，而是", False),
    ("内容之间对不上", True),
    ("：15 分钟的单局时长，装不下 990 点总血量；M1 验收要「Boss 三阶段」，但 Boss 章节只列了 4 个招式；"
     "M3 才做「结算评价」，M1 验收里却已经有「通关能结算」。这类矛盾会让人在开发第三周才发现方向错了。", False),
])

heading("本评审的三类问题", 2)
table(
    ["级别", "含义", "数量", "处理建议"],
    [
        ["P0 阻断", "不补就会返工、或根本做不完的问题（自相矛盾 / 数值算不通 / 核心规则没定义）", "8 条", "动工前必须解决"],
        ["P1 缺失", "会显著影响手感、工期和成本，但没有它会先「能跑」的模块", "9 类", "M1 期间补"],
        ["P2 完善", "上线前需要、现在可以只留位置的内容", "7 类", "M2 / M3 再补"],
    ],
    widths=[2.2, 9.0, 1.6, 3.4],
)

callout("建议先看", "如果只有十分钟，请直接看 1.1（时长与内容量的缺口）、1.2（帧数与手感）、"
        "1.3（数值公式缺失）、1.4（Boss 三阶段没写），这四条决定了 M1 能不能立住。")

# =========================================================
# 1. P0
# =========================================================
heading("1. P0 阻断项：动工前必须补", 1)

heading("1.1 单局 15 分钟，但内容量只够 3–5 分钟", 2)
para("这是全文最大的结构性矛盾。第 3 节写「单局 10-15 分钟」，第 15 节验收写「从启动到通关不超过 15 分钟」，"
     "但第 6 节的关卡只有 3 波小怪（3 + 3 + 3 = 9 只小怪，再加 1 个 Boss）。把所有血量加起来：", space_after=4)
table(
    ["敌人", "数量", "单体 HP", "小计", "出现位置"],
    [
        ["近战小怪", "7", "40", "280", "三波均有"],
        ["远程小怪", "1", "30", "30", "第二波"],
        ["盾兵", "1", "80", "80", "第三波"],
        ["Boss「夜巡」", "1", "600", "600", "Boss 战"],
        ["合计", "10", "—", "990", "—"],
    ],
    widths=[3.6, 2.4, 2.8, 2.8, 4.6],
)
para("按 ATK 12、三连平均每秒约 12 点伤害估算，990 点血纯输出约 82 秒；"
     "算上走位、闪避、拾取、波次间隔和 Boss 演出，实际战斗时长约 3–4 分钟。"
     "要撑到 15 分钟，中间还差 10 分钟以上的内容——而文档里没有任何一处说明这 10 分钟由什么填充。", space_after=6)
para("两条路，选一条并写进文档：", bold=True, space_before=4)
bullet("A｜把目标改成「5 分钟竖切片」：保留现有敌人量，把 15 分钟改成「3–5 分钟可通关」。"
       "竖切片的本来含义就是「最短路径展示全部核心体验」，5 分钟完全够用，也更容易在两周内做完。")
bullet("B｜保留 15 分钟，但补足内容：至少 6–8 波敌人（每波 4–6 只）、3 个战斗区域（中间用平台跳跃或可破坏物过渡）、"
       "2 个中 Boss、1 段剧情过场。工作量至少翻 3 倍，两周的 M1 不再成立。")
callout("待拍板", "15 分钟是「目标体验时长」还是「M1 验收硬指标」？建议先把 M1 定为 A（3–5 分钟），"
        "把 15 分钟挪到 M2 的正式关，避免用两周去追一个不属于竖切片的目标。")

heading("1.2 帧数、帧率与手感互相打架", 2)
para("第 5 节写「12fps 帧动画、每组 4–8 帧」，第 4 节写「命中停顿 40–80ms」「空中可追打最多 2 段」「闪避无敌帧」。"
     "这三组数字放在一起，会让「脆但快」的定位做不出来：", space_after=4)
bullet("12fps 意味着每帧 83ms。一组 6 帧的普攻 = 0.5 秒，三连全打完 = 1.5 秒，"
       "再叠加 3 次 40–80ms 的命中停顿，实际收招接近 1.8 秒。横版动作游戏的三连通常控制在 0.6–0.9 秒，1.8 秒会显得拖沓。")
bullet("「空中追打 2 段」需要空中攻击动作，但第 5 节列出的动作表里没有「跳攻」和「落地」——现在的动作清单只够地面战。")
bullet("「闪避无敌帧」是动作游戏的生命线，但全文没写无敌帧持续多久、闪避距离多少、能否取消攻击后摇。"
       "冷却 1.2 秒、无敌帧 0.3 秒的话，无敌覆盖率 25%，配合「橙闪」穿人，玩家几乎可以不掉血——难度会直接失效。")
para("建议补一张「帧数据表」，这是横版动作游戏真正的施工图。模板：", bold=True, space_before=6)
table(
    ["动作", "总帧", "起/判/收", "可取消点", "倍率", "说明"],
    [
        ["普攻 1", "6", "1–2 / 3 / 4–6", "第 4 帧起可接普攻 2", "1.0", "—"],
        ["普攻 2", "6", "1–2 / 3 / 4–6", "第 4 帧起可接普攻 3", "1.0", "—"],
        ["普攻 3", "8", "1–3 / 4–5 / 6–8", "第 6 帧起可接闪避", "1.5", "命中击飞"],
        ["橙闪", "8", "1–2 / 3–5 / 6–8", "第 6 帧起可接普攻", "1.5", "位移 220px，3–5 帧无敌"],
        ["逆鳞", "10", "1–3 / 4 / 5–10", "第 8 帧起可接闪避", "1.2", "半径 120px，2 秒霸体"],
        ["闪避", "5", "1 / 1–3 / 4–5", "—（第 1–3 帧无敌）", "0", "位移 160px"],
    ],
    widths=[2.2, 1.4, 3.6, 4.4, 1.4, 3.2],
    font_size=8.5,
)
para("配套还要定：帧率改成 12 还是 15/18 fps（15fps 每帧 66ms，和三连节奏更搭）；"
     "是否引入「输入缓冲」（硬直结束前 0.15 秒内按下的指令自动生效）——这是「按着顺」和「按不出来」的分界线，动作游戏不能省。",
     space_after=4)

heading("1.3 伤害公式与数值链条缺失", 2)
para("第 4 节给了 HP/ATK/DEF/暴击率，第 7 节给了敌人 HP，但中间没有公式。以下每个问题现在都无解：", space_after=4)
bullet("DEF 是「固定减伤」还是「百分比减伤」？DEF 3 对 12 点伤害是减到 9 还是减 3%？这决定后期成长曲线。")
bullet("普攻三连每一段的倍率分别是多少？如果都是 1.0，三连 = 36 点，刚好打不死 40 血的近战小怪（差 4 点）；"
       "如果三段是 1.0/1.0/1.5，总计 42 点才能刚好击杀。这个「刚好」是设计还是巧合？文档没说。")
bullet("「橙闪」的 1.5 倍是「总伤害 18」还是「每段 1.5 倍」？「逆鳞」的伤害数字全文没有出现过。")
bullet("「零点」按连击数加成，加成公式是什么？每 1 连击 +1% 还是 +2%？封顶多少？")
bullet("暴击 5% 的倍率是多少（1.5 倍还是 2 倍）？暴击是否影响命中停顿和震屏强度？")
bullet("敌人没有任何 ATK 数据——玩家 100 血、DEF 3，小怪一刀打多少？如果打 10 点，玩家能挨 10 刀，"
       "在 3 只小怪围攻下几乎不会死；如果打 30 点，4 刀就死，又太脆。难度完全取决于一个没写的数字。")
para("建议在文档里固定一条主公式，例如：", bold=True, space_before=6)
p = para(indent=0.8, space_after=6)
rich(p, [("最终伤害 = max(1, 攻击力 × 技能倍率 × 暴击倍率 − 防御) × 连击加成 × 评价加成", True)], size=10.5)
para("并把每个技能、每种敌人、Boss 每个招式的「攻击力 / 倍率 / 是否可闪避 / 命中硬直」填进表里。", space_after=4)

heading("1.4 Boss「三阶段」在正文里不存在", 2)
para("第 15 节验收标准写「Boss 有三个阶段」，但第 7 节 Boss 只有一行：「三连斩、跳劈、召唤小怪、狂暴」，"
     "既没写阶段如何切换，也没写每阶段新增什么招式。这会导致验收时无法判断「做没做到」。需要补：", space_after=4)
table(
    ["阶段", "触发条件", "可用招式", "行为变化", "玩家应对"],
    [
        ["P1", "100%–66% HP", "三连斩、跳劈", "直线压制，攻击间隔 2.0s", "绕背、闪避后反击"],
        ["P2", "66%–33% HP", "+ 召唤小怪（最多 2 只）", "间隔 1.6s，召唤后短暂硬直", "先清小怪或强杀"],
        ["P3", "33%–0% HP", "+ 狂暴（攻速 ×1.3、范围 +20%）", "间隔 1.1s，招式带前摇红光", "留大招与霸体硬吃"],
    ],
    widths=[1.2, 2.8, 4.8, 4.2, 3.2],
    font_size=8.5,
)
para("还要补 Boss 的「预警」规则：每招起手多少秒开始亮红光 / 音效提示？跳劈的落点是否提前显示？"
     "召唤的小怪计入掉落和评价吗？狂暴阶段能不能被打断？——这些是 Boss 战「公平感」的全部来源。", space_after=4)

heading("1.5 评价 S/A/B 没有判定标准", 2)
para("第 6 节和第 9 节都出现了「评价（S/A/B）」，但全文没有一处说明按什么算。"
     "评价系统是重复游玩的驱动力，也是存档里要记录的字段（「最高评价」），必须先定规则。建议：", space_after=4)
table(
    ["维度", "权重", "S", "A", "B"],
    [
        ["通关时间", "40%", "≤ 4 分钟", "≤ 6 分钟", "> 6 分钟"],
        ["受伤次数", "35%", "0 次", "≤ 3 次", "> 3 次"],
        ["最高连击", "25%", "≥ 30", "≥ 15", "< 15"],
    ],
    widths=[3.4, 2.2, 3.6, 3.6, 3.4],
)
para("三档打分后取加权总分，≥ 90 为 S、≥ 70 为 A，其余 B。数值可以再调，但「维度 + 阈值」这个结构必须先写进文档。",
     space_after=4)

heading("1.6 存档没有版本、没有原子写入", 2)
para("第 12 节只写「存档：user://save.json」。本地 JSON 存档最容易出的事故是：写到一半崩溃 → 文件损坏 → 进度全丢。"
     "至少要补三条：", space_after=4)
bullet("存档结构带 version 字段，并预留 migration 逻辑（哪怕现在只有 1 个版本）。")
bullet("原子写入：先写 save.tmp，写完 fsync 再 rename 覆盖 save.json。")
bullet("定义自动存档时机：过波次、进 Boss 战前、结算后、退出游戏时。并明确「死亡重开」是否回滚到检查点。")
para("顺带：第 3 节说「死亡从最近的检查点重来」，但第 6 节的关卡流程里没有任何检查点位置。"
     "如果整关只有一个出生点，Boss 战死一次就要重打 3 波小怪——这在 15 分钟的关卡里是劝退设计。"
     "建议在 Boss 前设一个检查点。", space_after=4)

heading("1.7 盾兵机制没有数值", 2)
para("「正面减伤，绕后破防」是很好的设计点，但缺三个关键数字：正面减伤多少（50%？80%？）、"
     "「侧面 / 背面」的判定角度（±60° 还是 ±90°）、破防后持续多久、有没有破防硬直。"
     "另外要明确「哪些攻击可以直接破防」——大招「零点」是否无视盾牌？「逆鳞」的击退能否把盾兵推开？"
     "否则玩家会陷入「打不动 → 不知道该怎么打 → 放弃」的死循环。", space_after=4)

heading("1.8 里程碑与验收标准互相矛盾", 2)
table(
    ["冲突点", "文中位置", "问题"],
    [
        ["手柄支持", "技术方案写「支持键盘 + 手柄」；M3 才做「手柄」", "M1 到底做不做手柄？验收按哪个算？"],
        ["结算评价", "M1 验收要求「通关能结算」；M3 才做「结算评价」", "M1 的结算页长什么样？只有金币没有评价算不算过？"],
        ["Boss 三阶段", "M1 验收要求三阶段；Boss 章节只有 4 个招式", "M1 只做 2 个招式能不能验收通过？"],
        ["第二关", "M2 要加「第二关」，但全文没有第二关的任何需求", "第二关的场景、敌人、Boss 从哪来？"],
    ],
    widths=[3.0, 8.2, 5.0],
    font_size=9,
)
para("建议把 M1 的验收标准逐条改成「可观测、可判定」的句子，例如把「三连击、两个技能、闪避、大招都能用」"
     "改成「8 个输入动作在 100ms 内响应，三连可稳定接出，闪避无敌帧可躲开远程弹道」。", space_after=4)

# =========================================================
# 2. P1
# =========================================================
heading("2. P1 缺失模块：M1 期间必须补", 1)

heading("2.1 战斗系统还缺的规则", 2)
table(
    ["缺失项", "为什么必须有", "建议写法"],
    [
        ["连击数的实际作用", "现在只定义「3 秒内不断」，没说它影响什么。若只做显示就是装饰", "连击数 → 伤害加成（每 10 连 +3%，封顶 +30%）+ 大招倍率 + 评价维度"],
        ["受击规则", "玩家被击中后的硬直、无敌时间、是否打断连招，全未定义", "受击硬直 0.25s，之后 0.5s 无敌闪烁，连招中断"],
        ["霸体的定义", "「逆鳞」给 2 秒霸体，但霸体是「不被打断」还是「不减伤」？", "霸体 = 不受硬直 / 击退，仍受伤害；与无敌帧区分"],
        ["能量获取", "只写「命中回复 6」，是否受击掉能量？击杀是否额外回？", "命中 +6、击杀 +15、受击 −10，上限 100"],
        ["空中战斗", "「空中可追打 2 段」需要跳攻、落地动作与重力参数", "跳攻 1 段 + 空中追击 2 段，落地 0.15s 硬直"],
        ["击退与碰撞", "击退距离、是否撞墙反弹、敌人之间会不会互相推挤", "击退 60–120px，撞墙额外 0.2s 硬直"],
        ["敌我受击优先级", "同时命中多个敌人时判定顺序、无敌帧是否对多段攻击生效", "单次攻击对同一目标只结算一次"],
    ],
    widths=[3.2, 6.2, 6.8],
    font_size=8.5,
)

heading("2.2 敌人 AI 只有状态名，没有参数", 2)
para("「待机、追击、攻击、受击、死亡」是五个状态名，不是行为规格。同屏 3 只近战小怪时，"
     "它们会同时冲上来把玩家围死，还是排队进攻？这决定难度。每类敌人至少需要一张参数表：", space_after=4)
table(
    ["参数", "近战小怪", "远程小怪", "盾兵"],
    [
        ["视野 / 索敌距离", "300px", "420px", "320px"],
        ["移动速度", "90 px/s", "70 px/s", "60 px/s"],
        ["攻击距离", "60px", "350px", "70px"],
        ["攻击前摇", "0.4s", "0.6s", "0.5s"],
        ["攻击间隔", "1.8s", "2.4s", "2.0s"],
        ["攻击力", "8", "6", "12"],
        ["同屏进攻上限", "2 只", "1 只", "1 只"],
        ["正面减伤", "—", "—", "60%"],
        ["背面伤害倍率", "—", "—", "1.5×"],
        ["破防持续时间", "—", "—", "3s"],
    ],
    widths=[4.2, 4.0, 4.0, 4.0],
    font_size=9,
)
para("「同屏进攻上限」是最容易被忽略、又最影响体验的一条：没有它，9 只怪一起上就是不可能通关的关卡。",
     space_after=4)

heading("2.3 关卡结构：横向推进还是单屏竞技场？", 2)
para("第 1 节说「左右推进」，第 6 节却说「Boss：天台中央」，听起来又像单屏竞技场。这两种做法的关卡架构完全不同：", space_after=4)
bullet("横向推进：关卡是一条长 3000–5000px 的横轴，摄像机跟随，波次在固定 x 坐标触发，需要「清怪后开门」的推进逻辑。")
bullet("单屏竞技场：一个 1920px 宽的固定场景，波次按时间 / 击杀数刷新，不需要摄像机移动。")
para("另外缺：天台的可站立区域有多宽？有没有平台（高低差）？「掉下去扣血并复位」的复位点在哪？"
     "可破坏物放在哪、破坏后掉几个金币？「三层视差」每层的滚动系数是多少（建议 0.2 / 0.5 / 1.0）？", space_after=4)

heading("2.4 美术规格全是数量，没有尺寸和管线", 2)
table(
    ["缺失项", "为什么卡工期", "建议"],
    [
        ["角色在画面中的高度", "决定所有帧的绘制尺寸，改一次就要重画全部", "定 180px（1080p 下约占屏高 1/6）"],
        ["立绘来源与拆层", "D:\\蓝橙 里是成图，不是分层 PSD；骨骼动画需要拆层", "先用成图做「整体缩放 + 位移」的简易动画，验证手感后再拆层"],
        ["帧动画 vs 骨骼", "第 10 节写「先帧动画，后接 Live2D / 骨骼」，但这两套流程的资产不能复用", "M1 只选一套，建议先用骨骼（Skeleton2D）省帧数"],
        ["敌人 / Boss 尺寸", "影响碰撞盒与招式范围", "小怪 120px、盾兵 150px、Boss 260px"],
        ["场景单屏宽度与分层", "决定视差素材要画多宽", "三层各 3840px 宽（2 屏），可循环"],
        ["UI 分辨率与缩放", "1080p 基准，但没写 720p / 1440p 怎么办", "UI 用 CanvasLayer + 锚点自适应"],
    ],
    widths=[3.4, 6.4, 6.4],
    font_size=8.5,
)
para("还有一个可以直接核对的点：第 5 节说「共 13 组动作」，但列出来的只有 12 项"
     "（站立、跑、跳、普攻 1/2/3、受击、闪避、技能 1、技能 2、大招、死亡、胜利）。"
     "要么补一项（跳攻或落地），要么把 13 改成 12。这种小数字对不上，到排期时会变成「到底谁记错了」。", space_after=4)

heading("2.5 音效清单没有内容，只有数量", 2)
para("「战斗音效 12 个」不够指导制作。12 个位置很容易被占满：", space_after=4)
para("普攻 1 / 普攻 2 / 普攻 3 / 橙闪 / 逆鳞 / 零点 / 闪避 / 玩家受击 / 玩家死亡 / 小怪死亡 / Boss 怒吼 / Boss 攻击 —— 正好 12 个，"
     "但还缺：刀剑碰撞、暴击、金币拾取、可破坏物破碎、雨声环境、Boss 战 BGM 切换。", space_after=4)
para("建议扩到 20 个并逐个列名；BGM 从「1 首循环」扩到 3 首（关卡 / Boss / 结算），"
     "至少要有「Boss 战开始时切换」的规则。15 分钟的关卡只用一首循环曲，听 3 分钟就会烦。", space_after=4)

heading("2.6 叙事几乎为零", 2)
para("标题《自我开发——拯救》和主角「蓝橙」显然来自「蓝橙计划」的人设。但游戏里：", space_after=4)
bullet("她在拯救什么？谁在拯救她？「自我开发」和「拯救」是什么关系？")
bullet("为什么是雨夜天台？这个场景在故事里意味着什么？")
bullet("Boss「夜巡」是谁？为什么打它？")
para("这些不需要长篇剧本，但至少要有：开场 3 行独白、Boss 战前的 1 句台词、结算页的 1 段收尾文案。"
     "没有这些，游戏就只是「一个能打的 demo」，而不是「蓝橙的故事」。顺带，UI 文案要集中到一个 strings 文件里，"
     "方便以后做多语言和改口吻。", space_after=4)

heading("2.7 UI 缺了「第一眼」和「最后一公里」", 2)
para("第 9 节列了战斗中 HUD 和暂停 / 结算，但缺：", space_after=4)
bullet("主菜单 / 标题画面：开始、继续、设置、退出。现在游戏启动后直接进关卡吗？")
bullet("首次进入的教学提示：8 个按键，玩家不可能全记住，需要「按 J 攻击」之类的浮层。")
bullet("设置项：音量（BGM / SFX 分离）、震屏强度、分辨率 / 全屏、按键重映射、语言。「暂停菜单里有设置」但没写设置里有什么。")
bullet("伤害数字的样式与开关（有些玩家不喜欢满屏数字）。")
bullet("敌人血条：Boss 有，小怪没有——至少精英怪 / 盾兵应该有。")
bullet("读档 / 继续游戏的入口。")
callout("无障碍", "震屏、闪白、满屏特效是这类游戏的「爽点」，也是晕动症和光敏玩家的「雷点」。"
        "建议在设置里加「减少震屏」「关闭闪白」「降低特效密度」三个开关，成本很低。")

heading("2.8 技术方案缺「怎么落地」", 2)
table(
    ["缺失项", "建议补充"],
    [
        ["节点结构", "Player（CharacterBody2D）→ 状态机 → 动画 / 命中盒（Area2D）；Enemy 同构；AttackHitbox 独立场景"],
        ["碰撞层", "1 玩家、2 敌人、3 玩家攻击、4 敌人攻击、5 可破坏物、6 边界 —— 写进文档，避免后期乱"],
        ["状态机方案", "用 AnimationTree + StateMachine 还是手写 enum？建议 M1 手写 enum，简单可控"],
        ["JSON schema", "给出 characters.json / enemies.json / levels.json 的字段样例（见第 4 节模板）"],
        ["热重载", "改 JSON 后要不要重启？建议加 F5 重载当前关卡，调试效率差 5 倍"],
        ["输入缓冲", "0.15s 输入缓冲 + 手柄死区 0.25，写进技术方案"],
        ["性能预算", "16.6ms/帧：逻辑 4ms、渲染 8ms、物理 2ms；压力场景「6 敌人 + 30 特效粒子」"],
        ["导出", "Windows 导出模板、版本号规则、安装包（可选 Steam）"],
    ],
    widths=[3.4, 12.8],
    font_size=8.5,
)

heading("2.9 风险没有「应对」", 2)
para("第 16 节四条风险都只描述了现象，没有写「发生了怎么办」。风险条目的价值在于预案，建议每条补一句应对：",
     space_after=4)
table(
    ["风险", "现状", "建议补的应对"],
    [
        ["动作量", "「13 组是最大工作量」", "若两周画不完 → 先用色块占位跑通逻辑，美术延后到 M2"],
        ["手感", "「要一遍遍试」", "建一个「手感调试场景」，滑条实时调停顿 / 震屏 / 击退，不写死"],
        ["范围", "「别加第二角色」", "把「非目标」做成硬性检查项：每个新需求先问「竖切片需要吗」"],
        ["美术一致性", "「以同一张立绘为基准」", "先定一张标准立绘 + 配色表（十六进制），所有素材对表验收"],
    ],
    widths=[3.0, 6.2, 7.0],
    font_size=8.5,
)

# =========================================================
# 3. P2
# =========================================================
heading("3. P2 完善项：可以晚点补，但要留位置", 1)
table(
    ["模块", "现状", "建议"],
    [
        ["装备 3 把武器", "只说「数值不同」", "补一张武器表：名称、ATK、攻速、暴击、特殊效果、获取方式"],
        ["金币经济", "只有「掉落 + 结算发放」", "定金币产出（每只怪 5–15）、消耗口（升级 / 买武器）、价格区间"],
        ["升级曲线", "「升级加 HP/ATK」", "每级 +8 HP / +2 ATK，满级 10 级，经验曲线约 100 × 等级^1.5"],
        ["第 13 节工具映射", "是笔记整理，不是游戏模块", "移到附录，避免和正式需求混淆"],
        ["本地化", "无", "UI 文案集中到 strings.csv，中英双语预留字段"],
        ["调试工具", "无", "无敌模式、秒杀、跳关、显示碰撞盒、FPS 叠加 —— 自己开发时最省时间"],
        ["发布计划", "无", "目标平台、发行渠道（itch.io / Steam）、是否收费、预告片素材"],
    ],
    widths=[3.2, 5.8, 7.2],
    font_size=8.5,
)

# =========================================================
# 4. 模板
# =========================================================
heading("4. 可以直接抄的模板", 1)
para("下面几段是建议直接加进 v0.2 的骨架。字段名可以改，但「每个字段都要有值」这件事不能省。", space_after=6)

heading("4.1 characters.json", 2)
code_block([
    "{",
    '  "id": "lancheng",',
    '  "name": "蓝橙",',
    '  "max_hp": 100,',
    '  "atk": 12,',
    '  "def": 3,',
    '  "crit_rate": 0.05,',
    '  "crit_mult": 1.5,',
    '  "move_speed": 220,',
    '  "jump_velocity": -520,',
    '  "gravity": 1400,',
    '  "dodge": { "cooldown": 1.2, "distance": 160, "invuln_frames": [1, 3] },',
    '  "energy": { "max": 100, "on_hit": 6, "on_kill": 15, "on_hurt": -10 },',
    '  "combo": { "window": 3.0, "dmg_bonus_per_10": 0.03, "cap": 0.30 },',
    '  "skills": [',
    '    { "id": "basic_1", "damage_mult": 1.0, "frames": 6, "hit_frames": [3, 3] },',
    '    { "id": "basic_3", "damage_mult": 1.5, "frames": 8, "hit_frames": [4, 5], "launch": true },',
    '    { "id": "dash", "damage_mult": 1.5, "cooldown": 6.0, "frames": 8, "invuln_frames": [3, 5] },',
    '    { "id": "reverse_scale", "damage_mult": 1.2, "cooldown": 10.0, "radius": 120, "super_armor": 2.0 },',
    '    { "id": "zero_point", "cost": 100, "damage_mult": 4.0, "combo_scale": true }',
    "  ]",
    "}",
])
para("（上面是示意，数值需与 1.2 的帧数据表对齐。）", size=8.5, color=GRAY, space_after=6)

heading("4.2 enemies.json 片段", 2)
code_block([
    "{",
    '  "id": "melee_grunt",',
    '  "hp": 40,',
    '  "atk": 8,',
    '  "speed": 90,',
    '  "sight": 300,',
    '  "attack_range": 60,',
    '  "windup": 0.4,',
    '  "cooldown": 1.8,',
    '  "max_attackers": 2,',
    '  "reward": { "gold": 8, "exp": 10 },',
    '  "state_machine": ["idle", "chase", "attack", "hurt", "death"]',
    "}",
])

heading("4.3 levels.json 片段", 2)
code_block([
    "{",
    '  "id": "rooftop_rain",',
    '  "length": 3200,',
    '  "parallax": [0.2, 0.5, 1.0],',
    '  "waves": [',
    '    { "trigger_x": 600,  "enemies": [{ "id": "melee_grunt", "count": 3 }] },',
    '    { "trigger_x": 1400, "enemies": [{ "id": "melee_grunt", "count": 2 },',
    '                                   { "id": "ranged_grunt", "count": 1 }] },',
    '    { "trigger_x": 2200, "enemies": [{ "id": "shield", "count": 1 },',
    '                                   { "id": "melee_grunt", "count": 2 }] }',
    "  ],",
    '  "checkpoint": [1600, 2600],',
    '  "boss": { "id": "night_patrol", "trigger_x": 3000, "phases": [0.66, 0.33] },',
    '  "destructibles": [{ "type": "ac_unit", "x": 900 }, { "type": "billboard", "x": 1900 }],',
    '  "rating": { "time": [240, 360], "hits": [0, 3], "combo": [30, 15] }',
    "}",
])

heading("4.4 关卡时长核算表", 2)
para("把「15 分钟」拆成可核对的段落，一眼就能看出缺口：", space_after=4)
table(
    ["段落", "内容", "预计时长", "累计"],
    [
        ["开场", "镜头推进、独白、雨声", "0:20", "0:20"],
        ["第一波", "3 近战", "0:40", "1:00"],
        ["推进", "走过平台、破坏空调外机", "0:30", "1:30"],
        ["第二波", "2 近战 + 1 远程", "0:50", "2:20"],
        ["推进", "检查点、广告牌", "0:20", "2:40"],
        ["第三波", "1 盾兵 + 2 近战", "1:00", "3:40"],
        ["Boss", "三阶段 + 演出", "2:00", "5:40"],
        ["结算", "评价、金币、经验", "0:30", "6:10"],
    ],
    widths=[2.6, 7.0, 3.2, 3.4],
)
para("这张表算出来是 6 分钟左右——正好落在「竖切片合理范围」内。如果目标是 15 分钟，"
     "就要在这张表上继续加段落，而不是在文档里改一个数字。", space_after=4)

# =========================================================
# 5. 拍板
# =========================================================
heading("5. 需要先拍板的五件事", 1)
para("第 17 节已经列了 5 个「待确认」，但它们性质不同。按「不定就没法开工」的程度重排：", space_after=4)
table(
    ["优先级", "问题", "为什么卡住", "建议默认值"],
    [
        ["必须", "画风：像素 / 手绘 / 骨骼", "决定全部美术流程和资产规格", "手绘 2D + 骨骼，复用「蓝橙」现有成图"],
        ["必须", "视角：纯横版 / 带上下移动", "决定碰撞、摄像机、关卡设计", "纯横版 + 可跳跃（竖切片够用）"],
        ["必须", "15 分钟还是 5 分钟", "决定 M1 内容量与工期", "M1 做 5 分钟，15 分钟放 M2"],
        ["重要", "单机先做还是考虑联机", "影响架构（但竖切片可完全单机）", "单机，联机只留接口"],
        ["可后置", "只做蓝橙还是加角色", "影响角色系统抽象程度", "只做蓝橙，但数据层留多角色字段"],
    ],
    widths=[1.8, 5.2, 5.2, 4.0],
    font_size=8.5,
)

# =========================================================
# 6. 建议
# =========================================================
heading("6. 建议的下一步", 1)
para("不需要一次把文档补全。按下面的顺序，两三天内就能把 v0.1 变成能开工的 v0.2：", space_after=4)
bullet("第一天：拍板第 5 节的 3 个「必须」项，把结论写回文档第 17 节，删掉「待确认」。")
bullet("第二天：补第 4 节主公式 + 帧数据表 + 敌人参数表（本文 1.2 / 1.3 / 2.2 有模板）。")
bullet("第三天：补 Boss 三阶段表、评价规则、关卡时长核算表（1.4 / 1.5 / 4.4），并把 M1 验收标准改成可判定句式（1.8）。")
bullet("然后：把 M1 拆成「灰盒可玩（第 1 周）」和「接入美术（第 2 周）」，灰盒阶段就能验证手感，不依赖美术完成度。")
p = para(space_before=8, space_after=4)
rich(p, [
    ("如果只能做一件事：", False),
    ("把 M1 的验收标准改成「可观测的句子」", True),
    ("。因为验收标准是唯一能防止「做了两周发现方向错了」的东西。", False),
])

# ---------- 页脚 ----------
footer = sec.footer
fp = footer.paragraphs[0]
fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
run = fp.add_run()
set_cn(run, 8.5, False, GRAY)
fld1 = OxmlElement("w:fldChar"); fld1.set(qn("w:fldCharType"), "begin")
instr = OxmlElement("w:instrText"); instr.set(qn("xml:space"), "preserve"); instr.text = "PAGE"
fld2 = OxmlElement("w:fldChar"); fld2.set(qn("w:fldCharType"), "end")
run._r.append(fld1); run._r.append(instr); run._r.append(fld2)
run2 = fp.add_run("  /  《自我开发——拯救》PRD 评审 · v0.1")
set_cn(run2, 8.5, False, GRAY)

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = os.path.join(ROOT, "docs", "prd", "游戏需求文档_v0.1_评审与扩展建议.docx")
doc.save(out)
print("saved:", out)
