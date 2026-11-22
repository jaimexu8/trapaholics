#!/usr/bin/env bash
# Re-runnable permission + creative-world bootstrap for trapaholics.
#
#   1. Applies scripts/luckperms/groups.lp (LuckPerms groups default/builder/admin)
#      through the survival console over RCON. LuckPerms stores everything in the
#      shared MariaDB, so velocity/survival/creative all see the same groups.
#   2. Creative: creates the Multiverse `build` world (normal terrain) if missing and
#      protects it with WorldGuard: __global__ passthrough=deny, members g:builder,
#      g:admin -> only builders/admins can build there.
#   3. Prints the resulting groups and permission counts straight from MariaDB.
#
# Usage (from the repo root, stack running):
#   scripts/luckperms/setup.sh            # everything
#   scripts/luckperms/setup.sh --no-world # only LuckPerms groups
#
# Safe to run again at any time: groups are cleared and rebuilt from groups.lp;
# player memberships are untouched; world/region steps are idempotent.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GROUPS_FILE="$HERE/groups.lp"
LP_CONTAINER="${LP_CONTAINER:-survival}"
CREATIVE="${CREATIVE_CONTAINER:-creative}"
DB_CONTAINER="${DB_CONTAINER:-mariadb}"
DO_WORLD=1
[[ "${1:-}" == "--no-world" ]] && DO_WORLD=0

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# rcon <container> <command...>  (whole command passed as ONE argument so that
# flags like `-w` reach the server instead of rcon-cli)
rcon() {
  local c="$1"; shift
  docker exec "$c" rcon-cli "$*" | sed 's/\x1b\[[0-9;]*m//g'
}

wait_ready() {
  local c="$1"
  for _ in $(seq 1 60); do
    if docker exec "$c" rcon-cli list >/dev/null 2>&1; then return 0; fi
    sleep 5
  done
  die "$c did not answer RCON within 5 minutes (is it running? docker compose ps)"
}

[[ -f "$GROUPS_FILE" ]] || die "missing $GROUPS_FILE"

log "Waiting for $LP_CONTAINER RCON"
wait_ready "$LP_CONTAINER"

log "Applying $(grep -cvE '^\s*(#|$)' "$GROUPS_FILE") LuckPerms commands via $LP_CONTAINER"
# LuckPerms answers asynchronously, so RCON shows little output; commands run in
# order on LuckPerms' single command thread. Results are verified from the DB below.
# `creategroup` reports "already exists" on re-runs; that is expected.
grep -vE '^\s*(#|$)' "$GROUPS_FILE" | docker exec -i "$LP_CONTAINER" rcon-cli >/dev/null

if (( DO_WORLD )); then
  log "Waiting for $CREATIVE RCON"
  wait_ready "$CREATIVE"
  if rcon "$CREATIVE" mv list | grep -qE '^build - '; then
    echo "World 'build' already exists"
  else
    log "Creating Multiverse world 'build' (normal terrain; takes a while)"
    rcon "$CREATIVE" mv create build normal
  fi
  log "Protecting 'build' with WorldGuard (__global__ passthrough deny, g:builder g:admin)"
  rcon "$CREATIVE" rg flag -w build __global__ passthrough deny
  rcon "$CREATIVE" rg addmember -w build __global__ g:builder g:admin >/dev/null
  # WorldGuard answers region commands asynchronously (nothing comes back over
  # RCON) and saves regions a few seconds later; verify from the saved file.
  regions="$(cd "$HERE/../.." && pwd)/creative/plugins/WorldGuard/worlds/build/regions.yml"
  for _ in $(seq 1 30); do
    grep -q 'passthrough: deny' "$regions" 2>/dev/null && break
    sleep 3
  done
  [[ -r "$regions" ]] || die "cannot read $regions (run from the repo root on the host)"
  echo "--- $regions (__global__):"
  global="$(sed -n '/__global__:/,/priority:/p' "$regions")"
  echo "$global"
  grep -q 'passthrough: deny' <<<"$global" \
    || die "build world __global__ is missing 'passthrough: deny'"
  members="$(sed -n '/members:/,/flags:/p' <<<"$global" | sed -n 's/.*groups: *\[\(.*\)\].*/\1/p' | tr -d ' ')"
  for g in builder admin; do
    [[ ",$members," == *",$g,"* ]] \
      || die "build world __global__ is missing member group '$g' (members: '${members:-none}')"
  done
  echo "OK: build world __global__ has passthrough deny and member groups builder, admin"
fi

log "Waiting for LuckPerms to finish writing"
sleep 5
log "LuckPerms groups in MariaDB"
# shellcheck disable=SC2016  # $MARIADB_PASSWORD is expanded inside the container
docker exec "$DB_CONTAINER" sh -c 'mariadb -uluckperms -p"$MARIADB_PASSWORD" luckperms -t -e "
  SELECT g.name AS \`group\`, COUNT(p.id) AS nodes
    FROM luckperms_groups g LEFT JOIN luckperms_group_permissions p ON p.name = g.name
   GROUP BY g.name ORDER BY g.name;
  SELECT name AS \`group\`, permission, value, server, world
    FROM luckperms_group_permissions
   WHERE permission LIKE \"group.%\" OR permission LIKE \"weight.%\" OR permission = \"*\"
   ORDER BY name, permission;"'

log "Done. In game / console:  lp listgroups   lp group builder permission info"
echo "Promote a player:  docker exec $LP_CONTAINER rcon-cli \"lp user <name> parent add builder\""
