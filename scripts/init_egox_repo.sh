#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/GloryyrolG/EgoX.git"
TARGET_DIR="${1:-$(pwd)}"
BRANCH="${2:-main}"
MODE="${3:-safe}"

usage() {
  cat <<'EOF'
Usage:
  init_egox_repo.sh [target_dir] [branch] [mode]

Modes:
  safe               Default. Never deletes local untracked files.
                     If checkout would overwrite local files, script exits.
  --backup-and-force Backup current files, then force checkout.
EOF
}

if [ "$MODE" != "safe" ] && [ "$MODE" != "--backup-and-force" ]; then
  usage
  exit 1
fi

mkdir -p "$TARGET_DIR"
cd "$TARGET_DIR"

# Avoid "dubious ownership" failures in shared/containerized environments.
git config --global --add safe.directory "$TARGET_DIR" || true

if [ ! -d .git ]; then
  git init
fi

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REPO_URL"
else
  git remote add origin "$REPO_URL"
fi

git fetch origin --prune

if [ "$MODE" = "--backup-and-force" ]; then
  backup_dir="${TARGET_DIR%/}_backup_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$backup_dir"
  shopt -s dotglob
  for f in "$TARGET_DIR"/*; do
    base="$(basename "$f")"
    if [ "$base" != ".git" ]; then
      cp -a "$f" "$backup_dir/"
    fi
  done
  echo "Backup created at: $backup_dir"
  git clean -fdx
  git checkout -f -B "$BRANCH" "origin/$BRANCH"
else
  if ! git checkout -B "$BRANCH" "origin/$BRANCH"; then
    cat <<EOF
Checkout blocked to protect local files.
No files were deleted.
If you want force overwrite with backup, run:
  $0 "$TARGET_DIR" "$BRANCH" --backup-and-force
EOF
    exit 1
  fi
fi

git branch --set-upstream-to="origin/$BRANCH" "$BRANCH"

git submodule sync --recursive
git submodule update --init --recursive

# Always move this submodule to its latest main branch tip.
if [ -d "EgoX-EgoPriorRenderer" ]; then
  git -C EgoX-EgoPriorRenderer fetch origin --prune
  git -C EgoX-EgoPriorRenderer checkout -B main origin/main
fi

echo "Repo ready: $TARGET_DIR @ $BRANCH (mode: $MODE)"
