#!/usr/bin/env bash
# Local test harness for trapaholics backup scripts (Mac/Linux, no Docker/rclone required).
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPTS="${ROOT}/scripts/backup"
PASS=0
FAIL=0
SKIP=0

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for candidate in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$candidate" ]]; then
      exec "$candidate" "$0" "$@"
    fi
  done
  echo "ERROR: need bash ≥ 4 (found ${BASH_VERSION})" >&2
  exit 1
fi

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
  local desc="$1"; shift
  if "$@"; then
    echo "  PASS: ${desc}"; PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc}"; FAIL=$((FAIL + 1))
  fi
}

assert_false() {
  local desc="$1"; shift
  if ! "$@"; then
    echo "  PASS: ${desc}"; PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc} (expected failure)"; FAIL=$((FAIL + 1))
  fi
}

assert_file_contains() {
  local desc="$1" file="$2" pattern="$3"
  if [[ -f "$file" ]] && grep -qE "$pattern" "$file"; then
    echo "  PASS: ${desc}"; PASS=$((PASS + 1))
  else
    echo "  FAIL: ${desc} (pattern '${pattern}' in ${file})"
    FAIL=$((FAIL + 1))
  fi
}

assert_alert_title() {
  local desc="$1" title="$2"
  assert_file_contains "$desc" "${FIX}/state/curl.log" "$title"
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
  mkdir -p "$FIX/repo/survival/libraries"
  echo "lib" >"$FIX/repo/survival/libraries/skip.jar"
  chmod 700 "$FIX/repo/backups"

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
OFFLOAD_FAIL_ALERT_THRESHOLD=3
OFFLOAD_LOCK_SKIP_ALERT_THRESHOLD=3
PAPER_CONTAINERS="survival creative"
MARIADB_CONTAINER="mariadb"
MARIADB_DATABASE="luckperms"
DOCKER_TIMEOUT_SEC=5
SAVE_ALL_FLUSH_TIMEOUT_SEC=5
MARIADB_DUMP_TIMEOUT_SEC=5
OFFLOAD_LOCK_WAIT_SEC=2
PRUNE_LOCK_WAIT_SEC=2
BACKUP_EXCLUDES="survival/libraries survival/cache survival/versions"
BACKUP_INCLUDE_PATHS="velocity survival creative config scripts docker-compose.yml .env"
LOCK_NAME=".backup.lock"
OFFLOAD_LOCK_NAME=".offload.lock"
PRUNE_LOCK_NAME=".prune.lock"
UPLOADED_LOG_NAME=".uploaded.log"
OFFLOAD_FAIL_COUNT_NAME=".offload-fail-count"
OFFLOAD_LOCK_SKIP_COUNT_NAME=".offload-lock-skip-count"
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
  export OFFLOAD_FAIL_ALERT_THRESHOLD=3
  export OFFLOAD_LOCK_SKIP_ALERT_THRESHOLD=3
  export OFFLOAD_LOCK_WAIT_SEC=2
  export PRUNE_LOCK_WAIT_SEC=2
  export DOCKER_TIMEOUT_SEC=5
  export SAVE_ALL_FLUSH_TIMEOUT_SEC=5
  export MARIADB_DUMP_TIMEOUT_SEC=5
  export PAPER_CONTAINERS="survival creative"
  export MARIADB_CONTAINER="mariadb"
  export MARIADB_DATABASE="luckperms"
  export BACKUP_EXCLUDES="survival/libraries survival/cache survival/versions"
  export BACKUP_INCLUDE_PATHS="velocity survival creative config scripts docker-compose.yml .env"
  unset BACKUP_ARCHIVE_STAMP

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

  cat >"${FIX}/stubs/timeout" <<'EOS'
#!/usr/bin/env bash
shift
exec "$@"
EOS
  chmod +x "${FIX}/stubs/timeout"

  if [[ -z "$REAL_FLOCK" ]]; then
    cat >"${FIX}/stubs/flock" <<'EOS'
#!/usr/bin/env bash
set -e
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|-x|-s|-u|-e) shift ;;
    -w) shift 2 ;;
    -c) shift; exec bash -c "$1" ;;
    [0-9]*) exit 0 ;;
    *) exec "$@" ;;
  esac
done
exit 0
EOS
    chmod +x "${FIX}/stubs/flock"
  fi

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
    shift
    while [[ "\$1" == -* ]]; do
      if [[ "\$1" == "-e" ]]; then shift 2; else shift; fi
    done
    container="\$1"; shift
    if [[ "\$1" == "rcon-cli" ]]; then
      shift
      cmd="\$*"
      echo "\$container rcon \$cmd" >>"\$STATE_DIR/rcon.log"
      if [[ -f "\$STATE_DIR/rcon.fail" ]] && grep -qx "\$cmd" "\$STATE_DIR/rcon.fail"; then
        echo "rcon forced failure: \$cmd" >&2; exit 1
      fi
      exit 0
    fi
    if [[ "\$1" == "mariadb-dump" ]]; then
      if [[ -f "\$STATE_DIR/dump.fail" ]]; then
        echo "mariadb-dump forced failure" >&2; exit 1
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
  echo "ok" >"${FIX}/state/rclone_touch"
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
  touch)
    # Accept optional --no-create / -C before the remote path.
    while [[ "\${1:-}" == -* ]]; do shift; done
    remote="\$1"
    base=\${remote##*/}
    base=\${base##*:}
    if [[ "\$(cat "${FIX}/state/rclone_touch")" != "ok" ]]; then
      echo "rclone touch failed (stub)" >&2; exit 1
    fi
    echo "\$remote" >>"${FIX}/state/rclone_touch.log"
    touch "${FIX}/state/remote/\$base" 2>/dev/null || true
    ;;
  deletefile)
    remote="\$1"
    base=\${remote##*/}
    base=\${base##*:}
    # Optional injected raw error text for false-positive tests
    if [[ -f "${FIX}/state/rclone_deletefile_msg" ]]; then
      cat "${FIX}/state/rclone_deletefile_msg" >&2
      exit 1
    fi
    if [[ "\$(cat "${FIX}/state/rclone_deletefile")" == "notfound" ]]; then
      echo "object not found" >&2; exit 1
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

  cat >"${FIX}/stubs/curl" <<EOF
#!/usr/bin/env bash
mkdir -p "${FIX}/state"
# Log argv (includes -d payload with alert title) and any -K stdin config.
echo "curl \$*" >>"${FIX}/state/curl.log"
if [[ "\$*" == *-K* ]]; then
  cat >>"${FIX}/state/curl.conf" || true
fi
# Also capture -d payload explicitly when present
prev=""
for a in "\$@"; do
  if [[ "\$prev" == "-d" ]]; then
    echo "\$a" >>"${FIX}/state/curl.payload"
  fi
  prev="\$a"
done
exit 0
EOF
  chmod +x "${FIX}/stubs/curl"

  # shellcheck source=../lib.sh disable=SC1091
  source "${SCRIPTS}/lib.sh"
  backup_load_config
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
    BACKUP_ARCHIVE_STAMP="${BACKUP_ARCHIVE_STAMP:-}" \
    PATH="${FIX}/stubs:${PATH}" \
    "${SCRIPTS}/backup.sh"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_a_normal_backup_keeps_world_data() {
  echo "TEST (a): normal backup + save-off/on; world/data retained"
  setup_fixture
  export BACKUP_ARCHIVE_STAMP="2026-01-15_1200"
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
  assert_true "world/data kept" grep -q 'survival/world/data/KEEP_ME' <<<"$listing"
  assert_true "plugins data kept" grep -q 'survival/plugins/GriefPrevention/data/KEEP_ME' <<<"$listing"
  assert_false "libraries excluded" grep -q 'survival/libraries/skip.jar' <<<"$listing"
  teardown_fixture
}

test_b_flush_fail_still_save_on_via_backup_sh() {
  echo "TEST (b): flush failure restores save-on via backup.sh EXIT trap"
  setup_fixture
  echo "save-all flush" >"${FIX}/state/rcon.fail"
  echo "999999999" >"${FIX}/state/df_avail_kb"
  set +e
  run_backup_sh >/dev/null 2>"${FIX}/state/backup.err"
  local rc=$?
  set -e
  assert_true "backup.sh failed" test "$rc" -ne 0
  assert_true "save-on restored" grep -q 'save-on' "${FIX}/state/rcon.log"
  assert_alert_title "backup failure alert title" "backup failure"
  teardown_fixture
}

test_c_dump_failure_fails_and_alerts() {
  echo "TEST (c): mariadb-dump failure fails backup and alerts"
  setup_fixture
  touch "${FIX}/state/dump.fail"
  set +e
  run_backup_sh >/dev/null 2>"${FIX}/state/backup.err"
  local rc=$?
  set -e
  assert_true "backup failed" test "$rc" -ne 0
  assert_true "save-on ran" grep -q 'save-on' "${FIX}/state/rcon.log"
  assert_alert_title "dump failure alert" "backup failure"
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
  assert_true "oldest kept" test -f "$old"
  assert_true "newer kept" test -f "$new"
  assert_alert_title "low-disk alert title" "backup skipped \\(low disk\\)"
  teardown_fixture
}

test_e_offload_cryptcheck_and_partial_skip() {
  echo "TEST (e): cryptcheck gate; .partial never offloaded"
  setup_fixture
  local arch
  arch="$(make_fake_archive 'trapaholics-2026-03-01_1200.tar.zst')"
  assert_true "offload succeeds" offload_archive "$arch"
  assert_false "local deleted" test -f "$arch"
  assert_file_contains "remote touched after cryptcheck" "${FIX}/state/rclone_touch.log" 'trapaholics-2026-03-01_1200'

  arch="$(make_fake_archive 'trapaholics-2026-03-02_1200.tar.zst')"
  echo "fail" >"${FIX}/state/rclone_cryptcheck"
  assert_false "cryptcheck failure" offload_archive "$arch"
  assert_true "kept on fail" test -f "$arch"

  echo "partial-body" | zstd -q -o "${BACKUP_DIR}/trapaholics-2026-03-03_1200.tar.zst.partial"
  assert_false "partial skipped" offload_archive "${BACKUP_DIR}/trapaholics-2026-03-03_1200.tar.zst.partial"
  assert_true "partial still present" test -f "${BACKUP_DIR}/trapaholics-2026-03-03_1200.tar.zst.partial"
  teardown_fixture
}

test_f_prune_boundaries_and_malformed() {
  echo "TEST (f): prune 29d23h kept, 30d00h deleted; malformed skipped"
  setup_fixture
  echo "old" >"${FIX}/state/remote/trapaholics-2020-01-01_0000.tar.zst"
  echo "edge" >"${FIX}/state/remote/trapaholics-2020-01-02_0000.tar.zst"
  echo "new" >"${FIX}/state/remote/trapaholics-2020-01-03_0000.tar.zst"
  local now iso_30 iso_29 iso_1
  now="$(date -u +%s)"
  iso_30="$(iso_from_epoch $((now - 30 * 86400)))"
  iso_29="$(iso_from_epoch $((now - 29 * 86400 - 23 * 3600)))"
  iso_1="$(iso_from_epoch $((now - 86400)))"
  cat >"$UPLOADED_LOG" <<EOF
trapaholics-2020-01-01_0000.tar.zst ${iso_30}
trapaholics-2020-01-02_0000.tar.zst ${iso_29}
trapaholics-2020-01-03_0000.tar.zst ${iso_1}
evil-file.tar.zst ${iso_30}
EOF
  prune_drive_from_log
  assert_false "30d deleted" test -f "${FIX}/state/remote/trapaholics-2020-01-01_0000.tar.zst"
  assert_true "29d23h kept" test -f "${FIX}/state/remote/trapaholics-2020-01-02_0000.tar.zst"
  assert_true "malformed kept in log" grep -q 'evil-file.tar.zst' "$UPLOADED_LOG"

  echo "trapaholics-2019-01-01_0000.tar.zst ${iso_30}" >>"$UPLOADED_LOG"
  echo "notfound" >"${FIX}/state/rclone_deletefile"
  prune_drive_from_log
  assert_false "object-not-found drops line" grep -q 'trapaholics-2019-01-01_0000.tar.zst' "$UPLOADED_LOG"
  teardown_fixture
}

test_g_rclone_remote_validation_and_join() {
  echo "TEST (g): RCLONE_REMOTE validation + subpath joining"
  setup_fixture
  RCLONE_REMOTE=""; export RCLONE_REMOTE
  assert_false "empty refused" backup_validate_rclone_remote
  RCLONE_REMOTE="gdrive:"; export RCLONE_REMOTE
  assert_false "gdrive: refused" backup_validate_rclone_remote
  RCLONE_REMOTE="gdrive-crypt"; export RCLONE_REMOTE
  assert_false "missing colon refused" backup_validate_rclone_remote
  RCLONE_REMOTE="gdrive-crypt:"; export RCLONE_REMOTE
  assert_true "gdrive-crypt: ok" backup_validate_rclone_remote
  local joined
  joined="$(rclone_remote_path "trapaholics-2026-01-01_0000.tar.zst")"
  assert_true "join with trailing colon" \
    test "$joined" = "gdrive-crypt:trapaholics-2026-01-01_0000.tar.zst"

  RCLONE_REMOTE="gdrive-crypt:mc-backups"; export RCLONE_REMOTE
  assert_true "subpath accepted" backup_validate_rclone_remote
  joined="$(rclone_remote_path "trapaholics-2026-01-01_0000.tar.zst")"
  assert_true "join inserts slash for subpath" \
    test "$joined" = "gdrive-crypt:mc-backups/trapaholics-2026-01-01_0000.tar.zst"
  teardown_fixture
}

test_h_same_minute_frozen_stamp() {
  echo "TEST (h): same-minute rerun with frozen stamp; partial cleaned on failure"
  setup_fixture
  export BACKUP_ARCHIVE_STAMP="2026-06-01_1530"
  local name archive
  name="trapaholics-${BACKUP_ARCHIVE_STAMP}.tar.zst"
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
  assert_true "same-stamp create failed" test "$rc" -ne 0
  assert_true "existing archive intact" test -f "$archive"
  assert_false "no leftover partial" bash -c "ls '${BACKUP_DIR}'/*.partial >/dev/null 2>&1"

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
  unset ZSTD_BIN; ZSTD_BIN=zstd
  assert_true "zstd fail" test "$rc" -ne 0
  assert_false "partial cleaned" bash -c "ls '${BACKUP_DIR}'/*.partial >/dev/null 2>&1"
  teardown_fixture
}

test_i_locking() {
  echo "TEST (i): real flock serialises offload lock"
  if [[ -z "$REAL_FLOCK" ]]; then
    echo "  SKIP: no real flock (install util-linux); locking not exercised"
    SKIP=$((SKIP + 1))
    return 0
  fi
  setup_fixture
  (
    exec 201>"$OFFLOAD_LOCK_FILE"
    "$REAL_FLOCK" 201
    sleep 5
  ) &
  local holder=$!
  sleep 0.3
  # Threshold=3 so first skip does not alert
  export OFFLOAD_LOCK_SKIP_ALERT_THRESHOLD=3
  assert_false "non-blocking acquire fails while held" acquire_offload_lock 0
  assert_false "no alert on first skip" grep -q 'offload lock held' "${FIX}/state/curl.log" 2>/dev/null

  # Bump to threshold
  acquire_offload_lock 0 || true
  acquire_offload_lock 0 || true
  assert_alert_title "alert after N skips" "offload lock held"

  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  assert_true "acquire after release" acquire_offload_lock 0
  teardown_fixture
}

test_j_env_overrides_take_effect() {
  echo "TEST (j): exported tunable overrides take effect"
  setup_fixture
  export SAFETY_MARGIN_BYTES=12345
  export PRUNE_AGE_DAYS=7
  unset TRAPAHOLICS_BACKUP_LIB_LOADED
  # shellcheck source=../lib.sh disable=SC1091
  source "${SCRIPTS}/lib.sh"
  backup_load_config
  assert_true "SAFETY_MARGIN_BYTES" test "$SAFETY_MARGIN_BYTES" -eq 12345
  assert_true "PRUNE_AGE_DAYS" test "$PRUNE_AGE_DAYS" -eq 7
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
  assert_true "startup warns" grep -q 'DISCORD_WEBHOOK_URL unset' <<<"$out"
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
# calls: 1 initial, 2 after lock, 3 after offload
if [[ "\$n" -le 2 ]]; then avail=0; else avail=999999999; fi
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 \${avail} 1% /"
EOF
  chmod +x "${FIX}/stubs/df"
  assert_true "ensure_space succeeds" backup_ensure_space
  assert_false "oldest removed" test -f "$old"
  assert_true "newer kept" test -f "$new"
  teardown_fixture
}

test_m_upload_fail_then_retry_by_filename_age() {
  echo "TEST (m/R1): copy fail then offload_aged retries (filename age, not mtime)"
  setup_fixture
  # Stamp is >24h ago so age stays eligible even if mtime were touched
  local arch
  arch="$(make_fake_archive 'trapaholics-2020-01-01_0000.tar.zst')"
  # Touch local file to "now" — old bug would make age 0h; filename age must win
  touch "$arch"

  echo "fail" >"${FIX}/state/rclone_copy"
  offload_aged
  assert_true "still local after failed copy" test -f "$arch"

  echo "ok" >"${FIX}/state/rclone_copy"
  offload_aged
  assert_false "retried and removed after success" test -f "$arch"
  assert_true "uploaded" test -f "${FIX}/state/remote/trapaholics-2020-01-01_0000.tar.zst"
  teardown_fixture
}

test_n_ensure_space_lock_timeout() {
  echo "TEST (n): backup_ensure_space times out on offload lock"
  if [[ -z "$REAL_FLOCK" ]]; then
    echo "  SKIP: no real flock for lock-timeout test"
    SKIP=$((SKIP + 1))
    return 0
  fi
  setup_fixture
  make_fake_archive 'trapaholics-2026-01-01_0000.tar.zst' >/dev/null
  cat >"${FIX}/stubs/df" <<EOF
#!/usr/bin/env bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 0 1% /"
EOF
  chmod +x "${FIX}/stubs/df"
  export OFFLOAD_LOCK_WAIT_SEC=1
  (
    exec 201>"$OFFLOAD_LOCK_FILE"
    "$REAL_FLOCK" 201
    sleep 5
  ) &
  local holder=$!
  sleep 0.2
  assert_false "ensure_space fails on lock timeout" backup_ensure_space
  assert_alert_title "lock timeout or low-disk alert" "backup skipped \\(low disk\\)|offload lock timeout"
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  teardown_fixture
}

test_o_notfound_false_positive() {
  echo "TEST (o): config-not-found must NOT drop prune log line"
  setup_fixture
  local now iso_30
  now="$(date -u +%s)"
  iso_30="$(iso_from_epoch $((now - 30 * 86400)))"
  echo "trapaholics-2018-01-01_0000.tar.zst ${iso_30}" >"$UPLOADED_LOG"
  echo "old" >"${FIX}/state/remote/trapaholics-2018-01-01_0000.tar.zst"
  printf 'Config file "%s" not found\n' "/home/jt/.config/rclone/rclone.conf" \
    >"${FIX}/state/rclone_deletefile_msg"
  prune_drive_from_log
  assert_true "config-not-found keeps log line" grep -q 'trapaholics-2018-01-01_0000.tar.zst' "$UPLOADED_LOG"
  assert_true "remote file kept" test -f "${FIX}/state/remote/trapaholics-2018-01-01_0000.tar.zst"
  assert_alert_title "prune failure alert" "prune failure"
  teardown_fixture
}

test_p_missing_sha256_skips_in_oldest_one() {
  echo "TEST (p): missing .sha256 does not block offload_oldest_one"
  setup_fixture
  # Oldest has no sha256; newer has one — oldest_one should skip to newer
  echo "nosum" | zstd -q -o "${BACKUP_DIR}/trapaholics-2026-01-01_0000.tar.zst"
  local good
  good="$(make_fake_archive 'trapaholics-2026-01-02_0000.tar.zst')"
  assert_true "offload_oldest_one succeeds via next candidate" offload_oldest_one
  assert_true "no-sha256 archive still local" test -f "${BACKUP_DIR}/trapaholics-2026-01-01_0000.tar.zst"
  assert_false "good archive uploaded+deleted" test -f "$good"
  teardown_fixture
}

test_q_release_lock_preserves_stderr() {
  echo "TEST (q): release_offload_lock must not discard shell stderr"
  setup_fixture
  # Reproduce the path that used to permanently redirect stderr (test d → ensure_space).
  cat >"${FIX}/stubs/df" <<EOF
#!/usr/bin/env bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 0 1% /"
EOF
  chmod +x "${FIX}/stubs/df"
  echo "fail" >"${FIX}/state/rclone_copy"
  make_fake_archive 'trapaholics-2026-01-01_0000.tar.zst' >/dev/null
  backup_ensure_space >/dev/null 2>"${FIX}/state/ensure.err" || true

  # After release_offload_lock inside ensure_space, stderr must still work.
  local line
  line="$(log_warn "stderr-still-alive-$$" 2>&1 >/dev/null)"
  assert_true "log_warn reaches stderr after release_offload_lock" \
    grep -q "stderr-still-alive-$$" <<<"$line"

  # Direct call too
  acquire_offload_lock 0 || true
  release_offload_lock
  line="$(log_warn "stderr-after-direct-release-$$" 2>&1 >/dev/null)"
  assert_true "stderr ok after direct release" \
    grep -q "stderr-after-direct-release-$$" <<<"$line"
  teardown_fixture
}

test_r_orphan_sha256_and_stamp_validation() {
  echo "TEST (r): orphan .sha256 cleanup; invalid BACKUP_ARCHIVE_STAMP refused"
  setup_fixture
  printf 'deadbeef  trapaholics-2026-01-01_0000.tar.zst\n' \
    >"${BACKUP_DIR}/trapaholics-2026-01-01_0000.tar.zst.sha256"
  backup_cleanup_partials
  assert_false "orphan sha256 removed" \
    test -f "${BACKUP_DIR}/trapaholics-2026-01-01_0000.tar.zst.sha256"

  export BACKUP_ARCHIVE_STAMP="not-a-stamp"
  set +e
  backup_create_archive >/dev/null 2>&1
  local rc=$?
  set -e
  assert_true "invalid stamp rejected" test "$rc" -ne 0
  unset BACKUP_ARCHIVE_STAMP
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
test_g_rclone_remote_validation_and_join
test_h_same_minute_frozen_stamp
test_i_locking
test_j_env_overrides_take_effect
test_k_webhook_warning_at_startup
test_l_low_space_success_offloads_oldest_only
test_m_upload_fail_then_retry_by_filename_age
test_n_ensure_space_lock_timeout
test_o_notfound_false_positive
test_p_missing_sha256_skips_in_oldest_one
test_q_release_lock_preserves_stderr
test_r_orphan_sha256_and_stamp_validation

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
if [[ -z "$REAL_FLOCK" ]]; then
  echo "WARNING: REAL_FLOCK unavailable — locking tests were SKIPPED, not passed."
fi
exit 0
