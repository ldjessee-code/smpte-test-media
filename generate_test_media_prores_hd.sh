#!/usr/bin/env bash
# =============================================================================
# SMPTE Test Media Generator — HD ProRes 422 HQ reference suite
# =============================================================================
#
# Produces pristine 1080p masters for encoder QA, downscale tests, and
# professional handoff workflows (bars + tone leaders).
#
# Encoder selection:
#   macOS  → prores_videotoolbox (Apple; recommended — handles all content)
#   Linux  → prores_ks (FFmpeg software ProRes; random-noise may need fallback)
#
# Random-noise stress frames can trigger prores_ks "Packet too small" on
# non-macOS builds. This script falls back to near-lossless H.264 for those
# clips only when that happens.
#
# Usage:
#   ./generate_test_media_prores_hd.sh [output_directory]
#
# Output path: CLI argument overrides test-media.conf (see test-media.conf.example)
# Stress H.264 fallback: PRORES_STRESS_H264_FALLBACK=auto|always|never in config
#
# Requirements: FFmpeg with ProRes support (see README.md)
# =============================================================================

set -euo pipefail

_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=load_config.sh
source "${_SCRIPT_DIR}/load_config.sh"

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg not found. See README.md for install instructions." >&2
  exit 1
fi

# Return 0 if FFmpeg lists the named video encoder
has_encoder() {
  ffmpeg -hide_banner -encoders 2>/dev/null | grep -qE "^\s*V.*\s+${1}\s"
}

# --- Pick ProRes encoder for this platform ---
PRORES_ENCODER=""
PRORES_V_ARGS=()
STRESS_V_ARGS=()

if [[ "$(uname -s)" == "Darwin" ]] && has_encoder "prores_videotoolbox"; then
  PRORES_ENCODER="prores_videotoolbox"
  # profile:v 3 = Apple ProRes 422 HQ
  PRORES_V_ARGS=(-c:v prores_videotoolbox -profile:v 3)
  STRESS_V_ARGS=("${PRORES_V_ARGS[@]}")
  echo "note: using prores_videotoolbox (Apple) for all clips"
elif has_encoder "prores_ks"; then
  PRORES_ENCODER="prores_ks"
  PRORES_V_ARGS=(-c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le)
  # Smaller macroblock slices reduce peak slice size on high-entropy frames
  STRESS_V_ARGS=(-c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le -mbs_per_slice 1)
  echo "note: using prores_ks — on macOS, install FFmpeg with VideoToolbox for best results"
else
  echo "error: need prores_videotoolbox (macOS) or prores_ks encoder." >&2
  echo "       See README.md — try: brew install ffmpeg" >&2
  exit 1
fi

# PCM audio for toned clips (lossless line-up tone; no AAC generation loss)
PRORES_A=(-c:a pcm_s16le -ar 48000 -ac 2)

OUT="${1:-${OUTPUT_DIR_PRORES}}"
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
    "${PRORES_V_ARGS[@]}" \
    -movflags +faststart \
    "$out"
}

encode_av() {
  local out="$1"
  shift
  ffmpeg -hide_banner -loglevel warning -y "$@" \
    "${PRORES_V_ARGS[@]}" \
    "${PRORES_A[@]}" \
    -movflags +faststart \
    "$out"
}

# Encode stress clip as near-lossless H.264 (yuv422p, CRF 0)
_encode_stress_h264_fallback() {
  local out_mov="$1"
  shift
  local h264_out="${out_mov%.mov}.mp4"
  echo "note: stress clip → H.264 near-lossless: $(basename "$h264_out")" >&2
  ffmpeg -hide_banner -loglevel warning -y "$@" \
    -c:v libx264 -pix_fmt yuv422p -preset veryslow -crf 0 \
    -movflags +faststart \
    "$h264_out"
}

# Stress content: ProRes unless PRORES_STRESS_H264_FALLBACK=always|auto|never
encode_stress_video() {
  local out="$1"
  shift

  if [[ "$PRORES_STRESS_H264_FALLBACK" == "always" ]]; then
    _encode_stress_h264_fallback "$out" "$@"
    return 0
  fi

  local prores_out="${out%.mov}_prores.mov"
  local err
  err=$(mktemp)
  if ffmpeg -hide_banner -loglevel error -y "$@" \
    "${STRESS_V_ARGS[@]}" \
    -movflags +faststart \
    "$prores_out" 2>"$err"; then
    mv -f "$prores_out" "$out"
    rm -f "$err"
    return 0
  fi
  rm -f "$prores_out"

  if [[ "$PRORES_STRESS_H264_FALLBACK" == "never" ]]; then
    echo "error: ProRes stress encode failed (PRORES_STRESS_H264_FALLBACK=never)" >&2
    cat "$err" >&2
    rm -f "$err"
    return 1
  fi

  # auto: fall back to H.264 on any ProRes stress failure
  if grep -q "Packet too small" "$err" 2>/dev/null; then
    echo "warn: ProRes failed on random noise (Packet too small)" >&2
  else
    echo "warn: ProRes stress encode failed — trying H.264 fallback" >&2
  fi
  rm -f "$err"
  _encode_stress_h264_fallback "$out" "$@"
  return 0
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

echo "==> Calibration (SMPTE HD bars, ProRes 422 HQ)"
encode_video "$OUT/calibration/bars_hd_silent_${CAL_DURATION}s.mov" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS}" -t "$CAL_DURATION"

encode_av "$OUT/calibration/bars_hd_10k_${CAL_DURATION}s.mov" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS}" \
  -f lavfi -i "sine=frequency=${TONE_10K}:sample_rate=48000:duration=${CAL_DURATION}" \
  -filter:a "volume=${TONE_VOL}" -t "$CAL_DURATION" -shortest

encode_av "$OUT/calibration/bars_hd_7k_${CAL_DURATION}s.mov" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS}" \
  -f lavfi -i "sine=frequency=${TONE_7K}:sample_rate=48000:duration=${CAL_DURATION}" \
  -filter:a "volume=${TONE_VOL}" -t "$CAL_DURATION" -shortest

echo "==> Motion loops (${LOOP_FRAMES} frames @ ${FPS} fps)"
encode_video "$OUT/motion/pan_h_hd_${LOOP_FRAMES}f.mov" \
  -f lavfi -i "smptehdbars=size=3840x1080:rate=${FPS},crop=1920:1080:'mod(n*64\\,1920)':0" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/motion/pan_v_hd_${LOOP_FRAMES}f.mov" \
  -f lavfi -i "smptehdbars=size=1920x2160:rate=${FPS},crop=1920:1080:0:'mod(n*36\\,1080)'" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/motion/zoom_in_hd_${LOOP_FRAMES}f.mov" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS},zoompan=z='1+0.02*on':d=${LOOP_FRAMES}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${HD_SIZE}:fps=${FPS}" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/motion/zoom_out_hd_${LOOP_FRAMES}f.mov" \
  -f lavfi -i "smptehdbars=size=${HD_SIZE}:rate=${FPS},zoompan=z='if(eq(on,0),1.5,max(1,zoom-0.02))':d=${LOOP_FRAMES}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${HD_SIZE}:fps=${FPS}" \
  -frames:v "$LOOP_FRAMES"

encode_video "$OUT/motion/scroll_testsrc2_${LOOP_FRAMES}f.mov" \
  -f lavfi -i "testsrc2=size=${HD_SIZE}:rate=${FPS}" \
  -frames:v "$LOOP_FRAMES"

echo "==> Stress loops (random static, ${LOOP_FRAMES} frames)"
encode_stress_video "$OUT/stress/static_bw_noise_${LOOP_FRAMES}f.mov" \
  -f lavfi -i "nullsrc=size=${HD_SIZE}:rate=${FPS},format=yuv422p,geq=lum='random(1)*255':cb='128':cr='128'" \
  -frames:v "$LOOP_FRAMES"

encode_stress_video "$OUT/stress/static_color_noise_${LOOP_FRAMES}f.mov" \
  -f lavfi -i "nullsrc=size=${HD_SIZE}:rate=${FPS},format=yuv422p,geq=lum='random(1)*255':cb='random(1)*255':cr='random(1)*255'" \
  -frames:v "$LOOP_FRAMES"

echo "==> Workload proxy (low motion, 30 s)"
encode_video "$OUT/workload/static_head_proxy_30s.mov" \
  -f lavfi -i "color=c=0x3A4A5A:s=${HD_SIZE}:r=${FPS},format=yuv422p,geq=lum='p(X,Y)':cb='128':cr='128',drawbox=x='960-40+30*sin(2*PI*t)':y='800':w=80:h=30:color=white@0.9:t=fill" \
  -t 30

echo "==> Long duration (stream_loop ${LONG_SEC}s)"
STRESS_LONG_SRC="$OUT/stress/static_color_noise_${LOOP_FRAMES}f.mov"
if [[ ! -f "$STRESS_LONG_SRC" ]]; then
  STRESS_LONG_SRC="$OUT/stress/static_color_noise_${LOOP_FRAMES}f.mp4"
fi

for clip in \
  "$OUT/motion/pan_h_hd_${LOOP_FRAMES}f.mov" \
  "$OUT/motion/zoom_in_hd_${LOOP_FRAMES}f.mov" \
  "$STRESS_LONG_SRC"; do
  [[ -f "$clip" ]] || continue
  base=$(basename "$clip")
  base="${base%.*}"
  ext="${clip##*.}"
  make_long "$clip" "$OUT/long/${base}_loop_${LONG_SEC}s.${ext}"
done

echo ""
echo "Done. Output: $OUT"
echo "Encoder: ${PRORES_ENCODER} (ProRes 422 HQ). Audio: PCM 48 kHz (toned clips)."
echo "Use calibration/ .mov files as reference masters for downscale / recompress QA."
echo "Loop duration per short clip: ${LOOP_SEC}s (${LOOP_FRAMES} frames @ ${FPS} fps)"