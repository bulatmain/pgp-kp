#!/usr/bin/env python3
import argparse
import random
import struct


def build_values(n: int, mode: str, seed: int, value: int) -> bytes:
    rng = random.Random(seed)

    if mode == "random":
        data = [rng.randrange(0, 256) for _ in range(n)]
    elif mode == "reverse":
        data = [(255 - (i % 256)) for i in range(n)]
    elif mode == "sorted":
        data = [(i % 256) for i in range(n)]
    elif mode == "constant":
        data = [value for _ in range(n)]
    else:
        raise ValueError("unsupported mode")

    return bytes(data)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate binary test for lab5: [int32 n][n x uchar]."
    )
    parser.add_argument("-n", type=int, help="array length")
    parser.add_argument("--output", help="output binary file")
    parser.add_argument("--mode", choices=["random", "reverse", "sorted", "constant"], default="random")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--value", type=int, default=7, help="value for --mode constant")
    args = parser.parse_args()

    if args.n < 0:
        raise SystemExit("n must be >= 0")
    if not (0 <= args.value <= 255):
        raise SystemExit("--value must be in [0, 255]")

    payload = build_values(args.n, args.mode, args.seed, args.value)

    with open(args.output, "wb") as f:
        f.write(struct.pack("<i", args.n))
        f.write(payload)


if __name__ == "__main__":
    main()
