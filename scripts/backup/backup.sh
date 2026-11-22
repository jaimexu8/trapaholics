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
  # Alert already sent by acquire_backup_lock
  exit 1
fi

cleanup() {
  local rc=$?
  trap - EXIT
  # Always restore autosave.
  paper_save_on || true
  rm -rf "${REPO_ROOT}/.backup-staging" "$STAGING_DIR" 2>/dev/null || true
  # Any non-zero exit that hasn't already alerted gets a Discord alert.
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
    # discord already sent by backup_ensure_space
    exit 1
  fi

  paper_save_off

  local archive
  if ! archive="$(backup_create_archive)"; then
    log_error "Backup archive creation failed"
    discord_alert "backup failure" \
      "Archive creation failed on $(hostname -s 2>/dev/null || hostname). Check journalctl -u trapaholics-backup.service"
    exit 1
  fi

  # save-on runs via EXIT trap
  log_info "=== backup complete: ${archive} ==="
}

main "$@"
