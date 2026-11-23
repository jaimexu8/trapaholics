#!/usr/bin/env bash
# Offline test of setup.sh --no-world against a stubbed docker/mariadb (sqlite).
#   1. partial: admin has only weight+displayname for the first reads → waits, passes
#   2. missing: one admin false node never appears → fails, names the node
#   3. stale:   an extra node not in groups.lp → unset over RCON, then passes
# Usage: scripts/luckperms/test/test-setup-wait.sh   (needs sqlite3)
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$HERE/../setup.sh"
GROUPS_FILE="$HERE/../groups.lp"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"; cp "$HERE/stub-docker" "$TMP/bin/docker"; chmod +x "$TMP/bin/docker"
fail=0

# Builds a sqlite db with every node groups.lp defines (same parse as LuckPerms).
make_full_db() {
  local db="$1"
  sqlite3 "$db" "CREATE TABLE luckperms_groups(name TEXT PRIMARY KEY);
    CREATE TABLE luckperms_group_permissions(id INTEGER PRIMARY KEY, name TEXT,
      permission TEXT, value INTEGER, server TEXT, world TEXT, expiry INTEGER, contexts TEXT);
    INSERT INTO luckperms_groups VALUES ('default'),('builder'),('admin');"
  awk '$1=="lp" && $2=="group" {
      g=$3; s="global"; w="global"; v=1
      if ($4=="setweight") n="weight." $5
      else if ($4=="setdisplayname") n="displayname." $5
      else if ($4=="parent") n="group." $6
      else if ($4=="permission") { n=$6; i=7
        if ($7=="false") { v=0; i=8 } else if ($7=="true") i=8
        for (; i<=NF; i++) if ($i ~ /^world=/) w=substr($i,7) }
      else next
      printf "INSERT INTO luckperms_group_permissions(name,permission,value,server,world,expiry,contexts) VALUES (\x27%s\x27,\x27%s\x27,%d,\x27%s\x27,\x27%s\x27,0,\x27{}\x27);\n", g,n,v,s,w
    }' "$GROUPS_FILE" | sqlite3 "$db"
}

run_case() { # name expect_rc env...
  local name="$1" want="$2"; shift 2
  echo "=== case: $name (expect exit $want)"
  env PATH="$TMP/bin:$PATH" STUB_DIR="$TMP/$name" LP_POLL_INTERVAL=1 LP_STABLE_READS=3 \
    "$@" bash "$SETUP" --no-world >"$TMP/$name/out" 2>&1
  local rc=$?
  sed 's/^/    /' "$TMP/$name/out"
  if [[ "$want" == 0 && $rc -ne 0 ]] || [[ "$want" != 0 && $rc -eq 0 ]]; then
    echo "FAIL: $name exited $rc"; fail=1; return 1
  fi
  echo "--- $name: exit $rc as expected"
}

# 1. partial for the first 3 db reads, then complete.
d="$TMP/partial"; mkdir -p "$d"
make_full_db "$d/final.db"; cp "$d/final.db" "$d/live.db"
sqlite3 "$d/live.db" "DELETE FROM luckperms_group_permissions WHERE name='admin'
  AND permission NOT LIKE 'weight.%' AND permission NOT LIKE 'displayname.%';"
if run_case partial 0 STUB_PARTIAL_CALLS=3 LP_WAIT_TIMEOUT=30; then
  grep -q 'waiting (0s): 6 missing' "$d/out" || { echo "FAIL: partial did not wait"; fail=1; }
  grep -q 'LuckPerms settled' "$d/out" || { echo "FAIL: partial never settled"; fail=1; }
fi

# 2. a node that never shows up.
d="$TMP/missing"; mkdir -p "$d"
make_full_db "$d/live.db"
sqlite3 "$d/live.db" "DELETE FROM luckperms_group_permissions WHERE name='admin' AND permission='mv.bypass.gamemode.*';"
if run_case missing 1 LP_WAIT_TIMEOUT=4; then
  grep -q $'admin\tmv.bypass.gamemode.\*\t0\tglobal\tglobal' "$d/out" \
    || { echo "FAIL: missing node not named"; fail=1; }
  grep -q 'did not settle in MariaDB within 4s' "$d/out" || { echo "FAIL: no timeout error"; fail=1; }
fi

# 3. a stale node gets unset (and nothing is cleared).
d="$TMP/stale"; mkdir -p "$d"
make_full_db "$d/live.db"
sqlite3 "$d/live.db" "INSERT INTO luckperms_group_permissions(name,permission,value,server,world,expiry,contexts)
  VALUES ('default','essentials.fly',1,'global','creative',0,'{}');"
if run_case stale 0 LP_WAIT_TIMEOUT=10; then
  grep -qx 'lp group default permission unset essentials.fly world=creative' "$d/rcon.log" \
    || { echo "FAIL: stale node not unset"; fail=1; }
  ! grep -q ' clear$' "$d/rcon.log" || { echo "FAIL: a group was cleared"; fail=1; }
fi

if (( fail )); then echo "SOME FAILED"; exit 1; fi
echo "ALL PASS"
