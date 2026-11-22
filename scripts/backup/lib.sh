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

# Set when discord_alert successfully sends; EXIT handlers use this to avoid dupes.
ALERT_SENT=0

# Archive basename pattern (and optional .sha256 companion).
ARCHIVE_NAME_RE='^trapaholics-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}\.tar\.zst$'
ARCHIVE_OR_SHA_RE='^trapaholics-[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}\.tar\.zst(\.sha256)?$'

# ---------------------------------------------------------------------------
# Config + env
# ---------------------------------------------------------------------------

_BACKUP_OVERRIDE_KEYS=(
  REPO_ROOT BACKUP_SUBDIR BACKUP_DIR ENV_FILE STAGING_DIR
  SAFETY_MARGIN_BYTES BACKUP_SIZE_MULTIPLIER
  RCLONE_REMOTE RCLONE_BWLIMIT
  OFFLOAD_AGE_HOURS PRUNE_AGE_DAYS PRUNE_SAFETY_MIN_AGE_DAYS
  OFFLOAD_FAIL_ALERT_THRESHOLD OFFLOAD_LOCK_SKIP_ALERT_THRESHOLD
  PAPER_CONTAINERS MARIADB_CONTAINER MARIADB_DATABASE
  BACKUP_EXCLUDES BACKUP_INCLUDE_PATHS
  DOCKER_TIMEOUT_SEC SAVE_ALL_FLUSH_TIMEOUT_SEC MARIADB_DUMP_TIMEOUT_SEC
  OFFLOAD_LOCK_WAIT_SEC PRUNE_LOCK_WAIT_SEC
  LOCK_NAME OFFLOAD_LOCK_NAME PRUNE_LOCK_NAME
  UPLOADED_LOG_NAME OFFLOAD_FAIL_COUNT_NAME OFFLOAD_LOCK_SKIP_COUNT_NAME
  DOCKER_BIN RCLONE_BIN TAR_BIN ZSTD_BIN DF_BIN DATE_BIN CURL_BIN TIMEOUT_BIN FLOCK_BIN
  SHA256SUM_BIN BACKUP_ARCHIVE_STAMP
)

_backup_snapshot_env_overrides() {
  _BACKUP_OVERRIDE_SNAPSHOT=()
  local key val
  for key in "${_BACKUP_OVERRIDE_KEYS[@]}"; do
    if val="$(printenv "$key" 2>/dev/null)"; then
      _BACKUP_OVERRIDE_SNAPSHOT+=("${key}=${val}")
    fi
  done
}

_backup_apply_env_overrides() {
  local entry key val
  for entry in "${_BACKUP_OVERRIDE_SNAPSHOT[@]+"${_BACKUP_OVERRIDE_SNAPSHOT[@]}"}"; do
    key="${entry%%=*}"
    val="${entry#*=}"
    printf -v "$key" '%s' "$val"
  done
}

backup_validate_rclone_remote() {
  local remote="${RCLONE_REMOTE:-}"
  if [[ -z "$remote" ]]; then
    log_error "RCLONE_REMOTE is empty; refusing to continue"
    return 1
  fi
  if [[ ! "$remote" =~ ^gdrive-crypt: ]]; then
    log_error "RCLONE_REMOTE must match gdrive-crypt: or gdrive-crypt:<subpath> (got '${remote}')"
    return 1
  fi
  return 0
}

# Detect GNU tar once (for --anchored). Capture --version; never pipe under pipefail.
_detect_gnu_tar() {
  local ver
  TAR_IS_GNU=0
  ver="$("$TAR_BIN" --version 2>/dev/null)" || true
  if [[ "$ver" == *GNU\ tar* || "$ver" == GNU* ]]; then
    TAR_IS_GNU=1
  fi
}

backup_load_config() {
  _backup_snapshot_env_overrides

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
  OFFLOAD_LOCK_SKIP_ALERT_THRESHOLD=3
  PAPER_CONTAINERS="survival creative"
  MARIADB_CONTAINER="mariadb"
  MARIADB_DATABASE="luckperms"
  BACKUP_EXCLUDES="survival/libraries survival/cache survival/versions creative/libraries creative/cache creative/versions velocity/libraries survival/logs/*.log.gz creative/logs/*.log.gz"
  BACKUP_INCLUDE_PATHS="velocity survival creative config scripts docker-compose.yml .env frpc.toml relay"
  DOCKER_TIMEOUT_SEC=60
  SAVE_ALL_FLUSH_TIMEOUT_SEC=300
  MARIADB_DUMP_TIMEOUT_SEC=900
  # Keep well under backup unit TimeoutStartSec=2h (worst case + archive time).
  OFFLOAD_LOCK_WAIT_SEC=1800
  # Consumed by prune-drive.sh after sourcing.
  # shellcheck disable=SC2034
  PRUNE_LOCK_WAIT_SEC=900
  LOCK_NAME=".backup.lock"
  OFFLOAD_LOCK_NAME=".offload.lock"
  PRUNE_LOCK_NAME=".prune.lock"
  UPLOADED_LOG_NAME=".uploaded.log"
  OFFLOAD_FAIL_COUNT_NAME=".offload-fail-count"
  OFFLOAD_LOCK_SKIP_COUNT_NAME=".offload-lock-skip-count"
  BACKUP_ARCHIVE_STAMP="${BACKUP_ARCHIVE_STAMP:-}"

  if [[ -f "$BACKUP_CONF" ]]; then
    # shellcheck disable=SC1090
    source "$BACKUP_CONF"
  else
    log_warn "backup.conf not found at ${BACKUP_CONF}; using built-in defaults"
  fi

  _backup_apply_env_overrides

  if [[ -z "${REPO_ROOT}" ]]; then
    REPO_ROOT="$(cd "${_lib_dir}/../.." && pwd)"
  fi

  BACKUP_DIR="${BACKUP_DIR:-${REPO_ROOT}/${BACKUP_SUBDIR}}"
  ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
  STAGING_DIR="${STAGING_DIR:-${BACKUP_DIR}/.staging}"
  UPLOADED_LOG="${BACKUP_DIR}/${UPLOADED_LOG_NAME}"
  OFFLOAD_FAIL_COUNT_FILE="${BACKUP_DIR}/${OFFLOAD_FAIL_COUNT_NAME}"
  OFFLOAD_LOCK_SKIP_COUNT_FILE="${BACKUP_DIR}/${OFFLOAD_LOCK_SKIP_COUNT_NAME}"
  # shellcheck disable=SC2034
  LOCK_FILE="${BACKUP_DIR}/${LOCK_NAME}"
  # shellcheck disable=SC2034
  OFFLOAD_LOCK_FILE="${BACKUP_DIR}/${OFFLOAD_LOCK_NAME}"
  # shellcheck disable=SC2034
  PRUNE_LOCK_FILE="${BACKUP_DIR}/${PRUNE_LOCK_NAME}"

  DOCKER_BIN="${DOCKER_BIN:-docker}"
  RCLONE_BIN="${RCLONE_BIN:-rclone}"
  TAR_BIN="${TAR_BIN:-tar}"
  ZSTD_BIN="${ZSTD_BIN:-zstd}"
  DF_BIN="${DF_BIN:-df}"
  DATE_BIN="${DATE_BIN:-date}"
  CURL_BIN="${CURL_BIN:-curl}"
  TIMEOUT_BIN="${TIMEOUT_BIN:-timeout}"
  FLOCK_BIN="${FLOCK_BIN:-flock}"
  if command -v sha256sum >/dev/null 2>&1; then
    SHA256SUM_BIN="${SHA256SUM_BIN:-sha256sum}"
  else
    SHA256SUM_BIN="${SHA256SUM_BIN:-shasum}"
  fi

  _backup_apply_env_overrides
  BACKUP_DIR="${BACKUP_DIR:-${REPO_ROOT}/${BACKUP_SUBDIR}}"
  ENV_FILE="${ENV_FILE:-${REPO_ROOT}/.env}"
  STAGING_DIR="${STAGING_DIR:-${BACKUP_DIR}/.staging}"
  UPLOADED_LOG="${BACKUP_DIR}/${UPLOADED_LOG_NAME}"
  OFFLOAD_FAIL_COUNT_FILE="${BACKUP_DIR}/${OFFLOAD_FAIL_COUNT_NAME}"
  OFFLOAD_LOCK_SKIP_COUNT_FILE="${BACKUP_DIR}/${OFFLOAD_LOCK_SKIP_COUNT_NAME}"
  # shellcheck disable=SC2034
  LOCK_FILE="${BACKUP_DIR}/${LOCK_NAME}"
  # shellcheck disable=SC2034
  OFFLOAD_LOCK_FILE="${BACKUP_DIR}/${OFFLOAD_LOCK_NAME}"
  # shellcheck disable=SC2034
  PRUNE_LOCK_FILE="${BACKUP_DIR}/${PRUNE_LOCK_NAME}"

  _detect_gnu_tar

  if ! backup_validate_rclone_remote; then
    return 1
  fi
}

backup_warn_missing_webhook() {
  local webhook=""
  if ! backup_get_env DISCORD_WEBHOOK_URL webhook || [[ -z "$webhook" ]]; then
    log_warn "DISCORD_WEBHOOK_URL unset; Discord alerts disabled"
  fi
}

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
# Logging
# ---------------------------------------------------------------------------

log_info()  { printf '%s [INFO]  %s\n'  "$(_ts)" "$*" >&2; }
log_warn()  { printf '%s [WARN]  %s\n'  "$(_ts)" "$*" >&2; }
log_error() { printf '%s [ERROR] %s\n'  "$(_ts)" "$*" >&2; }

_ts() { "$DATE_BIN" -u '+%Y-%m-%dT%H:%M:%SZ'; }

# ---------------------------------------------------------------------------
# Discord alerts
# ---------------------------------------------------------------------------

discord_alert() {
  local title="$1"
  local message="$2"
  local webhook=""
  backup_get_env DISCORD_WEBHOOK_URL webhook || true
  if [[ -z "$webhook" ]]; then
    log_warn "DISCORD_WEBHOOK_URL unset; skipping Discord alert: ${title}"
    return 0
  fi
  local body payload
  body="$(printf '%s\n%s' "**trapaholics backup:** ${title}" "${message}" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')"
  payload="$(printf '{"content":"%s"}' "$body")"
  if ! printf 'url = "%s"\n' "$webhook" | "$CURL_BIN" -fsS -K - \
      -H 'Content-Type: application/json' \
      -d "$payload" >/dev/null; then
    log_warn "Discord alert delivery failed (webhook URL not logged)"
    return 1
  fi
  # shellcheck disable=SC2034
  ALERT_SENT=1
  log_info "Discord alert sent: ${title}"
  return 0
}

# ---------------------------------------------------------------------------
# Filesystem helpers
# ---------------------------------------------------------------------------

backup_ensure_dirs() {
  mkdir -p "$BACKUP_DIR" "$STAGING_DIR" || return 1
  chmod 700 "$BACKUP_DIR" || return 1
}

# Remove leftover *.partial* and orphaned .sha256 files (call while holding backup lock).
backup_cleanup_partials() {
  local f base archive
  shopt -s nullglob
  for f in "$BACKUP_DIR"/trapaholics-*.partial "$BACKUP_DIR"/trapaholics-*.partial.*; do
    log_warn "removing stale partial: $(basename "$f")"
    rm -f "$f"
  done
  for f in "$BACKUP_DIR"/trapaholics-*.tar.zst.sha256; do
    base="$(basename "$f" .sha256)"
    archive="${BACKUP_DIR}/${base}"
    if [[ ! -f "$archive" ]]; then
      log_warn "removing orphaned checksum (no archive): $(basename "$f")"
      rm -f "$f"
    fi
  done
  shopt -u nullglob
}

backup_free_bytes() {
  # Multiply in bash — awk may print scientific notation for large products,
  # which bash arithmetic cannot parse.
  local kb
  kb="$("$DF_BIN" -Pk "$BACKUP_DIR" | awk 'NR==2 { print $4 }')"
  printf '%s' "$((kb * 1024))"
}

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

backup_newest_archive_bytes() {
  local newest
  newest="$(backup_list_archives | tail -n1 || true)"
  if [[ -z "$newest" || ! -f "$newest" ]]; then
    printf '0'
    return 0
  fi
  wc -c <"$newest" | tr -d ' '
}

backup_estimate_bytes() {
  local newest
  newest="$(backup_newest_archive_bytes)"
  if [[ "$newest" -gt 0 ]]; then
    awk -v n="$newest" -v m="$BACKUP_SIZE_MULTIPLIER" 'BEGIN { printf "%d", n * m }'
  else
    backup_live_data_bytes
  fi
}

# List local complete archives oldest-first by name. Skips *.partial.
backup_list_archives() {
  find "$BACKUP_DIR" -maxdepth 1 -type f -name 'trapaholics-*.tar.zst' ! -name '*.partial' -print 2>/dev/null \
    | while IFS= read -r f; do
        local base
        base="$(basename "$f")"
        if [[ "$base" =~ $ARCHIVE_NAME_RE ]]; then
          printf '%s\n' "$f"
        fi
      done \
    | sort
}

# Epoch seconds from trapaholics-YYYY-MM-DD_HHMM.tar.zst (UTC).
archive_stamp_epoch() {
  local base="$1"
  local stamp date_part time_part hh mm iso
  if [[ ! "$base" =~ $ARCHIVE_NAME_RE ]]; then
    return 1
  fi
  stamp="${base#trapaholics-}"
  stamp="${stamp%.tar.zst}"
  date_part="${stamp%_*}"
  time_part="${stamp#*_}"
  hh="${time_part:0:2}"
  mm="${time_part:2:2}"
  iso="${date_part}T${hh}:${mm}:00Z"
  parse_utc_iso "$iso"
}

# Age in whole hours from the filename UTC stamp (NOT mtime — R1).
file_age_hours() {
  local path="$1"
  local base epoch now
  base="$(basename "$path")"
  epoch="$(archive_stamp_epoch "$base")" || {
    log_warn "cannot parse stamp from ${base}"
    printf '0'
    return 1
  }
  now="$("$DATE_BIN" +%s)"
  awk -v now="$now" -v m="$epoch" 'BEGIN { printf "%d", (now - m) / 3600 }'
}

sha256_file() {
  local path="$1"
  if [[ "$(basename "$SHA256SUM_BIN")" == "shasum" ]]; then
    "$SHA256SUM_BIN" -a 256 "$path" | awk '{print $1}'
  else
    "$SHA256SUM_BIN" "$path" | awk '{print $1}'
  fi
}

verify_sha256() {
  local archive="$1"
  local sumfile="${archive}.sha256"
  local dir
  if [[ ! -f "$sumfile" ]]; then
    log_error "missing checksum file: ${sumfile}"
    return 1
  fi
  dir="$(dirname "$archive")"
  if [[ "$(basename "$SHA256SUM_BIN")" == "shasum" ]]; then
    (cd "$dir" && "$SHA256SUM_BIN" -a 256 -c "$(basename "$sumfile")")
  else
    (cd "$dir" && "$SHA256SUM_BIN" -c "$(basename "$sumfile")")
  fi
}

# ---------------------------------------------------------------------------
# Docker / RCON helpers
# ---------------------------------------------------------------------------

# with_timeout <seconds> <cmd...>
with_timeout() {
  local secs="$1"
  shift
  if command -v "$TIMEOUT_BIN" >/dev/null 2>&1 || [[ -x "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" "$secs" "$@"
  else
    "$@"
  fi
}

container_running() {
  local name="$1"
  local state
  state="$(with_timeout "$DOCKER_TIMEOUT_SEC" "$DOCKER_BIN" inspect -f '{{.State.Running}}' "$name" 2>/dev/null || true)"
  [[ "$state" == "true" ]]
}

rcon_cmd() {
  local container="$1"
  shift
  local secs="$DOCKER_TIMEOUT_SEC"
  # save-all flush can take a long time on big worlds
  if [[ "$*" == "save-all flush" ]]; then
    secs="$SAVE_ALL_FLUSH_TIMEOUT_SEC"
  fi
  with_timeout "$secs" "$DOCKER_BIN" exec "$container" rcon-cli "$@"
}

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
    SAVE_OFF_CONTAINERS+=("$c")
    log_info "RCON ${c}: save-off"
    rcon_cmd "$c" save-off || return 1
    log_info "RCON ${c}: save-all flush"
    rcon_cmd "$c" save-all flush || return 1
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
  if ! backup_get_env MARIADB_ROOT_PASSWORD password || [[ -z "$password" ]]; then
    log_error "MARIADB_ROOT_PASSWORD missing from .env; cannot dump database"
    return 1
  fi
  log_info "Dumping ${MARIADB_DATABASE} from ${MARIADB_CONTAINER}"
  # Inherit MYSQL_PWD from this process env into the container (-e MYSQL_PWD with
  # no =value). Keeps the password off docker's argv.
  if ! MYSQL_PWD="$password" with_timeout "$MARIADB_DUMP_TIMEOUT_SEC" \
      "$DOCKER_BIN" exec -e MYSQL_PWD "$MARIADB_CONTAINER" \
      mariadb-dump -uroot --single-transaction --databases "$MARIADB_DATABASE" \
      >"$outfile"; then
    log_error "mariadb-dump failed"
    rm -f "$outfile"
    return 1
  fi
  if [[ ! -s "$outfile" ]]; then
    log_error "mariadb-dump produced empty output"
    rm -f "$outfile"
    return 1
  fi
  chmod 600 "$outfile" || return 1
}

# ---------------------------------------------------------------------------
# Archive creation
# ---------------------------------------------------------------------------

backup_build_tar_args() {
  local -n _out="$1"
  _out=()
  if [[ "${TAR_IS_GNU:-0}" -eq 1 ]]; then
    _out+=(--anchored)
  fi
  local ex
  # shellcheck disable=SC2086
  for ex in $BACKUP_EXCLUDES; do
    _out+=(--exclude="$ex")
  done
}

# Create trapaholics-YYYY-MM-DD_HHMM.tar.zst + .sha256 in BACKUP_DIR.
# Writes via .partial; writes .sha256 to the final path BEFORE moving the archive.
backup_create_archive() {
  local stamp name archive partial dump_abs stage_link
  if [[ -n "${BACKUP_ARCHIVE_STAMP:-}" ]]; then
    if [[ ! "$BACKUP_ARCHIVE_STAMP" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$ ]]; then
      log_error "BACKUP_ARCHIVE_STAMP must match YYYY-MM-DD_HHMM (got '${BACKUP_ARCHIVE_STAMP}')"
      return 1
    fi
    stamp="$BACKUP_ARCHIVE_STAMP"
  else
    stamp="$("$DATE_BIN" -u '+%Y-%m-%d_%H%M')"
  fi
  name="trapaholics-${stamp}.tar.zst"
  archive="${BACKUP_DIR}/${name}"
  partial="${archive}.partial"
  dump_abs="${STAGING_DIR}/${MARIADB_DATABASE}.sql"
  stage_link="${REPO_ROOT}/.backup-staging"

  if [[ -e "$archive" ]]; then
    log_error "archive already exists (same-minute rerun?): ${archive}"
    return 1
  fi

  rm -rf "$STAGING_DIR" || return 1
  mkdir -p "$STAGING_DIR" || return 1
  chmod 700 "$STAGING_DIR" || return 1

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

  rm -rf "$stage_link" || return 1
  if [[ -f "$dump_abs" ]]; then
    mkdir -p "$stage_link" || return 1
    cp -a "$dump_abs" "${stage_link}/${MARIADB_DATABASE}.sql" || return 1
    include_args+=(".backup-staging")
  else
    log_warn "No DB dump file; archive will not include MariaDB dump"
  fi

  if [[ ${#include_args[@]} -eq 0 ]]; then
    log_error "nothing to archive under ${REPO_ROOT}"
    rm -rf "$stage_link"
    return 1
  fi

  log_info "Creating archive ${name} (via .partial)"
  rm -f "$partial"
  if ! "$TAR_BIN" -C "$REPO_ROOT" "${tar_excludes[@]}" -cf - "${include_args[@]}" \
      | "$ZSTD_BIN" -T0 -q -o "$partial"; then
    rm -f "$partial"
    rm -rf "$stage_link"
    log_error "tar|zstd failed"
    return 1
  fi
  rm -rf "$stage_link" || true
  chmod 600 "$partial" || { rm -f "$partial"; return 1; }

  log_info "Verifying partial archive with zstd -t"
  if ! "$ZSTD_BIN" -t "$partial"; then
    log_error "zstd -t failed for ${name}.partial"
    rm -f "$partial"
    return 1
  fi

  # Write the final .sha256 BEFORE moving the archive into place.
  local sum
  sum="$(sha256_file "$partial")" || { rm -f "$partial"; return 1; }
  if [[ -e "${archive}.sha256" ]]; then
    log_error "checksum already exists: ${archive}.sha256"
    rm -f "$partial"
    return 1
  fi
  printf '%s  %s\n' "$sum" "$name" >"${archive}.sha256" || { rm -f "$partial" "${archive}.sha256"; return 1; }
  chmod 600 "${archive}.sha256" || { rm -f "$partial" "${archive}.sha256"; return 1; }

  if [[ -e "$archive" ]]; then
    log_error "refusing to overwrite existing archive: ${archive}"
    rm -f "$partial" "${archive}.sha256"
    return 1
  fi
  if ! mv -n "$partial" "$archive"; then
    log_error "mv -n failed (target exists?): ${archive}"
    rm -f "$partial" "${archive}.sha256"
    return 1
  fi
  # Debian coreutils 9.1 mv -n returns 0 when it skips; assert the move happened.
  if [[ -e "$partial" ]]; then
    log_error "mv -n left source in place (target likely exists): ${archive}"
    rm -f "$partial"
    # Keep .sha256 only if the final archive exists and matches.
    if [[ ! -f "$archive" ]]; then
      rm -f "${archive}.sha256"
    fi
    return 1
  fi

  rm -rf "$STAGING_DIR" || true
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

# Join RCLONE_REMOTE + filename, inserting '/' when the remote has a subpath
# without a trailing slash/colon terminator (e.g. gdrive-crypt:mc-backups).
rclone_remote_path() {
  local fname="$1"
  local remote="${RCLONE_REMOTE}"
  if [[ "$remote" == *: || "$remote" == */ ]]; then
    printf '%s%s' "$remote" "$fname"
  else
    printf '%s/%s' "$remote" "$fname"
  fi
}

# Close FD 201 only. Never put redirects on a bare `exec` — they permanently
# alter the shell's own fds (e.g. `exec 201>&- 2>/dev/null` discards stderr).
# Wrapping in `{ ... } 2>/dev/null` silences "not open" without touching fd 2.
release_offload_lock() {
  { exec 201>&-; } 2>/dev/null || true
}

_offload_lock_skip_bump() {
  local count=0
  if [[ -f "$OFFLOAD_LOCK_SKIP_COUNT_FILE" ]]; then
    count="$(tr -d '[:space:]' <"$OFFLOAD_LOCK_SKIP_COUNT_FILE" || echo 0)"
  fi
  count=$((count + 1))
  printf '%s\n' "$count" >"$OFFLOAD_LOCK_SKIP_COUNT_FILE"
  if [[ "$count" -ge "$OFFLOAD_LOCK_SKIP_ALERT_THRESHOLD" ]]; then
    discord_alert "offload lock held" \
      "Offload lock ${OFFLOAD_LOCK_FILE} skipped ${count} consecutive times."
    rm -f "$OFFLOAD_LOCK_SKIP_COUNT_FILE"
  else
    log_warn "Offload lock held (skip ${count}/${OFFLOAD_LOCK_SKIP_ALERT_THRESHOLD} before alert)"
  fi
}

_offload_lock_skip_reset() {
  rm -f "$OFFLOAD_LOCK_SKIP_COUNT_FILE"
}

# Acquire the offload lock on FD 201. wait_sec 0 = non-blocking.
acquire_offload_lock() {
  local wait_sec="${1:-0}"
  exec 201>"$OFFLOAD_LOCK_FILE"
  if [[ "$wait_sec" -gt 0 ]]; then
    if ! "$FLOCK_BIN" -w "$wait_sec" 201; then
      log_error "Could not acquire offload lock within ${wait_sec}s"
      discord_alert "offload lock timeout" \
        "Failed to acquire ${OFFLOAD_LOCK_FILE} within ${wait_sec}s"
      return 1
    fi
  else
    if ! "$FLOCK_BIN" -n 201; then
      _offload_lock_skip_bump
      return 1
    fi
  fi
  _offload_lock_skip_reset
  return 0
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

  if [[ "$base" == *.partial ]]; then
    log_warn "offload: skipping partial file ${base}"
    return 1
  fi
  if [[ ! "$base" =~ $ARCHIVE_NAME_RE ]]; then
    log_warn "offload: skipping non-matching filename ${base}"
    return 1
  fi
  if [[ ! -f "${archive}.sha256" ]]; then
    log_error "offload: missing ${base}.sha256; refusing to upload"
    return 1
  fi
  if ! verify_sha256 "$archive"; then
    log_error "offload: sha256 check failed for ${base}; refusing to upload"
    _offload_fail_bump "sha256 check failed for ${base}"
    return 1
  fi

  # Do NOT touch the local file — age comes from the filename stamp (R1).

  log_info "Uploading ${base} → ${RCLONE_REMOTE}"
  if ! "$RCLONE_BIN" copy "$archive" "$RCLONE_REMOTE" "${remote_args[@]+"${remote_args[@]}"}"; then
    log_error "rclone copy failed for ${base}"
    _offload_fail_bump "rclone copy failed for ${base}"
    return 1
  fi

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

  # Safety-net age tracks upload time: touch REMOTE objects after verify.
  # --no-create (-C): never invent a missing remote file.
  if ! "$RCLONE_BIN" touch --no-create "$(rclone_remote_path "$base")"; then
    log_warn "rclone touch failed for ${base} (safety-net age may be off)"
    _offload_fail_bump "rclone touch failed for ${base}"
  fi
  if ! "$RCLONE_BIN" touch --no-create "$(rclone_remote_path "${base}.sha256")"; then
    log_warn "rclone touch failed for ${base}.sha256 (safety-net age may be off)"
    _offload_fail_bump "rclone touch failed for ${base}.sha256"
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

# Offload the oldest archive that has a .sha256; skip candidates missing checksums.
offload_oldest_one() {
  local f
  local saw=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    saw=1
    if [[ ! -f "${f}.sha256" ]]; then
      log_warn "offload_oldest_one: skipping $(basename "$f") (missing .sha256)"
      continue
    fi
    log_info "Offloading oldest archive (age rule ignored): $(basename "$f")"
    offload_archive "$f"
    return $?
  done < <(backup_list_archives)
  if [[ "$saw" -eq 0 ]]; then
    log_warn "no local archives available to offload"
  else
    log_warn "no offloadable archives (all missing .sha256)"
  fi
  return 1
}

# Offload every local archive older than OFFLOAD_AGE_HOURS (oldest first).
# Age is from the filename stamp. Missing .sha256 counts toward the fail alert.
offload_aged() {
  local f age
  local any=0
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    age="$(file_age_hours "$f")" || continue
    if [[ "$age" -ge "$OFFLOAD_AGE_HOURS" ]]; then
      any=1
      if [[ ! -f "${f}.sha256" ]]; then
        log_error "offload_aged: missing .sha256 for $(basename "$f")"
        _offload_fail_bump "missing .sha256 for $(basename "$f")"
        continue
      fi
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

backup_ensure_space() {
  local estimate needed free
  estimate="$(backup_estimate_bytes)"
  needed=$((estimate + SAFETY_MARGIN_BYTES))
  free="$(backup_free_bytes)"
  log_info "Space check: free=${free} estimate=${estimate} margin=${SAFETY_MARGIN_BYTES} needed=${needed}"

  if [[ "$free" -ge "$needed" ]]; then
    return 0
  fi

  if ! acquire_offload_lock "$OFFLOAD_LOCK_WAIT_SEC"; then
    discord_alert "backup skipped (low disk)" \
      "Needed ${needed} bytes, free ${free}, and could not acquire offload lock."
    return 1
  fi

  # Another process may have freed space while we waited for the lock.
  free="$(backup_free_bytes)"
  log_info "Space re-check after offload lock: free=${free} needed=${needed}"
  if [[ "$free" -ge "$needed" ]]; then
    release_offload_lock
    return 0
  fi

  while [[ "$free" -lt "$needed" ]]; do
    log_warn "Insufficient free space (${free} < ${needed}); offloading oldest local backup"
    if ! offload_oldest_one; then
      log_error "Cannot free enough space (Drive unreachable or nothing left to move)"
      discord_alert "backup skipped (low disk)" \
        "Needed ${needed} bytes, free ${free}. Offload failed or no archives left. Aborting without deleting anything."
      release_offload_lock
      return 1
    fi
    free="$(backup_free_bytes)"
    log_info "After offload: free=${free}"
  done
  release_offload_lock
  return 0
}

# ---------------------------------------------------------------------------
# Prune Drive
# ---------------------------------------------------------------------------

# Match only rclone's object/file-not-found errors (not "Config file not found").
_rclone_not_found() {
  local output="$1"
  grep -qiE \
    'object not found|file not found|directory not found|Failed to find .* object|can.t find .* object' \
    <<<"$output"
}

prune_drive_from_log() {
  local tmp
  local line fname uploaded_at uploaded_epoch cutoff now rc out
  now="$("$DATE_BIN" +%s)"
  cutoff=$((now - PRUNE_AGE_DAYS * 24 * 3600))

  if [[ ! -f "$UPLOADED_LOG" ]]; then
    log_info "No ${UPLOADED_LOG_NAME}; nothing to prune from log"
    return 0
  fi

  tmp="$(mktemp "${BACKUP_DIR}/.uploaded.log.tmp.XXXXXX")" || return 1
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    fname="${line%% *}"
    uploaded_at="${line#* }"
    uploaded_at="${uploaded_at%% *}"

    if [[ ! "$fname" =~ $ARCHIVE_OR_SHA_RE ]]; then
      log_warn "prune: skipping malformed filename in log: ${fname}"
      printf '%s\n' "$line" >>"$tmp"
      continue
    fi

    uploaded_epoch="$(parse_utc_iso "$uploaded_at")" || {
      log_warn "unparseable upload time in log, keeping line: ${line}"
      printf '%s\n' "$line" >>"$tmp"
      continue
    }
    if [[ "$uploaded_epoch" -le "$cutoff" ]]; then
      log_info "Pruning Drive file ${fname} (uploaded ${uploaded_at})"
      out="$("$RCLONE_BIN" deletefile "$(rclone_remote_path "$fname")" --drive-use-trash=false 2>&1)" && rc=0 || rc=$?
      if [[ "$rc" -ne 0 ]]; then
        if _rclone_not_found "$out"; then
          log_warn "prune: ${fname} already absent on Drive; dropping log line"
        else
          log_error "Failed to delete ${fname} from Drive: ${out}"
          printf '%s\n' "$line" >>"$tmp"
          discord_alert "prune failure" "rclone deletefile failed for ${fname}"
          continue
        fi
      fi
      "$RCLONE_BIN" deletefile "$(rclone_remote_path "${fname}.sha256")" --drive-use-trash=false 2>/dev/null || true
    else
      printf '%s\n' "$line" >>"$tmp"
    fi
  done <"$UPLOADED_LOG"

  mv "$tmp" "$UPLOADED_LOG" || return 1
  chmod 600 "$UPLOADED_LOG" 2>/dev/null || true
}

prune_drive_safety_net() {
  log_info "Safety-net prune: rclone delete ${RCLONE_REMOTE} --min-age ${PRUNE_SAFETY_MIN_AGE_DAYS}d (trapaholics archives only)"
  if ! "$RCLONE_BIN" delete "$RCLONE_REMOTE" \
      --min-age "${PRUNE_SAFETY_MIN_AGE_DAYS}d" \
      --drive-use-trash=false \
      --include 'trapaholics-*.tar.zst' \
      --include 'trapaholics-*.tar.zst.sha256'; then
    log_error "Safety-net prune failed"
    discord_alert "prune failure" "rclone delete --min-age ${PRUNE_SAFETY_MIN_AGE_DAYS}d failed"
    return 1
  fi
  return 0
}

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

acquire_backup_lock() {
  exec 200>"$LOCK_FILE"
  if ! "$FLOCK_BIN" -n 200; then
    log_warn "Another backup is already running"
    discord_alert "backup lock held" \
      "Backup lock ${LOCK_FILE} is held; this run is skipping."
    return 1
  fi
  return 0
}
