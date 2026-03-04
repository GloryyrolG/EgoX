#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="${1:-$(pwd)}"
REMOTE="${2:-origin}"
BRANCH="${3:-$(git -C "${REPO_DIR}" rev-parse --abbrev-ref HEAD)}"

cd "$REPO_DIR"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is not installed."
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is not installed."
  echo "Install gh first, then rerun this script."
  exit 1
fi

echo "[1/3] Checking GitHub auth status..."
if ! gh auth status -h github.com >/dev/null 2>&1; then
  echo "Not authenticated. Starting interactive GitHub login."
  echo "Please complete the browser/device flow when prompted."
  gh auth login -h github.com -w
fi

echo "[2/3] Validating authentication..."
gh auth status -h github.com
gh auth setup-git -h github.com >/dev/null

echo "[3/3] Pushing ${BRANCH} to ${REMOTE}..."
git push "$REMOTE" "$BRANCH"
echo "Push completed: ${REMOTE}/${BRANCH}"
