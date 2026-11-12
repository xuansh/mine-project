# -*- coding: utf-8 -*-
"""Deterministic pixel-exact HUD panel frame generator (no anti-aliasing).

Palette (locked):
  #0A0810 outer 1px line
  #6E6884 2px gray-purple line
  #2A2438 2px inner shadow line
  #181420 flat interior
  #D9A227 2px amber tick (accent)
  #FF00FF chroma background (optional variant only)
"""
import os
import struct
import zlib

W = H = 1024

BLACK = (0x0A, 0x08, 0x10)
GREY = (0x6E, 0x68, 0x84)
SHADOW = (0x2A, 0x24, 0x38)
INNER = (0x18, 0x14, 0x20)
AMBER = (0xD9, 0xA2, 0x27)
MAGENTA = (0xFF, 0x00, 0xFF)


def new_canvas(color):
    return bytearray(bytes(color) * (W * H))


def put(buf, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        i = (y * W + x) * 3
        buf[i] = c[0]
        buf[i + 1] = c[1]
        buf[i + 2] = c[2]


def rect(buf, x0, y0, x1, y1, c):
    if x0 > x1:
        x0, x1 = x1, x0
    if y0 > y1:
        y0, y1 = y1, y0
    row = bytes(c) * (x1 - x0 + 1)
    for y in range(max(0, y0), min(H - 1, y1) + 1):
        i = (y * W + x0) * 3
        buf[i:i + len(row)] = row


def draw_frame(buf, ox, oy, s):
    """Rings: 1px black, 2px grey-purple, 2px shadow, then flat interior."""
    rect(buf, ox, oy, ox + s - 1, oy + s - 1, BLACK)          # 1px outer
    rect(buf, ox + 1, oy + 1, ox + s - 2, oy + s - 2, GREY)   # 2px
    rect(buf, ox + 3, oy + 3, ox + s - 4, oy + s - 4, SHADOW)  # 2px
    rect(buf, ox + 5, oy + 5, ox + s - 6, oy + s - 6, INNER)   # flat empty

    def cxy(xi, yi, right, bottom):
        x = ox + s - 1 - xi if right else ox + xi
        y = oy + s - 1 - yi if bottom else oy + yi
        return x, y

    for right in (False, True):
        for bottom in (False, True):
            parts = (
                ((14, 14, 15, 70), GREY),    # vertical arm, 2px thick
                ((14, 14, 70, 15), GREY),    # horizontal arm, 2px thick
                ((76, 14, 99, 15), AMBER),   # 2px amber tick
            )
            for (x0, y0, x1, y1), col in parts:
                ax, ay = cxy(x0, y0, right, bottom)
                bx, by = cxy(x1, y1, right, bottom)
                rect(buf, ax, ay, bx, by, col)


def save_png(path, buf):
    raw = bytearray()
    stride = W * 3
    for y in range(H):
        raw.append(0)
        raw += buf[y * stride:(y + 1) * stride]

    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += chunk(b'IEND', b'')
    with open(path, 'wb') as f:
        f.write(png)


out = os.path.dirname(os.path.abspath(__file__))

# Variant 1: frame fills the canvas edge to edge (texture-ready, no magenta)
b1 = new_canvas(INNER)
draw_frame(b1, 0, 0, W)
save_png(os.path.join(out, 'hud_panel_frame_edgetoedge_1024.png'), b1)

# Variant 2: identical frame inset 32px on pure magenta chroma background
b2 = new_canvas(MAGENTA)
draw_frame(b2, 32, 32, W - 64)
save_png(os.path.join(out, 'hud_panel_frame_chroma_1024.png'), b2)

print('done')
