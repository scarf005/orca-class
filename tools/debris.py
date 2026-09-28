"""Draws the debris sprites: flat pixel-art shards, several per material.

Run: uv run --with pillow tools/debris.py
Writes assets/debris/<material>_<n>.png (32x32, ink-rimmed). The game stacks them into one texture
array in the order of Fx.DEBRIS_MATERIALS, VARIANTS per material, so keep the two lists in sync.
"""

import math
import os
import random

from PIL import Image, ImageDraw

SIZE = 32
VARIANTS = 6
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "debris")

INK = (43, 33, 64)


def hexc(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def shade(color, k):
    """Lighter for k > 0, darker for k < 0."""
    if k >= 0:
        return tuple(int(c + (255 - c) * k) for c in color)
    return tuple(int(c * (1 + k)) for c in color)


def jagged(rng, cx, cy, rx, ry, points, rough=0.35, angle=0.0):
    """An irregular polygon around (cx, cy), stretched to rx by ry and turned by `angle`."""
    result = []
    for i in range(points):
        a = math.tau * i / points + rng.uniform(-0.25, 0.25)
        r = 1.0 - rng.uniform(0, rough)
        x, y = math.cos(a) * rx * r, math.sin(a) * ry * r
        result.append((cx + x * math.cos(angle) - y * math.sin(angle), cy + x * math.sin(angle) + y * math.cos(angle)))
    return result


def lit_fill(img, mask, base, light_dir=(-1, -1)):
    """Fills the mask with `base`, a bright rim toward the light and a dark rim away from it."""
    px, m = img.load(), mask.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if not m[x, y]:
                continue
            color = base
            lx, ly = x + light_dir[0], y + light_dir[1]
            dx, dy = x - light_dir[0], y - light_dir[1]
            if not (0 <= lx < SIZE and 0 <= ly < SIZE and m[lx, ly]):
                color = shade(base, 0.35)
            elif not (0 <= dx < SIZE and 0 <= dy < SIZE and m[dx, dy]):
                color = shade(base, -0.3)
            px[x, y] = color + (255,)


def outline(img):
    """A one-pixel ink rim around everything drawn."""
    px = img.load()
    solid = [[px[x, y][3] > 0 for x in range(SIZE)] for y in range(SIZE)]
    for y in range(SIZE):
        for x in range(SIZE):
            if solid[y][x]:
                continue
            if any(0 <= x + dx < SIZE and 0 <= y + dy < SIZE and solid[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = INK + (255,)


def polygon_sprite(rng, poly, base, img=None):
    img = img or Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new("1", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(poly, fill=1)
    lit_fill(img, mask, base)
    return img, mask


def inside(mask, x, y):
    return 0 <= x < SIZE and 0 <= y < SIZE and mask.getpixel((int(x), int(y)))


def speckle(img, mask, rng, color, count):
    px = img.load()
    for _ in range(count):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        if inside(mask, x, y):
            px[x, y] = color + (255,)


def wood(rng, i):
    base = hexc(rng.choice(["8a6a5a", "a07c5e", "6f5446", "b38b66"]))
    angle = rng.uniform(0, math.pi)
    length, width = rng.uniform(11, 14), rng.uniform(2.5, 4.5)
    # A splinter: long, narrow, pointed at both ends with torn edges.
    poly = []
    for k in range(9):
        t = k / 8
        x = (t * 2 - 1) * length
        w = width * math.sin(math.pi * t) ** 0.6 * rng.uniform(0.6, 1.2)
        poly.append((x, -w))
    for k in range(8, -1, -1):
        t = k / 8
        x = (t * 2 - 1) * length
        w = width * math.sin(math.pi * t) ** 0.6 * rng.uniform(0.6, 1.2)
        poly.append((x, w))
    c, s = math.cos(angle), math.sin(angle)
    poly = [(16 + x * c - y * s, 16 + x * s + y * c) for x, y in poly]
    img, mask = polygon_sprite(rng, poly, base)
    # Grain along the splinter.
    draw = ImageDraw.Draw(img)
    for g in (-1, 1):
        off = g * width * 0.35
        a = (16 - length * 0.8 * c - off * s, 16 - length * 0.8 * s + off * c)
        b = (16 + length * 0.8 * c - off * s, 16 + length * 0.8 * s + off * c)
        draw.line([a, b], fill=shade(base, -0.25) + (255,))
    outline(img)
    return img


def concrete(rng, i):
    base = hexc(rng.choice(["c8c2c0", "ddd3e3", "fbf3e4", "d9c9b0"]))
    img, mask = polygon_sprite(rng, jagged(rng, 16, 16, rng.uniform(9, 12), rng.uniform(7, 11), rng.randint(5, 7), 0.4, rng.uniform(0, 3)), base)
    speckle(img, mask, rng, shade(base, -0.2), 18)
    if i % 3 == 0:
        # A bent stub of rebar sticking out.
        draw = ImageDraw.Draw(img)
        x0, y0 = 16 + rng.uniform(-3, 3), 16 + rng.uniform(-3, 3)
        a = rng.uniform(0, math.tau)
        draw.line([(x0, y0), (x0 + math.cos(a) * 13, y0 + math.sin(a) * 13)], fill=hexc("7a4e3a") + (255,), width=2)
    outline(img)
    return img


def roof(rng, i):
    base = hexc(["9a9ee6", "f28a7a", "7fb7b8", "a8e0c8", "a7c8f0", "9c7aa8"][i % 6])
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new("1", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(mask)
    # A curved roof tile or a bent strip of corrugated tin: a thick arc.
    r = rng.uniform(10, 14)
    start = rng.uniform(0, 360)
    draw.arc([16 - r, 16 - r + 4, 16 + r, 16 + r + 4], start, start + rng.uniform(80, 130), fill=1, width=rng.randint(5, 7))
    lit_fill(img, mask, base)
    if i % 2:
        speckle(img, mask, rng, shade(base, -0.25), 14)
    outline(img)
    return img


def glass(rng, i):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    base = hexc(rng.choice(["a7c8f0", "a8e0c8", "ddd3e3"]))
    for _ in range(rng.randint(1, 2)):
        cx, cy = 16 + rng.uniform(-4, 4), 16 + rng.uniform(-4, 4)
        a = rng.uniform(0, math.tau)
        poly = [(cx + math.cos(a + k * 2.2 + rng.uniform(-0.4, 0.4)) * rng.uniform(6, 13), cy + math.sin(a + k * 2.2 + rng.uniform(-0.4, 0.4)) * rng.uniform(6, 13)) for k in range(3)]
        polygon_sprite(rng, poly, base, img)
    px = img.load()
    # Glass is see-through (dithered) with a white glint line.
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (r, g, b, 190)
    draw = ImageDraw.Draw(img)
    gx = rng.uniform(10, 18)
    draw.line([(gx, 10), (gx + 5, 16)], fill=(255, 250, 245, 255))
    outline(img)
    return img


def metal(rng, i):
    base = hexc(rng.choice(["8d8792", "5d6a82", "aaa3b3", "4a3b63"]))
    img, mask = polygon_sprite(rng, jagged(rng, 16, 16, rng.uniform(10, 13), rng.uniform(5, 9), rng.randint(4, 6), 0.25, rng.uniform(0, 3)), base)
    draw = ImageDraw.Draw(img)
    # A bright bend line and rivets.
    a = rng.uniform(0, math.pi)
    draw.line([(16 - math.cos(a) * 9, 16 - math.sin(a) * 9), (16 + math.cos(a) * 9, 16 + math.sin(a) * 9)], fill=shade(base, 0.45) + (255,))
    px = img.load()
    for _ in range(4):
        x, y = rng.randrange(8, 24), rng.randrange(8, 24)
        if inside(mask, x, y):
            px[x, y] = shade(base, -0.45) + (255,)
    outline(img)
    return img


def paint(rng, i):
    base = hexc(["a7c8f0", "f2b8c6", "f6e6a0", "ddd3e3", "a8e0c8", "e0506a"][i % 6])
    img, mask = polygon_sprite(rng, jagged(rng, 16, 16, rng.uniform(10, 13), rng.uniform(6, 10), rng.randint(4, 6), 0.3, rng.uniform(0, 3)), base)
    draw = ImageDraw.Draw(img)
    # Glossy paint catches a white streak; the torn edge shows bare grey metal.
    draw.line([(10, 12), (15, 9)], fill=(255, 250, 245, 255), width=2)
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if mask.getpixel((x, y)) and not inside(mask, x + 2, y + 2):
                px[x, y] = hexc("8d8792") + (255,)
    outline(img)
    return img


def armor(rng, i):
    base = hexc(rng.choice(["9aa58e", "5f7f63", "3f5a4f", "5d6a82"]))
    img, mask = polygon_sprite(rng, jagged(rng, 16, 16, rng.uniform(9, 12), rng.uniform(8, 11), rng.randint(4, 5), 0.2, rng.uniform(0, 3)), base)
    px = img.load()
    if i % 3 == 0:
        # A hazard stripe in the enemy's hot red.
        for y in range(SIZE):
            for x in range(SIZE):
                if mask.getpixel((x, y)) and (x + y) // 3 % 2 == 0 and 12 < y < 20:
                    px[x, y] = hexc("e0506a") + (255,)
    for _ in range(5):
        x, y = rng.randrange(8, 24), rng.randrange(8, 24)
        if inside(mask, x, y):
            px[x, y] = shade(base, 0.5) + (255,)
    outline(img)
    return img


def vinyl(rng, i):
    base = hexc(rng.choice(["fffaf5", "fbf3e4", "ddd3e3"]))
    img, mask = polygon_sprite(rng, jagged(rng, 16, 16, rng.uniform(11, 14), rng.uniform(8, 12), rng.randint(7, 9), 0.5, rng.uniform(0, 3)), base)
    folds = Image.new("1", (SIZE, SIZE), 0)
    for _ in range(3):
        x0, y0 = rng.uniform(6, 26), rng.uniform(6, 26)
        ImageDraw.Draw(folds).line([(x0, y0), (x0 + rng.uniform(-8, 8), y0 + rng.uniform(-8, 8))], fill=1)
    px = img.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if folds.getpixel((x, y)) and mask.getpixel((x, y)):
                px[x, y] = shade(base, -0.18) + (255,)
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = px[x, y]
            if a:
                px[x, y] = (r, g, b, 200)
    outline(img)
    return img


def flesh(rng, i):
    base = hexc(rng.choice(["ff8fb8", "f2b8c6", "c3a6e8", "9c7aa8"]))
    img, mask = polygon_sprite(rng, jagged(rng, 16, 16, rng.uniform(8, 12), rng.uniform(7, 11), rng.randint(8, 11), 0.25), base)
    draw = ImageDraw.Draw(img)
    # Weeping pustules: dark rings with a bright wet core.
    for _ in range(rng.randint(2, 4)):
        x, y = rng.uniform(9, 23), rng.uniform(9, 23)
        if inside(mask, x, y):
            r = rng.uniform(1.5, 3)
            draw.ellipse([x - r, y - r, x + r, y + r], fill=shade(base, -0.35) + (255,))
            draw.point((x - 0.5, y - 0.5), fill=hexc("fbf3e4") + (255,))
    outline(img)
    return img


def spore(rng, i):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    base = hexc(["ff8fb8", "f2b8c6", "c3a6e8", "fbf3e4", "f6e6a0", "ff8fb8"][i % 6])
    draw = ImageDraw.Draw(img)
    for _ in range(rng.randint(2, 4)):
        x, y, r = 16 + rng.uniform(-5, 5), 16 + rng.uniform(-5, 5), rng.uniform(3, 6)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=base + (255,))
        draw.ellipse([x - r * 0.4 - 1, y - r * 0.4 - 1, x - r * 0.4 + 1, y - r * 0.4 + 1], fill=shade(base, 0.5) + (255,))
    outline(img)
    return img


def foliage(rng, i):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    base = hexc(["b5d19a", "8fae8b", "5f7f63", "f7c59f", "ffb01f", "b5d19a"][i % 6])
    for _ in range(rng.randint(1, 3)):
        a = rng.uniform(0, math.pi)
        cx, cy = 16 + rng.uniform(-4, 4), 16 + rng.uniform(-4, 4)
        leaf = []
        for k in range(12):
            t = k / 11
            x = (t * 2 - 1) * 9
            leaf.append((x, -math.sin(math.pi * t) * 4))
        leaf += [(x, -y) for x, y in reversed(leaf)]
        c, s = math.cos(a), math.sin(a)
        poly = [(cx + x * c - y * s, cy + x * s + y * c) for x, y in leaf]
        polygon_sprite(rng, poly, base, img)
        ImageDraw.Draw(img).line([(cx - 8 * c, cy - 8 * s), (cx + 8 * c, cy + 8 * s)], fill=shade(base, -0.3) + (255,))
    outline(img)
    return img


def straw(rng, i):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    a = rng.uniform(0, math.pi)
    for _ in range(rng.randint(4, 7)):
        b = a + rng.uniform(-0.35, 0.35)
        cx, cy, length = 16 + rng.uniform(-4, 4), 16 + rng.uniform(-4, 4), rng.uniform(8, 13)
        color = hexc(rng.choice(["e0cf8a", "f6e6a0", "c79a6b"]))
        draw.line([(cx - math.cos(b) * length, cy - math.sin(b) * length), (cx + math.cos(b) * length, cy + math.sin(b) * length)], fill=color + (255,), width=2)
    outline(img)
    return img


def ceramic(rng, i):
    # Broken onggi from the soy-sauce jars: glazed dark brown outside, a paler clay edge.
    base = hexc(rng.choice(["6f4a3a", "5a3a2e", "7d5746"]))
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new("1", (SIZE, SIZE), 0)
    r = rng.uniform(11, 14)
    start = rng.uniform(0, 360)
    ImageDraw.Draw(mask).chord([16 - r, 16 - r, 16 + r, 16 + r], start, start + rng.uniform(90, 150), fill=1)
    lit_fill(img, mask, base)
    draw = ImageDraw.Draw(img)
    draw.arc([16 - r + 3, 16 - r + 3, 16 + r - 3, 16 + r - 3], start + 20, start + 60, fill=shade(base, 0.6) + (255,))
    outline(img)
    return img


def rock(rng, i):
    base = hexc(rng.choice(["8d8792", "aaa3b3", "c8c2c0", "5d6a82"]))
    img, mask = polygon_sprite(rng, jagged(rng, 16, 16, rng.uniform(8, 11), rng.uniform(8, 11), rng.randint(5, 6), 0.3, rng.uniform(0, 3)), base)
    # A facet: one side of the chunk in shadow.
    px = img.load()
    a = rng.uniform(0, math.tau)
    for y in range(SIZE):
        for x in range(SIZE):
            if mask.getpixel((x, y)) and (x - 16) * math.cos(a) + (y - 16) * math.sin(a) > 2:
                px[x, y] = shade(base, -0.25) + (255,)
    speckle(img, mask, rng, shade(base, 0.3), 8)
    outline(img)
    return img


def brass(rng, i):
    # A spent casing: a small golden tube with a darker rim.
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    a = rng.uniform(0, math.pi)
    length, width = rng.uniform(6, 9), rng.uniform(2.5, 3.5)
    c, s = math.cos(a), math.sin(a)
    corners = [(-length, -width), (length, -width), (length, width), (-length, width)]
    poly = [(16 + x * c - y * s, 16 + x * s + y * c) for x, y in corners]
    polygon_sprite(rng, poly, hexc("ffb01f"), img)
    draw = ImageDraw.Draw(img)
    draw.line([(16 - length * c - width * s, 16 - length * s + width * c), (16 - length * c + width * s, 16 - length * s - width * c)], fill=hexc("c79a6b") + (255,), width=2)
    outline(img)
    return img


def dirt(rng, i):
    base = hexc(rng.choice(["c79a6b", "8a6a5a", "a07c5e"]))
    img, mask = polygon_sprite(rng, jagged(rng, 16, 16, rng.uniform(6, 10), rng.uniform(6, 9), rng.randint(7, 9), 0.45), base)
    speckle(img, mask, rng, hexc("8d8792"), 10)
    speckle(img, mask, rng, shade(base, 0.3), 8)
    outline(img)
    return img


MATERIALS = [
    ("wood", wood), ("concrete", concrete), ("roof", roof), ("glass", glass), ("metal", metal), ("paint", paint),
    ("armor", armor), ("vinyl", vinyl), ("flesh", flesh), ("spore", spore), ("foliage", foliage), ("straw", straw),
    ("ceramic", ceramic), ("rock", rock), ("brass", brass), ("dirt", dirt),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    for index, (name, draw) in enumerate(MATERIALS):
        for i in range(VARIANTS):
            rng = random.Random(index * 100 + i)
            draw(rng, i).save(os.path.join(OUT, f"{name}_{i}.png"))
    print(f"{len(MATERIALS) * VARIANTS} sprites in {OUT}")


if __name__ == "__main__":
    main()
