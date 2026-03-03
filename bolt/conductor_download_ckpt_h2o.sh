#!/usr/bin/env bash
set -euo pipefail

# Download Egox checkpoint + H2O dataset bundle from Conductor.
# Default mode is MOCK to avoid pulling huge checkpoint files by accident.

CKPT_SRC="${1:-s3://outs/egox}"
H2O_SRC="${2:-s3://dses/egox/h2o}"
DEST_ROOT="${3:-/mnt/task_runtime/tmp/downloads/egox_pull_$(date +%Y%m%d_%H%M%S)}"

MOCK="${MOCK:-1}"                     # 1: sample ckpt files only
MOCK_SMALL_LIMIT="${MOCK_SMALL_LIMIT:-4}"
MOCK_LARGE_LIMIT="${MOCK_LARGE_LIMIT:-1}"
MOCK_SMALL_MAX_BYTES="${MOCK_SMALL_MAX_BYTES:-52428800}"        # <= 50MB
MOCK_LARGE_MIN_BYTES="${MOCK_LARGE_MIN_BYTES:-1073741824}"      # >= 1GB
MOCK_LARGE_RANGE_BYTES="${MOCK_LARGE_RANGE_BYTES:-1048576}"     # range download bytes for large files
AUTO_EXTRACT_H2O="${AUTO_EXTRACT_H2O:-1}"
NORMALIZE_H2O_LAYOUT="${NORMALIZE_H2O_LAYOUT:-1}"
CLEAN_GROUPED_DIRS="${CLEAN_GROUPED_DIRS:-1}"
SETUP_SCRIPT="${SETUP_SCRIPT:-/mnt/task_runtime/bolt/set_conductor_env.sh}"

if [[ "$CKPT_SRC" != s3://* || "$H2O_SRC" != s3://* ]]; then
  echo "ERROR: CKPT_SRC and H2O_SRC must be s3:// URIs" >&2
  exit 1
fi

if [[ -e "$DEST_ROOT" ]]; then
  echo "ERROR: DEST_ROOT already exists, refusing to overwrite: $DEST_ROOT" >&2
  exit 1
fi

if [[ ! -f "$SETUP_SCRIPT" ]]; then
  echo "ERROR: setup script not found: $SETUP_SCRIPT" >&2
  exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "ERROR: unzip not found" >&2
  exit 1
fi

echo "[1/8] Refreshing Conductor auth"
# shellcheck disable=SC1090
source "$SETUP_SCRIPT" >/tmp/conductor_env_refresh_download.log 2>&1 || {
  echo "ERROR: failed to source $SETUP_SCRIPT" >&2
  sed -n '1,80p' /tmp/conductor_env_refresh_download.log >&2
  exit 1
}

if ! command -v conductor >/dev/null 2>&1; then
  echo "ERROR: conductor command not found after setup" >&2
  exit 1
fi

echo "[2/8] Creating destination layout"
mkdir -p "$DEST_ROOT"/{ckpt,h2o_zips,h2o_data,manifests}
echo "  DEST_ROOT=$DEST_ROOT"

echo "[3/8] Listing checkpoint objects"
conductor s3 ls "$CKPT_SRC" --recursive >"$DEST_ROOT/manifests/ckpt_ls.txt"
CKPT_COUNT="$(wc -l <"$DEST_ROOT/manifests/ckpt_ls.txt" | tr -d ' ')"
echo "  ckpt object count: $CKPT_COUNT"

echo "[4/8] Downloading checkpoint objects"
if [[ "$MOCK" == "1" ]]; then
  echo "  mock mode: small(full) + large(range) mixed sampling"
  awk -v maxb="$MOCK_SMALL_MAX_BYTES" '($3+0) <= maxb {print $4}' "$DEST_ROOT/manifests/ckpt_ls.txt" \
    | sed -n "1,${MOCK_SMALL_LIMIT}p" >"$DEST_ROOT/manifests/ckpt_keys_small.txt"
  awk -v minb="$MOCK_LARGE_MIN_BYTES" '($3+0) >= minb {print $4}' "$DEST_ROOT/manifests/ckpt_ls.txt" \
    | sed -n "1,${MOCK_LARGE_LIMIT}p" >"$DEST_ROOT/manifests/ckpt_keys_large.txt"
  small_n="$(wc -l <"$DEST_ROOT/manifests/ckpt_keys_small.txt" | tr -d ' ')"
  large_n="$(wc -l <"$DEST_ROOT/manifests/ckpt_keys_large.txt" | tr -d ' ')"
  echo "    selected small(full): $small_n"
  echo "    selected large(range): $large_n"
else
  echo "  full mode: download all checkpoint objects from $CKPT_SRC"
  awk '{print $4}' "$DEST_ROOT/manifests/ckpt_ls.txt" >"$DEST_ROOT/manifests/ckpt_keys_full.txt"
fi

CKPT_URI_NO_SCHEME="${CKPT_SRC#s3://}"
CKPT_BUCKET="${CKPT_URI_NO_SCHEME%%/*}"
CKPT_PREFIX="${CKPT_URI_NO_SCHEME#${CKPT_BUCKET}}"
CKPT_PREFIX="${CKPT_PREFIX#/}"

ckpt_relpath() {
  local key="$1"
  local rel="$key"
  if [[ -n "$CKPT_PREFIX" && "$key" == "$CKPT_PREFIX/"* ]]; then
    rel="${key#${CKPT_PREFIX}/}"
  elif [[ "$key" == "$CKPT_PREFIX" ]]; then
    rel="$(basename "$key")"
  fi
  echo "$rel"
}

selected_full=0
selected_partial=0
if [[ "$MOCK" == "1" ]]; then
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    rel="$(ckpt_relpath "$key")"
    dst="$DEST_ROOT/ckpt/$rel"
    mkdir -p "$(dirname "$dst")"
    conductor s3 cp "s3://${CKPT_BUCKET}/${key}" "$dst" --no-progress --only-show-errors
    selected_full=$((selected_full + 1))
  done <"$DEST_ROOT/manifests/ckpt_keys_small.txt"

  end_byte=$((MOCK_LARGE_RANGE_BYTES - 1))
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    rel="$(ckpt_relpath "$key")"
    dst="$DEST_ROOT/ckpt/${rel}.partial"
    mkdir -p "$(dirname "$dst")"
    conductor s3api get-object \
      --bucket "$CKPT_BUCKET" \
      --key "$key" \
      --range "bytes=0-${end_byte}" \
      "$dst" >/dev/null
    selected_partial=$((selected_partial + 1))
  done <"$DEST_ROOT/manifests/ckpt_keys_large.txt"
  echo "  ckpt downloaded full files: $selected_full"
  echo "  ckpt downloaded large partial files: $selected_partial"
else
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    rel="$(ckpt_relpath "$key")"
    dst="$DEST_ROOT/ckpt/$rel"
    mkdir -p "$(dirname "$dst")"
    conductor s3 cp "s3://${CKPT_BUCKET}/${key}" "$dst" --no-progress --only-show-errors
    selected_full=$((selected_full + 1))
  done <"$DEST_ROOT/manifests/ckpt_keys_full.txt"
  echo "  ckpt downloaded objects: $selected_full"
fi

echo "[5/8] Downloading H2O zip bundles"
conductor s3 cp "$H2O_SRC/" "$DEST_ROOT/h2o_zips/" --recursive --no-progress --only-show-errors
H2O_ZIP_COUNT="$(find "$DEST_ROOT/h2o_zips" -type f -name '*.zip' | wc -l | tr -d ' ')"
echo "  h2o zip count: $H2O_ZIP_COUNT"

echo "[6/8] Extracting H2O bundles"
if [[ "$AUTO_EXTRACT_H2O" == "1" ]]; then
  while IFS= read -r z; do
    [[ -z "$z" ]] && continue
    unzip -o -q "$z" -d "$DEST_ROOT/h2o_data"
  done < <(find "$DEST_ROOT/h2o_zips" -type f -name '*.zip' | sort)
  if [[ "$NORMALIZE_H2O_LAYOUT" == "1" ]]; then
    # Restore original h2o layout from grouped archive roots:
    # - egox_smallfiles___ROOT__/meta.json -> h2o_data/meta.json
    # - egox_smallfiles_videos/videos -> h2o_data/videos
    # - egox_smallfiles_vipe_results/vipe_results -> h2o_data/vipe_results
    if [[ -f "$DEST_ROOT/h2o_data/egox_smallfiles___ROOT__/meta.json" ]]; then
      cp -f "$DEST_ROOT/h2o_data/egox_smallfiles___ROOT__/meta.json" "$DEST_ROOT/h2o_data/meta.json"
    fi
    if [[ -d "$DEST_ROOT/h2o_data/egox_smallfiles_videos/videos" ]]; then
      mkdir -p "$DEST_ROOT/h2o_data/videos"
      cp -a "$DEST_ROOT/h2o_data/egox_smallfiles_videos/videos/." "$DEST_ROOT/h2o_data/videos/"
    fi
    if [[ -d "$DEST_ROOT/h2o_data/egox_smallfiles_vipe_results/vipe_results" ]]; then
      mkdir -p "$DEST_ROOT/h2o_data/vipe_results"
      cp -a "$DEST_ROOT/h2o_data/egox_smallfiles_vipe_results/vipe_results/." "$DEST_ROOT/h2o_data/vipe_results/"
    fi
    if [[ "$CLEAN_GROUPED_DIRS" == "1" ]]; then
      rm -rf \
        "$DEST_ROOT/h2o_data/egox_smallfiles___ROOT__" \
        "$DEST_ROOT/h2o_data/egox_smallfiles_videos" \
        "$DEST_ROOT/h2o_data/egox_smallfiles_vipe_results"
    fi
  fi
  echo "  extracted to: $DEST_ROOT/h2o_data"
else
  echo "  skip extraction (AUTO_EXTRACT_H2O=$AUTO_EXTRACT_H2O)"
fi

echo "[7/8] Structure snapshot"
echo "  ckpt tree:"
find "$DEST_ROOT/ckpt" -maxdepth 4 -type f | sed "s#^$DEST_ROOT/##" | sed -n '1,40p'
echo "  h2o tree:"
find "$DEST_ROOT/h2o_data" -maxdepth 5 -type f | sed "s#^$DEST_ROOT/##" | sed -n '1,40p'

echo "[8/8] Done"
echo "  output: $DEST_ROOT"
