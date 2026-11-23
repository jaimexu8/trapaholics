#!/usr/bin/env bash
# Re-runnable permission + creative-world bootstrap for trapaholics.
#
#   1. Applies scripts/luckperms/groups.lp (LuckPerms groups default/builder/admin)
#      through the minecraft console over RCON.
#   2. Creates the Multiverse `creative` world (normal terrain, forced creative,
#      peaceful, nether/end portals disabled) if missing; copies Paper per-world
#      limits; protects spawn with WorldGuard placeholders noted in DEPLOY.md.
#   3. Ensures Multiverse-Inventories groups are loaded; prints LuckPerms result.
#
# Usage (from the repo root, stack running):
#   scripts/luckperms/setup.sh            # everything
#   scripts/luckperms/setup.sh --no-world # only LuckPerms groups
#
# Safe to run again at any time: groups are cleared and rebuilt from groups.lp;
# player memberships are untouched; world steps are idempotent.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GROUPS_FILE="$HERE/groups.lp"
MC_CONTAINER="${MC_CONTAINER:-minecraft}"
DB_CONTAINER="${DB_CONTAINER:-mariadb}"
DO_WORLD=1
[[ "${1:-}" == "--no-world" ]] && DO_WORLD=0

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# rcon <container> <command...>  (whole command as ONE argument)
rcon() {
  local c="$1"; shift
  docker exec "$c" rcon-cli "$*" | sed 's/\x1b\[[0-9;]*m//g'
}

wait_ready() {
  local c="$1"
  for _ in $(seq 1 90); do
    if docker exec "$c" rcon-cli list >/dev/null 2>&1; then return 0; fi
    sleep 5
  done
  die "$c did not answer RCON within ~7.5 minutes (is it running? docker compose ps)"
}

[[ -f "$GROUPS_FILE" ]] || die "missing $GROUPS_FILE"

log "Waiting for $MC_CONTAINER RCON"
wait_ready "$MC_CONTAINER"

log "Applying $(grep -cvE '^\s*(#|$)' "$GROUPS_FILE") LuckPerms commands via $MC_CONTAINER"
grep -vE '^\s*(#|$)' "$GROUPS_FILE" | docker exec -i "$MC_CONTAINER" rcon-cli >/dev/null

if (( DO_WORLD )); then
  # Multiverse list output varies by version; accept several forms.
  if rcon "$MC_CONTAINER" mv list | grep -qiE '(^|[^-])creative([^-]|$)'; then
    echo "World 'creative' already exists"
  else
    log "Creating Multiverse world 'creative' (normal terrain; takes a while)"
    rcon "$MC_CONTAINER" mv create creative normal
  fi

  log "Configuring creative world (gamemode creative, peaceful, no nether/end portals)"
  # Multiverse-Core 5: mv modify [world] set <property> <value>
  rcon "$MC_CONTAINER" mv modify creative set gamemode creative
  rcon "$MC_CONTAINER" mv modify creative set difficulty peaceful
  rcon "$MC_CONTAINER" mv modify creative set pvp false
  rcon "$MC_CONTAINER" mv modify creative set allow-flight true
  rcon "$MC_CONTAINER" mv modify creative set hunger false
  # portal-form none blocks nether/end portal creation/use in this world.
  rcon "$MC_CONTAINER" mv modify creative set portal-form none
  # Multiverse-NetherPortals: unlink so any leftover links go nowhere.
  rcon "$MC_CONTAINER" mvnp unlink nether creative || true
  rcon "$MC_CONTAINER" mvnp unlink end creative || true

  # Paper per-world limits for creative (ARCHITECTURE §5.6).
  paper_src="$ROOT/config/minecraft/creative-paper-world.yml"
  paper_dst="$ROOT/minecraft/creative/paper-world.yml"
  if [[ -f "$paper_src" ]]; then
    mkdir -p "$(dirname "$paper_dst")"
    cp "$paper_src" "$paper_dst"
    echo "Wrote $paper_dst"
  fi

  # Ensure Multiverse-Inventories has potion_effects on both groups (idempotent).
  rcon "$MC_CONTAINER" mvinv add-shares survival potion_effects || true
  rcon "$MC_CONTAINER" mvinv add-shares creative potion_effects || true
  rcon "$MC_CONTAINER" mvinv reload || true

  log "WorldGuard: define spawn regions in-game (see DEPLOY.md). Soft spawn protection note only."
fi

log "Waiting for LuckPerms to finish writing"
sleep 5
log "LuckPerms groups in MariaDB"
# shellcheck disable=SC2016  # $MARIADB_PASSWORD may be unset; use root + env from compose
docker exec "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" luckperms -t -e "
  SELECT g.name AS \`group\`, COUNT(p.id) AS nodes
    FROM luckperms_groups g LEFT JOIN luckperms_group_permissions p ON p.name = g.name
   GROUP BY g.name ORDER BY g.name;
  SELECT name AS \`group\`, permission, value, server, world
    FROM luckperms_group_permissions
   WHERE permission LIKE \"group.%\" OR permission LIKE \"weight.%\" OR permission = \"*\"
      OR permission LIKE \"fawe.%\" OR permission LIKE \"voxelsniper.%\"
   ORDER BY name, permission, world;"'

log "Verifying: no explicit false nodes; builder FAWE only in world=creative"
# shellcheck disable=SC2016
false_count="$(docker exec "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N luckperms -e "
  SELECT COUNT(*) FROM luckperms_group_permissions WHERE value = 0;"')"
[[ "$false_count" == "0" ]] || die "found $false_count explicit false nodes (must be zero)"

# shellcheck disable=SC2016
bad_fawe="$(docker exec "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N luckperms -e "
  SELECT COUNT(*) FROM luckperms_group_permissions
   WHERE name = \"builder\" AND permission LIKE \"fawe.%\"
     AND world <> \"creative\";"')"
[[ "$bad_fawe" == "0" ]] || die "builder has $bad_fawe FAWE nodes outside world=creative"

echo "OK: no false nodes; builder FAWE nodes are world=creative only"
log "Done. In game / console:  lp listgroups   lp group builder permission info"
echo "Promote a player:  docker exec $MC_CONTAINER rcon-cli \"lp user <name> parent add builder\""
