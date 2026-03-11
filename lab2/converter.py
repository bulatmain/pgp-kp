#!/usr/bin/env python3
import argparse
import struct
from PIL import Image

Image.MAX_IMAGE_PIXELS = None


def bin_to_png(src, dst):
    with open(src, "rb") as f:
        w, h = struct.unpack("<ii", f.read(8))
        rgba = f.read(w * h * 4)
    # In lab2 alpha is not used; many outputs contain a=0, which makes PNG fully transparent.
    # Export as RGB to keep the image visible in standard viewers.
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
    p = argparse.ArgumentParser(description="lab2 image converter: bin <-> png")
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--reverse", action="store_true", help="png -> bin (default: bin -> png)")
    a = p.parse_args()
    (png_to_bin if a.reverse else bin_to_png)(a.input, a.output)


if __name__ == "__main__":
    main()
