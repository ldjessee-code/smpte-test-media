#!/usr/bin/env bash
# =============================================================================
# load_config.sh — shared settings for generate_test_media*.sh
#
# Sourced by the generator scripts. Do not run directly.
#
# Loads test-media.conf from the repo root if present (copy from
# test-media.conf.example). Environment variables set before sourcing
# take precedence over the file.
# =============================================================================

# Directory containing the generator scripts (repo root)
_SMTE_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults (used when no config file and no env override)
: "${OUTPUT_DIR_H264:="${_SMTE_REPO_ROOT}/output"}"
: "${OUTPUT_DIR_PRORES:="${_SMTE_REPO_ROOT}/output-prores-hd"}"
: "${OUTPUT_DIR_HEVC:="${_SMTE_REPO_ROOT}/output-hevc-hd"}"
: "${OUTPUT_DIR_PYTHON:="${OUTPUT_DIR_H264}"}"
: "${PRORES_STRESS_H264_FALLBACK:=auto}"
: "${HEVC_CRF:=23}"
: "${HEVC_VT_QUALITY:=65}"

_CONFIG_FILE="${CONFIG_FILE:-${_SMTE_REPO_ROOT}/test-media.conf}"

if [[ -f "$_CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$_CONFIG_FILE"
  echo "note: loaded config from ${_CONFIG_FILE}"
fi

# Normalize fallback mode
PRORES_STRESS_H264_FALLBACK="$(echo "${PRORES_STRESS_H264_FALLBACK}" | tr '[:upper:]' '[:lower:]')"
case "$PRORES_STRESS_H264_FALLBACK" in
  auto|always|never) ;;
  *)
    echo "warn: invalid PRORES_STRESS_H264_FALLBACK='${PRORES_STRESS_H264_FALLBACK}' — using auto" >&2
    PRORES_STRESS_H264_FALLBACK="auto"
    ;;
esac

# Expand leading ~/ in paths
expand_path() {
  local p="$1"
  if [[ "$p" == ~/* ]]; then
    echo "${HOME}/${p:2}"
  elif [[ "$p" == "~" ]]; then
    echo "${HOME}"
  else
    echo "$p"
  fi
}

OUTPUT_DIR_H264="$(expand_path "$OUTPUT_DIR_H264")"
OUTPUT_DIR_PRORES="$(expand_path "$OUTPUT_DIR_PRORES")"
OUTPUT_DIR_HEVC="$(expand_path "$OUTPUT_DIR_HEVC")"
OUTPUT_DIR_PYTHON="$(expand_path "$OUTPUT_DIR_PYTHON")"