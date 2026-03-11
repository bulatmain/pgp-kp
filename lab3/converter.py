#!/usr/bin/env python3
import argparse
import struct
from PIL import Image

Image.MAX_IMAGE_PIXELS = None


def bin_to_png(src, dst, alpha_map=False):
    with open(src, "rb") as f:
        w, h = struct.unpack("<ii", f.read(8))
        rgba = f.read(w * h * 4)

    if alpha_map:
        a = bytearray(w * h)
        j = 0
        for i in range(3, len(rgba), 4):
            a[j] = rgba[i]
            j += 1
        # Class ids in alpha are usually small (0..N-1). Stretch them to 0..255
        # so class maps are visible in ordinary image viewers.
        max_a = max(a) if a else 0
        if max_a < 255:
            den = max_a + 1
            for i in range(len(a)):
                a[i] = ((a[i] + 1) * 255) // den
        Image.frombytes("L", (w, h), bytes(a)).save(dst, compress_level=9)
        return

    rgb = bytearray(w * h * 3)
    j = 0
    for i in range(0, len(rgba), 4):
        rgb[j] = rgba[i]
        rgb[j + 1] = rgba[i + 1]
        rgb[j + 2] = rgba[i + 2]
        j += 3
    Image.frombytes("RGB", (w, h), bytes(rgb)).save(dst, compress_level=9)


def png_to_bin(src, dst):
    img = Image.open(src).convert("RGBA")
    w, h = img.size
    with open(dst, "wb") as f:
        f.write(struct.pack("<ii", w, h))
        f.write(img.tobytes())


def main():
    p = argparse.ArgumentParser(description="lab3 image converter: bin <-> png")
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--reverse", action="store_true", help="png -> bin (default: bin -> png)")
    p.add_argument("--alpha-map", action="store_true", help="when bin->png, render alpha channel as grayscale")
    a = p.parse_args()
    if a.reverse:
        png_to_bin(a.input, a.output)
    else:
        bin_to_png(a.input, a.output, a.alpha_map)


if __name__ == "__main__":
    main()
