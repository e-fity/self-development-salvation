# -*- coding: utf-8 -*-
"""给 Godot 编辑器截图加中文标注"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, "docs", "assets")
SRC = os.path.join(ASSETS, "editor_source.png")
OUT = os.path.join(ASSETS, "editor_标注.png")

FONT_CN = r"C:\Windows\Fonts\msyh.ttc"
FONT_BOLD = r"C:\Windows\Fonts\msyhbd.ttc"

img = Image.open(SRC).convert("RGB")
W, H = img.size
layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(layer)

f_badge = ImageFont.truetype(FONT_BOLD, 17)
f_title = ImageFont.truetype(FONT_BOLD, 21)
f_item = ImageFont.truetype(FONT_CN, 18)
f_note = ImageFont.truetype(FONT_CN, 18)

AMBER = (255, 183, 3, 255)
WHITE = (255, 255, 255, 255)
PANEL_BG = (16, 18, 22, 228)
LINE = (255, 183, 3, 230)


def badge(cx, cy, num):
    r = 13
    d.ellipse([cx - r - 2, cy - r - 2, cx + r + 2, cy + r + 2], fill=(0, 0, 0, 160))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=AMBER)
    t = str(num)
    tb = d.textbbox((0, 0), t, font=f_badge)
    d.text((cx - (tb[2] - tb[0]) / 2, cy - (tb[3] - tb[1]) / 2 - 1), t, font=f_badge, fill=(20, 20, 20, 255))


def box(x1, y1, x2, y2, width=3):
    d.rectangle([x1, y1, x2, y2], outline=AMBER, width=width)


def legend(x, y, w, items, title="界面说明（数字对应图上编号）"):
    lh = 37
    h = 46 + lh * len(items) + 10
    d.rounded_rectangle([x, y, x + w, y + h], radius=12, fill=PANEL_BG, outline=AMBER, width=2)
    d.text((x + 18, y + 13), title, font=f_title, fill=WHITE)
    for i, s in enumerate(items):
        d.text((x + 18, y + 52 + i * lh), s, font=f_item, fill=WHITE)
    return y + h


def note(x, y, text, target=None, w=None):
    tb = d.textbbox((0, 0), text, font=f_note)
    tw = tb[2] - tb[0]
    w = w or tw + 24
    h = 32
    d.rounded_rectangle([x, y, x + w, y + h], radius=8, fill=PANEL_BG, outline=AMBER, width=2)
    d.text((x + 12, y + 6), text, font=f_note, fill=WHITE)
    if target:
        tx, ty = target
        # 从标签最近的边连到目标
        sx = x + w if tx > x + w else (x if tx < x else x + w / 2)
        sy = y + h / 2
        d.line([sx, sy, tx, ty], fill=LINE, width=2)
        d.ellipse([tx - 4, ty - 4, tx + 4, ty + 4], fill=AMBER)


# ---------- 区域框 ----------
box(0, 0, 500, 24)          # 1 菜单栏
box(795, 26, 1130, 56)      # 2 主界面切换
box(313, 64, 497, 96)       # 3 场景标签
box(0, 48, 262, 558)        # 4 场景树
box(300, 98, 885, 136)      # 5 2D 工具条
box(279, 139, 1630, 814)    # 6 2D 视图
box(1633, 48, 1918, 820)    # 7 检查器
box(0, 512, 262, 814)       # 8 文件系统
box(0, 816, 1628, 1071)     # 9 输出 / 调试器
box(1639, 1044, 1918, 1073) # 10 状态栏

# ---------- 编号 ----------
badge(516, 12, 1)
badge(1146, 41, 2)
badge(510, 80, 3)
badge(274, 62, 4)
badge(899, 117, 5)
badge(294, 170, 6)
badge(1619, 62, 7)
badge(274, 526, 8)
badge(1616, 832, 9)
badge(1650, 1028, 10)

# ---------- 图例 ----------
legend(330, 196, 520, [
    "① 菜单栏：保存、撤销、项目设置",
    "② 主界面：2D / 3D / 脚本 / 游戏",
    "③ 场景标签：现在打开哪个场景",
    "④ 场景树：场景里有哪些节点",
    "⑤ 2D 工具：选择 / 移动 / 旋转 / 缩放",
    "⑥ 2D 视图：摆位置、看效果的地方",
    "⑦ 检查器：选中节点的属性都在这里",
    "⑧ 文件系统：工程里的文件",
    "⑨ 输出 / 调试器：报错和日志看这里",
    "⑩ 状态栏：红字 = 脚本错误数",
])

# ---------- 图上就地注释 ----------
note(660, 690, "蓝块 = 玩家（60×180 占位）", target=(918, 645))
note(1002, 596, "橙点 = 朝向标记", target=(976, 524))
note(1120, 700, "粉色线 = 摄像机视野边界", target=(1210, 670))
note(1200, 900, "这里是日志：报错和打印都在这", w=310)

out = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
out.save(OUT, quality=95)
print("saved", OUT, out.size)
