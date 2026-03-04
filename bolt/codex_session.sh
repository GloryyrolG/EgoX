#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_DIR="$ROOT_DIR/.codex/logs"
SESSION_DIR="${CODEX_HOME:-$HOME/.codex}/sessions"
mkdir -p "$LOG_DIR"

MODE="${1:-start}"
shift || true

TS="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/codex-${MODE}-${TS}.log"

sync_latest_rollout() {
  if [[ ! -d "$SESSION_DIR" ]]; then
    echo "[codex-session] no session dir: $SESSION_DIR"
    return 0
  fi

  latest_rollout="$(find "$SESSION_DIR" -type f -name 'rollout-*.jsonl' -print0 \
    | xargs -0 ls -1t 2>/dev/null | head -n 1 || true)"

  if [[ -z "${latest_rollout:-}" ]]; then
    echo "[codex-session] no rollout jsonl found under $SESSION_DIR"
    return 0
  fi

  target="$LOG_DIR/$(basename "$latest_rollout")"
  cp -f "$latest_rollout" "$target"
  echo "[codex-session] synced rollout -> $target"
}

case "$MODE" in
  start)
    echo "[codex-session] mode=start"
    echo "[codex-session] log=$LOG_FILE"
    codex --cd "$ROOT_DIR" --no-alt-screen "$@" 2>&1 | tee -a "$LOG_FILE"
    sync_latest_rollout
    ;;
  resume)
    echo "[codex-session] mode=resume --last"
    echo "[codex-session] log=$LOG_FILE"
    codex resume --last --cd "$ROOT_DIR" --no-alt-screen "$@" 2>&1 | tee -a "$LOG_FILE"
    sync_latest_rollout
    ;;
  picker)
    echo "[codex-session] mode=resume picker"
    echo "[codex-session] log=$LOG_FILE"
    codex resume --cd "$ROOT_DIR" --no-alt-screen "$@" 2>&1 | tee -a "$LOG_FILE"
    sync_latest_rollout
    ;;
  sync)
    echo "[codex-session] mode=sync rollout"
    sync_latest_rollout
    ;;
  *)
    echo "Usage: $0 [start|resume|picker|sync] [extra codex args...]" >&2
    exit 2
    ;;
esac
