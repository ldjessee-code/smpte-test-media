#!/usr/bin/env python3
"""
SMPTE Test Media — seeded random-noise generator (optional companion to shell scripts).

Purpose
-------
The bash scripts use FFmpeg's random() for stress frames — non-deterministic across runs.
This script writes PNG frame sequences from a fixed --seed so A/B encoder comparisons
are bit-identical on the luma/chroma values.

Requirements
------------
- Python 3.9+ (stdlib only — no pip packages)
- FFmpeg (optional): encodes PNG sequences to H.264 and builds 120 s loops

Usage
-----
  python3 generate_test_media.py --output ./output --seed 42

Reads test-media.conf when present (OUTPUT_DIR_PYTHON or OUTPUT_DIR_H264).
Copy test-media.conf.example → test-media.conf to set defaults.

For the full suite (SMPTE bars, pan, zoom, tones), run:
  ./generate_test_media.sh
"""

from __future__ import annotations

import argparse
import re
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

_REPO_ROOT = Path(__file__).resolve().parent
_CONFIG_FILE = _REPO_ROOT / "test-media.conf"


def load_config() -> dict[str, str]:
    """Parse test-media.conf (KEY=value, # comments). Returns upper-case keys."""
    cfg: dict[str, str] = {}
    if not _CONFIG_FILE.is_file():
        return cfg
    for line in _CONFIG_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", line)
        if not m:
            continue
        key, raw = m.group(1), m.group(2).strip()
        if (raw.startswith('"') and raw.endswith('"')) or (
            raw.startswith("'") and raw.endswith("'")
        ):
            raw = raw[1:-1]
        cfg[key.upper()] = raw
    return cfg

# Match shell script defaults
FPS = 30
LOOP_FRAMES = 30
HD_W, HD_H = 1920, 1080


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    """Build one PNG chunk with CRC."""
    crc = zlib.crc32(tag + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)


def write_grayscale_png(path: Path, width: int, height: int, samples: bytes) -> None:
    """Write 8-bit grayscale PNG (stress: B&W random noise)."""
    if len(samples) != width * height:
        raise ValueError("sample count mismatch")
    raw = b"".join(b"\x00" + samples[y * width : (y + 1) * width] for y in range(height))
    compressed = zlib.compress(raw, 9)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += _png_chunk(b"IHDR", ihdr)
    png += _png_chunk(b"IDAT", compressed)
    png += _png_chunk(b"IEND", b"")
    path.write_bytes(png)


def write_rgb_png(path: Path, width: int, height: int, rgb: bytes) -> None:
    """Write 8-bit RGB PNG (stress: full-color random noise)."""
    if len(rgb) != width * height * 3:
        raise ValueError("rgb byte count mismatch")
    raw = b"".join(b"\x00" + rgb[y * width * 3 : (y + 1) * width * 3] for y in range(height))
    compressed = zlib.compress(raw, 9)
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n"
    png += _png_chunk(b"IHDR", ihdr)
    png += _png_chunk(b"IDAT", compressed)
    png += _png_chunk(b"IEND", b"")
    path.write_bytes(png)


def generate_noise_sequence(
    out_dir: Path,
    prefix: str,
    color: bool,
    frames: int,
    seed: int,
) -> Path:
    """Emit frame_XXXX.png sequence; return sequence directory path."""
    import random

    seq_dir = out_dir / f"{prefix}_seed{seed}"
    seq_dir.mkdir(parents=True, exist_ok=True)
    rng = random.Random(seed)

    for i in range(frames):
        if color:
            rgb = bytes(rng.randint(0, 255) for _ in range(HD_W * HD_H * 3))
            write_rgb_png(seq_dir / f"frame_{i:04d}.png", HD_W, HD_H, rgb)
        else:
            lum = bytes(rng.randint(0, 255) for _ in range(HD_W * HD_H))
            write_grayscale_png(seq_dir / f"frame_{i:04d}.png", HD_W, HD_H, lum)

    return seq_dir


def encode_png_sequence(seq_dir: Path, out_mp4: Path, fps: int) -> bool:
    """Mux PNG sequence to H.264 MP4 via FFmpeg."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        print("ffmpeg not found — PNG sequences written only", file=sys.stderr)
        return False

    pattern = str(seq_dir / "frame_%04d.png")
    cmd = [
        ffmpeg,
        "-hide_banner", "-loglevel", "warning", "-y",
        "-framerate", str(fps),
        "-i", pattern,
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-preset", "medium", "-crf", "18",
        "-movflags", "+faststart",
        str(out_mp4),
    ]
    subprocess.run(cmd, check=True)
    return True


def loop_to_long(src: Path, dest: Path, seconds: int = 120) -> bool:
    """stream_loop copy to extend a short clip without re-encoding."""
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        return False
    subprocess.run(
        [
            ffmpeg, "-hide_banner", "-loglevel", "warning", "-y",
            "-stream_loop", "-1", "-i", str(src),
            "-t", str(seconds), "-c", "copy", str(dest),
        ],
        check=True,
    )
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate seeded stress-pattern PNG sequences (deterministic noise)"
    )
    cfg = load_config()
    default_out = cfg.get("OUTPUT_DIR_PYTHON") or cfg.get("OUTPUT_DIR_H264") or "output"
    default_path = Path(default_out)
    if not default_path.is_absolute():
        default_path = _REPO_ROOT / default_path

    parser.add_argument(
        "--output", type=Path,
        default=default_path,
        help="Output root directory (default: from test-media.conf or ./output)",
    )
    parser.add_argument("--seed", type=int, default=42, help="RNG seed for reproducible noise")
    parser.add_argument("--frames", type=int, default=LOOP_FRAMES, help="Frames per sequence")
    parser.add_argument("--fps", type=int, default=FPS, help="Frame rate when encoding to MP4")
    args = parser.parse_args()

    stress_dir = args.output / "stress"
    long_dir = args.output / "long"
    stress_dir.mkdir(parents=True, exist_ok=True)
    long_dir.mkdir(parents=True, exist_ok=True)

    print(f"==> Seeded B&W noise ({args.frames} frames, seed={args.seed})")
    bw_dir = generate_noise_sequence(
        stress_dir, "static_bw_noise_png", False, args.frames, args.seed
    )
    bw_mp4 = stress_dir / f"static_bw_noise_{args.frames}f_seed{args.seed}.mp4"
    if encode_png_sequence(bw_dir, bw_mp4, args.fps):
        loop_to_long(bw_mp4, long_dir / f"static_bw_noise_seed{args.seed}_loop_120s.mp4")

    print(f"==> Seeded color noise ({args.frames} frames, seed={args.seed})")
    color_dir = generate_noise_sequence(
        stress_dir, "static_color_noise_png", True, args.frames, args.seed
    )
    color_mp4 = stress_dir / f"static_color_noise_{args.frames}f_seed{args.seed}.mp4"
    if encode_png_sequence(color_dir, color_mp4, args.fps):
        loop_to_long(color_mp4, long_dir / f"static_color_noise_seed{args.seed}_loop_120s.mp4")

    print(f"\nDone. Output: {args.output}")
    print("For full suite (bars, pan, zoom, tones), run: ./generate_test_media.sh")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())