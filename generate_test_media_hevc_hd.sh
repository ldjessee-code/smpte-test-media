#!/usr/bin/env bash
# =============================================================================
# SMPTE Test Media Generator — HD HEVC (H.265) suite  [PROTOTYPE / UNTESTED]
# =============================================================================
#
# *** This script is a starting point for contributors — not fully validated. ***
#
# Mirrors the HD ProRes suite structure but encodes with HEVC instead:
#   macOS  → hevc_videotoolbox (hardware, when available)
#   other  → libx265 (software x265)
#
# Intended use: smaller “delivery-style” masters than ProRes, higher efficiency
# than H.264, for encoder QA experiments. Parameters (CRF, tag) may need tuning
# for your FFmpeg build and players.
#
# Usage:
#   ./generate_test_media_hevc_hd.sh [output_directory]
#
# Config: OUTPUT_DIR_HEVC, HEVC_CRF in test-media.conf (see test-media.conf.example)
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=load_config.sh
source "${_SCRIPT_DIR}/load_config.sh"

echo "================================================================" >&2
echo "  PROTOTYPE / UNTESTED — HD HEVC generator" >&2
echo "  Verify output in your target players before relying on it." >&2
echo "================================================================" >&2

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg not found. See README.md for install instructions." >&2
  exit 1
fi

has_encoder() {
  ffmpeg -hide_banner -encoders 2>/dev/null | grep -qE "^\s*V.*\s+${1}\s"
}

# --- Pick HEVC encoder ---
HEVC_ENCODER=""
HEVC_V_ARGS=()

if [[ "$(uname -s)" == "Darwin" ]] && has_encoder "hevc_videotoolbox"; then
  HEVC_ENCODER="hevc_videotoolbox"
  # q:v 0–100 (higher = better quality, larger files). 65 is a reasonable prototype default.
  HEVC_V_ARGS=(-c:v hevc_videotoolbox -q:v "${HEVC_VT_QUALITY:-65}")
  echo "note: using hevc_videotoolbox (Apple) — prototype quality=${HEVC_VT_QUALITY:-65}"
elif has_encoder "libx265"; then
  HEVC_ENCODER="libx265"
  # CRF: 0=lossless-ish, 23=default, 28=smaller. Configurable via HEVC_CRF in test-media.conf
  HEVC_V_ARGS=(-c:v libx265 -pix_fmt yuv420p -crf "${HEVC_CRF:-23}" -preset medium)
  echo "note: using libx265 (x265) — prototype CRF=${HEVC_CRF:-23}"
else
  echo "error: need hevc_videotoolbox (macOS) or libx265 encoder." >&2
  echo "       Check: ffmpeg -encoders 2>/dev/null | grep -E '265|hevc'" >&2
  exit 1
fi

HEVC_A=(-c:a aac -b:a 128k -ar 48000 -ac 2)

OUT="${1:-${OUTPUT_DIR_HEVC}}"
FPS=30
LOOP_FRAMES=30
LOOP_SEC=$(awk "BEGIN {printf \"%.4f\", $LOOP_FRAMES / $FPS}")
LONG_SEC=120
CAL_DURATION=10

HD_SIZE="1920x1080"
TONE_10K=10000
TONE_7K=7000
TONE_VOL=0.25

mkdir -p "$OUT"/{calibration,motion,stress,workload,long}

encode_video() {
  local out="$1"
  shift
  ffmpeg -hide_banner -loglevel warning -y "$@" \
    "${HEVC_V_ARGS[@]}" \
    -tag:v hvc1 \
    -movflags +faststart \
    "$out"
}

encode_av() {
  local out="$1"
  shift
  ffmpeg -hide_banner -loglevel warning -y "$@" \
    "${HEVC_V_ARGS[@]}" \
    -tag:v hvc1 \
    "${HEVC_A[@]}" \
    -movflags +faststart \
    "$out"
}

make_long() {
  local src="$1"
  local dest="$2"
  if [[ ! -f "$src" ]]; then
    echo "warn: skipping long loop — missing: $src" >&2
    return 0
  fi
  ffmpeg -hide_banner -loglevel warning -y \
    -stream_loop -1 -i "$src" -t "$LONG_SEC" -c copy \
    "$dest"
}

echo "==> Calibration (SMPTE HD bars, HEVC / H.265)"
encode_video "$OUT/calibration/bars_hd_silent_${CAL_DURATION}s.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS}" -t "$CAL_DURATION"

encode_av "$OUT/calibration/bars_hd_10k_${CAL_DURATION}s.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS}" \
  -f lavfi -i "sine=frequency=${TONE_10K}:sample_rate=48000:duration=${CAL_DURATION}" \
  -filter:a "volume=${TONE_VOL}" -t "$CAL_DURATION" -shortest

encode_av "$OUT/calibration/bars_hd_7k_${CAL_DURATION}s.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS}" \
  -f lavfi -i "sine=frequency=${TONE_7K}:sample_rate=48000:duration=${CAL_DURATION}" \
  -filter:a "volume=${TONE_VOL}" -t "$CAL_DURATION" -shortest

echo "==> Motion loops (${LOOP_FRAMES} frames @ ${FPS} fps)"
encode_video "$OUT/motion/pan_h_hd_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "smptehdbars=size=3840x1080:rate=${FPS},format=yuv420p,crop=1920:1080:'mod(n*64\\,1920)':0" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/motion/pan_v_hd_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "smptehdbars=size=1920x2160:rate=${FPS},format=yuv420p,crop=1920:1080:0:'mod(n*36\\,1080)'" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/motion/zoom_in_hd_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS},format=yuv420p,zoompan=z='1+0.02*on':d=${LOOP_FRAMES}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${HD_SIZE}:fps=${FPS}" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/motion/zoom_out_hd_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS},format=yuv420p,zoompan=z='if(eq(on,0),1.5,max(1,zoom-0.02))':d=${LOOP_FRAMES}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${HD_SIZE}:fps=${FPS}" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/motion/scroll_testsrc2_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "testsrc2=size=${HD_SIZE}:rate=${FPS}" \
  -frames:v "$LOOP_FRAMES"

echo "==> Stress loops (random static, ${LOOP_FRAMES} frames)"
encode_video "$OUT/stress/static_bw_noise_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "nullsrc=size=${HD_SIZE}:rate=${FPS},format=yuv420p,geq=lum='random(1)*255':cb='128':cr='128'" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/stress/static_color_noise_${LOOP_FRAMES}f.mp4" \
  -f lavfi -i "nullsrc=size=${HD_SIZE}:rate=${FPS},format=yuv420p,geq=lum='random(1)*255':cb='random(1)*255':cr='random(1)*255'" \
  -frames:v "$LOOP_FRAMES"

echo "==> Workload proxy (low motion, 30 s)"
encode_video "$OUT/workload/static_head_proxy_30s.mp4" \
  -f lavfi -i "color=c=0x3A4A5A:s=${HD_SIZE}:r=${FPS},format=yuv420p,geq=lum='p(X,Y)':cb='128':cr='128',drawbox=x='960-40+30*sin(2*PI*t)':y='800':w=80:h=30:color=white@0.9:t=fill" \
  -t 30

echo "==> Long duration (stream_loop ${LONG_SEC}s)"
for clip in \
  "$OUT/motion/pan_h_hd_${LOOP_FRAMES}f.mp4" \
  "$OUT/motion/zoom_in_hd_${LOOP_FRAMES}f.mp4" \
  "$OUT/stress/static_color_noise_${LOOP_FRAMES}f.mp4"; do
  [[ -f "$clip" ]] || continue
  base=$(basename "$clip" .mp4)
  make_long "$clip" "$OUT/long/${base}_loop_${LONG_SEC}s.mp4"
done

echo ""
echo "Done. Output: $OUT"
echo "Encoder: ${HEVC_ENCODER} (HEVC / H.265). Audio: AAC 48 kHz (toned clips)."
echo "PROTOTYPE — please verify compatibility (hvc1 tag, player support, bar fidelity)."
echo "Loop duration per short clip: ${LOOP_SEC}s (${LOOP_FRAMES} frames @ ${FPS} fps)"