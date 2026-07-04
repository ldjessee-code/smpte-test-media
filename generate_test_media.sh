#!/usr/bin/env bash
# =============================================================================
# SMPTE Test Media Generator — H.264 delivery-style suite
# =============================================================================
#
# Generates broadcast-style calibration and encoder-stress clips using FFmpeg
# libavfilter (lavfi). No external assets required.
#
# Standards referenced (implemented by FFmpeg built-in filters):
#   - SMPTE EG 1-1990  → smptebars   (SD color bars)
#   - SMPTE RP 219-2002 → smptehdbars (HD color bars + PLUGE)
#
# Output codec: H.264 (libx264) yuv420p — simulates typical camera/phone
# delivery. For pristine ProRes 422 reference masters, use:
#   ./generate_test_media_prores_hd.sh
#
# Usage:
#   ./generate_test_media.sh [output_directory]
#
# Output path: CLI argument overrides test-media.conf (see test-media.conf.example)
#
# Requirements: FFmpeg with libx264 and AAC (see README.md)
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=load_config.sh
source "${_SCRIPT_DIR}/load_config.sh"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg not found. See README.md for install instructions." >&2
  exit 1
fi

# --- Timing & geometry ---
# CLI argument wins; else OUTPUT_DIR_H264 from config
OUT="${1:-${OUTPUT_DIR_H264}}"
FPS=30                    # Frame rate for all generated clips
LOOP_FRAMES=30              # Short motion/stress loops (1 second at 30 fps)
LOOP_SEC=$(awk "BEGIN {printf \"%.4f\", $LOOP_FRAMES / $FPS}")
LONG_SEC=120                # Extended loops via stream_loop

SD_SIZE="720x486"           # NTSC-ish SD canvas for smptebars
HD_SIZE="1920x1080"         # 1080p HD for smptehdbars

# Line-up tones (broadcast practice: 10 kHz common; 7 kHz legacy alternate)
TONE_10K=10000
TONE_7K=7000
# volume=0.25 ≈ −12 dBFS relative to full-scale sine in AAC/PCM mux
TONE_VOL=0.25

mkdir -p "$OUT"/{calibration,motion,stress,workload,long}

# Encode video-only clip: H.264, high quality (CRF 18), web-friendly faststart
encode_video() {
  local out="$1"
  shift
  ffmpeg -hide_banner -loglevel warning -y "$@" \
    -c:v libx264 -pix_fmt yuv420p -preset medium -crf 18 \
    -movflags +faststart \
    "$out"
}

# Encode video + audio: AAC stereo 48 kHz for toned calibration clips
encode_av() {
  local out="$1"
  shift
  ffmpeg -hide_banner -loglevel warning -y "$@" \
    -c:v libx264 -pix_fmt yuv420p -preset medium -crf 18 \
    -c:a aac -b:a 128k -ar 48000 -ac 2 \
    -movflags +faststart \
    "$out"
}

# Loop a short clip to LONG_SEC without re-encoding (stream copy)
make_long() {
  local src="$1"
  local dest="$2"
  ffmpeg -hide_banner -loglevel warning -y \
    -stream_loop -1 -i "$src" -t "$LONG_SEC" -c copy \
    "$dest"
}

# -----------------------------------------------------------------------------
# Tier A: Calibration — SMPTE color bars ± line-up tone
# -----------------------------------------------------------------------------
echo "==> Calibration (SMPTE bars)"

# SD bars (silent + 10 kHz + 7 kHz)
encode_video "$OUT/calibration/bars_sd_silent_10s.mp4" \
  -f lavfi -i "smptebars=size=${SD_SIZE}:rate=${FPS}" -t 10

encode_av "$OUT/calibration/bars_sd_10k_10s.mp4" \
  -f lavfi -i "smptebars=size=${SD_SIZE}:rate=${FPS}" \
  -f lavfi -i "sine=frequency=${TONE_10K}:sample_rate=48000:duration=10" \
  -filter:a "volume=${TONE_VOL}" -t 10 -shortest

encode_av "$OUT/calibration/bars_sd_7k_10s.mp4" \
  -f lavfi -i "smptebars=size=${SD_SIZE}:rate=${FPS}" \
  -f lavfi -i "sine=frequency=${TONE_7K}:sample_rate=48000:duration=10" \
  -filter:a "volume=${TONE_VOL}" -t 10 -shortest

# HD bars (silent + 10 kHz + 7 kHz)
encode_video "$OUT/calibration/bars_hd_silent_10s.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS}" -t 10

encode_av "$OUT/calibration/bars_hd_10k_10s.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS}" \
  -f lavfi -i "sine=frequency=${TONE_10K}:sample_rate=48000:duration=10" \
  -filter:a "volume=${TONE_VOL}" -t 10 -shortest

encode_av "$OUT/calibration/bars_hd_7k_10s.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS}" \
  -f lavfi -i "sine=frequency=${TONE_7K}:sample_rate=48000:duration=10" \
  -filter:a "volume=${TONE_VOL}" -t 10 -shortest

# -----------------------------------------------------------------------------
# Tier B: Motion — 30-frame loops (stresses motion estimation / scene detection)
# -----------------------------------------------------------------------------
echo "==> Motion loops (${LOOP_FRAMES} frames @ ${FPS} fps)"

# Pan across 2× wide bar canvas (horizontal motion)
encode_video "$OUT/motion/pan_h_hd_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "smptehdbars=size=3840x1080:rate=${FPS},format=yuv420p,crop=1920:1080:'mod(n*64\\,1920)':0" \
  -frames:v "$LOOP_FRAMES"

# Pan across 2× tall bar canvas (vertical motion)
encode_video "$OUT/motion/pan_v_hd_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "smptehdbars=size=1920x2160:rate=${FPS},format=yuv420p,crop=1920:1080:0:'mod(n*36\\,1080)'" \
  -frames:v "$LOOP_FRAMES"

# Slow zoom into center (scale / GOP stress)
encode_video "$OUT/motion/zoom_in_hd_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS},format=yuv420p,zoompan=z='1+0.02*on':d=${LOOP_FRAMES}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${HD_SIZE}:fps=${FPS}" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/motion/zoom_out_hd_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS},format=yuv420p,zoompan=z='if(eq(on,0),1.5,max(1,zoom-0.02))':d=${LOOP_FRAMES}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${HD_SIZE}:fps=${FPS}" \
  -frames:v "$LOOP_FRAMES"

# FFmpeg testsrc2 scroll (mixed detail + motion)
encode_video "$OUT/motion/scroll_testsrc2_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "testsrc2=size=${HD_SIZE}:rate=${FPS}" \
  -frames:v "$LOOP_FRAMES"

# -----------------------------------------------------------------------------
# Tier C: Stress — per-frame random noise (worst case for inter-frame compression)
# -----------------------------------------------------------------------------
echo "==> Stress loops (random static, ${LOOP_FRAMES} frames)"

encode_video "$OUT/stress/static_bw_noise_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "nullsrc=size=${HD_SIZE}:rate=${FPS},format=yuv420p,geq=lum='random(1)*255':cb='128':cr='128'" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/stress/static_color_noise_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "nullsrc=size=${HD_SIZE}:rate=${FPS},format=yuv420p,geq=lum='random(1)*255':cb='random(1)*255':cr='random(1)*255'" \
  -frames:v "$LOOP_FRAMES"

# -----------------------------------------------------------------------------
# Tier D: Workload — low motion proxy (talking-head-ish CPU load)
# -----------------------------------------------------------------------------
echo "==> Workload proxy (low motion)"
encode_video "$OUT/workload/static_head_proxy_30s.mp4" \
  -f lavfi -i "color=c=0x3A4A5A:s=${HD_SIZE}:r=${FPS},format=yuv420p,geq=lum='p(X,Y)':cb='128':cr='128',drawbox=x='960-40+30*sin(2*PI*t)':y='800':w=80:h=30:color=white@0.9:t=fill" \
  -t 30

# -----------------------------------------------------------------------------
# Tier E: Long duration — loop short clips to 120 s without generation loss
# -----------------------------------------------------------------------------
echo "==> Long duration (stream_loop ${LONG_SEC}s)"
for clip in \
  "$OUT/motion/pan_h_hd_${LOOP_FRAMES}f.mp4" \
  "$OUT/motion/zoom_in_hd_${LOOP_FRAMES}f.mp4" \
  "$OUT/stress/static_color_noise_${LOOP_FRAMES}f.mp4"; do
  base=$(basename "$clip" .mp4)
  make_long "$clip" "$OUT/long/${base}_loop_${LONG_SEC}s.mp4"
done

echo ""
echo "Done. Output: $OUT"
echo "Codec: H.264 (libx264) yuv420p. Toned clips: AAC 48 kHz."
echo "For ProRes 422 HQ reference masters: ./generate_test_media_prores_hd.sh"
echo "Loop duration per short clip: ${LOOP_SEC}s (${LOOP_FRAMES} frames @ ${FPS} fps)"