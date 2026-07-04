# Standards reference

Brief notes on what the generators implement. This is not legal advice.

## Video

| FFmpeg filter | SMPTE document | Typical use |
|---------------|----------------|-------------|
| `smptebars` | EG 1-1990 | SD-style 75% color bars |
| `smptehdbars` | RP 219-2002 | HD bars, PLUGE, optional BT.709 framing |

Patterns are synthesized at encode time — no bitmap assets shipped.

## Audio

| Tone | Frequency | Practice |
|------|-----------|----------|
| Primary line-up | 10 kHz | Common HD/broadcast facility alignment |
| Alternate | 7 kHz | Legacy / some plant standards |
| Level | ~−12 dBFS | Script uses `volume=0.25` on full-scale sine |

ProRes toned clips use **PCM** (lossless). H.264 toned clips use **AAC 128 kbps**.

## FFmpeg documentation

- [smptebars / smptehdbars](https://ffmpeg.org/ffmpeg-filters.html#smptebars)
- [sine audio source](https://ffmpeg.org/ffmpeg-filters.html#sine)
- [prores_videotoolbox](https://ffmpeg.org/ffmpeg-codecs.html#prores_videotoolbox) (macOS)
