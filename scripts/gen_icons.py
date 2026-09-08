#!/usr/bin/env python3
"""Generate PNG and ICO icons for the PWA manifest."""
import os
import math
from PIL import Image, ImageDraw

STATIC_DIR = "static"
SUPERSAMPLE = 4


def star_points(cx, cy, outer, inner, points=5):
    out = []
    for i in range(points * 2):
        angle = -math.pi / 2 + i * math.pi / points
        radius = outer if i % 2 == 0 else inner
        out.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return out


def cubic(p0, p1, p2, p3, steps=24):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def rounded_line(draw, points, fill, width):
    draw.line(points, fill=fill, width=width, joint="curve")
    radius = width / 2
    for x, y in (points[0], points[-1]):
        draw.ellipse([x - radius, y - radius, x + radius, y + radius], fill=fill)


def composite_shape(base, draw_fn):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    base.alpha_composite(layer)


def draw_base_icon(size, maskable=False):
    """Draw the BookStark icon without external rendering dependencies."""
    canvas_size = size * SUPERSAMPLE
    img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    pad = int(canvas_size * 0.08) if maskable else 0
    rect = [pad, pad, canvas_size - pad, canvas_size - pad]
    radius = int(canvas_size * (0.22 if maskable else 0.1875))

    # Polished blue background with a subtle top-left highlight.
    gradient = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(gradient)
    stops = [(15, 79, 214), (35, 104, 234), (56, 163, 245)]
    for y in range(canvas_size):
        t = y / max(canvas_size - 1, 1)
        if t < 0.58:
            local = t / 0.58
            a, b = stops[0], stops[1]
        else:
            local = (t - 0.58) / 0.42
            a, b = stops[1], stops[2]
        color = tuple(int(a[i] * (1 - local) + b[i] * local) for i in range(3)) + (255,)
        gdraw.line([(0, y), (canvas_size, y)], fill=color)

    mask = Image.new("L", (canvas_size, canvas_size), 0)
    mdraw = ImageDraw.Draw(mask)
    mdraw.rounded_rectangle(rect, radius=radius, fill=255)
    img.alpha_composite(Image.composite(gradient, Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0)), mask))

    glow = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.ellipse(
        [int(canvas_size * -0.28), int(canvas_size * -0.36), int(canvas_size * 0.95), int(canvas_size * 0.82)],
        fill=(255, 255, 255, 38),
    )
    img.alpha_composite(Image.composite(glow, Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0)), mask))

    content_pad = pad
    content_size = canvas_size - pad * 2

    def xy(x, y, dx=0, dy=0):
        return (
            content_pad + (x * content_size / 512) + dx,
            content_pad + (y * content_size / 512) + dy,
        )

    def pts(items, dx=0, dy=0):
        return [xy(x, y, dx=dx, dy=dy) for x, y in items]

    def w(value):
        return max(1, int(value * content_size / 512))

    left_top = cubic((256, 150), (216, 126), (155, 124), (96, 144))
    left_bottom = cubic((96, 384), (158, 374), (216, 388), (256, 416))
    left_page = pts(left_top + [(96, 384)] + left_bottom[1:] + [(256, 150)])
    right_top = cubic((256, 150), (296, 126), (357, 124), (416, 144))
    right_bottom = cubic((416, 384), (354, 374), (296, 388), (256, 416))
    right_page = pts(right_top + [(416, 384)] + right_bottom[1:] + [(256, 150)])

    shadow_offset = w(12)
    composite_shape(img, lambda d: d.polygon([(x, y + shadow_offset) for x, y in left_page], fill=(15, 23, 42, 52)))
    composite_shape(img, lambda d: d.polygon([(x, y + shadow_offset) for x, y in right_page], fill=(15, 23, 42, 52)))
    draw.polygon(left_page, fill=(252, 254, 255, 255))
    draw.polygon(right_page, fill=(244, 250, 255, 255))
    draw.line(pts([(256, 150), (256, 416)]), fill=(15, 63, 189, 255), width=w(9))

    for page in (left_page, right_page):
        draw.line(page + [page[0]], fill=(15, 63, 189, 255), width=w(10), joint="curve")

    for x1, y, x2, alpha in [
        (132, 200, 228, 184), (132, 244, 228, 184), (132, 288, 220, 184),
    ]:
        line = cubic((x1, y), (164, y - 10), (198, y - 7), (x2, y + 6), steps=12)
        rounded_line(draw, pts(line), fill=(15, 79, 214, 255), width=w(13))

    for x1, y1, x2, y2, alpha in [
        (284, 206, 380, 200, 184), (284, 250, 380, 244, 184),
        (292, 294, 380, 288, 184),
    ]:
        line = cubic((x1, y1), (314, y1 - 13), (348, y2 - 10), (x2, y2), steps=12)
        rounded_line(draw, pts(line), fill=(15, 79, 214, 255), width=w(13))

    star = pts(star_points(378, 105, 49, 22))
    composite_shape(img, lambda d: d.polygon([(x, y + w(5)) for x, y in star], fill=(120, 53, 15, 72)))
    draw.polygon(star, fill=(251, 191, 36, 255))
    draw.line(star + [star[0]], fill=(253, 230, 138, 255), width=w(5), joint="curve")

    # App icons should be opaque inside the rounded square. Keep transparency only outside the icon shape.
    img.putalpha(mask)

    if size != canvas_size:
        resample = Image.Resampling.LANCZOS if hasattr(Image, "Resampling") else Image.LANCZOS
        img = img.resize((size, size), resample)
    return img


def save_png(name, size, maskable=False):
    out = os.path.join(STATIC_DIR, name)
    draw_base_icon(size, maskable=maskable).save(out, "PNG")
    print(f"  {out} ({size}x{size})")


def main():
    for size, name in [(512, "icon-512.png"), (192, "icon-192.png"), (180, "apple-touch-icon.png")]:
        save_png(name, size)
    for size, name in [(512, "icon-maskable-512.png"), (192, "icon-maskable-192.png")]:
        save_png(name, size, maskable=True)
    for name in [
        "shortcut-search-192.png",
        "shortcut-books-192.png",
        "shortcut-notes-192.png",
        "shortcut-bookmarks-192.png",
    ]:
        save_png(name, 192)

    sizes = [16, 32, 48]
    ico_path = os.path.join(STATIC_DIR, "favicon.ico")
    draw_base_icon(max(sizes)).save(ico_path, format="ICO", sizes=[(s, s) for s in sizes])
    print(f"  {ico_path} (16+32+48)")


if __name__ == "__main__":
    main()
