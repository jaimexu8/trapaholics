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

# ---------------------------------------------------------------------------
# Fixture: fake repo + stub bin dir
# ---------------------------------------------------------------------------

setup_fixture() {
  FIX="$(mktemp -d -t trapaholics-backup-test.XXXXXX)"
  mkdir -p \
    "$FIX/repo/velocity" \
    "$FIX/repo/survival/world" \
    "$FIX/repo/creative/world" \
    "$FIX/repo/config" \
    "$FIX/repo/scripts" \
    "$FIX/repo/backups" \
    "$FIX/stubs" \
    "$FIX/state"

  echo "fake-compose" >"$FIX/repo/docker-compose.yml"
  echo "MARIADB_ROOT_PASSWORD=test-secret" >"$FIX/repo/.env"
  echo "DISCORD_WEBHOOK_URL=" >>"$FIX/repo/.env"
  echo "world data" >"$FIX/repo/survival/world/level.dat"
  echo "creative data" >"$FIX/repo/creative/world/level.dat"
  echo "proxy" >"$FIX/repo/velocity/velocity.toml"
  chmod 700 "$FIX/repo/backups"

  # Point backup.conf at this fixture via env overrides (lib respects these).
  export BACKUP_CONF="${SCRIPTS}/backup.conf"
  export REPO_ROOT="$FIX/repo"
  export BACKUP_DIR="$FIX/repo/backups"
  export ENV_FILE="$FIX/repo/.env"
  export STAGING_DIR="$FIX/repo/backups/.staging"
  export SAFETY_MARGIN_BYTES=0
  export BACKUP_SIZE_MULTIPLIER="1.0"
  export OFFLOAD_AGE_HOURS=24
  export PRUNE_AGE_DAYS=30
  export OFFLOAD_FAIL_ALERT_THRESHOLD=99
  export RCLONE_REMOTE="gdrive-crypt:"
  export RCLONE_BWLIMIT=""
  export PAPER_CONTAINERS="survival creative"
  export MARIADB_CONTAINER="mariadb"
  export MARIADB_DATABASE="luckperms"

  # Stub tools on PATH
  export PATH="${FIX}/stubs:${PATH}"
  export DOCKER_BIN="${FIX}/stubs/docker"
  export RCLONE_BIN="${FIX}/stubs/rclone"
  export DF_BIN="${FIX}/stubs/df"
  export CURL_BIN="${FIX}/stubs/curl"

  # flock stub: ignore lock args, run the command or succeed for fd mode
  cat >"${FIX}/stubs/flock" <<'EOF'
#!/usr/bin/env bash
# Minimal flock stub for tests (no real locking).
set -e
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|-x|-s|-u|-e) shift ;;
    -c) shift; exec bash -c "$1" ;;
    -w) shift 2 ;;
    [0-9]*) shift; exit 0 ;;  # fd mode: caller already has the body
    *) exec "$@" ;;
  esac
done
exit 0
EOF
  chmod +x "${FIX}/stubs/flock"

  # docker stub: track rcon commands; fake inspect/dump
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
      echo "false"
      exit 0
    fi
    echo "true"
    ;;
  exec)
    container="\$2"
    shift 2
    if [[ "\$1" == "rcon-cli" ]]; then
      shift
      echo "\$container rcon \$*" >>"\$STATE_DIR/rcon.log"
      exit 0
    fi
    if [[ "\$1" == "mariadb-dump" ]]; then
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

  # df stub: reads free KB from state file (default huge)
  echo "999999999" >"${FIX}/state/df_avail_kb"
  cat >"${FIX}/stubs/df" <<EOF
#!/usr/bin/env bash
# Emulate: df -Pk PATH → avail in 1K blocks in column 4
avail=\$(cat "${FIX}/state/df_avail_kb")
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 \${avail} 1% /"
EOF
  chmod +x "${FIX}/stubs/df"

  # rclone stub: controllable copy/cryptcheck/delete behaviour
  echo "ok" >"${FIX}/state/rclone_copy"
  echo "ok" >"${FIX}/state/rclone_cryptcheck"
  echo "ok" >"${FIX}/state/rclone_deletefile"
  echo "ok" >"${FIX}/state/rclone_delete"
  mkdir -p "${FIX}/state/remote"
  cat >"${FIX}/stubs/rclone" <<EOF
#!/usr/bin/env bash
set -e
echo "\$*" >>"${FIX}/state/rclone.log"
cmd="\$1"
shift || true
case "\$cmd" in
  copy)
    src="\$1"
    if [[ "\$(cat "${FIX}/state/rclone_copy")" != "ok" ]]; then
      echo "rclone copy failed (stub)" >&2
      exit 1
    fi
    cp -a "\$src" "${FIX}/state/remote/\$(basename "\$src")"
    ;;
  cryptcheck)
    src="\$1"
    if [[ "\$(cat "${FIX}/state/rclone_cryptcheck")" != "ok" ]]; then
      echo "rclone cryptcheck failed (stub)" >&2
      exit 1
    fi
    base=\$(basename "\$src")
    if [[ ! -f "${FIX}/state/remote/\$base" ]]; then
      echo "cryptcheck: remote missing \$base" >&2
      exit 1
    fi
    ;;
  deletefile)
    remote="\$1"
    if [[ "\$(cat "${FIX}/state/rclone_deletefile")" != "ok" ]]; then
      echo "rclone deletefile failed (stub)" >&2
      exit 1
    fi
    base=\${remote##*:}
    rm -f "${FIX}/state/remote/\$base"
    echo "\$base" >>"${FIX}/state/rclone_deleted.log"
    ;;
  delete)
    if [[ "\$(cat "${FIX}/state/rclone_delete")" != "ok" ]]; then
      echo "rclone delete failed (stub)" >&2
      exit 1
    fi
    echo "delete \$*" >>"${FIX}/state/rclone_deleted.log"
    ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "${FIX}/stubs/rclone"

  cat >"${FIX}/stubs/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${FIX}/stubs/curl"

  # shellcheck source=../lib.sh disable=SC1091
  source "${SCRIPTS}/lib.sh"
  # Force config load then overlay fixture paths (backup.conf may reset REPO_ROOT).
  backup_load_config
  REPO_ROOT="$FIX/repo"
  BACKUP_DIR="$FIX/repo/backups"
  ENV_FILE="$FIX/repo/.env"
  STAGING_DIR="$FIX/repo/backups/.staging"
  UPLOADED_LOG="${BACKUP_DIR}/.uploaded.log"
  SAFETY_MARGIN_BYTES=0
  BACKUP_SIZE_MULTIPLIER="1.0"
  DOCKER_BIN="${FIX}/stubs/docker"
  RCLONE_BIN="${FIX}/stubs/rclone"
  DF_BIN="${FIX}/stubs/df"
  CURL_BIN="${FIX}/stubs/curl"
  RCLONE_BWLIMIT=""
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
  write_sha256 "$path"
  # Optionally set mtime via second arg (epoch)
  if [[ -n "${2:-}" ]]; then
    if touch -d "@${2}" "$path" 2>/dev/null; then
      :
    else
      # BSD touch
      touch -t "$(date -r "$2" +%Y%m%d%H%M.%S)" "$path" 2>/dev/null || true
    fi
  fi
  printf '%s' "$path"
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

test_a_normal_backup() {
  echo "TEST (a): normal backup produces archive + sha256 and calls save-off/save-on"
  setup_fixture
  rm -f "${FIX}/state/rcon.log"

  local archive
  paper_save_off
  archive="$(backup_create_archive)"
  paper_save_on

  assert_true "archive file exists" test -f "$archive"
  assert_true "sha256 file exists" test -f "${archive}.sha256"
  assert_true "archive mode is 600" bash -c "[[ \$(stat -f '%Lp' '$archive' 2>/dev/null || stat -c '%a' '$archive') == 600 ]]"
  assert_true "rcon save-off called" grep -q 'save-off' "${FIX}/state/rcon.log"
  assert_true "rcon save-all flush called" grep -q 'save-all flush' "${FIX}/state/rcon.log"
  assert_true "rcon save-on called" grep -q 'save-on' "${FIX}/state/rcon.log"
  assert_true "zstd archive verifies" zstd -t "$archive"

  teardown_fixture
}

test_b_save_on_on_failure() {
  echo "TEST (b): save-on still runs when archiving fails"
  setup_fixture
  rm -f "${FIX}/state/rcon.log"

  # Break zstd to force archive failure after save-off
  export ZSTD_BIN="${FIX}/stubs/zstd-fail"
  cat >"$ZSTD_BIN" <<'EOF'
#!/usr/bin/env bash
echo "zstd forced failure" >&2
exit 1
EOF
  chmod +x "$ZSTD_BIN"

  paper_save_off
  set +e
  backup_create_archive >/dev/null 2>&1
  local rc=$?
  set -e
  paper_save_on
  ZSTD_BIN=zstd

  assert_true "archive creation failed" test "$rc" -ne 0
  assert_true "save-off was issued" grep -q 'save-off' "${FIX}/state/rcon.log"
  assert_true "save-on was still issued" grep -q 'save-on' "${FIX}/state/rcon.log"
  assert_false "no archive left behind" bash -c "ls '${BACKUP_DIR}'/trapaholics-*.tar.zst >/dev/null 2>&1"

  teardown_fixture
}

test_c_low_space_path() {
  echo "TEST (c): low-space offloads oldest until room; aborts without delete when upload fails"
  setup_fixture

  local old new
  old="$(make_fake_archive 'trapaholics-2026-01-01_0000.tar.zst')"
  new="$(make_fake_archive 'trapaholics-2026-01-02_0000.tar.zst')"

  # df reports KB. Start with 0 available so free < needed (newest size, margin 0),
  # then report plenty of space after the first offload attempt.
  cat >"${FIX}/stubs/df" <<EOF
#!/usr/bin/env bash
count_file="${FIX}/state/df_calls"
n=\$(( \$(cat "\$count_file" 2>/dev/null || echo 0) + 1 ))
echo "\$n" >"\$count_file"
# First df call = initial space check (too low). Later calls = after offload.
if [[ "\$n" -le 1 ]]; then
  avail=0
else
  avail=999999999
fi
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 \${avail} 1% /"
EOF
  chmod +x "${FIX}/stubs/df"

  assert_true "ensure_space succeeds after offloading oldest" backup_ensure_space
  assert_false "oldest archive removed after verified offload" test -f "$old"
  assert_true "newer archive still local" test -f "$new"
  assert_true "oldest present on remote stub" test -f "${FIX}/state/remote/$(basename "$old")"
  assert_true "uploaded log has oldest" grep -q "$(basename "$old")" "$UPLOADED_LOG"

  # Reset: upload failure must not delete
  teardown_fixture
  setup_fixture
  old="$(make_fake_archive 'trapaholics-2026-01-01_0000.tar.zst')"
  make_fake_archive 'trapaholics-2026-01-02_0000.tar.zst' >/dev/null
  echo "fail" >"${FIX}/state/rclone_copy"
  cat >"${FIX}/stubs/df" <<EOF
#!/usr/bin/env bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 0 1% /"
EOF
  chmod +x "${FIX}/stubs/df"

  assert_false "ensure_space aborts when offload fails" backup_ensure_space
  assert_true "local oldest kept after failed upload (B5)" test -f "$old"
  assert_false "oldest not on remote" test -f "${FIX}/state/remote/$(basename "$old")"

  teardown_fixture
}

test_d_offload_cryptcheck_gate() {
  echo "TEST (d): offload deletes only after cryptcheck passes; keeps on failure"
  setup_fixture
  local arch
  arch="$(make_fake_archive 'trapaholics-2026-03-01_1200.tar.zst')"

  # Success path
  assert_true "offload_archive succeeds" offload_archive "$arch"
  assert_false "local archive deleted after cryptcheck" test -f "$arch"
  assert_false "local sha256 deleted after cryptcheck" test -f "${arch}.sha256"
  assert_true "remote has archive" test -f "${FIX}/state/remote/$(basename "$arch")"
  assert_true "uploaded log updated" grep -q "$(basename "$arch")" "$UPLOADED_LOG"

  # Failure path: copy ok, cryptcheck fails → keep local
  arch="$(make_fake_archive 'trapaholics-2026-03-02_1200.tar.zst')"
  echo "ok" >"${FIX}/state/rclone_copy"
  echo "fail" >"${FIX}/state/rclone_cryptcheck"
  assert_false "offload_archive fails on cryptcheck" offload_archive "$arch"
  assert_true "local archive kept when cryptcheck fails" test -f "$arch"
  assert_true "local sha256 kept when cryptcheck fails" test -f "${arch}.sha256"

  teardown_fixture
}

test_e_prune_age() {
  echo "TEST (e): pruning removes only entries ≥ 30 days old"
  setup_fixture

  # Put two remote files
  echo "old" >"${FIX}/state/remote/trapaholics-old.tar.zst"
  echo "new" >"${FIX}/state/remote/trapaholics-new.tar.zst"

  local now old_iso new_iso
  now="$(date -u +%s)"
  # 31 days ago and 1 day ago
  if date -u -d "@$((now - 31*86400))" +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    old_iso="$(date -u -d "@$((now - 31*86400))" +%Y-%m-%dT%H:%M:%SZ)"
    new_iso="$(date -u -d "@$((now - 1*86400))" +%Y-%m-%dT%H:%M:%SZ)"
  else
    old_iso="$(date -u -r "$((now - 31*86400))" +%Y-%m-%dT%H:%M:%SZ)"
    new_iso="$(date -u -r "$((now - 1*86400))" +%Y-%m-%dT%H:%M:%SZ)"
  fi

  cat >"$UPLOADED_LOG" <<EOF
trapaholics-old.tar.zst ${old_iso}
trapaholics-new.tar.zst ${new_iso}
EOF

  prune_drive_from_log

  assert_false "old remote file deleted" test -f "${FIX}/state/remote/trapaholics-old.tar.zst"
  assert_true "new remote file kept" test -f "${FIX}/state/remote/trapaholics-new.tar.zst"
  assert_false "old log line removed" grep -q 'trapaholics-old.tar.zst' "$UPLOADED_LOG"
  assert_true "new log line kept" grep -q 'trapaholics-new.tar.zst' "$UPLOADED_LOG"

  # Safety net still invoked by prune-drive.sh — call directly
  assert_true "safety-net prune runs" prune_drive_safety_net
  assert_true "safety-net logged" grep -q 'delete' "${FIX}/state/rclone_deleted.log"

  teardown_fixture
}

test_backup_sh_trap_integration() {
  echo "TEST (extra): backup.sh EXIT trap restores save-on when zstd fails"
  setup_fixture
  # Use a broken zstd on PATH for the real script invocation
  cat >"${FIX}/stubs/zstd" <<'EOF'
#!/usr/bin/env bash
echo "forced zstd fail" >&2
exit 1
EOF
  chmod +x "${FIX}/stubs/zstd"

  set +e
  # Override REPO_ROOT via a temporary conf
  cat >"${FIX}/backup.conf" <<EOF
REPO_ROOT="${FIX}/repo"
BACKUP_SUBDIR="backups"
SAFETY_MARGIN_BYTES=0
BACKUP_SIZE_MULTIPLIER="1.0"
RCLONE_REMOTE="gdrive-crypt:"
RCLONE_BWLIMIT=""
OFFLOAD_AGE_HOURS=24
PRUNE_AGE_DAYS=30
OFFLOAD_FAIL_ALERT_THRESHOLD=99
PAPER_CONTAINERS="survival creative"
MARIADB_CONTAINER="mariadb"
MARIADB_DATABASE="luckperms"
BACKUP_EXCLUDES="libraries cache versions"
BACKUP_INCLUDE_PATHS="velocity survival creative config scripts docker-compose.yml .env"
EOF
  # df with plenty of space
  echo "999999999" >"${FIX}/state/df_avail_kb"
  cat >"${FIX}/stubs/df" <<EOF
#!/usr/bin/env bash
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/test 1000000000 1 999999999 1% /"
EOF
  chmod +x "${FIX}/stubs/df"

  BACKUP_CONF="${FIX}/backup.conf" \
    DOCKER_BIN="${FIX}/stubs/docker" \
    RCLONE_BIN="${FIX}/stubs/rclone" \
    DF_BIN="${FIX}/stubs/df" \
    CURL_BIN="${FIX}/stubs/curl" \
    PATH="${FIX}/stubs:${PATH}" \
    "${SCRIPTS}/backup.sh" >/dev/null 2>&1
  local rc=$?
  set -e

  assert_true "backup.sh exited non-zero" test "$rc" -ne 0
  assert_true "save-on via EXIT trap" grep -q 'save-on' "${FIX}/state/rcon.log"

  teardown_fixture
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=== trapaholics backup test harness ==="
echo "ROOT=${ROOT}"

test_a_normal_backup
test_b_save_on_on_failure
test_c_low_space_path
test_d_offload_cryptcheck_gate
test_e_prune_age
test_backup_sh_trap_integration

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [[ "$FAIL" -ne 0 ]]; then
  exit 1
fi
exit 0
