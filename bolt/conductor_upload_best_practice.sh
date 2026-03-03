#!/usr/bin/env bash
set -euo pipefail

# Best-practice upload for Conductor:
# - Small files (<=10MB): archive via s3zip to reduce metadata pressure.
# - Large files (>10MB): upload directly with conductor s3 cp.

SRC_DIR="${1:-/mnt/shared/egox/output}"
DEST_PREFIX="${2:-s3://outs/egox}"
SMALL_THRESHOLD_MB="${SMALL_THRESHOLD_MB:-10}"
SETUP_SCRIPT="/mnt/task_runtime/bolt/set_conductor_env.sh"
S3ZIP_BIN="${S3ZIP_BIN:-/miniforge/bin/s3zip}"
DRY_RUN="${DRY_RUN:-0}"
ARCHIVE_STRATEGY="${ARCHIVE_STRATEGY:-single}" # single | topdir
TRACE="${TRACE:-0}" # set to 1 to enable bash xtrace (-x), aligned with docs guidance

if [[ "$TRACE" == "1" ]]; then
  set -x
fi

run_cmd() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '[dry-run] '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

if [[ "$DEST_PREFIX" != s3://* ]]; then
  echo "ERROR: destination must be an s3 uri, got: $DEST_PREFIX" >&2
  exit 1
fi

DEST_NO_SCHEME="${DEST_PREFIX#s3://}"
DEST_BUCKET="${DEST_NO_SCHEME%%/*}"
DEST_BASE_PREFIX="${DEST_NO_SCHEME#${DEST_BUCKET}}"
DEST_BASE_PREFIX="${DEST_BASE_PREFIX#/}"

if [[ ! -d "$SRC_DIR" ]]; then
  echo "ERROR: source dir not found: $SRC_DIR" >&2
  exit 1
fi

if [[ ! -f "$SETUP_SCRIPT" ]]; then
  echo "ERROR: setup script not found: $SETUP_SCRIPT" >&2
  exit 1
fi

if ! command -v conductor >/dev/null 2>&1; then
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "WARN: conductor command not found, but continuing in dry-run mode"
  else
    echo "ERROR: conductor command not found in PATH" >&2
    exit 1
  fi
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "ERROR: rsync is required but not found" >&2
  exit 1
fi

if [[ "$ARCHIVE_STRATEGY" != "single" && "$ARCHIVE_STRATEGY" != "topdir" ]]; then
  echo "ERROR: ARCHIVE_STRATEGY must be one of: single, topdir (got: $ARCHIVE_STRATEGY)" >&2
  exit 1
fi

echo "[1/8] Refreshing Conductor credentials"
if [[ "$DRY_RUN" == "1" ]]; then
  echo "  dry-run mode: skip credential refresh"
else
  # shellcheck disable=SC1090
  source "$SETUP_SCRIPT" >/tmp/conductor_env_refresh_upload.log 2>&1 || {
    echo "ERROR: failed to source $SETUP_SCRIPT" >&2
    sed -n '1,80p' /tmp/conductor_env_refresh_upload.log >&2
    exit 1
  }
fi

echo "[2/8] Checking s3zip availability"
if [[ ! -x "$S3ZIP_BIN" ]]; then
  echo "  s3zip not found at $S3ZIP_BIN, installing..."
  run_cmd python3 -m pip install -q s3zip==7.3.0
fi

if [[ ! -x "$S3ZIP_BIN" ]]; then
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "  dry-run mode: s3zip binary missing locally, continuing with plan only"
  else
  echo "ERROR: s3zip binary still not found: $S3ZIP_BIN" >&2
  exit 1
  fi
fi

# s3zip defaults to old blobby endpoint unless overridden.
export S3ZIP_ENDPOINT_URL="https://conductor.data.apple.com"

echo "[3/8] Building file lists from $SRC_DIR"
WORKDIR="$(mktemp -d /tmp/conductor-upload-XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

SMALL_THRESHOLD_BYTES="$((SMALL_THRESHOLD_MB * 1024 * 1024))"
python3 - "$SRC_DIR" "$SMALL_THRESHOLD_BYTES" "$WORKDIR/small_files.txt" "$WORKDIR/large_files.txt" "$WORKDIR/small_topdirs.txt" <<'PY'
import os
import sys

src_dir = sys.argv[1]
threshold = int(sys.argv[2])
small_out = sys.argv[3]
large_out = sys.argv[4]
topdirs_out = sys.argv[5]

small = []
large = []
topdirs = set()
for root, _, files in os.walk(src_dir):
    for name in files:
        path = os.path.join(root, name)
        rel = os.path.relpath(path, src_dir)
        size = os.path.getsize(path)
        if size <= threshold:
            small.append(rel)
            topdirs.add(rel.split(os.sep, 1)[0] if os.sep in rel else "__ROOT__")
        else:
            large.append(rel)

small.sort()
large.sort()
with open(small_out, "w", encoding="utf-8") as f:
    for p in small:
        f.write(p + "\n")
with open(large_out, "w", encoding="utf-8") as f:
    for p in large:
        f.write(p + "\n")
with open(topdirs_out, "w", encoding="utf-8") as f:
    for d in sorted(topdirs):
        f.write(d + "\n")
PY

SMALL_COUNT="$(wc -l <"$WORKDIR/small_files.txt" | tr -d ' ')"
LARGE_COUNT="$(wc -l <"$WORKDIR/large_files.txt" | tr -d ' ')"
echo "  small_files(<=${SMALL_THRESHOLD_MB}MB): $SMALL_COUNT"
echo "  large_files(>${SMALL_THRESHOLD_MB}MB):  $LARGE_COUNT"
echo "  archive strategy: $ARCHIVE_STRATEGY"
if [[ "$SMALL_COUNT" -ge 10000 && "$ARCHIVE_STRATEGY" == "single" ]]; then
  echo "  WARN: many small files detected; consider ARCHIVE_STRATEGY=topdir for grouped compression"
fi

TS="$(date +%Y%m%d_%H%M%S)"

small_archives=()
if [[ "$SMALL_COUNT" -gt 0 ]]; then
  echo "[4/8] Archiving small files with s3zip"
  if [[ "$ARCHIVE_STRATEGY" == "single" ]]; then
    STAGE_ROOT="$WORKDIR/egox_smallfiles"
    mkdir -p "$STAGE_ROOT"
    run_cmd rsync -a --files-from="$WORKDIR/small_files.txt" "$SRC_DIR/" "$STAGE_ROOT/"
    archive_key="${DEST_PREFIX%/}/_smallfiles_${TS}.zip"
    run_cmd "$S3ZIP_BIN" -c "$archive_key" "$STAGE_ROOT" --no_progress
    small_archives+=("$archive_key")
    echo "  archive uploaded: $archive_key"
  else
    while IFS= read -r topdir; do
      [[ -z "$topdir" ]] && continue
      STAGE_ROOT="$WORKDIR/egox_smallfiles_${topdir}"
      mkdir -p "$STAGE_ROOT"
      if [[ "$topdir" == "__ROOT__" ]]; then
        awk -F/ 'NF==1 {print}' "$WORKDIR/small_files.txt" >"$WORKDIR/small_files_${topdir}.txt"
      else
        awk -v d="$topdir/" 'index($0,d)==1 {print}' "$WORKDIR/small_files.txt" >"$WORKDIR/small_files_${topdir}.txt"
      fi
      count_this="$(wc -l <"$WORKDIR/small_files_${topdir}.txt" | tr -d ' ')"
      [[ "$count_this" == "0" ]] && continue
      run_cmd rsync -a --files-from="$WORKDIR/small_files_${topdir}.txt" "$SRC_DIR/" "$STAGE_ROOT/"
      suffix="$topdir"
      [[ "$suffix" == "__ROOT__" ]] && suffix="root"
      archive_key="${DEST_PREFIX%/}/_smallfiles_${suffix}_${TS}.zip"
      run_cmd "$S3ZIP_BIN" -c "$archive_key" "$STAGE_ROOT" --no_progress
      small_archives+=("$archive_key")
      echo "  archive uploaded: $archive_key ($count_this files)"
    done <"$WORKDIR/small_topdirs.txt"
  fi
else
  echo "[4/8] No small files to archive"
fi

if [[ "$LARGE_COUNT" -gt 0 ]]; then
  echo "[5/8] Uploading large files directly"
  i=0
  skipped=0
  uploaded=0
  while IFS= read -r relpath; do
    [[ -z "$relpath" ]] && continue
    i=$((i + 1))
    src="$SRC_DIR/$relpath"
    key="$relpath"
    if [[ -n "$DEST_BASE_PREFIX" ]]; then
      key="${DEST_BASE_PREFIX}/${relpath}"
    fi
    dst="s3://${DEST_BUCKET}/${key}"
    if [[ "$DRY_RUN" != "1" ]]; then
      local_size="$(stat -c%s "$src")"
      remote_size="$(conductor s3api head-object --bucket "$DEST_BUCKET" --key "$key" --query 'ContentLength' --output text 2>/dev/null || true)"
      if [[ "$remote_size" == "$local_size" ]]; then
        skipped=$((skipped + 1))
        echo "  [$i/$LARGE_COUNT] skip existing same size: $relpath"
        continue
      fi
    fi
    echo "  [$i/$LARGE_COUNT] $relpath"
    run_cmd conductor s3 cp "$src" "$dst" --no-progress --only-show-errors
    uploaded=$((uploaded + 1))
  done <"$WORKDIR/large_files.txt"
else
  echo "[5/8] No large files to upload directly"
fi

echo "[6/8] Summary"
echo "  destination prefix: ${DEST_PREFIX%/}/"
if [[ "${#small_archives[@]}" -gt 0 ]]; then
  echo "  small archive count: ${#small_archives[@]}"
  for key in "${small_archives[@]}"; do
    echo "    - $key"
  done
fi
if [[ "$LARGE_COUNT" -gt 0 ]]; then
  echo "  large files uploaded: ${uploaded:-0}"
  echo "  large files skipped:  ${skipped:-0}"
fi

echo "[7/8] Restore hint"
echo "  small archives are named _smallfiles*.zip; unpack after download if needed."

echo "[8/8] Done"
