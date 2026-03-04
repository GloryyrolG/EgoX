#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOLT_DIR="$ROOT_DIR/bolt"
ENV_SETUP_SH="$BOLT_DIR/setup_envs.sh"
CODEX_PERSIST_SH="$BOLT_DIR/persist_codex_sessions.sh"

MODE="all"
ENV_ROOT="/mnt/shared/envs"
CODEX_TARGET="/mnt/shared/codex/sessions"
CODEX_FORCE=0
CODEX_DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage: bolt/setup.sh [mode] [options]

Modes:
  all      Run env setup + codex persistence (default)
  env      Run env setup only
  codex    Run codex persistence only
  check    Validate setup state (env dirs + codex links)

Options:
  --env-root <dir>      Conda env root for setup_envs.sh (default: /mnt/shared/envs)
  --codex-target <dir>  Codex sessions target dir (default: /mnt/shared/codex/sessions)
  --force               Pass --force to codex persistence
  --dry-run             Pass --dry-run to codex persistence
  -h, --help            Show help
USAGE
}

log() {
  printf '[setup] %s\n' "$*"
}

die() {
  printf '[setup] ERROR: %s\n' "$*" >&2
  exit 1
}

parse_args() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      all|env|codex|check)
        MODE="$1"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
    esac
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env-root)
        shift
        [[ $# -gt 0 ]] || die "--env-root requires a value"
        ENV_ROOT="$1"
        ;;
      --codex-target)
        shift
        [[ $# -gt 0 ]] || die "--codex-target requires a value"
        CODEX_TARGET="$1"
        ;;
      --force)
        CODEX_FORCE=1
        ;;
      --dry-run)
        CODEX_DRY_RUN=1
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
}

ensure_scripts() {
  [[ -x "$ENV_SETUP_SH" ]] || die "missing executable: $ENV_SETUP_SH"
  [[ -x "$CODEX_PERSIST_SH" ]] || die "missing executable: $CODEX_PERSIST_SH"
}

run_env_setup() {
  log "env setup: $ENV_ROOT"
  bash "$ENV_SETUP_SH" "$ENV_ROOT"
}

run_codex_persist() {
  local args=("--target" "$CODEX_TARGET")
  [[ "$CODEX_FORCE" == "1" ]] && args+=("--force")
  [[ "$CODEX_DRY_RUN" == "1" ]] && args+=("--dry-run")
  log "codex persistence: ${args[*]}"
  bash "$CODEX_PERSIST_SH" "${args[@]}"
}

check_env_state() {
  local egox_env="$ENV_ROOT/egox"
  local ego_prior_env="$ENV_ROOT/egox-egoprior"
  [[ -d "$egox_env" ]] || die "env missing: $egox_env"
  [[ -d "$ego_prior_env" ]] || die "env missing: $ego_prior_env"
  log "env check OK: $egox_env, $ego_prior_env"
}

check_codex_state() {
  log "codex check: --target $CODEX_TARGET"
  bash "$CODEX_PERSIST_SH" --target "$CODEX_TARGET" --check
}

main() {
  parse_args "$@"
  ensure_scripts

  case "$MODE" in
    all)
      run_env_setup
      run_codex_persist
      ;;
    env)
      run_env_setup
      ;;
    codex)
      run_codex_persist
      ;;
    check)
      check_env_state
      check_codex_state
      ;;
    *)
      die "unsupported mode: $MODE"
      ;;
  esac
}

main "$@"
