#!/usr/bin/env python3
"""从截图里量「文字行距 / 文字行数」—— 客观判断字号、行高、布局有没有真的变。

## 为什么需要它

**别用肉眼,也别用文件大小。** 本机没有 PIL / numpy(实测),而截图内容是会变的。
在电视上实测被坑过两次:

  · 把「功能键行的字变大了」当成「终端字号变了」(文件大小确实变了,但那不是终端)
  · 把「前后两次画面内容不同」当成「字号变了」(行距 115 → 163,其实是终端滚到了别处)

只有「**先控住内容,再量行距**」才是硬判据。

## 用法

    png-rowpitch.py <png> [起始y] [结束y]    # 量一张图(限定 y 范围可避开无关区域)
    png-rowpitch.py --selftest               # 自检,不碰设备

输出里有三个数:文字行数、平均行距(px)、文字块总高(px)。
比字号就是比这几个数 —— 值一样就是没变,不用猜。

## 实现说明

自己解 PNG:只支持 8 位色深 + 5 种扫描线滤波(0/1/2/3/4),够解码 `screencap` 的输出。
不依赖任何第三方库。
"""

import struct
import sys
import zlib

__all__ = ['decode_png', 'text_bands', 'row_pitch']


# ---------------------------------------------------------------- 解码

def decode_png(path, max_rows=None):
    """返回 (宽, 高, 通道数, [每行的原始字节])。只解前 max_rows 行就够时能省一半时间。"""
    b = open(path, 'rb').read()
    if b[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError(f"{path}: 不是 PNG(缺签名)")

    i, idat = 8, b''
    w = h = bitdepth = colortype = None
    while i < len(b):
        ln = struct.unpack('>I', b[i:i + 4])[0]
        typ = b[i + 4:i + 8]
        data = b[i + 8:i + 8 + ln]
        if typ == b'IHDR':
            w, h, bitdepth, colortype = struct.unpack('>IIBB', data[:10])
        elif typ == b'IDAT':
            idat += data
        elif typ == b'IEND':
            break
        i += 12 + ln

    if bitdepth != 8:
        raise ValueError(f"只支持 8 位色深,这张是 {bitdepth}")
    try:
        channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    except KeyError:
        raise ValueError(f"不支持的 PNG 颜色类型 {colortype}")

    stride = w * channels
    raw = zlib.decompress(idat)
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(h if max_rows is None else min(h, max_rows)):
        f = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if f == 1:                                    # Sub
            for x in range(channels, stride):
                line[x] = (line[x] + line[x - channels]) & 255
        elif f == 2:                                  # Up
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif f == 3:                                  # Average
            for x in range(stride):
                a = line[x - channels] if x >= channels else 0
                line[x] = (line[x] + ((a + prev[x]) >> 1)) & 255
        elif f == 4:                                  # Paeth
            for x in range(stride):
                a = line[x - channels] if x >= channels else 0
                c = prev[x - channels] if x >= channels else 0
                bb = prev[x]
                p = a + bb - c
                pa, pb, pc = abs(p - a), abs(p - bb), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (bb if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        rows.append(bytes(line))
        prev = line
    return w, h, channels, rows


# ---------------------------------------------------------------- 分析

def text_bands(rows, channels, y0=0, y1=None, min_bright_px=8, thresh=110):
    """把「连续够亮的行」聚成文字行,返回 [[起始y, 结束y], ...]。

    判据:一行里亮像素个数 >= min_bright_px 就算这一行有字。
    黑底白字的终端截图直接可用;浅色主题请调 thresh。
    """
    y1 = len(rows) if y1 is None else min(y1, len(rows))
    bands, cur = [], None
    for y in range(y0, y1):
        row = rows[y]
        n = 0
        for x in range(0, len(row), channels):
            if row[x] > thresh:
                n += 1
                if n >= min_bright_px:
                    break
        if n >= min_bright_px:
            cur = [y, y] if cur is None else [cur[0], y]
        elif cur is not None:
            bands.append(cur)
            cur = None
    if cur is not None:
        bands.append(cur)
    return bands


def row_pitch(rows, channels, y0=0, y1=None, **kw):
    """返回 (行数, 平均行距px, 文字块总高px)。行数 < 2 时后两项为 None。"""
    bands = text_bands(rows, channels, y0, y1, **kw)
    centers = [(a + b) / 2 for a, b in bands]
    if len(centers) < 2:
        return len(centers), None, None
    pitches = [centers[i + 1] - centers[i] for i in range(len(centers) - 1)]
    return len(centers), sum(pitches) / len(pitches), centers[-1] - centers[0]


# ---------------------------------------------------------------- 自检

def _write_png(path, w, h, rgb_rows):
    """写一张 RGB PNG(只用 filter 0),给自检造输入用。"""
    body = b''.join(b'\x00' + r for r in rgb_rows)

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff))

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(body, 6))
           + chunk(b'IEND', b''))
    open(path, 'wb').write(png)


def selftest():
    """造三张已知行距的图,量回来必须对得上。这样它能进 CI/verify-all。"""
    import tempfile
    import os
    ok = True
    cases = [(30, 12), (40, 8), (60, 20)]          # (行距px, 文字行数)
    for pitch, n in cases:
        w, h = 200, pitch * n + 40
        rows = []
        for y in range(h):
            on = (y % pitch) < 6                   # 每 pitch 像素里 6 像素亮 = 一行"文字"
            rows.append((bytes([255, 255, 255]) * w) if on else (bytes([0, 0, 0]) * w))
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as f:
            tmp = f.name
        try:
            _write_png(tmp, w, h, rows)
            _w, _h, ch, rws = decode_png(tmp)      # 只解一次(解一遍 200x~400 就要几秒)
            cnt, avg, tot = row_pitch(rws, ch)
            good = (abs(avg - pitch) <= 1.0)
            print(f"  {'✅' if good else '❌'} 构造行距={pitch}px 行数={n} "
                  f"→ 量到 行数={cnt} 平均行距={avg:.2f}px 总高={tot}")
            ok = ok and good
        finally:
            os.unlink(tmp)
    print(f"  {'自检通过' if ok else '自检失败'}")
    return 0 if ok else 1


# ---------------------------------------------------------------- CLI

def main(argv):
    if len(argv) >= 2 and argv[1] == '--selftest':
        return selftest()
    if len(argv) < 2:
        print(__doc__)
        return 2
    path = argv[1]
    y0 = int(argv[2]) if len(argv) > 2 else 0
    y1 = int(argv[3]) if len(argv) > 3 else None
    w, h, ch, rows = decode_png(path, max_rows=y1)
    sheet = text_bands(rows, ch, y0, y1)
    centers = [(a + b) / 2 for a, b in sheet]
    print(f"  {path}  {w}x{h}  {ch} 通道")
    print(f"  文字行数 = {len(sheet)}")
    if len(centers) >= 2:
        pitches = [centers[i + 1] - centers[i] for i in range(len(centers) - 1)]
        print(f"  平均行距 = {sum(pitches) / len(pitches):.2f}px"
              f"   min={min(pitches):.1f} max={max(pitches):.1f}")
        print(f"  文字块总高 = {centers[-1] - centers[0]:.0f}px")
    for a, b in sheet[:8]:
        print(f"    行 y={a}..{b}  高 {b - a + 1}px")
    if len(sheet) > 8:
        print(f"    …(共 {len(sheet)} 行)")
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
