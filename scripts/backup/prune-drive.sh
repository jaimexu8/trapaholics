#!/usr/bin/env bash
# Permanently delete Drive archives ≥ 30 days after verified upload (B7).
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

backup_load_config
backup_ensure_dirs

exec 202>"$PRUNE_LOCK_FILE"
if ! flock -n 202; then
  log_warn "Another prune is already running; exiting"
  exit 0
fi

main() {
  log_info "=== prune-drive start ==="
  local rc=0
  if ! prune_drive_from_log; then
    rc=1
  fi
  if ! prune_drive_safety_net; then
    rc=1
  fi
  if [[ "$rc" -ne 0 ]]; then
    log_error "prune-drive finished with errors"
    exit 1
  fi
  log_info "=== prune-drive complete ==="
}

main "$@"
