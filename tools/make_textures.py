"""Flat tileable wall textures. The image model keeps turning these into scenes."""
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures"
SIZE = 512


def hash_noise(x: int, y: int) -> float:
    v = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return (v & 255) / 255.0


def clamp(value: int) -> int:
    return max(0, min(255, value))


def make_bricks() -> Image.Image:
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    brick_w, brick_h, mortar = 68, 30, 6
    period_x = brick_w + mortar
    period_y = brick_h + mortar
    for y in range(SIZE):
        row = y // period_y
        y_in = y % period_y
        shift = period_x // 2 if row % 2 else 0
        for x in range(SIZE):
            if y_in >= brick_h:
                shade = int(42 + hash_noise(x, y) * 18)
                pixels[x, y] = (shade, shade - 8, shade - 12)
                continue
            x_in = (x + shift) % period_x
            if x_in >= brick_w:
                shade = int(42 + hash_noise(x, y) * 18)
                pixels[x, y] = (shade, shade - 8, shade - 12)
                continue
            col = (x + shift) // period_x
            tone = hash_noise(col * 13, row * 29)
            red = int(118 + tone * 55)
            green = int(38 + tone * 22)
            blue = int(32 + tone * 12)
            grit = int((hash_noise(x, y) - 0.5) * 28)
            edge = min(x_in, brick_w - 1 - x_in, y_in, brick_h - 1 - y_in)
            if edge < 2:
                pixels[x, y] = (16, 10, 8)
            else:
                if edge < 5:
                    red = int(red * 0.62)
                    green = int(green * 0.62)
                    blue = int(blue * 0.62)
                stain = hash_noise(x // 3, y // 3)
                if stain > 0.86:
                    red = int(red * 0.55)
                    green = int(green * 0.7)
                    blue = int(blue * 0.5)
                pixels[x, y] = (clamp(red + grit), clamp(green + grit // 2), clamp(blue + grit // 3))
    return image


def make_planks() -> Image.Image:
    image = Image.new("RGB", (SIZE, SIZE))
    pixels = image.load()
    board_h, gap = 58, 6
    period = board_h + gap
    for y in range(SIZE):
        row = y // period
        y_in = y % period
        tone = 0.35 + hash_noise(3, row * 17) * 0.3
        for x in range(SIZE):
            if y_in >= board_h:
                pixels[x, y] = (22, 14, 9)
                continue
            if y_in < 3 or y_in > board_h - 4:
                pixels[x, y] = (18, 12, 8)
                continue
            grain = hash_noise(x // 8, row * 5 + y_in // 6)
            wave = hash_noise(x // 24, row)
            red = int(92 + tone * 70 + (grain - 0.5) * 24)
            green = int(58 + tone * 36 + (grain - 0.5) * 14)
            blue = int(34 + tone * 16)
            if abs((y_in / board_h) - (0.25 + wave * 0.5)) < 0.035:
                red = int(red * 0.45)
                green = int(green * 0.45)
                blue = int(blue * 0.45)
            if y_in % 9 == 0:
                red = int(red * 0.8)
                green = int(green * 0.8)
                blue = int(blue * 0.8)
            nail = (x % period > period - 18 or x % period < 14) and 20 < y_in < 38 and abs((x % 16) - 8) < 3 and abs(y_in - 29) < 3
            if nail:
                pixels[x, y] = (28, 24, 20)
            else:
                pixels[x, y] = (clamp(red), clamp(green), clamp(blue))
    return image


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    bricks = make_bricks()
    planks = make_planks()
    bricks.save(OUT / "brick.png")
    planks.save(OUT / "planks.png")
    print("saved=brick.png")
    print("saved=planks.png")


if __name__ == "__main__":
    main()
