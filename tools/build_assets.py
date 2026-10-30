#!/usr/bin/env python3
"""
从一张角色立绘生成 dsh-dafeiyu 兼容的动作素材。

用法：
    python build_assets.py <角色立绘.png> <输出目录> [--height 330]

要求：
  - 立绘为**纯白或纯色背景**的正面/3-4 侧照片或插画（PNG/JPG 均可）
  - 输出：<输出目录>/pet-manifest.json + <输出目录>/pet/<clip>/*.webp（412×344）

原理：
  1) 以四角/边缘的"背景色"为基准，按亮度阈值 + 最大连通域抠出角色
  2) 形态学重建填补内部空洞（眼睛、蕾丝间的缝隙）
  3) 用整体变换（呼吸/摇摆/跳动/垂头/挤压）生成 16 组动作帧
     单张静图无法产生真实分层肢体动画，这一点无法回避
"""
from __future__ import annotations

import argparse
import json
import math
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

CANVAS_W, CANVAS_H = 412, 344
WHITE_T = 248  # 背景亮度阈值：min(R,G,B) >= 248 视为背景


def largest_component(mask: np.ndarray) -> np.ndarray:
    h, w = mask.shape
    seen = np.zeros((h, w), bool)
    best: list[tuple[int, int]] = []
    for y0 in range(h):
        row = mask[y0]
        for x0 in range(w):
            if not row[x0] or seen[y0, x0]:
                continue
            q = deque([(y0, x0)])
            seen[y0, x0] = True
            cells = []
            while q:
                y, x = q.popleft()
                cells.append((y, x))
                for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                    if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
            if len(cells) > len(best):
                best = cells
    out = np.zeros((h, w), bool)
    for y, x in best:
        out[y, x] = True
    return out


def fill_holes(comp: np.ndarray, ksize: int = 5, max_iter: int = 900) -> np.ndarray:
    bg = (~comp).astype(np.uint8) * 255
    seed = np.zeros_like(bg)
    seed[0, :] = bg[0, :]; seed[-1, :] = bg[-1, :]
    seed[:, 0] = bg[:, 0]; seed[:, -1] = bg[:, -1]
    prev = None
    for _ in range(max_iter):
        grown = np.array(Image.fromarray(seed, "L").filter(ImageFilter.MaxFilter(ksize)))
        seed = np.minimum(grown, bg)
        if prev is not None and np.array_equal(seed, prev):
            break
        prev = seed.copy()
    return comp | ((~comp) & (seed <= 127))


def cutout_master(src: Path, target_height: int) -> Image.Image:
    img = Image.open(src).convert("RGB")
    arr = np.array(img).astype(np.int16)
    near_white = arr.min(axis=2) >= WHITE_T
    bg = largest_component(near_white)
    doll = ~bg
    d = np.array(Image.fromarray((doll.astype(np.uint8) * 255), "L")
                 .filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))) > 127
    d = largest_component(d)
    d = fill_holes(d, ksize=5)

    alpha = Image.fromarray((d.astype(np.uint8) * 255), "L").filter(ImageFilter.GaussianBlur(0.8))
    rgba = img.convert("RGBA")
    rgba.putalpha(alpha)
    bb = alpha.point(lambda v: 255 if v > 16 else 0).getbbox()
    if bb:
        rgba = rgba.crop(bb)

    w, h = rgba.size
    s = target_height / h
    new = rgba.resize((max(1, int(round(w * s))), target_height), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    canvas.alpha_composite(new, ((CANVAS_W - new.size[0]) // 2, CANVAS_H - target_height - 7))
    return canvas


def transform(base: Image.Image, *, sx=1.0, sy=1.0, dx=0, dy=0, rot=0.0, bright=1.0) -> Image.Image:
    al = base.split()[3]
    bb = al.point(lambda v: 255 if v > 16 else 0).getbbox()
    x0, y0, x1, y1 = bb
    body = base.crop(bb)
    if bright != 1.0:
        r, g, b, a = body.split()
        rgb = ImageEnhance.Brightness(Image.merge("RGB", (r, g, b))).enhance(bright)
        r2, g2, b2 = rgb.split()
        body = Image.merge("RGBA", (r2, g2, b2, a))
    nw, nh = max(1, int(round(body.size[0] * sx))), max(1, int(round(body.size[1] * sy)))
    body = body.resize((nw, nh), Image.LANCZOS)
    if rot:
        body = body.rotate(rot, resample=Image.BICUBIC, expand=True)
    out = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    px = int(round((x0 + x1) // 2 - body.size[0] // 2 + dx))
    py = int(round((CANVAS_H - 7) - body.size[1] + dy))
    out.alpha_composite(body, (px, py))
    return out


def make_clip(kind: str, n: int, base: Image.Image) -> list[Image.Image]:
    frames = []
    for i in range(n):
        ph = 2 * math.pi * (i / n)
        if kind == "breath":
            f = transform(base, sy=1 + 0.010 * math.sin(ph), sx=1 - 0.005 * math.sin(ph))
        elif kind == "sway":
            f = transform(base, rot=1.1 * math.sin(ph))
        elif kind == "sway_soft":
            f = transform(base, rot=0.8 * math.sin(ph), dy=-1.0 * math.sin(ph))
        elif kind == "tilt":
            f = transform(base, rot=-1.6 + 1.2 * math.sin(ph), dy=-1.0 * math.sin(ph))
        elif kind == "bob":
            f = transform(base, dy=-4.0 * abs(math.sin(ph)), sy=1 + 0.006 * math.sin(ph))
        elif kind == "hop":
            lift = max(0.0, math.sin(ph))
            f = transform(base, dy=-16.0 * lift, sy=1 + 0.02 * lift)
        elif kind == "droop":
            f = transform(base, sy=0.965, dy=5, rot=-1.8, bright=0.96)
        elif kind == "droop_soft":
            f = transform(base, sy=0.975 + 0.006 * math.sin(ph), dy=3,
                          rot=-1.2 + 0.6 * math.sin(ph), bright=0.97)
        elif kind == "squash":
            k = abs(math.sin(ph))
            f = transform(base, sy=1 - 0.055 * k, sx=1 + 0.030 * k, dy=2.5 * k)
        elif kind == "stretch":
            k = abs(math.sin(ph))
            f = transform(base, sy=1 + 0.050 * k, sx=1 - 0.025 * k, dy=-2.0 * k)
        elif kind == "wiggle":
            f = transform(base, rot=2.2 * math.sin(2 * ph), dx=2.0 * math.sin(ph))
        elif kind == "pulse":
            k = 0.5 + 0.5 * math.sin(ph)
            f = transform(base, sx=1 + 0.03 * k, sy=1 + 0.03 * k, dy=-2 * k)
        else:
            raise ValueError(kind)
        frames.append(f)
    return frames


# name: (帧数, 变换类型, 每帧毫秒, 是否循环)
CLIPS: dict[str, tuple[int, str, int, bool]] = {
    "idle": (16, "breath", 200, True),
    "waiting": (12, "sway_soft", 200, True),
    "thinking": (12, "tilt", 200, True),
    "working": (10, "bob", 120, True),
    "working_search": (10, "bob", 110, True),
    "working_command": (10, "bob", 110, True),
    "success": (10, "hop", 90, False),
    "error": (10, "droop", 150, False),
    "dragging": (6, "stretch", 120, True),
    "dragging_release": (5, "squash", 80, False),
    "head_pat": (10, "squash", 90, False),
    "poke": (10, "wiggle", 90, False),
    "tail": (12, "sway_soft", 200, True),
    "eat_token": (10, "pulse", 110, False),
    "idle_stretch": (10, "stretch", 140, False),
    "idle_yawn": (12, "droop_soft", 160, False),
}

STATE_MAP = {
    "IDLE": "idle", "THINKING": "thinking", "WORKING": "working",
    "WAITING": "waiting", "SUCCESS": "success", "ERROR": "error",
    "DISCONNECTED": "idle",
}
WORKING_ACTIVITY_MAP = {
    "searching": "working_search", "commanding": "working_command",
    "editing": "working", "testing": "working_command", "using-tool": "working",
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", help="角色立绘路径（纯白/纯色背景）")
    ap.add_argument("out", help="输出目录")
    ap.add_argument("--height", type=int, default=330, help="角色在画布中的高度，默认 330")
    ap.add_argument("--character-id", default="yueyuji")
    args = ap.parse_args()

    src = Path(args.source)
    out = Path(args.out)
    if not src.exists():
        raise SystemExit(f"找不到素材: {src}")
    (out / "pet").mkdir(parents=True, exist_ok=True)

    base = cutout_master(src, args.height)
    base.save(out / "character-base.png")

    manifest = {
        "formatVersion": 1,
        "characterId": args.character_id,
        "baseSize": CANVAS_W,
        "maxFrameWidth": CANVAS_W,
        "maxFrameHeight": CANVAS_H,
        "assetSource": {"note": "generated by build_assets.py", "fps": 24},
        "clips": {},
        "stateMap": STATE_MAP,
        "workingActivityMap": WORKING_ACTIVITY_MAP,
        "idleMicroClips": ["idle_stretch", "idle_yawn", "eat_token"],
        "idleMicroIntervalsMs": {
            "quiet": [45000, 90000], "normal": [25000, 45000], "lively": [12000, 22000],
        },
        "interactionCooldownMs": 1200,
    }

    total = 0
    for name, (n, kind, frame_ms, loop) in CLIPS.items():
        (out / "pet" / name).mkdir(parents=True, exist_ok=True)
        paths = []
        for i, frame in enumerate(make_clip(kind, n, base), start=1):
            rel = f"{name}/{name}_{i:03d}.webp"
            frame.save(out / "pet" / rel, format="WEBP", quality=82, method=6)
            paths.append(rel)
            total += 1
        manifest["clips"][name] = {"frames": paths, "frameMs": frame_ms, "loop": loop}
        print(f"  {name:<16} {n:>3} 帧  {frame_ms}ms/帧  loop={loop}")

    (out / "pet-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n完成：{total} 帧 → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
