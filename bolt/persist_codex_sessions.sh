#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: persist_codex_sessions.sh [options]

Persist key ~/.codex state into shared storage and replace local paths with symlinks.

Options:
  --target <dir>   Shared sessions directory (default: /mnt/shared/codex/sessions)
                   Note: related files are stored under parent dir (e.g. /mnt/shared/codex)
  --check          Only verify whether all configured paths are persisted as expected
  --dry-run        Print actions without changing filesystem
  --force          Replace unexpected existing symlink/file conflicts
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
TARGET_ROOT="$(dirname "$TARGET")"

ITEMS=(
  "sessions|$LOCAL_SESSIONS|$TARGET|dir"
  "auth|$LOCAL_CODEX_HOME/auth.json|$TARGET_ROOT/auth.json|file"
  "models_cache|$LOCAL_CODEX_HOME/models_cache.json|$TARGET_ROOT/models_cache.json|file"
  "state_sqlite|$LOCAL_CODEX_HOME/state_*.sqlite*|$TARGET_ROOT|glob"
)

ensure_parent() {
  local p="$1"
  run mkdir -p "$(dirname "$p")"
}

check_link() {
  local local_path="$1"
  local expected="$2"

  if [[ ! -L "$local_path" ]]; then
    log "NOT OK: $local_path is not a symlink"
    return 1
  fi

  local link_target resolved_target
  link_target="$(readlink "$local_path")"
  resolved_target="$(readlink -f "$local_path")"

  if [[ "$resolved_target" != "$(readlink -f "$expected" 2>/dev/null || echo "$expected")" ]]; then
    log "NOT OK: symlink points to $link_target, expected $expected"
    return 1
  fi

  if [[ ! -e "$resolved_target" ]]; then
    log "NOT OK: target does not exist: $resolved_target"
    return 1
  fi

  if [[ ! -w "$resolved_target" ]]; then
    log "NOT OK: target is not writable: $resolved_target"
    return 1
  fi

  log "OK: $local_path -> $resolved_target"
  return 0
}

persist_one() {
  local local_path="$1"
  local target_path="$2"
  local kind="$3"
  local stamp backup current current_resolved target_resolved

  ensure_parent "$target_path"
  run mkdir -p "$TARGET_ROOT"
  if [[ "$kind" == "dir" ]]; then
    run mkdir -p "$target_path"
  fi

  if [[ -L "$local_path" ]]; then
    current="$(readlink "$local_path")"
    current_resolved="$(readlink -f "$local_path" || true)"
    target_resolved="$(readlink -f "$target_path")"

    if [[ "$current_resolved" == "$target_resolved" ]]; then
      log "already persisted: $local_path -> $current"
      return 0
    fi

    if [[ "$FORCE" != "1" ]]; then
      die "$local_path already links to $current (use --force to replace)"
    fi

    run rm "$local_path"
  fi

  if [[ -e "$local_path" && ! -L "$local_path" ]]; then
    if [[ "$kind" == "dir" && -d "$local_path" ]]; then
      if find "$local_path" -mindepth 1 -print -quit | grep -q .; then
        log "copying existing dir data: $local_path -> $target_path"
        run cp -a "$local_path"/. "$target_path"/
      fi
    elif [[ "$kind" == "file" && -f "$local_path" ]]; then
      log "copying existing file: $local_path -> $target_path"
      run cp -a "$local_path" "$target_path"
    elif [[ "$FORCE" != "1" ]]; then
      die "$local_path exists but type mismatches expected $kind (use --force to replace)"
    fi

    stamp="$(date +%Y%m%d-%H%M%S)"
    backup="$LOCAL_CODEX_HOME/$(basename "$local_path").backup.$stamp"
    run mv "$local_path" "$backup"
    log "backup created: $backup"
  fi

  run ln -s "$target_path" "$local_path"
  log "persisted: $local_path -> $target_path"
}

persist_glob_states() {
  local pattern="$1"
  local dest_dir="$2"
  local f base target_file
  local matched=0

  shopt -s nullglob
  for f in $pattern; do
    [[ "$f" == *.backup.* ]] && continue
    matched=1
    base="$(basename "$f")"
    target_file="$dest_dir/$base"
    persist_one "$f" "$target_file" "file"
  done
  shopt -u nullglob

  if [[ "$matched" == "0" ]]; then
    log "no local sqlite state files found for pattern: $pattern"
  fi
}

check_all() {
  local entry name local_path target_path kind rc=0
  local f
  for entry in "${ITEMS[@]}"; do
    IFS='|' read -r name local_path target_path kind <<< "$entry"
    if [[ "$kind" == "glob" ]]; then
      shopt -s nullglob
      for f in $local_path; do
        [[ "$f" == *.backup.* ]] && continue
        target_path="$TARGET_ROOT/$(basename "$f")"
        check_link "$f" "$target_path" || rc=1
      done
      shopt -u nullglob
      continue
    fi
    check_link "$local_path" "$target_path" || rc=1
  done
  return "$rc"
}

if [[ "$CHECK_ONLY" == "1" ]]; then
  check_all
  exit $?
fi

run mkdir -p "$TARGET"
run mkdir -p "$TARGET_ROOT"
run mkdir -p "$LOCAL_CODEX_HOME"

for entry in "${ITEMS[@]}"; do
  IFS='|' read -r name local_path target_path kind <<< "$entry"
  if [[ "$kind" == "glob" ]]; then
    persist_glob_states "$local_path" "$target_path"
    continue
  fi
  persist_one "$local_path" "$target_path" "$kind"
done

if [[ "$DRY_RUN" == "1" ]]; then
  log "dry-run complete"
  exit 0
fi

check_all
