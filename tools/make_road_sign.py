# -*- coding: utf-8 -*-
"""生成「国道」龙门架路牌贴图（1024x288，蓝底白字），供 scripts/highway_arena.gd 直接 load。

    python tools/make_road_sign.py

改文案只动下面的 TEXT_BIG / TEXT_SMALL，重跑一次即可；尺寸保持不变
（highway_arena.gd 里路牌面片是按贴图长宽比铺的，改尺寸要同步调面片）。
"""
from PIL import Image, ImageDraw, ImageFont
import os

W, H = 1024, 288
BG = (0x10, 0x40, 0x96)          # 蓝底
FG = (255, 255, 255)             # 白字
TEXT_BIG = "国道"
TEXT_SMALL = "G108 · NATIONAL ROAD"
FONT = r"C:\Windows\Fonts\simhei.ttf"

out = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assets", "props", "road", "g108_sign.png")

img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

# 白色外框（国道标志牌的边框样式）
d.rectangle([14, 14, W - 15, H - 15], outline=FG, width=8)

def draw_centered(text, size, y_top):
    f = ImageFont.truetype(FONT, size)
    box = d.textbbox((0, 0), text, font=f)
    tw, th = box[2] - box[0], box[3] - box[1]
    d.text(((W - tw) / 2 - box[0], y_top), text, font=f, fill=FG)
    return th

# 主字：拉大字号并加字间空格，让两个字撑满牌面
big = TEXT_BIG if len(TEXT_BIG) >= 3 else " ".join(list(TEXT_BIG))
draw_centered(big, 132, 34)
draw_centered(TEXT_SMALL, 46, 196)

os.makedirs(os.path.dirname(out), exist_ok=True)
img.save(out)
print("WROTE", out, img.size)
