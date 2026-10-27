"""Renders the Beam mark (ink squircle + white cursor) into every icon and
logo file the Windows build uses. Run from the repo root:

    python3 res/beam/make_brand_assets.py
"""
from PIL import Image, ImageDraw

INK = (17, 17, 19, 255)
WHITE = (255, 255, 255, 255)
SS = 4  # supersampling factor for smooth edges

# Cursor from the Beam prototype, in a 24-unit box.
CURSOR = [(5, 3), (20, 12), (13.5, 13.2), (10, 20)]


def mark(size, pad_ratio=0.04):
    """Ink squircle with a centred white cursor, rendered at `size` px."""
    s = size * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = round(s * pad_ratio)
    box = s - 2 * pad
    d.rounded_rectangle((pad, pad, s - pad, s - pad), radius=box * 0.235, fill=INK)

    xs = [p[0] for p in CURSOR]
    ys = [p[1] for p in CURSOR]
    w, h = max(xs) - min(xs), max(ys) - min(ys)
    scale = box * 0.48 / h
    # The cursor's visual weight sits up-left; nudge it right/down to balance.
    ox = s / 2 - w * scale / 2 + box * 0.03 - min(xs) * scale
    oy = s / 2 - h * scale / 2 + box * 0.01 - min(ys) * scale
    pts = [(ox + x * scale, oy + y * scale) for x, y in CURSOR]

    d.polygon(pts, fill=WHITE)
    # Round the cursor's corners like the portfolio's soft shapes.
    r = box * 0.022
    for i, p in enumerate(pts):
        q = pts[(i + 1) % len(pts)]
        d.line([p, q], fill=WHITE, width=round(2 * r))
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=WHITE)

    return img.resize((size, size), Image.LANCZOS)


def ico(path, sizes):
    # Tiny sizes get less padding so the mark stays legible.
    imgs = [mark(n, pad_ratio=0.0 if n <= 24 else 0.04) for n in sizes]
    imgs[-1].save(path, format="ICO", sizes=[(n, n) for n in sizes],
                  append_images=imgs[:-1])


def main():
    ico("res/icon.ico", [16, 24, 32, 48, 64, 128, 256])
    ico("res/tray-icon.ico", [16, 20, 24, 32, 48])
    ico("flutter/windows/runner/resources/app_icon.ico", [16, 24, 32, 48, 64, 128, 256])
    mark(1024).save("res/icon.png")
    # *png is gitignored; add these two with `git add -f`.
    mark(512).save("flutter/assets/icon.png")
    mark(240).save("flutter/assets/logo.png")
    mark(1024).save("res/beam/beam-mark-1024.png")


if __name__ == "__main__":
    main()
