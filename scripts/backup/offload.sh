#!/usr/bin/env bash
# Upload local archives older than 24h to gdrive-crypt (B2, B3, B5, B6).
# Usage:
#   offload.sh              # offload all archives older than OFFLOAD_AGE_HOURS
#   offload.sh --oldest-one # offload only the oldest archive, ignoring age
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

backup_load_config || exit 1
backup_ensure_dirs || exit 1
backup_warn_missing_webhook

MODE="aged"
if [[ "${1:-}" == "--oldest-one" ]]; then
  MODE="oldest-one"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--oldest-one]" >&2
  exit 2
fi

# Non-blocking: if backup_ensure_space (or another offload) holds the lock, alert and exit.
if ! acquire_offload_lock 0; then
  exit 1
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
