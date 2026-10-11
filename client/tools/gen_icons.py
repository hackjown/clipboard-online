#!/usr/bin/env python3
"""生成「纸与墨」App 图标（iOS / macOS / Android）。用法：python3 tools/gen_icons.py  (需要 Pillow)"""
import json
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
PAPER = (250, 246, 236)      # --paper  #faf6ec
BG = (236, 230, 217)         # --bg     #ece6d9
PAPER2 = (243, 237, 223)     # --paper-2
INK = (23, 20, 15)           # --ink    #17140f
ACCENT = (255, 79, 43)       # --accent #ff4f2b
SUN = (255, 216, 74)
S = 4  # 超采样


def art(size, scale=1.0, bg=True, dots=True):
    """size: 输出边长；scale: 图案占画布比例；bg: 是否绘制纸底（False=透明，用于 Android 前景）"""
    N = size * S
    img = Image.new('RGBA', (N, N), BG + (255,) if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    u = N / 1024.0
    if bg and dots:
        ov = Image.new('RGBA', (N, N), (0, 0, 0, 0))
        od = ImageDraw.Draw(ov)
        step = 44 * u
        y = step / 2
        while y < N:
            x = step / 2
            while x < N:
                r = 2.6 * u
                od.ellipse([x - r, y - r, x + r, y + r], fill=(23, 20, 15, 34))
                x += step
            y += step
        img = Image.alpha_composite(img, ov)
        d = ImageDraw.Draw(img)
    # 图案坐标系：以画布中心缩放
    cx = cy = N / 2

    def P(v):  # 1024 坐标 -> 像素（围绕中心缩放）
        return cx + (v - 512) * u * scale

    def box(x0, y0, x1, y1):
        return [P(x0), P(y0), P(x1), P(y1)]

    lw = max(2, int(30 * u * scale))
    rad = 90 * u * scale
    off = 38 * u * scale
    # 剪贴板本体：硬阴影 + 纸面 + 墨线
    bx = (232, 190, 792, 880)
    d.rounded_rectangle([P(bx[0]) + off, P(bx[1]) + off, P(bx[2]) + off, P(bx[3]) + off], rad, fill=INK)
    d.rounded_rectangle(box(*bx), rad, fill=PAPER, outline=INK, width=lw)
    # 纸面文字线
    for i, (y, x1) in enumerate([(430, 690), (530, 690), (630, 600)]):
        d.rounded_rectangle(box(318, y - 17, x1, y + 17), 17 * u * scale, fill=INK)
    # 朱红点缀（书签/标记）
    d.rounded_rectangle(box(318, 720, 470, 790), 22 * u * scale, fill=ACCENT, outline=INK, width=int(lw * 0.6))
    # 夹子：朱红圆角块 + 墨线，压在顶部
    cb = (372, 120, 652, 300)
    d.rounded_rectangle([P(cb[0]) + off * 0.6, P(cb[1]) + off * 0.6, P(cb[2]) + off * 0.6, P(cb[3]) + off * 0.6],
                        62 * u * scale, fill=INK)
    d.rounded_rectangle(box(*cb), 62 * u * scale, fill=ACCENT, outline=INK, width=lw)
    # 夹子上的孔
    hr = 26 * u * scale
    d.ellipse([P(512) - hr, P(210) - hr, P(512) + hr, P(210) + hr], fill=PAPER, outline=INK, width=int(lw * 0.5))
    return img.resize((size, size), Image.LANCZOS)


def flatten(img):
    bg = Image.new('RGB', img.size, BG)
    bg.paste(img, mask=img.split()[3])
    return bg


def mac_icon(size):
    """macOS：圆角方块 + 四周留白（824/1024）+ 轻阴影"""
    N = size * S
    out = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    inner = int(N * 824 / 1024)
    a = art(inner // S, 0.9).resize((inner, inner), Image.LANCZOS)
    mask = Image.new('L', (inner, inner), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, inner - 1, inner - 1], inner * 0.2237, fill=255)
    off = (N - inner) // 2
    # 柔和投影
    sh = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    shm = Image.new('L', (inner, inner), 0)
    ImageDraw.Draw(shm).rounded_rectangle([0, 0, inner - 1, inner - 1], inner * 0.2237, fill=70)
    sh.paste((0, 0, 0, 255), (off, off + int(N * 0.012)), shm)
    out = Image.alpha_composite(out, sh)
    out.paste(a, (off, off), mask)
    return out.resize((size, size), Image.LANCZOS)


def main():
    (ROOT / 'assets/icon').mkdir(parents=True, exist_ok=True)
    master = flatten(art(1024, 1.0))
    master.save(ROOT / 'assets/icon/icon_master_1024.png')               # iOS 全出血、无透明
    mac_icon(1024).save(ROOT / 'assets/icon/icon_macos_1024.png')
    art(1024, 0.62, bg=False).save(ROOT / 'assets/icon/icon_android_foreground_1024.png')

    # --- iOS ---
    ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    cj = json.loads((ios / 'Contents.json').read_text())
    for im in cj['images']:
        w = float(im['size'].split('x')[0]) * int(im['scale'].rstrip('x'))
        px = int(round(w))
        flatten(art(px, 1.0)).convert('RGB').save(ios / im['filename'])

    # --- macOS ---
    mac = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    cj = json.loads((mac / 'Contents.json').read_text())
    for im in cj['images']:
        w = float(im['size'].split('x')[0]) * int(im['scale'].rstrip('x'))
        mac_icon(int(round(w))).save(mac / im['filename'])

    # --- Android ---
    res = ROOT / 'android/app/src/main/res'
    legacy = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    fg = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
    for k, px in legacy.items():
        # 旧版：圆角方块纸底
        a = art(px * 2, 0.92).resize((px, px), Image.LANCZOS)
        m = Image.new('L', (px, px), 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, px - 1, px - 1], px * 0.22, fill=255)
        o = Image.new('RGBA', (px, px), (0, 0, 0, 0))
        o.paste(a, (0, 0), m)
        o.save(res / f'mipmap-{k}/ic_launcher.png')
        art(fg[k], 0.62, bg=False).save(res / f'mipmap-{k}/ic_launcher_foreground.png')
    (res / 'mipmap-anydpi-v26').mkdir(exist_ok=True)
    (res / 'mipmap-anydpi-v26/ic_launcher.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n')
    (res / 'mipmap-anydpi-v26/ic_launcher_round.xml').write_text(
        (res / 'mipmap-anydpi-v26/ic_launcher.xml').read_text())
    (res / 'values/ic_launcher_background.xml').write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
        '    <color name="ic_launcher_background">#ECE6D9</color>\n</resources>\n')
    print('icons generated')


if __name__ == '__main__':
    main()
