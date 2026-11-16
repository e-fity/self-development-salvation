"""把绿幕立绘处理成游戏用透明贴图。

用法：python tools/assets/import_player_art.py [源图] [输出名]
默认：game/art/player/source/bluecheng_stand.png → game/art/player/idle.png

做的事：
1. 按「绿得比红蓝都多」判断背景，边缘做半透明过渡
2. 去绿边（despill），避免描边发绿
3. 裁掉透明边，等比缩到 512px 高（游戏里再缩到 180px，留余量）
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(HERE, "game", "art", "player", "source", "bluecheng_stand.png")
DST = os.path.join(HERE, "game", "art", "player", "idle.png")
TARGET_H = 512


def key_green(img: Image.Image) -> Image.Image:
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, _a = px[x, y]
            green = g - max(r, b)
            if green <= 8:
                continue
            if green >= 45:
                px[x, y] = (r, g, b, 0)
            else:
                # 边缘：按「有多绿」给一部分透明度，并压掉绿
                alpha = int(255 * (1.0 - green / 45.0))
                g2 = min(g, int((r + b) * 0.5) + 12)
                px[x, y] = (r, g2, b, alpha)
    return img


def despill(img: Image.Image) -> Image.Image:
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            cap = int((r + b) * 0.5) + 14
            if g > cap:
                px[x, y] = (r, cap, b, a)
    return img


def main() -> None:
    src = sys.argv[1] if len(sys.argv) > 1 else SRC
    dst = sys.argv[2] if len(sys.argv) > 2 else DST
    img = Image.open(src)
    print("源图 %dx%d" % img.size)
    img = key_green(img)
    img = despill(img)
    box = img.getbbox()
    if box is None:
        raise SystemExit("整张图都被判成背景了，检查阈值")
    img = img.crop(box)
    img = img.transpose(Image.FLIP_LEFT_RIGHT)   # 默认朝右，跟 _facing = 1 对齐
    scale = TARGET_H / float(img.height)
    size = (max(1, int(img.width * scale)), TARGET_H)
    img = img.resize(size, Image.LANCZOS)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    img.save(dst)
    print("输出 %s %dx%d（裁切后 %dx%d）" % (dst, size[0], size[1], box[2] - box[0], box[3] - box[1]))


if __name__ == "__main__":
    main()
