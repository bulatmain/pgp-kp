#!/usr/bin/env python3
from pathlib import Path


def make_config(frames: int, out_pattern: str, width: int, height: int, ssaa_sqrt: int) -> str:
    # Orbit params (camera + target)
    cam = {
        "baseR": 8.0,
        "baseZ": 3.2,
        "basePhi": 0.0,
        "ampR": 1.2,
        "ampZ": 0.6,
        "omegaR": 2.0,
        "omegaZ": 3.0,
        "omegaPhi": 1.0,
        "phaseR": 0.0,
        "phaseZ": 0.0,
    }
    target = {
        "baseR": 0.0,
        "baseZ": 0.8,
        "basePhi": 0.0,
        "ampR": 0.4,
        "ampZ": 0.3,
        "omegaR": 1.0,
        "omegaZ": 2.0,
        "omegaPhi": 0.5,
        "phaseR": 0.0,
        "phaseZ": 0.0,
    }

    # Bodies: tetrahedron, hexahedron, icosahedron
    bodies = [
        (-2.0, -0.6, 0.8, 1.0, 0.2, 0.2, 1.0, 0.0, 0.0, 0),
        (0.2, 1.1, 1.0, 0.1, 0.9, 0.2, 1.2, 0.0, 0.0, 0),
        (2.0, -0.8, 1.1, 0.2, 0.5, 1.0, 1.3, 0.0, 0.0, 0),
    ]

    lines = []
    lines.append(str(frames))
    lines.append(out_pattern)
    lines.append(f"{width} {height} 75")

    for o in (cam, target):
        lines.append(f"{o['baseR']} {o['baseZ']} {o['basePhi']}")
        lines.append(f"{o['ampR']} {o['ampZ']}")
        lines.append(f"{o['omegaR']} {o['omegaZ']} {o['omegaPhi']}")
        lines.append(f"{o['phaseR']} {o['phaseZ']}")

    for b in bodies:
        cx, cy, cz, cr, cg, cb, radius, refl, transp, loe = b
        lines.append(f"{cx} {cy} {cz}")
        lines.append(f"{cr} {cg} {cb}")
        lines.append(f"{radius} {refl} {transp} {loe}")

    # Floor
    lines.append("-6.0 -6.0 -1.0")
    lines.append("-6.0 6.0 -1.0")
    lines.append("6.0 6.0 -1.0")
    lines.append("6.0 -6.0 -1.0")
    lines.append("-")
    lines.append("0.8 0.8 0.85 0.0")

    # Lights (max 4 by task; project uses first light)
    lines.append("1")
    lines.append("-2.0 -1.0 7.0")
    lines.append("1.0 1.0 1.0")

    # maxDepth ssaaSqrt
    lines.append(f"1 {ssaa_sqrt}")

    return "\n".join(lines) + "\n"


def main() -> None:
    root = Path(__file__).resolve().parent
    cases = root / "cases"
    cases.mkdir(parents=True, exist_ok=True)

    perf = [
        ("perf_640x480_ssaa1", 16, 640, 480, 1),
        ("perf_640x480_ssaa2", 16, 640, 480, 2),
        ("perf_960x540_ssaa1", 16, 960, 540, 1),
        ("perf_960x540_ssaa2", 16, 960, 540, 2),
        ("perf_1280x720_ssaa1", 16, 1280, 720, 1),
        ("perf_1280x720_ssaa2", 16, 1280, 720, 2),
    ]

    profile = [
        ("profile_960x540_ssaa1", 1, 960, 540, 1),
    ]

    all_cases = perf + profile

    for name, frames, w, h, ssaa in all_cases:
        out_pattern = f"out/{name}_%04d.ppm"
        text = make_config(frames, out_pattern, w, h, ssaa)
        (cases / f"{name}.in").write_text(text, encoding="utf-8")

    print(f"generated {len(all_cases)} files in {cases}")


if __name__ == "__main__":
    main()
