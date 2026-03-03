#!/usr/bin/env bash
set -euo pipefail

# Thin wrapper for H2O processed data upload.
# Core logic remains in conductor_upload_best_practice.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/conductor_upload_best_practice.sh"

SRC_DIR="${1:-/mnt/shared/egox/data/processed/h2o}"
DEST_PREFIX="${2:-s3://outs/egox/h2o}"

# H2O usually has many small artifacts; topdir split keeps archives manageable.
ARCHIVE_STRATEGY="${ARCHIVE_STRATEGY:-topdir}" \
SMALL_THRESHOLD_MB="${SMALL_THRESHOLD_MB:-10}" \
DRY_RUN="${DRY_RUN:-0}" \
bash "$MAIN_SCRIPT" "$SRC_DIR" "$DEST_PREFIX"
