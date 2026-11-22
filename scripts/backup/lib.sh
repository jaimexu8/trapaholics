# Shared helpers for trapaholics backup scripts.
# shellcheck shell=bash
# Intended to be sourced:  source "$(dirname "$0")/lib.sh"

# Prevent double-sourcing
if [[ -n "${TRAPAHOLICS_BACKUP_LIB_LOADED:-}" ]]; then
  # shellcheck disable=SC2317
  return 0 2>/dev/null || true
fi
TRAPAHOLICS_BACKUP_LIB_LOADED=1

_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_CONF="${BACKUP_CONF:-${_lib_dir}/backup.conf}"

# ---------------------------------------------------------------------------
# Config + env
# ---------------------------------------------------------------------------

backup_load_config() {
  # Defaults (overridden by backup.conf)
  REPO_ROOT=""
  BACKUP_SUBDIR="backups"
  SAFETY_MARGIN_BYTES=$((5 * 1024 * 1024 * 1024))
  BACKUP_SIZE_MULTIPLIER="1.25"
  RCLONE_REMOTE="gdrive-crypt:"
  RCLONE_BWLIMIT="8M"
  OFFLOAD_AGE_HOURS=24
  PRUNE_AGE_DAYS=30
  PRUNE_SAFETY_MIN_AGE_DAYS=31
  OFFLOAD_FAIL_ALERT_THRESHOLD=3
  PAPER_CONTAINERS="survival creative"
  MARIADB_CONTAINER="mariadb"
  MARIADB_DATABASE="luckperms"
  BACKUP_EXCLUDES="libraries cache versions logs/*.log.gz"
  BACKUP_INCLUDE_PATHS="velocity survival creative config scripts docker-compose.yml .env frpc.toml relay"
  LOCK_NAME=".backup.lock"
  OFFLOAD_LOCK_NAME=".offload.lock"
  PRUNE_LOCK_NAME=".prune.lock"
  UPLOADED_LOG_NAME=".uploaded.log"
  OFFLOAD_FAIL_COUNT_NAME=".offload-fail-count"

  if [[ -f "$BACKUP_CONF" ]]; then
    # shellcheck disable=SC1090
    source "$BACKUP_CONF"
  else
    log_warn "backup.conf not found at ${BACKUP_CONF}; using built-in defaults"
  fi

  if [[ -z "${REPO_ROOT}" ]]; then
    REPO_ROOT="$(cd "${_lib_dir}/../.." && pwd)"
  fi

  BACKUP_DIR="${BACKUP_DIR:-${REPO_ROOT}/${BACKUP_SUBDIR}}"
  ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
  STAGING_DIR="${STAGING_DIR:-${BACKUP_DIR}/.staging}"
  UPLOADED_LOG="${BACKUP_DIR}/${UPLOADED_LOG_NAME}"
  OFFLOAD_FAIL_COUNT_FILE="${BACKUP_DIR}/${OFFLOAD_FAIL_COUNT_NAME}"
  # Consumed by backup.sh / offload.sh / prune-drive.sh after sourcing.
  # shellcheck disable=SC2034
  LOCK_FILE="${BACKUP_DIR}/${LOCK_NAME}"
  # shellcheck disable=SC2034
  OFFLOAD_LOCK_FILE="${BACKUP_DIR}/${OFFLOAD_LOCK_NAME}"
  # shellcheck disable=SC2034
  PRUNE_LOCK_FILE="${BACKUP_DIR}/${PRUNE_LOCK_NAME}"

  # Allow tests / callers to override external tools via env.
  DOCKER_BIN="${DOCKER_BIN:-docker}"
  RCLONE_BIN="${RCLONE_BIN:-rclone}"
  TAR_BIN="${TAR_BIN:-tar}"
  ZSTD_BIN="${ZSTD_BIN:-zstd}"
  DF_BIN="${DF_BIN:-df}"
  DATE_BIN="${DATE_BIN:-date}"
  CURL_BIN="${CURL_BIN:-curl}"
}

# Read KEY=value from .env without sourcing the whole file. Strips surrounding quotes.
# Does not print the value. Sets the named variable in the caller.
backup_get_env() {
  local key="$1"
  local dest_var="$2"
  local file="${3:-$ENV_FILE}"
  local line raw
  if [[ ! -f "$file" ]]; then
    printf -v "$dest_var" '%s' ""
    return 1
  fi
  line="$(grep -E "^${key}=" "$file" 2>/dev/null | tail -n1 || true)"
  if [[ -z "$line" ]]; then
    printf -v "$dest_var" '%s' ""
    return 1
  fi
  raw="${line#*=}"
  if [[ "$raw" == \"*\" ]]; then
    raw="${raw#\"}"
    raw="${raw%\"}"
  elif [[ "$raw" == \'*\' ]]; then
    raw="${raw#\'}"
    raw="${raw%\'}"
  fi
  printf -v "$dest_var" '%s' "$raw"
  return 0
}

# ---------------------------------------------------------------------------
# Logging (systemd journal picks up stdout/stderr)
# ---------------------------------------------------------------------------

# All logs go to stderr so command substitutions only capture return values.
log_info()  { printf '%s [INFO]  %s\n'  "$(_ts)" "$*" >&2; }
log_warn()  { printf '%s [WARN]  %s\n'  "$(_ts)" "$*" >&2; }
log_error() { printf '%s [ERROR] %s\n'  "$(_ts)" "$*" >&2; }

_ts() { "$DATE_BIN" -u '+%Y-%m-%dT%H:%M:%SZ'; }

# ---------------------------------------------------------------------------
# Discord alerts (webhook URL never logged)
# ---------------------------------------------------------------------------

# discord_alert <title> <message>
discord_alert() {
  local title="$1"
  local message="$2"
  local webhook=""
  backup_get_env DISCORD_WEBHOOK_URL webhook || true
  if [[ -z "$webhook" ]]; then
    log_warn "DISCORD_WEBHOOK_URL unset; skipping Discord alert: ${title}"
    return 0
  fi
  local payload
  payload="$(printf '{"content":"%s"}' \
    "$(printf '%s\n%s' "**trapaholics backup:** ${title}" "${message}" \
      | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g')")"
  if ! "$CURL_BIN" -fsS -H 'Content-Type: application/json' \
      -d "$payload" "$webhook" >/dev/null; then
    log_warn "Discord alert delivery failed (webhook URL not logged)"
    return 1
  fi
  log_info "Discord alert sent: ${title}"
  return 0
}

# ---------------------------------------------------------------------------
# Filesystem helpers
# ---------------------------------------------------------------------------

backup_ensure_dirs() {
  mkdir -p "$BACKUP_DIR" "$STAGING_DIR"
  chmod 700 "$BACKUP_DIR"
}

# Free bytes on the filesystem that holds BACKUP_DIR.
backup_free_bytes() {
  local path="${1:-$BACKUP_DIR}"
  # POSIX portable: df -Pk prints 1024-byte blocks; available is column 4.
  "$DF_BIN" -Pk "$path" | awk 'NR==2 { print $4 * 1024 }'
}

# Bytes of live data that would go into a first backup (excludes mariadb/, data/).
backup_live_data_bytes() {
  local total=0
  local item path
  # shellcheck disable=SC2086
  for item in $BACKUP_INCLUDE_PATHS; do
    path="${REPO_ROOT}/${item}"
    if [[ -e "$path" ]]; then
      total=$((total + $(du -sk "$path" 2>/dev/null | awk '{print $1 * 1024}')))
    fi
  done
  printf '%s' "$total"
}

# Size of newest local .tar.zst archive, or 0 if none.
backup_newest_archive_bytes() {
  local newest
  newest="$(backup_list_archives | tail -n1 || true)"
  if [[ -z "$newest" || ! -f "$newest" ]]; then
    printf '0'
    return 0
  fi
  # Portable size
  wc -c <"$newest" | tr -d ' '
}

# Estimate bytes needed for the next archive (before safety margin).
backup_estimate_bytes() {
  local newest
  newest="$(backup_newest_archive_bytes)"
  if [[ "$newest" -gt 0 ]]; then
    # awk for float multiply then truncate
    awk -v n="$newest" -v m="$BACKUP_SIZE_MULTIPLIER" 'BEGIN { printf "%d", n * m }'
  else
    backup_live_data_bytes
  fi
}

# List local archives oldest-first (full paths).
backup_list_archives() {
  # Prefer null-safe find; sort by mtime then name.
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'trapaholics-*.tar.zst' -print 2>/dev/null \
    | while IFS= read -r f; do
        printf '%s\t%s\n' "$(stat_mtime "$f")" "$f"
      done \
    | sort -n \
    | cut -f2-
}

stat_mtime() {
  # GNU stat first, then BSD.
  if stat -c '%Y' "$1" >/dev/null 2>&1; then
    stat -c '%Y' "$1"
  else
    stat -f '%m' "$1"
  fi
}

file_age_hours() {
  local path="$1"
  local now mtime
  now="$("$DATE_BIN" +%s)"
  mtime="$(stat_mtime "$path")"
  awk -v now="$now" -v m="$mtime" 'BEGIN { printf "%d", (now - m) / 3600 }'
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  else
    shasum -a 256 "$path" | awk '{print $1}'
  fi
}

write_sha256() {
  local archive="$1"
  local sum
  sum="$(sha256_file "$archive")"
  # Format compatible with sha256sum -c
  printf '%s  %s\n' "$sum" "$(basename "$archive")" >"${archive}.sha256"
  chmod 600 "${archive}.sha256"
}

# ---------------------------------------------------------------------------
# Docker / RCON helpers
# ---------------------------------------------------------------------------

container_running() {
  local name="$1"
  local state
  state="$("$DOCKER_BIN" inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)"
  [[ "$state" == "true" ]]
}

rcon_cmd() {
  local container="$1"
  shift
  "$DOCKER_BIN" exec "$container" rcon-cli "$@"
}

# Track which paper containers we successfully ran save-off on.
SAVE_OFF_CONTAINERS=()

paper_save_off() {
  SAVE_OFF_CONTAINERS=()
  local c
  # shellcheck disable=SC2086
  for c in $PAPER_CONTAINERS; do
    if ! container_running "$c"; then
      log_warn "container ${c} not running; skipping save-off"
      continue
    fi
    log_info "RCON ${c}: save-off"
    rcon_cmd "$c" save-off
    log_info "RCON ${c}: save-all flush"
    rcon_cmd "$c" save-all flush
    SAVE_OFF_CONTAINERS+=("$c")
  done
}

paper_save_on() {
  local c
  for c in "${SAVE_OFF_CONTAINERS[@]+"${SAVE_OFF_CONTAINERS[@]}"}"; do
    if ! container_running "$c"; then
      log_warn "container ${c} not running; cannot restore save-on"
      continue
    fi
    log_info "RCON ${c}: save-on"
    if ! rcon_cmd "$c" save-on; then
      log_error "failed to restore save-on on ${c}"
    fi
  done
  SAVE_OFF_CONTAINERS=()
}

# ---------------------------------------------------------------------------
# MariaDB dump
# ---------------------------------------------------------------------------

mariadb_dump_to() {
  local outfile="$1"
  local password=""
  if ! container_running "$MARIADB_CONTAINER"; then
    log_warn "container ${MARIADB_CONTAINER} not running; skipping DB dump"
    return 0
  fi
  if ! backup_get_env MARIADB_ROOT_PASSWORD password; then
    log_error "MARIADB_ROOT_PASSWORD missing from .env; cannot dump database"
    return 1
  fi
  log_info "Dumping ${MARIADB_DATABASE} from ${MARIADB_CONTAINER}"
  # -pPASSWORD (no space). Password is not written to the journal.
  "$DOCKER_BIN" exec "$MARIADB_CONTAINER" \
    mariadb-dump -uroot -p"${password}" --single-transaction --databases "$MARIADB_DATABASE" \
    >"$outfile"
  chmod 600 "$outfile"
}

# ---------------------------------------------------------------------------
# Archive creation
# ---------------------------------------------------------------------------

backup_build_tar_args() {
  local -n _out="$1"
  _out=()
  local ex
  # shellcheck disable=SC2086
  for ex in $BACKUP_EXCLUDES; do
    _out+=(--exclude="$ex")
  done
  # Always exclude unused legacy data/ and live MariaDB datadir if somehow listed.
  _out+=(--exclude='data' --exclude='mariadb' --exclude='backups')
}

# Create trapaholics-YYYY-MM-DD_HHMM.tar.zst + .sha256 in BACKUP_DIR.
# Prints the archive path on stdout (last line); logs go to stderr via log_*.
backup_create_archive() {
  local stamp name archive dump_abs
  stamp="$("$DATE_BIN" -u '+%Y-%m-%d_%H%M')"
  name="trapaholics-${stamp}.tar.zst"
  archive="${BACKUP_DIR}/${name}"
  dump_abs="${STAGING_DIR}/${MARIADB_DATABASE}.sql"

  rm -rf "$STAGING_DIR"
  mkdir -p "$STAGING_DIR"
  chmod 700 "$STAGING_DIR"

  if ! mariadb_dump_to "$dump_abs"; then
    return 1
  fi

  local tar_excludes=()
  backup_build_tar_args tar_excludes

  local include_args=()
  local item
  # shellcheck disable=SC2086
  for item in $BACKUP_INCLUDE_PATHS; do
    if [[ -e "${REPO_ROOT}/${item}" ]]; then
      include_args+=("$item")
    else
      log_warn "include path missing, skipping: ${item}"
    fi
  done

  # Stage dump so it appears at .backup-staging/<db>.sql inside the archive
  # without putting staging under REPO_ROOT permanently.
  local stage_link="${REPO_ROOT}/.backup-staging"
  rm -rf "$stage_link"
  if [[ -f "$dump_abs" ]]; then
    mkdir -p "$stage_link"
    cp -a "$dump_abs" "${stage_link}/${MARIADB_DATABASE}.sql"
    include_args+=(".backup-staging")
  else
    log_warn "No DB dump file; archive will not include MariaDB dump"
  fi

  log_info "Creating archive ${name}"
  # tar → zstd. Use -C REPO_ROOT so paths are relative.
  if [[ ${#include_args[@]} -eq 0 ]]; then
    log_error "nothing to archive under ${REPO_ROOT}"
    rm -rf "$stage_link"
    return 1
  fi
  if ! "$TAR_BIN" -C "$REPO_ROOT" "${tar_excludes[@]}" -cf - "${include_args[@]}" \
      | "$ZSTD_BIN" -T0 -q -o "$archive"; then
    rm -f "$archive"
    rm -rf "$stage_link"
    log_error "tar|zstd failed"
    return 1
  fi
  rm -rf "$stage_link"
  chmod 600 "$archive"

  log_info "Verifying archive with zstd -t"
  if ! "$ZSTD_BIN" -t "$archive"; then
    log_error "zstd -t failed for ${name}"
    rm -f "$archive"
    return 1
  fi

  write_sha256 "$archive"
  rm -rf "$STAGING_DIR"
  log_info "Archive ready: ${archive} ($(wc -c <"$archive" | tr -d ' ') bytes)"
  printf '%s\n' "$archive"
}

# ---------------------------------------------------------------------------
# Offload (rclone copy → cryptcheck → log → delete)
# ---------------------------------------------------------------------------

rclone_bwlimit_args() {
  if [[ -n "${RCLONE_BWLIMIT}" ]]; then
    printf -- '--bwlimit=%s' "$RCLONE_BWLIMIT"
  fi
}

# offload_archive <local-tar.zst-path>
# Returns 0 only after verified upload and local delete.
offload_archive() {
  local archive="$1"
  local base remote_args=()
  local bw
  bw="$(rclone_bwlimit_args || true)"
  if [[ -n "$bw" ]]; then
    remote_args+=("$bw")
  fi

  if [[ ! -f "$archive" ]]; then
    log_error "offload: archive not found: ${archive}"
    return 1
  fi
  base="$(basename "$archive")"

  log_info "Uploading ${base} → ${RCLONE_REMOTE}"
  if ! "$RCLONE_BIN" copy "$archive" "$RCLONE_REMOTE" "${remote_args[@]+"${remote_args[@]}"}"; then
    log_error "rclone copy failed for ${base}"
    _offload_fail_bump "rclone copy failed for ${base}"
    return 1
  fi

  # Also upload the checksum file (not encrypted content of interest, but useful).
  if [[ -f "${archive}.sha256" ]]; then
    if ! "$RCLONE_BIN" copy "${archive}.sha256" "$RCLONE_REMOTE" "${remote_args[@]+"${remote_args[@]}"}"; then
      log_warn "rclone copy of ${base}.sha256 failed (continuing; cryptcheck is authoritative)"
    fi
  fi

  log_info "Verifying ${base} with rclone cryptcheck"
  if ! "$RCLONE_BIN" cryptcheck "$archive" "$RCLONE_REMOTE" "${remote_args[@]+"${remote_args[@]}"}"; then
    log_error "rclone cryptcheck FAILED for ${base}; keeping local copy (B5)"
    _offload_fail_bump "rclone cryptcheck failed for ${base}"
    return 1
  fi

  local uploaded_at
  uploaded_at="$("$DATE_BIN" -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s %s\n' "$base" "$uploaded_at" >>"$UPLOADED_LOG"
  chmod 600 "$UPLOADED_LOG" 2>/dev/null || true

  log_info "Verified upload of ${base} at ${uploaded_at}; deleting local archive"
  rm -f "$archive" "${archive}.sha256"
  _offload_fail_reset
  return 0
}

_offload_fail_bump() {
  local reason="$1"
  local count=0
  if [[ -f "$OFFLOAD_FAIL_COUNT_FILE" ]]; then
    count="$(tr -d '[:space:]' <"$OFFLOAD_FAIL_COUNT_FILE" || echo 0)"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$OFFLOAD_FAIL_COUNT_FILE"
  if [[ "$count" -ge "$OFFLOAD_FAIL_ALERT_THRESHOLD" ]]; then
    discord_alert "upload/verify failure" \
      "Repeated offload failures (${count}): ${reason}"
    _offload_fail_reset
  fi
}

_offload_fail_reset() {
  rm -f "$OFFLOAD_FAIL_COUNT_FILE"
}

# Offload a single oldest local archive, ignoring the 24h age rule.
# Returns 1 if nothing to offload or upload failed.
offload_oldest_one() {
  local oldest
  oldest="$(backup_list_archives | head -n1 || true)"
  if [[ -z "$oldest" ]]; then
    log_warn "no local archives available to offload"
    return 1
  fi
  log_info "Offloading oldest archive (age rule ignored): $(basename "$oldest")"
  offload_archive "$oldest"
}

# Offload every local archive older than OFFLOAD_AGE_HOURS (oldest first).
offload_aged() {
  local f age
  local any=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    age="$(file_age_hours "$f")"
    if [[ "$age" -ge "$OFFLOAD_AGE_HOURS" ]]; then
      any=1
      offload_archive "$f" || log_warn "offload of $(basename "$f") failed; will retry later"
    fi
  done < <(backup_list_archives)
  if [[ "$any" -eq 0 ]]; then
    log_info "no local archives older than ${OFFLOAD_AGE_HOURS}h"
  fi
}

# ---------------------------------------------------------------------------
# Space management for backup.sh
# ---------------------------------------------------------------------------

# Ensure free space >= estimate + safety margin by offloading oldest archives.
# Returns 0 if enough space, 1 if not (after attempting offloads).
backup_ensure_space() {
  local estimate needed free
  estimate="$(backup_estimate_bytes)"
  needed=$((estimate + SAFETY_MARGIN_BYTES))
  free="$(backup_free_bytes)"
  log_info "Space check: free=${free} estimate=${estimate} margin=${SAFETY_MARGIN_BYTES} needed=${needed}"

  while [[ "$free" -lt "$needed" ]]; do
    log_warn "Insufficient free space (${free} < ${needed}); offloading oldest local backup"
    if ! offload_oldest_one; then
      log_error "Cannot free enough space (Drive unreachable or nothing left to move)"
      discord_alert "backup skipped (low disk)" \
        "Needed ${needed} bytes, free ${free}. Offload failed or no archives left. Aborting without deleting anything."
      return 1
    fi
    free="$(backup_free_bytes)"
    log_info "After offload: free=${free}"
  done
  return 0
}

# ---------------------------------------------------------------------------
# Prune Drive
# ---------------------------------------------------------------------------

# Parse uploaded log; delete remote files with upload time >= PRUNE_AGE_DAYS ago.
prune_drive_from_log() {
  local tmp
  local line fname uploaded_at uploaded_epoch cutoff now
  now="$("$DATE_BIN" +%s)"
  cutoff=$((now - PRUNE_AGE_DAYS * 24 * 3600))

  if [[ ! -f "$UPLOADED_LOG" ]]; then
    log_info "No ${UPLOADED_LOG_NAME}; nothing to prune from log"
    return 0
  fi

  tmp="$(mktemp)"
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    fname="${line%% *}"
    uploaded_at="${line#* }"
    uploaded_at="${uploaded_at%% *}"  # tolerate extra fields
    uploaded_epoch="$(parse_utc_iso "$uploaded_at")" || {
      log_warn "unparseable upload time in log, keeping line: ${line}"
      printf '%s\n' "$line" >>"$tmp"
      continue
    }
    if [[ "$uploaded_epoch" -le "$cutoff" ]]; then
      log_info "Pruning Drive file ${fname} (uploaded ${uploaded_at})"
      if ! "$RCLONE_BIN" deletefile "${RCLONE_REMOTE}${fname}" --drive-use-trash=false; then
        log_error "Failed to delete ${fname} from Drive"
        printf '%s\n' "$line" >>"$tmp"
        discord_alert "prune failure" "rclone deletefile failed for ${fname}"
        continue
      fi
      # Best-effort delete companion checksum
      "$RCLONE_BIN" deletefile "${RCLONE_REMOTE}${fname}.sha256" --drive-use-trash=false 2>/dev/null || true
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$UPLOADED_LOG"

  mv "$tmp" "$UPLOADED_LOG"
  chmod 600 "$UPLOADED_LOG" 2>/dev/null || true
}

prune_drive_safety_net() {
  log_info "Safety-net prune: rclone delete ${RCLONE_REMOTE} --min-age ${PRUNE_SAFETY_MIN_AGE_DAYS}d"
  if ! "$RCLONE_BIN" delete "$RCLONE_REMOTE" \
      --min-age "${PRUNE_SAFETY_MIN_AGE_DAYS}d" \
      --drive-use-trash=false; then
    log_error "Safety-net prune failed"
    discord_alert "prune failure" "rclone delete --min-age ${PRUNE_SAFETY_MIN_AGE_DAYS}d failed"
    return 1
  fi
  return 0
}

# Parse UTC ISO-8601 like 2026-11-22T04:00:00Z → epoch seconds.
parse_utc_iso() {
  local iso="$1"
  if "$DATE_BIN" -u -d "$iso" +%s >/dev/null 2>&1; then
    "$DATE_BIN" -u -d "$iso" +%s
  elif "$DATE_BIN" -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s >/dev/null 2>&1; then
    "$DATE_BIN" -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s
  else
    return 1
  fi
}
