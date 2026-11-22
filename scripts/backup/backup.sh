#!/usr/bin/env bash
# Full-network backup every 4 hours (B1, B4). See docs/BACKUPS.md.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

backup_load_config || exit 1
backup_ensure_dirs || exit 1
backup_warn_missing_webhook

# Single-flight: don't overlap with another backup run.
if ! acquire_backup_lock; then
  exit 1
fi

# Drop leftovers from interrupted runs before we start.
backup_cleanup_partials

cleanup() {
  local rc=$?
  trap - EXIT
  paper_save_on || true
  rm -rf "${REPO_ROOT}/.backup-staging" "$STAGING_DIR" 2>/dev/null || true
  release_offload_lock || true
  if [[ "$rc" -ne 0 && "${ALERT_SENT:-0}" -eq 0 ]]; then
    discord_alert "backup failure" \
      "backup.sh exited ${rc} on $(hostname -s 2>/dev/null || hostname). Check journalctl -u trapaholics-backup.service" || true
  fi
  exit "$rc"
}
trap cleanup EXIT

main() {
  log_info "=== backup start (repo=${REPO_ROOT}) ==="

  if ! backup_ensure_space; then
    log_error "Aborting backup: insufficient space after offload attempts"
    exit 1
  fi
  # backup_ensure_space releases the offload lock itself; belt-and-suspenders:
  release_offload_lock || true

  paper_save_off

  local archive
  if ! archive="$(backup_create_archive)"; then
    log_error "Backup archive creation failed"
    discord_alert "backup failure" \
      "Archive creation failed on $(hostname -s 2>/dev/null || hostname). Check journalctl -u trapaholics-backup.service"
    exit 1
  fi

  log_info "=== backup complete: ${archive} ==="
}

main "$@"
