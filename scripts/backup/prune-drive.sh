#!/usr/bin/env bash
# Permanently delete Drive archives ≥ 30 days after verified upload (B7).
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

backup_load_config || exit 1
backup_ensure_dirs || exit 1
backup_warn_missing_webhook

# Hold the offload lock while rewriting .uploaded.log so offload can't append mid-prune.
if ! acquire_offload_lock "$OFFLOAD_LOCK_WAIT_SEC"; then
  exit 1
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
