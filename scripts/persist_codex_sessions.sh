#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: persist_codex_sessions.sh [options]

Persist ~/.codex/sessions into shared storage and replace local dir with a symlink.

Options:
  --target <dir>   Shared sessions directory (default: /mnt/shared/codex/sessions)
  --check          Only verify whether sessions are already persisted as expected
  --dry-run        Print actions without changing filesystem
  --force          Replace unexpected existing symlink/file at ~/.codex/sessions
  -h, --help       Show help
USAGE
}

log() {
  printf '[persist-codex] %s\n' "$*"
}

die() {
  printf '[persist-codex] ERROR: %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN: $*"
  else
    "$@"
  fi
}

TARGET="/mnt/shared/codex/sessions"
CHECK_ONLY=0
DRY_RUN=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      shift
      [[ $# -gt 0 ]] || die "--target requires a value"
      TARGET="$1"
      ;;
    --check)
      CHECK_ONLY=1
      ;;
    --dry-run)
      DRY_RUN=1
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

LOCAL_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
LOCAL_SESSIONS="$LOCAL_CODEX_HOME/sessions"

check_state() {
  if [[ ! -L "$LOCAL_SESSIONS" ]]; then
    log "NOT OK: $LOCAL_SESSIONS is not a symlink"
    return 1
  fi

  local link_target resolved_target
  link_target="$(readlink "$LOCAL_SESSIONS")"
  resolved_target="$(readlink -f "$LOCAL_SESSIONS")"

  if [[ "$resolved_target" != "$(readlink -f "$TARGET" 2>/dev/null || echo "$TARGET")" ]]; then
    log "NOT OK: symlink points to $link_target, expected $TARGET"
    return 1
  fi

  if [[ ! -d "$resolved_target" ]]; then
    log "NOT OK: target dir does not exist: $resolved_target"
    return 1
  fi

  if [[ ! -w "$resolved_target" ]]; then
    log "NOT OK: target dir is not writable: $resolved_target"
    return 1
  fi

  log "OK: $LOCAL_SESSIONS -> $resolved_target"
  return 0
}

if [[ "$CHECK_ONLY" == "1" ]]; then
  check_state
  exit $?
fi

run mkdir -p "$TARGET"
run mkdir -p "$LOCAL_CODEX_HOME"

if [[ -L "$LOCAL_SESSIONS" ]]; then
  current="$(readlink "$LOCAL_SESSIONS")"
  current_resolved="$(readlink -f "$LOCAL_SESSIONS" || true)"
  target_resolved="$(readlink -f "$TARGET")"

  if [[ "$current_resolved" == "$target_resolved" ]]; then
    log "already persisted: $LOCAL_SESSIONS -> $current"
    exit 0
  fi

  if [[ "$FORCE" != "1" ]]; then
    die "$LOCAL_SESSIONS already links to $current (use --force to replace)"
  fi

  run rm "$LOCAL_SESSIONS"
fi

if [[ -e "$LOCAL_SESSIONS" && ! -d "$LOCAL_SESSIONS" ]]; then
  if [[ "$FORCE" != "1" ]]; then
    die "$LOCAL_SESSIONS exists and is not a directory (use --force to replace)"
  fi
  run rm -f "$LOCAL_SESSIONS"
fi

if [[ -d "$LOCAL_SESSIONS" ]]; then
  if find "$LOCAL_SESSIONS" -mindepth 1 -print -quit | grep -q .; then
    log "copying existing sessions into $TARGET"
    run cp -a "$LOCAL_SESSIONS"/. "$TARGET"/
  fi

  backup="$LOCAL_CODEX_HOME/sessions.backup.$(date +%Y%m%d-%H%M%S)"
  run mv "$LOCAL_SESSIONS" "$backup"
  log "backup created: $backup"
fi

run ln -s "$TARGET" "$LOCAL_SESSIONS"
log "persisted: $LOCAL_SESSIONS -> $TARGET"

if [[ "$DRY_RUN" == "1" ]]; then
  log "dry-run complete"
  exit 0
fi

check_state
