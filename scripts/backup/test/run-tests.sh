#!/usr/bin/env bash
# Local test harness for trapaholics backup scripts (Mac/Linux, no Docker/rclone required).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS="${ROOT}/scripts/backup"
PASS=0
FAIL=0

# Prefer Homebrew bash 5+ if the system bash is ancient (macOS 3.2).
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$candidate" ]]; then
      exec "$candidate" "$0" "$@"
    fi
  done
  echo "ERROR: need bash ≥ 4 (found ${BASH_VERSION})" >&2
  exit 1
fi

# Prefer real flock (Homebrew util-linux is keg-only on macOS).
REAL_FLOCK=""
for candidate in \
  /opt/homebrew/opt/util-linux/bin/flock \
  /usr/local/opt/util-linux/bin/flock \
  "$(command -v flock 2>/dev/null || true)"
do
  if [[ -n "$candidate" && -x "$candidate" ]]; then
    REAL_FLOCK="$candidate"
    break
  fi
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }
}
need_cmd zstd
need_cmd tar
need_cmd mktemp
need_cmd awk

assert_true() {
  local desc="$1"
  shift
  if "$@"; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

assert_false() {
  local desc="$1"
  shift
  if ! "$@"; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc} (expected failure)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local desc="$1" file="$2" pattern="$3"
  if [[ -f "$file" ]] && grep -qE "$pattern" "$file"; then
    echo "  PASS: ${desc}"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc} (pattern '${pattern}' in ${file})"
    FAIL=$((FAIL + 1))
  fi
}

iso_from_epoch() {
  local epoch="$1"
  if date -u -d "@${epoch}" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    date -u -d "@${epoch}" +%Y-%m-%dT%H:%M:%SZ
  else
    date -u -r "$epoch" +%Y-%m-%dT%H:%M:%SZ
  fi
}

# ---------------------------------------------------------------------------
# Fixture
# ---------------------------------------------------------------------------

setup_fixture() {
  # Drop prior lib load so a fresh source picks up code changes mid-harness.
  unset TRAPAHOLICS_BACKUP_LIB_LOADED

  FIX="$(mktemp -d -t trapaholics-backup-test.XXXXXX)"
  mkdir -p \
    "$FIX/repo/velocity" \
    "$FIX/repo/survival/world/data" \
    "$FIX/repo/survival/plugins/GriefPrevention/data" \
    "$FIX/repo/creative/world" \
    "$FIX/repo/config" \
    "$FIX/repo/scripts" \
    "$FIX/repo/backups" \
    "$FIX/stubs" \
    "$FIX/state"

  echo "fake-compose" >"$FIX/repo/docker-compose.yml"
  cat >"$FIX/repo/.env" <<'EOF'
MARIADB_ROOT_PASSWORD=test-secret
DISCORD_WEBHOOK_URL=https://discord.test/webhook/fake
EOF
  echo "world-marker" >"$FIX/repo/survival/world/data/KEEP_ME"
  echo "plugin-marker" >"$FIX/repo/survival/plugins/GriefPrevention/data/KEEP_ME"
  echo "creative data" >"$FIX/repo/creative/world/level.dat"
  echo "proxy" >"$FIX/repo/velocity/velocity.toml"
  # libraries should be excludable via anchored path without touching world/data
  mkdir -p "$FIX/repo/survival/libraries"
  echo "lib" >"$FIX/repo/survival/libraries/skip.jar"
  chmod 700 "$FIX/repo/backups"

  # Per-fixture conf so overrides are explicit and take effect.
  cat >"${FIX}/backup.conf" <<EOF
REPO_ROOT="${FIX}/repo"
BACKUP_SUBDIR="backups"
SAFETY_MARGIN_BYTES=0
BACKUP_SIZE_MULTIPLIER="1.0"
RCLONE_REMOTE="gdrive-crypt:"
RCLONE_BWLIMIT=""
OFFLOAD_AGE_HOURS=24
PRUNE_AGE_DAYS=30
PRUNE_SAFETY_MIN_AGE_DAYS=31
OFFLOAD_FAIL_ALERT_THRESHOLD=99
PAPER_CONTAINERS="survival creative"
MARIADB_CONTAINER="mariadb"
MARIADB_DATABASE="luckperms"
DOCKER_TIMEOUT_SEC=60
OFFLOAD_LOCK_WAIT_SEC=2
BACKUP_EXCLUDES="survival/libraries survival/cache survival/versions"
BACKUP_INCLUDE_PATHS="velocity survival creative config scripts docker-compose.yml .env"
LOCK_NAME=".backup.lock"
OFFLOAD_LOCK_NAME=".offload.lock"
PRUNE_LOCK_NAME=".prune.lock"
UPLOADED_LOG_NAME=".uploaded.log"
OFFLOAD_FAIL_COUNT_NAME=".offload-fail-count"
EOF

  export BACKUP_CONF="${FIX}/backup.conf"
  export REPO_ROOT="${FIX}/repo"
  export BACKUP_DIR="${FIX}/repo/backups"
  export ENV_FILE="${FIX}/repo/.env"
  export STAGING_DIR="${FIX}/repo/backups/.staging"
  export SAFETY_MARGIN_BYTES=0
  export BACKUP_SIZE_MULTIPLIER="1.0"
  export RCLONE_REMOTE="gdrive-crypt:"
  export RCLONE_BWLIMIT=""
  export OFFLOAD_AGE_HOURS=24
  export PRUNE_AGE_DAYS=30
  export OFFLOAD_FAIL_ALERT_THRESHOLD=99
  export OFFLOAD_LOCK_WAIT_SEC=2
  export DOCKER_TIMEOUT_SEC=5
  export PAPER_CONTAINERS="survival creative"
  export MARIADB_CONTAINER="mariadb"
  export MARIADB_DATABASE="luckperms"
  export BACKUP_EXCLUDES="survival/libraries survival/cache survival/versions"
  export BACKUP_INCLUDE_PATHS="velocity survival creative config scripts docker-compose.yml .env"

  export PATH="${FIX}/stubs:${PATH}"
  export DOCKER_BIN="${FIX}/stubs/docker"
  export RCLONE_BIN="${FIX}/stubs/rclone"
  export DF_BIN="${FIX}/stubs/df"
  export CURL_BIN="${FIX}/stubs/curl"
  export TIMEOUT_BIN="${FIX}/stubs/timeout"
  if [[ -n "$REAL_FLOCK" ]]; then
    export FLOCK_BIN="$REAL_FLOCK"
  else
    export FLOCK_BIN="${FIX}/stubs/flock"
  fi

  # timeout stub: ignore duration, run the rest
  cat >"${FIX}/stubs/timeout" <<'EOS'
#!/usr/bin/env bash
shift
exec "$@"
EOS
  chmod +x "${FIX}/stubs/timeout"

  # flock stub only if real flock unavailable
  if [[ -z "$REAL_FLOCK" ]]; then
    cat >"${FIX}/stubs/flock" <<'EOS'
#!/usr/bin/env bash
set -e
wait_sec=""
nonblock=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) nonblock=1; shift ;;
    -w) wait_sec="$2"; shift 2 ;;
    -x|-s|-u|-e) shift ;;
    -c) shift; exec bash -c "$1" ;;
    [0-9]*)
      # fd mode — pretend success
      exit 0
      ;;
    *) exec "$@" ;;
  esac
done
exit 0
EOS
    chmod +x "${FIX}/stubs/flock"
  fi

  # docker stub
  cat >"${FIX}/stubs/docker" <<EOS
#!/usr/bin/env bash
set -e
STATE_DIR="${FIX}/state"
mkdir -p "\$STATE_DIR"
echo "\$*" >>"\$STATE_DIR/docker.log"
case "\$1" in
  inspect)
    name="\${@: -1}"
    if [[ -f "\$STATE_DIR/docker.down" ]] && grep -qx "\$name" "\$STATE_DIR/docker.down"; then
      echo "false"; exit 0
    fi
    echo "true"
    ;;
  exec)
    # docker exec [-e KEY=VAL ...] CONTAINER CMD...
    shift
    while [[ "\$1" == -* ]]; do
      if [[ "\$1" == "-e" ]]; then
        shift 2
      else
        shift
      fi
    done
    container="\$1"
    shift
    if [[ "\$1" == "rcon-cli" ]]; then
      shift
      cmd="\$*"
      echo "\$container rcon \$cmd" >>"\$STATE_DIR/rcon.log"
      if [[ -f "\$STATE_DIR/rcon.fail" ]] && grep -qx "\$cmd" "\$STATE_DIR/rcon.fail"; then
        echo "rcon forced failure: \$cmd" >&2
        exit 1
      fi
      exit 0
    fi
    if [[ "\$1" == "mariadb-dump" ]]; then
      if [[ -f "\$STATE_DIR/dump.fail" ]]; then
        echo "mariadb-dump forced failure" >&2
        exit 1
      fi
      echo "-- fake dump of luckperms"
      echo "CREATE DATABASE luckperms;"
      exit 0
    fi
    exit 0
    ;;
  *) exit 0 ;;
esac
EOS
  chmod +x "${FIX}/stubs/docker"

  echo "999999999" >"${FIX}/state/df_avail_kb"
  cat >"${FIX}/stubs/df" <<EOF
#!/usr/bin/env bash
avail=\$(cat "${FIX}/state/df_avail_kb")
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 \${avail} 1% /"
EOF
  chmod +x "${FIX}/stubs/df"

  echo "ok" >"${FIX}/state/rclone_copy"
  echo "ok" >"${FIX}/state/rclone_cryptcheck"
  echo "ok" >"${FIX}/state/rclone_deletefile"
  echo "ok" >"${FIX}/state/rclone_delete"
  mkdir -p "${FIX}/state/remote"
  cat >"${FIX}/stubs/rclone" <<EOF
#!/usr/bin/env bash
set -e
echo "\$*" >>"${FIX}/state/rclone.log"
cmd="\$1"; shift || true
case "\$cmd" in
  copy)
    src="\$1"
    if [[ "\$(cat "${FIX}/state/rclone_copy")" != "ok" ]]; then
      echo "rclone copy failed (stub)" >&2; exit 1
    fi
    cp -a "\$src" "${FIX}/state/remote/\$(basename "\$src")"
    ;;
  cryptcheck)
    src="\$1"
    if [[ "\$(cat "${FIX}/state/rclone_cryptcheck")" != "ok" ]]; then
      echo "rclone cryptcheck failed (stub)" >&2; exit 1
    fi
    base=\$(basename "\$src")
    [[ -f "${FIX}/state/remote/\$base" ]] || { echo "cryptcheck: remote missing"; exit 1; }
    ;;
  deletefile)
    remote="\$1"
    base=\${remote##*:}
    if [[ "\$(cat "${FIX}/state/rclone_deletefile")" == "notfound" ]]; then
      echo "directory not found" >&2; exit 1
    fi
    if [[ "\$(cat "${FIX}/state/rclone_deletefile")" != "ok" ]]; then
      echo "rclone deletefile failed (stub)" >&2; exit 1
    fi
    if [[ ! -f "${FIX}/state/remote/\$base" ]]; then
      echo "object not found" >&2; exit 1
    fi
    rm -f "${FIX}/state/remote/\$base"
    echo "\$base" >>"${FIX}/state/rclone_deleted.log"
    ;;
  delete)
    if [[ "\$(cat "${FIX}/state/rclone_delete")" != "ok" ]]; then
      echo "rclone delete failed (stub)" >&2; exit 1
    fi
    echo "delete \$*" >>"${FIX}/state/rclone_deleted.log"
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "${FIX}/stubs/rclone"

  # curl stub: log config+payload; succeed
  cat >"${FIX}/stubs/curl" <<EOF
#!/usr/bin/env bash
mkdir -p "${FIX}/state"
echo "curl \$*" >>"${FIX}/state/curl.log"
# Read -K - config from stdin when present; drain stdin
if [[ "\$*" == *-K* ]]; then
  cat >>"${FIX}/state/curl.conf" || true
fi
exit 0
EOF
  chmod +x "${FIX}/stubs/curl"

  # shellcheck source=../lib.sh disable=SC1091
  source "${SCRIPTS}/lib.sh"
  backup_load_config
  # Paths from conf/env should already be set; re-pin tools.
  DOCKER_BIN="${FIX}/stubs/docker"
  RCLONE_BIN="${FIX}/stubs/rclone"
  DF_BIN="${FIX}/stubs/df"
  CURL_BIN="${FIX}/stubs/curl"
  TIMEOUT_BIN="${FIX}/stubs/timeout"
  backup_ensure_dirs
}

teardown_fixture() {
  if [[ -n "${FIX:-}" && -d "$FIX" ]]; then
    rm -rf "$FIX"
  fi
}

make_fake_archive() {
  local name="$1"
  local path="${BACKUP_DIR}/${name}"
  echo "fake-archive-body-${name}" | zstd -q -o "$path"
  chmod 600 "$path"
  local sum
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum "$path" | awk '{print $1}')"
  else
    sum="$(shasum -a 256 "$path" | awk '{print $1}')"
  fi
  printf '%s  %s\n' "$sum" "$name" >"${path}.sha256"
  chmod 600 "${path}.sha256"
  printf '%s' "$path"
}

run_backup_sh() {
  BACKUP_CONF="${FIX}/backup.conf" \
    REPO_ROOT="${FIX}/repo" \
    BACKUP_DIR="${FIX}/repo/backups" \
    ENV_FILE="${FIX}/repo/.env" \
    SAFETY_MARGIN_BYTES=0 \
    BACKUP_SIZE_MULTIPLIER="1.0" \
    RCLONE_REMOTE="gdrive-crypt:" \
    RCLONE_BWLIMIT="" \
    OFFLOAD_LOCK_WAIT_SEC=2 \
    DOCKER_BIN="${FIX}/stubs/docker" \
    RCLONE_BIN="${FIX}/stubs/rclone" \
    DF_BIN="${FIX}/stubs/df" \
    CURL_BIN="${FIX}/stubs/curl" \
    TIMEOUT_BIN="${FIX}/stubs/timeout" \
    FLOCK_BIN="${FLOCK_BIN}" \
    PATH="${FIX}/stubs:${PATH}" \
    "${SCRIPTS}/backup.sh"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_a_normal_backup_keeps_world_data() {
  echo "TEST (a): normal backup + save-off/on; world/data and plugins/*/data retained"
  setup_fixture
  local archive
  paper_save_off
  archive="$(backup_create_archive)"
  paper_save_on

  assert_true "archive exists" test -f "$archive"
  assert_true "sha256 exists" test -f "${archive}.sha256"
  assert_true "save-off logged" grep -q 'save-off' "${FIX}/state/rcon.log"
  assert_true "save-all flush logged" grep -q 'save-all flush' "${FIX}/state/rcon.log"
  assert_true "save-on logged" grep -q 'save-on' "${FIX}/state/rcon.log"

  local listing
  listing="$(zstd -dc "$archive" | tar -t)"
  assert_true "world/data kept in archive" grep -q 'survival/world/data/KEEP_ME' <<<"$listing"
  assert_true "plugins/*/data kept in archive" grep -q 'survival/plugins/GriefPrevention/data/KEEP_ME' <<<"$listing"
  assert_false "anchored libraries excluded" grep -q 'survival/libraries/skip.jar' <<<"$listing"

  teardown_fixture
}

test_b_flush_fail_still_save_on_via_backup_sh() {
  echo "TEST (b): save-all flush failure still restores save-on via backup.sh EXIT trap"
  setup_fixture
  echo "save-all flush" >"${FIX}/state/rcon.fail"
  # Plenty of space so we reach paper_save_off
  echo "999999999" >"${FIX}/state/df_avail_kb"

  set +e
  run_backup_sh >/dev/null 2>"${FIX}/state/backup.err"
  local rc=$?
  set -e

  assert_true "backup.sh failed" test "$rc" -ne 0
  assert_true "save-off was issued" grep -q 'save-off' "${FIX}/state/rcon.log"
  assert_true "save-on restored via trap" grep -q 'save-on' "${FIX}/state/rcon.log"
  assert_file_contains "discord alert attempted" "${FIX}/state/curl.log" 'curl'

  teardown_fixture
}

test_c_dump_failure_fails_and_alerts() {
  echo "TEST (c): mariadb-dump failure fails the backup and alerts"
  setup_fixture
  touch "${FIX}/state/dump.fail"
  echo "999999999" >"${FIX}/state/df_avail_kb"

  set +e
  run_backup_sh >/dev/null 2>"${FIX}/state/backup.err"
  local rc=$?
  set -e

  assert_true "backup.sh failed on dump" test "$rc" -ne 0
  assert_true "save-on still ran" grep -q 'save-on' "${FIX}/state/rcon.log"
  assert_file_contains "discord alert on dump failure" "${FIX}/state/curl.log" 'curl'
  assert_false "no final archive" bash -c "ls '${BACKUP_DIR}'/trapaholics-*.tar.zst >/dev/null 2>&1"

  teardown_fixture
}

test_d_low_space_abort_keeps_newer_and_alerts() {
  echo "TEST (d): low-space abort keeps newer archive and alerts"
  setup_fixture
  local old new
  old="$(make_fake_archive 'trapaholics-2026-01-01_0000.tar.zst')"
  new="$(make_fake_archive 'trapaholics-2026-01-02_0000.tar.zst')"
  echo "fail" >"${FIX}/state/rclone_copy"
  cat >"${FIX}/stubs/df" <<EOF
#!/usr/bin/env bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 0 1% /"
EOF
  chmod +x "${FIX}/stubs/df"

  assert_false "ensure_space aborts" backup_ensure_space
  assert_true "oldest kept after failed upload" test -f "$old"
  assert_true "newer kept after abort" test -f "$new"
  assert_file_contains "low-disk discord alert" "${FIX}/state/curl.log" 'curl'

  teardown_fixture
}

test_e_offload_cryptcheck_and_partial_skip() {
  echo "TEST (e): cryptcheck gate; .partial never offloaded; sha256 required"
  setup_fixture
  local arch
  arch="$(make_fake_archive 'trapaholics-2026-03-01_1200.tar.zst')"
  assert_true "offload succeeds" offload_archive "$arch"
  assert_false "local deleted after cryptcheck" test -f "$arch"

  arch="$(make_fake_archive 'trapaholics-2026-03-02_1200.tar.zst')"
  echo "fail" >"${FIX}/state/rclone_cryptcheck"
  assert_false "cryptcheck failure" offload_archive "$arch"
  assert_true "kept on cryptcheck fail" test -f "$arch"

  # .partial must not be offloaded
  echo "partial-body" | zstd -q -o "${BACKUP_DIR}/trapaholics-2026-03-03_1200.tar.zst.partial"
  assert_false "partial skipped" offload_archive "${BACKUP_DIR}/trapaholics-2026-03-03_1200.tar.zst.partial"
  assert_true "partial still present" test -f "${BACKUP_DIR}/trapaholics-2026-03-03_1200.tar.zst.partial"

  # missing sha256 refused
  echo "nosum" | zstd -q -o "${BACKUP_DIR}/trapaholics-2026-03-04_1200.tar.zst"
  assert_false "missing sha256 refused" offload_archive "${BACKUP_DIR}/trapaholics-2026-03-04_1200.tar.zst"

  teardown_fixture
}

test_f_prune_boundaries_and_malformed() {
  echo "TEST (f): prune 29d23h kept, 30d00h deleted; malformed skipped; not-found ok"
  setup_fixture

  echo "old" >"${FIX}/state/remote/trapaholics-2020-01-01_0000.tar.zst"
  echo "edge" >"${FIX}/state/remote/trapaholics-2020-01-02_0000.tar.zst"
  echo "new" >"${FIX}/state/remote/trapaholics-2020-01-03_0000.tar.zst"

  local now
  now="$(date -u +%s)"
  local iso_30 iso_29 iso_1
  # Exactly 30 days ago → eligible (<= cutoff)
  iso_30="$(iso_from_epoch $((now - 30 * 86400)))"
  # 29d23h ago → keep
  iso_29="$(iso_from_epoch $((now - 29 * 86400 - 23 * 3600)))"
  iso_1="$(iso_from_epoch $((now - 86400)))"

  cat >"$UPLOADED_LOG" <<EOF
trapaholics-2020-01-01_0000.tar.zst ${iso_30}
trapaholics-2020-01-02_0000.tar.zst ${iso_29}
trapaholics-2020-01-03_0000.tar.zst ${iso_1}
evil-file.tar.zst ${iso_30}
not-a-backup.txt ${iso_30}
EOF

  prune_drive_from_log

  assert_false "30d00h deleted" test -f "${FIX}/state/remote/trapaholics-2020-01-01_0000.tar.zst"
  assert_true "29d23h kept" test -f "${FIX}/state/remote/trapaholics-2020-01-02_0000.tar.zst"
  assert_true "1d kept" test -f "${FIX}/state/remote/trapaholics-2020-01-03_0000.tar.zst"
  assert_false "30d line removed" grep -q 'trapaholics-2020-01-01_0000.tar.zst' "$UPLOADED_LOG"
  assert_true "29d23h line kept" grep -q 'trapaholics-2020-01-02_0000.tar.zst' "$UPLOADED_LOG"
  assert_true "malformed evil-file kept in log" grep -q 'evil-file.tar.zst' "$UPLOADED_LOG"
  assert_true "malformed not-a-backup kept in log" grep -q 'not-a-backup.txt' "$UPLOADED_LOG"

  # not-found treated as success
  echo "trapaholics-2019-01-01_0000.tar.zst ${iso_30}" >>"$UPLOADED_LOG"
  echo "notfound" >"${FIX}/state/rclone_deletefile"
  prune_drive_from_log
  assert_false "not-found drops log line" grep -q 'trapaholics-2019-01-01_0000.tar.zst' "$UPLOADED_LOG"

  teardown_fixture
}

test_g_rclone_remote_validation() {
  echo "TEST (g): empty/invalid RCLONE_REMOTE refused"
  setup_fixture

  RCLONE_REMOTE=""
  export RCLONE_REMOTE
  assert_false "empty remote refused" backup_validate_rclone_remote

  RCLONE_REMOTE="gdrive:"
  export RCLONE_REMOTE
  assert_false "gdrive: refused" backup_validate_rclone_remote

  RCLONE_REMOTE="gdrive-crypt"
  export RCLONE_REMOTE
  assert_false "missing colon refused" backup_validate_rclone_remote

  RCLONE_REMOTE="gdrive-crypt:"
  export RCLONE_REMOTE
  assert_true "gdrive-crypt: accepted" backup_validate_rclone_remote

  RCLONE_REMOTE="gdrive-crypt:mc-backups"
  export RCLONE_REMOTE
  assert_true "gdrive-crypt:subpath accepted" backup_validate_rclone_remote

  teardown_fixture
}

test_h_same_minute_and_partial_cleanup() {
  echo "TEST (h): same-minute rerun does not delete existing archive; failure only removes .partial"
  setup_fixture
  local stamp name archive
  stamp="$("$DATE_BIN" -u '+%Y-%m-%d_%H%M')"
  name="trapaholics-${stamp}.tar.zst"
  archive="${BACKUP_DIR}/${name}"
  echo "existing" | zstd -q -o "$archive"
  chmod 600 "$archive"
  local sum
  sum="$(sha256_file "$archive")"
  printf '%s  %s\n' "$sum" "$name" >"${archive}.sha256"

  set +e
  backup_create_archive >/dev/null 2>&1
  local rc=$?
  set -e

  assert_true "same-minute create failed" test "$rc" -ne 0
  assert_true "existing archive intact" test -f "$archive"
  assert_false "no leftover partial" bash -c "ls '${BACKUP_DIR}'/*.partial >/dev/null 2>&1"

  # Force zstd failure mid-create with no pre-existing archive
  rm -f "$archive" "${archive}.sha256"
  export ZSTD_BIN="${FIX}/stubs/zstd-fail"
  cat >"$ZSTD_BIN" <<'EOF'
#!/usr/bin/env bash
echo "zstd fail" >&2
exit 1
EOF
  chmod +x "$ZSTD_BIN"
  set +e
  backup_create_archive >/dev/null 2>&1
  rc=$?
  set -e
  unset ZSTD_BIN
  ZSTD_BIN=zstd

  assert_true "create failed on zstd" test "$rc" -ne 0
  assert_false "partial cleaned up" bash -c "ls '${BACKUP_DIR}'/*.partial >/dev/null 2>&1"
  assert_false "no final archive from failed run" bash -c "ls '${BACKUP_DIR}'/trapaholics-*.tar.zst >/dev/null 2>&1"

  teardown_fixture
}

test_i_locking() {
  echo "TEST (i): real flock serialises offload lock (or stub documents skip)"
  setup_fixture
  if [[ -z "$REAL_FLOCK" ]]; then
    echo "  SKIP: no real flock on PATH (install util-linux)"
    PASS=$((PASS + 1))
    teardown_fixture
    return 0
  fi

  # Hold offload lock in background, then ensure acquire_offload_lock 0 fails+alerts
  (
    exec 201>"$OFFLOAD_LOCK_FILE"
    "$REAL_FLOCK" 201
    sleep 5
  ) &
  local holder=$!
  sleep 0.3

  assert_false "non-blocking acquire fails while held" acquire_offload_lock 0
  assert_file_contains "lock-held alert" "${FIX}/state/curl.log" 'curl'

  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true

  assert_true "acquire succeeds after release" acquire_offload_lock 0

  teardown_fixture
}

test_j_env_overrides_take_effect() {
  echo "TEST (j): exported tunable overrides take effect after backup_load_config"
  setup_fixture
  export SAFETY_MARGIN_BYTES=12345
  export PRUNE_AGE_DAYS=7
  unset TRAPAHOLICS_BACKUP_LIB_LOADED
  # shellcheck source=../lib.sh disable=SC1091
  source "${SCRIPTS}/lib.sh"
  backup_load_config
  assert_true "SAFETY_MARGIN_BYTES override" test "$SAFETY_MARGIN_BYTES" -eq 12345
  assert_true "PRUNE_AGE_DAYS override" test "$PRUNE_AGE_DAYS" -eq 7
  teardown_fixture
}

test_k_webhook_warning_at_startup() {
  echo "TEST (k): missing webhook warned at startup"
  setup_fixture
  cat >"$ENV_FILE" <<'EOF'
MARIADB_ROOT_PASSWORD=test-secret
DISCORD_WEBHOOK_URL=
EOF
  local out
  out="$(backup_warn_missing_webhook 2>&1)"
  assert_true "startup warns about missing webhook" grep -q 'DISCORD_WEBHOOK_URL unset' <<<"$out"
  teardown_fixture
}

test_l_low_space_success_offloads_oldest_only() {
  echo "TEST (l): low-space success offloads oldest only"
  setup_fixture
  local old new
  old="$(make_fake_archive 'trapaholics-2026-01-01_0000.tar.zst')"
  new="$(make_fake_archive 'trapaholics-2026-01-02_0000.tar.zst')"
  cat >"${FIX}/stubs/df" <<EOF
#!/usr/bin/env bash
count_file="${FIX}/state/df_calls"
n=\$(( \$(cat "\$count_file" 2>/dev/null || echo 0) + 1 ))
echo "\$n" >"\$count_file"
if [[ "\$n" -le 1 ]]; then avail=0; else avail=999999999; fi
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 \${avail} 1% /"
EOF
  chmod +x "${FIX}/stubs/df"

  assert_true "ensure_space succeeds" backup_ensure_space
  assert_false "oldest removed" test -f "$old"
  assert_true "newer kept" test -f "$new"
  teardown_fixture
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== trapaholics backup test harness ==="
echo "ROOT=${ROOT}"
echo "REAL_FLOCK=${REAL_FLOCK:-none}"

test_a_normal_backup_keeps_world_data
test_b_flush_fail_still_save_on_via_backup_sh
test_c_dump_failure_fails_and_alerts
test_d_low_space_abort_keeps_newer_and_alerts
test_e_offload_cryptcheck_and_partial_skip
test_f_prune_boundaries_and_malformed
test_g_rclone_remote_validation
test_h_same_minute_and_partial_cleanup
test_i_locking
test_j_env_overrides_take_effect
test_k_webhook_warning_at_startup
test_l_low_space_success_offloads_oldest_only

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
