#!/usr/bin/env bash
# =============================================================================
# Custom-duration ProRes random-static stress masters (worst-case encoder QA)
# =============================================================================
#
# Generates full-frame random noise (B&W or color) as Apple ProRes via
# VideoToolbox on macOS. Use for TrueEyed Jack / compressor ladders where
# short 1s loops are not enough (6s vs Pexels, 30s sustained stress).
#
# Usage:
#   ./generate_stress_prores_custom.sh <out_dir> [options]
#
# Options (env or flags):
#   --duration SEC     Clip length in seconds (default: 6)
#   --size WxH         e.g. 3840x2160 (default: 3840x2160)
#   --fps N            Frame rate (default: 30)
#   --mode bw|color    Noise type (default: color = worst entropy)
#   --profile N        VT ProRes profile: 0=Proxy 1=LT 2=422 3=HQ (default: 2)
#   --name STEM        Output stem without extension (auto if omitted)
#
# Example:
#   ./generate_stress_prores_custom.sh ./out --duration 6 --size 3840x2160 --mode color
#   ./generate_stress_prores_custom.sh ./out --duration 30 --size 3840x2160 --mode color
#
# Requirements: macOS + ffmpeg with prores_videotoolbox (brew install ffmpeg)
# =============================================================================

set -euo pipefail

OUT_DIR=""
DURATION=6
SIZE="3840x2160"
FPS=30
MODE="color"
PROFILE=2
NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --duration) DURATION="$2"; shift 2 ;;
    --size) SIZE="$2"; shift 2 ;;
    --fps) FPS="$2"; shift 2 ;;
    --mode) MODE="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$OUT_DIR" && "$1" != -* ]]; then
        OUT_DIR="$1"
        shift
      else
        echo "error: unknown arg: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  echo "error: output directory required" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg not found" >&2
  exit 1
fi

if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -qE 'prores_videotoolbox'; then
  echo "error: prores_videotoolbox not available (macOS Apple Silicon/Intel VT required)" >&2
  exit 1
fi

case "$MODE" in
  bw)
    GEQ="geq=lum='random(1)*255':cb='128':cr='128'"
    MODE_TAG="bw"
    ;;
  color)
    GEQ="geq=lum='random(1)*255':cb='random(1)*255':cr='random(1)*255'"
    MODE_TAG="color"
    ;;
  *)
    echo "error: --mode must be bw or color" >&2
    exit 1
    ;;
esac

FRAMES=$(awk -v d="$DURATION" -v f="$FPS" 'BEGIN { printf "%d", d*f }')
SIZE_TAG="${SIZE/x/}"
if [[ -z "$NAME" ]]; then
  NAME="static_${MODE_TAG}_noise_${DURATION}s_${SIZE_TAG}_${FPS}fps"
fi

mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/${NAME}.mov"

echo "==> ProRes stress: $OUT_FILE"
echo "    size=$SIZE fps=$FPS duration=${DURATION}s frames=$FRAMES mode=$MODE profile=$PROFILE"

# yuv422p10le is typical for ProRes; VT accepts yuv422p as well.
ffmpeg -hide_banner -loglevel info -y \
  -f lavfi -i "nullsrc=size=${SIZE}:rate=${FPS},format=yuv422p,${GEQ}" \
  -frames:v "$FRAMES" \
  -c:v prores_videotoolbox -profile:v "$PROFILE" \
  -movflags +faststart \
  "$OUT_FILE"

ls -lh "$OUT_FILE"
ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,profile,width,height,r_frame_rate,pix_fmt \
  -show_entries format=duration,size \
  -of default=nw=1:nk=0 \
  "$OUT_FILE"

echo "done."
