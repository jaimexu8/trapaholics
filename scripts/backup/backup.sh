#!/usr/bin/env bash
# Full-network backup every 4 hours (B1, B4). See docs/BACKUPS.md.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

backup_load_config
backup_ensure_dirs

# Single-flight: don't overlap with another backup run.
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log_warn "Another backup is already running; exiting"
  exit 0
fi

cleanup() {
  # Always restore autosave (B: trap save-on).
  paper_save_on || true
  rm -rf "${REPO_ROOT}/.backup-staging" "$STAGING_DIR" 2>/dev/null || true
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
    discord_alert "backup failure" "Archive creation failed on $(hostname). Check journalctl -u trapaholics-backup.service"
    exit 1
  fi

  # save-on runs via EXIT trap
  log_info "=== backup complete: ${archive} ==="
}

main "$@"
