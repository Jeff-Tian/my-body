#!/usr/bin/env python3
"""Generate a 1024×1024 App Icon for MyBody (我的身体).

Design: 健康绿底 + 白色圆角内块 + 品牌字「身」。简单、离线、可随代码仓库一起生成。
输出:
  MyBody/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
并同步更新同目录下的 Contents.json 引用该文件。

用法:
  python3 scripts/generate_app_icon.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / "MyBody" / "Assets.xcassets" / "AppIcon.appiconset"
OUT = ASSET / "AppIcon-1024.png"
SIZE = 1024

# 健康主题绿(与 App AccentColor 同系):从上到下浅→深。
GRADIENT_TOP = (108, 203, 143)     # #6CCB8F
GRADIENT_BOTTOM = (52, 168, 83)    # #34A853
RING_COLOR = (255, 255, 255, 230)
GLYPH_COLOR = (255, 255, 255, 255)

# macOS 自带中文字体(品牌字 "身")。
FONT_CANDIDATES = [
    "/System/Library/Fonts/PingFang.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/Library/Fonts/Arial Unicode.ttf",
]


def pick_font(size: int) -> ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    img = Image.new("RGB", (size, size), top)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        for x in range(size):
            px[x, y] = (r, g, b)
    return img


def main() -> None:
    icon = vertical_gradient(SIZE, GRADIENT_TOP, GRADIENT_BOTTOM).convert("RGBA")
    draw = ImageDraw.Draw(icon, "RGBA")

    cx = cy = SIZE // 2

    # 背景装饰:一条柔和的白色「成长弧」,像体脂曲线从左下扬到右上。
    arc_box = (
        int(SIZE * 0.12),
        int(SIZE * 0.12),
        int(SIZE * 0.88),
        int(SIZE * 0.88),
    )
    draw.arc(arc_box, start=200, end=340, fill=(255, 255, 255, 90), width=int(SIZE * 0.04))

    # 中心品牌字「身」。
    font = pick_font(int(SIZE * 0.58))
    text = "身"
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = cx - tw // 2 - bbox[0]
    ty = cy - th // 2 - bbox[1]
    shadow_offset = int(SIZE * 0.008)
    draw.text((tx + shadow_offset, ty + shadow_offset), text, font=font, fill=(0, 90, 40, 140))
    draw.text((tx, ty), text, font=font, fill=GLYPH_COLOR)

    # App Store 上传不允许带 alpha。1024 icon 必须是不透明 RGB。
    flat = Image.new("RGB", icon.size, GRADIENT_BOTTOM)
    flat.paste(icon, mask=icon.split()[3])
    ASSET.mkdir(parents=True, exist_ok=True)
    flat.save(OUT, format="PNG", optimize=True)

    # 同步 Contents.json —— 单 size 的 universal iOS 图标足够,Xcode 会在
    # 资产编译时自动生成 Info.plist 里的 CFBundleIcons 以及 120×120 / 180×180
    # 等设备尺寸,解决 altool 90022 错误。
    contents = {
        "images": [
            {
                "filename": OUT.name,
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }
    (ASSET / "Contents.json").write_text(
        json.dumps(contents, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(f"[generate_app_icon] ✅ wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
