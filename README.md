# SMPTE Test Media Generator
<img width="1580" height="565" alt="smpte_bars_image" src="https://github.com/user-attachments/assets/1f95da49-93f8-4553-a8b5-905a3afce17b" />

Generate **SMPTE color bars**, **line-up tones**, **motion loops**, and **encoder-stress patterns** for video QA — no external assets required. Built with [FFmpeg](https://ffmpeg.org/) `lavfi` filters.

Use cases:

- Calibrate displays and playback chains (HD/SD bars + PLUGE)
- Verify audio mux and tone level after recompression
- Stress-test encoders (random static, pan/zoom)
- Create **ProRes 422 HQ** reference masters for downscale / transcode A/B tests

Suitable for broadcast engineers, video developers, and anyone who needs repeatable encoder QA clips.

---

## Requirements

### Required

| Dependency | Purpose | Install |
|------------|---------|---------|
| **FFmpeg** ≥ 5.x | All generators; `smptebars`, `smptehdbars`, `sine`, motion filters | See [Install FFmpeg](#install-ffmpeg) |
| **libx264** | H.264 output (`generate_test_media.sh`) | Included in full FFmpeg builds |
| **libfdk_aac** or **native AAC** | AAC audio on toned H.264 clips | Included in most FFmpeg builds |

### ProRes script (`generate_test_media_prores_hd.sh`)

| Platform | Encoder | Notes |
|----------|---------|-------|
| **macOS** | `prores_videotoolbox` | **Recommended** — Apple ProRes 422 HQ via VideoToolbox |
| **Linux / Windows** | `prores_ks` | Software ProRes; random-noise stress may fall back to H.264 |

Verify encoders:

```bash
ffmpeg -encoders 2>/dev/null | grep -E 'libx264|prores'
```

### Optional

| Dependency | Purpose |
|------------|---------|
| **Python 3.9+** | `generate_test_media.py` — seeded, bit-identical random noise (stdlib only) |
| **bash**, **awk** | Shell scripts (standard on macOS/Linux) |

No pip packages, Node, or commercial plugins required.

---

## Install FFmpeg

**macOS (Homebrew):**

```bash
brew install ffmpeg
```

**Ubuntu / Debian:**

```bash
sudo apt update && sudo apt install ffmpeg
```

**Windows:**

Download from [ffmpeg.org](https://ffmpeg.org/download.html) or `winget install ffmpeg`.

---

## Configuration

Copy the example config and set output paths (and ProRes fallback behavior):

```bash
cp test-media.conf.example test-media.conf
```

| Setting | Purpose |
|---------|---------|
| `OUTPUT_DIR_H264` | Default output for `generate_test_media.sh` |
| `OUTPUT_DIR_PRORES` | Default output for `generate_test_media_prores_hd.sh` |
| `OUTPUT_DIR_HEVC` | Default output for `generate_test_media_hevc_hd.sh` (prototype) |
| `HEVC_CRF` | `libx265` quality (default `23`; lower = higher quality) |
| `HEVC_VT_QUALITY` | `hevc_videotoolbox` quality 0–100 on macOS (default `65`) |
| `OUTPUT_DIR_PYTHON` | Default output for `generate_test_media.py` (optional) |
| `PRORES_STRESS_H264_FALLBACK` | `auto` (default), `always`, or `never` — see [ProRes fallback](#prores-stress-fallback) |

`test-media.conf` is **gitignored** (local paths stay private). A command-line path still overrides the config:

```bash
./generate_test_media.sh /path/to/custom/output
```

---

## Quick start

```bash
git clone https://github.com/YOUR_USERNAME/smpte-test-media.git
cd smpte-test-media
chmod +x *.sh
cp test-media.conf.example test-media.conf   # optional
```

### H.264 suite (smaller files — simulates typical delivery)

```bash
./generate_test_media.sh
```

### HD ProRes 422 HQ (reference masters)

```bash
./generate_test_media_prores_hd.sh
```

On macOS you should see:

```
note: using prores_videotoolbox (Apple) for all clips
```

### HD HEVC / H.265 (prototype — untested)

```bash
./generate_test_media_hevc_hd.sh
```

Starting point for contributors. Prints a **PROTOTYPE / UNTESTED** warning; verify output in your players before relying on it.

### Seeded random noise (reproducible A/B)

```bash
python3 generate_test_media.py --output ./output --seed 42
```

---

## Output layout

### `generate_test_media.sh` → `output/` (default)

| Folder | Contents | Codec |
|--------|----------|-------|
| `calibration/` | SD + HD SMPTE bars; silent, 10 kHz, 7 kHz tone | H.264 + AAC |
| `motion/` | 30-frame pan H/V, zoom, testsrc2 scroll | H.264 |
| `stress/` | Per-frame random B&W and color static | H.264 |
| `workload/` | 30 s low-motion “talking head” proxy | H.264 |
| `long/` | 120 s looped copies (stream copy, no generation loss) | H.264 |

### `generate_test_media_prores_hd.sh` → `output-prores-hd/` (default)

| Folder | Contents | Codec |
|--------|----------|-------|
| `calibration/` | HD bars silent / 10 kHz / 7 kHz | ProRes 422 HQ `.mov` |
| `motion/`, `stress/`, `workload/`, `long/` | Same patterns as H.264 suite (1080p only) | ProRes (stress may be H.264 fallback on Linux) |

### `generate_test_media_hevc_hd.sh` → `output-hevc-hd/` (default) — **prototype**

| Folder | Contents | Codec |
|--------|----------|-------|
| `calibration/` | HD bars silent / 10 kHz / 7 kHz | HEVC `.mp4` (`hvc1` tag) |
| `motion/`, `stress/`, `workload/`, `long/` | Same HD patterns | HEVC (untested) |

**Key calibration files:**

| File | Standard | Audio |
|------|----------|-------|
| `bars_sd_*` | SMPTE EG 1-1990 (`smptebars`) | optional 10k / 7k |
| `bars_hd_*` | SMPTE RP 219-2002 (`smptehdbars`) | optional 10k / 7k |

Tone level: `volume=0.25` ≈ **−12 dBFS** (common broadcast line-up practice).

Use ProRes `calibration/` clips as pristine sources for transcode/downscale tests. Use H.264 clips to simulate already-compressed delivery formats.

### ProRes stress fallback

Random-noise stress clips can fail with FFmpeg’s `prores_ks` encoder (`Packet too small`). Set in `test-media.conf`:

| Value | Behavior |
|-------|----------|
| `auto` | Try ProRes; on failure, write near-lossless H.264 `.mp4` for stress clips only |
| `always` | Skip ProRes for stress; always use H.264 for those clips |
| `never` | ProRes only; script exits if stress encode fails |

On macOS, `prores_videotoolbox` usually succeeds for all clips including stress.

---

## Codecs (H.264, H.265 / HEVC, ProRes)

| Script | Codec | Status |
|--------|-------|--------|
| `generate_test_media.sh` | H.264 (`libx264`) | Supported |
| `generate_test_media_prores_hd.sh` | ProRes 422 HQ | Supported |
| `generate_test_media_hevc_hd.sh` | HEVC / H.265 | **Prototype / untested** |

**H.265 / HEVC is open source.** The main software encoder is **[x265](https://www.videolan.org/developers/x265.html)** (GPL), exposed in FFmpeg as **`libx265`**. Hardware encoding on Apple platforms uses **`hevc_videotoolbox`**.

Check your build:

```bash
ffmpeg -encoders 2>/dev/null | grep -E '265|hevc'
```

The HEVC script prefers VideoToolbox on macOS, then falls back to `libx265`. It sets `-tag:v hvc1` for broader player compatibility — still verify on your toolchain.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `prores_ks: Packet too small` on stress clips | Use macOS + `prores_videotoolbox`, or accept H.264 `.mp4` fallback for stress only |
| Color ringing on H.264 bars | Expected with yuv420p — use ProRes script for clean reference |
| `ffmpeg not found` | Install FFmpeg; ensure it is on your `PATH` |
| Bars look wrong in player | Confirm square pixels; some players ignore SAR |
| `.gitignore` not visible in Finder | Dotfiles are hidden by default; use Terminal, GitHub Desktop, or `ls -la` |

---

## Standards & IP note

Color bar **layouts** are defined by published SMPTE engineering guidelines (EG 1-1990, RP 219-2002). This project **generates** those patterns mathematically via FFmpeg — it does not redistribute copyrighted footage. Audio tones are pure sine waves.

Do not imply official SMPTE endorsement in derivative products. Describing output as “SMPTE-style” or “per RP 219” is standard industry language.

See [docs/STANDARDS.md](docs/STANDARDS.md) for references.

---

## License

This project is released under the **[MIT License](LICENSE)**. You may use, modify, and distribute the scripts freely; keep the copyright notice and license text when you redistribute.

## Contributing

Issues and PRs welcome: harden the HEVC prototype, 4K bars, 1 kHz tone, EBU PAL, Windows batch wrappers.
