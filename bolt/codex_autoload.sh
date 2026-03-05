#!/usr/bin/env bash
set -euo pipefail

TARGET_DEFAULT="/mnt/shared/codex/sessions"
WORKDIR_DEFAULT="/mnt/shared/code/EgoX"
TARGET="$TARGET_DEFAULT"
WORKDIR="$WORKDIR_DEFAULT"
CHECK_ONLY=0
NO_START=0
FORCE=0

usage() {
  cat <<'USAGE'
Usage: codex_autoload.sh [options]

Verify/fix Codex persistence and optionally auto-resume latest session.

Options:
  --target <dir>   Shared sessions directory (default: /mnt/shared/codex/sessions)
  --workdir <dir>  Codex working directory for resume (default: /mnt/shared/code/EgoX)
  --check          Check only, no filesystem changes
  --no-start       Verify/fix persistence but do not run `codex resume --last`
  --force          Replace unexpected ~/.codex/sessions symlink/file
  -h, --help       Show this help
USAGE
}

log() { printf '[codex-autoload] %s\n' "$*"; }
die() { printf '[codex-autoload] ERROR: %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      shift
      [[ $# -gt 0 ]] || die "--target requires value"
      TARGET="$1"
      ;;
    --workdir)
      shift
      [[ $# -gt 0 ]] || die "--workdir requires value"
      WORKDIR="$1"
      ;;
    --check)
      CHECK_ONLY=1
      ;;
    --no-start)
      NO_START=1
      ;;
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERSIST_SCRIPT="$SCRIPT_DIR/persist_codex_sessions.sh"
[[ -x "$PERSIST_SCRIPT" ]] || die "missing helper script: $PERSIST_SCRIPT"

PERSIST_ARGS=()
if [[ "$TARGET" != "$TARGET_DEFAULT" ]]; then
  PERSIST_ARGS+=(--target "$TARGET")
fi
if [[ "$FORCE" == "1" ]]; then
  PERSIST_ARGS+=(--force)
fi
if [[ "$CHECK_ONLY" == "1" ]]; then
  "$PERSIST_SCRIPT" "${PERSIST_ARGS[@]}" --check
  exit 0
fi

"$PERSIST_SCRIPT" "${PERSIST_ARGS[@]}"

if [[ "$NO_START" == "1" ]]; then
  log "skip auto-resume (--no-start)"
  exit 0
fi

CODEX_BIN="${CODEX_BIN:-codex}"
if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
  if [[ -x "/usr/local/bin/codex" ]]; then
    CODEX_BIN="/usr/local/bin/codex"
  else
    die "codex not found in PATH"
  fi
fi

if [[ ! -t 0 || ! -t 1 ]]; then
  die "no interactive TTY; run this in your terminal to auto-resume"
fi

if [[ -z "${TERM:-}" || "${TERM:-}" == "dumb" ]]; then
  die "TERM=${TERM:-unset} is not interactive; use a real terminal"
fi

log "starting: codex resume --last --cd $WORKDIR --no-alt-screen"
exec "$CODEX_BIN" resume --last --cd "$WORKDIR" --no-alt-screen
