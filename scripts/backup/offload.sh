#!/usr/bin/env bash
# Upload local archives older than 24h to gdrive-crypt (B2, B3, B5, B6).
# Usage:
#   offload.sh              # offload all archives older than OFFLOAD_AGE_HOURS
#   offload.sh --oldest-one # offload only the oldest archive, ignoring age
#                           # (used by backup.sh for the low-space path)
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

backup_load_config
backup_ensure_dirs

MODE="aged"
if [[ "${1:-}" == "--oldest-one" ]]; then
  MODE="oldest-one"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--oldest-one]" >&2
  exit 2
fi

# Don't overlap with another offload; backup.sh calls offload_oldest_one via
# lib directly (or this flag) and holds its own lock, so this lock only
# serialises hourly timer runs / manual invocations.
exec 201>"$OFFLOAD_LOCK_FILE"
if ! flock -n 201; then
  log_warn "Another offload is already running; exiting"
  exit 0
fi

main() {
  log_info "=== offload start (mode=${MODE}) ==="
  case "$MODE" in
    oldest-one)
      if ! offload_oldest_one; then
        log_error "oldest-one offload failed"
        exit 1
      fi
      ;;
    aged)
      offload_aged
      ;;
  esac
  log_info "=== offload complete ==="
}

main "$@"
