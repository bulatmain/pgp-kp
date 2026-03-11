#!/usr/bin/env python3
import argparse
import random


def main():
    p = argparse.ArgumentParser(description="Generate a diagonally-dominant SLAU case for lab4")
    p.add_argument("--n", type=int, required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--seed", type=int, default=42)
    args = p.parse_args()

    n = args.n
    if n <= 0:
        raise SystemExit("n must be positive")

    random.seed(args.seed)

    a = [[0.0] * n for _ in range(n)]
    x_true = [float(i + 1) for i in range(n)]

    for i in range(n):
        row_sum = 0.0
        for j in range(n):
            if i == j:
                continue
            v = random.uniform(-3.0, 3.0)
            a[i][j] = v
            row_sum += abs(v)
        a[i][i] = row_sum + random.uniform(1.0, 3.0)

    b = [sum(a[i][j] * x_true[j] for j in range(n)) for i in range(n)]

    with open(args.output, "w", encoding="utf-8") as f:
        f.write(f"{n}\n")
        for i in range(n):
            f.write(" ".join(f"{a[i][j]:.10e}" for j in range(n)) + "\n")
        f.write(" ".join(f"{v:.10e}" for v in b) + "\n")


if __name__ == "__main__":
    main()
