#!/usr/bin/env bash
set -euo pipefail
exec "$(cd "$(dirname "$0")/.." && pwd)/bolt/codex_autoload.sh" "$@"
