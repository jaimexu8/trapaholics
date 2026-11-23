#!/usr/bin/env bash
# Re-runnable permission + creative-world bootstrap for trapaholics.
#
#   1. Applies scripts/luckperms/groups.lp (LuckPerms groups default/builder/admin)
#      through the minecraft console over RCON.
#   2. Creates the Multiverse `creative` world (normal terrain, forced creative,
#      peaceful, nether/end portals disabled) if missing; copies Paper per-world
#      limits; installs WorldGuard spawn regions for survival + creative.
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
# Host path of the minecraft /data bind mount (smoke test overrides it).
MC_DATA_DIR="${MC_DATA_DIR:-$ROOT/minecraft}"
DO_WORLD=1
[[ "${1:-}" == "--no-world" ]] && DO_WORLD=0

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# rcon <container> <command...>  (whole command as ONE argument)
rcon() {
  local c="$1"; shift
  docker exec "$c" rcon-cli "$*" | sed 's/\x1b\[[0-9;]*m//g'
}

# rcon that must succeed (no silent failure). Multiverse prints errors to chat;
# treat empty/error-looking replies as failure when verifying.
rcon_ok() {
  local c="$1"; shift
  local out
  out="$(rcon "$c" "$@")" || die "rcon failed: $*"
  printf '%s\n' "$out"
  if printf '%s' "$out" | grep -qiE 'unknown|error|failed|invalid|does not exist|not found'; then
    die "command looked failed: $* → $out"
  fi
}

wait_ready() {
  local c="$1"
  for _ in $(seq 1 90); do
    if docker exec "$c" rcon-cli list >/dev/null 2>&1; then return 0; fi
    sleep 5
  done
  die "$c did not answer RCON within ~7.5 minutes (is it running? docker compose ps)"
}

# Writes the spawn region from config/worldguard/spawn-regions.yml into a world's
# WorldGuard regions.yml (only if that world has no `spawn` region yet). The
# caller then runs `wg reload` and verifies the region round-trips (see below).
install_wg_spawn() {
  local world="$1"
  local wg_dir="$MC_DATA_DIR/plugins/WorldGuard/worlds/$world"
  local regions="$wg_dir/regions.yml"
  local template="$ROOT/config/worldguard/spawn-regions.yml"
  local unit

  [[ -f "$template" ]] || die "missing $template"
  mkdir -p "$wg_dir"
  if [[ -f "$regions" ]] && grep -qE '^ +spawn:' "$regions"; then
    echo "WorldGuard spawn region already present in $world"
    return 0
  fi
  # No file, or a file with no regions (`regions: {}` / bare `regions:`): use the
  # template as-is. Otherwise append the template's spawn block under regions:,
  # re-indented to the file's indent unit (WorldGuard itself writes 4 spaces).
  if [[ ! -f "$regions" ]] || ! grep -qE '^ +[^ #]' "$regions"; then
    cp "$template" "$regions"
  else
    grep -qE '^regions:[[:space:]]*$' "$regions" \
      || die "unexpected layout in $regions; add the spawn region by hand (DEPLOY step 10)"
    unit="$(grep -m1 -oE '^ +' "$regions")"
    sed -n '/^  spawn:/,$p' "$template" | awk -v u="$unit" '{
      match($0, /^ */); n = RLENGTH / 2; pre = ""
      for (i = 0; i < n; i++) pre = pre u
      print pre substr($0, RLENGTH + 1) }' >>"$regions"
  fi
  echo "Wrote WorldGuard spawn region for $world -> $regions"
}

# The ONLY explicit false nodes allowed: admin's Multiverse-Core gamemode bypass
# (global context), so admin `*` does not keep admins in their gamemode across
# worlds. Everything else must be granted positively (false nodes beat `*`).
ALLOWED_FALSE_NODES=(
  mv.bypass.gamemode.survival
  mv.bypass.gamemode.survival_nether
  mv.bypass.gamemode.survival_the_end
  mv.bypass.gamemode.creative
  'mv.bypass.gamemode.*'
)

# Reads false nodes as TSV `group<TAB>permission<TAB>server<TAB>world` on stdin.
# Fails on any node that is not an allowed admin node in the global context, and
# if an allowed admin node is missing.
check_false_nodes() {
  local group perm server world p ok bad=0 seen=" "
  while IFS=$'\t' read -r group perm server world; do
    [[ -n "$group" ]] || continue
    ok=0
    if [[ "$group" == admin && "$server" == global && "$world" == global ]]; then
      for p in "${ALLOWED_FALSE_NODES[@]}"; do
        [[ "$perm" == "$p" ]] && ok=1
      done
    fi
    if (( ok )); then
      seen+="$perm "
    else
      printf 'unexpected false node: group=%s permission=%s server=%s world=%s\n' \
        "$group" "$perm" "$server" "$world" >&2
      bad=1
    fi
  done
  for p in "${ALLOWED_FALSE_NODES[@]}"; do
    [[ "$seen" == *" $p "* ]] || { printf 'missing admin false node: %s\n' "$p" >&2; bad=1; }
  done
  (( bad == 0 )) || die "explicit false nodes are wrong (only admin mv.bypass.gamemode.* allowed)"
  echo "false nodes: only admin mv.bypass.gamemode.* (${#ALLOWED_FALSE_NODES[@]} nodes)"
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
    rcon_ok "$MC_CONTAINER" mv create creative normal
  fi

  log "Configuring creative world (gamemode creative, peaceful, no nether/end portals)"
  # Multiverse-Core 5: mv modify [world] set <property> <value>
  rcon_ok "$MC_CONTAINER" mv modify creative set gamemode creative
  rcon_ok "$MC_CONTAINER" mv modify creative set difficulty peaceful
  rcon_ok "$MC_CONTAINER" mv modify creative set pvp false
  rcon_ok "$MC_CONTAINER" mv modify creative set allow-flight true
  rcon_ok "$MC_CONTAINER" mv modify creative set hunger false
  # portal-form none blocks nether/end portal creation/use in this world.
  rcon_ok "$MC_CONTAINER" mv modify creative set portal-form none

  # Read back from Multiverse-Core's worlds.yml (`mv info` output is paginated).
  mv_worlds="$MC_DATA_DIR/plugins/Multiverse-Core/worlds.yml"
  [[ -f "$mv_worlds" ]] || die "missing $mv_worlds"
  creative_cfg="$(awk '/^[^ #]/{p=($0 ~ /^(minecraft:)?creative:/)} p' "$mv_worlds")"
  for kv in 'gamemode: creative' 'difficulty: peaceful' 'portal-form: none'; do
    grep -qE "^  ${kv}\$" <<<"$creative_cfg" \
      || die "creative world: expected '${kv}' in $mv_worlds after mv modify"
  done
  echo "creative read back: gamemode creative, difficulty peaceful, portal-form none"

  # Multiverse-NetherPortals: unlink so any leftover links go nowhere.
  # Fail loudly if the plugin is missing; "already unlinked" is OK.
  unlink_n="$(rcon "$MC_CONTAINER" mvnp unlink nether creative)"
  unlink_e="$(rcon "$MC_CONTAINER" mvnp unlink end creative)"
  printf '%s\n%s\n' "$unlink_n" "$unlink_e"
  if printf '%s\n%s' "$unlink_n" "$unlink_e" | grep -qiE 'unknown command|plugin.*not'; then
    die "Multiverse-NetherPortals mvnp unavailable"
  fi

  # Paper per-world limits for creative (ARCHITECTURE §5.6). Paper 26.3 keeps
  # every dimension under the level folder (LEVEL=survival in compose). Keep the
  # header + `_version` Paper wrote, then append our overrides (idempotent).
  # Takes effect on the next minecraft restart (DEPLOY step 8).
  paper_src="$ROOT/config/paper/creative-paper-world.yml"
  paper_dst="$MC_DATA_DIR/survival/dimensions/minecraft/creative/paper-world.yml"
  [[ -f "$paper_src" ]] || die "missing $paper_src"
  [[ -f "$paper_dst" ]] || die "missing $paper_dst (Paper writes it when the world loads)"
  grep -qE '^_version: [0-9]+$' "$paper_dst" || die "no _version line in $paper_dst"
  { sed -n '1,/^_version:/p' "$paper_dst"; grep -vE '^[[:space:]]*#' "$paper_src"; } >"$paper_dst.new"
  mv "$paper_dst.new" "$paper_dst"
  echo "Wrote $paper_dst"

  # Multiverse-Inventories: groups.yml is seeded via /config sync with shares: [all].
  # Reload so a live server picks up template changes; fail if mvinv is missing.
  mvinv_out="$(rcon "$MC_CONTAINER" mvinv reload)"
  printf '%s\n' "$mvinv_out"
  ! printf '%s' "$mvinv_out" | grep -qiE 'unknown command|plugin.*not' \
    || die "Multiverse-Inventories mvinv unavailable"

  log "WorldGuard spawn regions (survival + creative)"
  install_wg_spawn survival
  install_wg_spawn creative
  # `wg reload` reloads config + region data. WorldGuard's `rg` commands reply
  # asynchronously (nothing comes back over RCON), so verify by round-trip:
  # `rg save` rewrites regions.yml from memory (dropping our template comments);
  # the spawn region with its flags must survive that.
  wg_out="$(rcon "$MC_CONTAINER" wg reload)"
  printf '%s\n' "$wg_out"
  grep -qi 'reloaded' <<<"$wg_out" || die "wg reload failed: $wg_out"
  for w in survival creative; do
    rcon "$MC_CONTAINER" rg save -w "$w" >/dev/null
  done
  sleep 5
  for w in survival creative; do
    f="$MC_DATA_DIR/plugins/WorldGuard/worlds/$w/regions.yml"
    if grep -q 'Template for WorldGuard' "$f" || ! grep -qE '^ +spawn:' "$f" \
       || ! grep -q 'pvp: deny' "$f"; then
      die "WorldGuard did not load the spawn region for $w (see $f)"
    fi
    echo "WorldGuard spawn region loaded in $w"
  done
fi

log "Waiting for LuckPerms to finish writing"
sleep 5
log "LuckPerms groups in MariaDB"
# shellcheck disable=SC2016  # passwords come from container env
docker exec "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" luckperms -t -e "
  SELECT g.name AS \`group\`, COUNT(p.id) AS nodes
    FROM luckperms_groups g LEFT JOIN luckperms_group_permissions p ON p.name = g.name
   GROUP BY g.name ORDER BY g.name;
  SELECT name AS \`group\`, permission, value, server, world
    FROM luckperms_group_permissions
   WHERE permission LIKE \"group.%\" OR permission LIKE \"weight.%\" OR permission = \"*\"
      OR permission LIKE \"fawe.%\" OR permission LIKE \"voxelsniper.%\"
      OR permission LIKE \"worldedit.%\"
   ORDER BY name, permission, world;"'

log "Verifying: only the allowed false nodes; builder FAWE/Voxel only in world=creative; default has no edit tools"
# shellcheck disable=SC2016
false_nodes="$(docker exec "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N luckperms -e "
  SELECT name, permission, server, world FROM luckperms_group_permissions
   WHERE value = 0 ORDER BY name, permission;"')"
check_false_nodes <<<"$false_nodes"

# shellcheck disable=SC2016
bad_fawe="$(docker exec "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N luckperms -e "
  SELECT COUNT(*) FROM luckperms_group_permissions
   WHERE name = \"builder\" AND permission LIKE \"fawe.%\"
     AND world <> \"creative\";"')"
[[ "$bad_fawe" == "0" ]] || die "builder has $bad_fawe FAWE nodes outside world=creative"

# shellcheck disable=SC2016
bad_voxel="$(docker exec "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N luckperms -e "
  SELECT COUNT(*) FROM luckperms_group_permissions
   WHERE name = \"builder\" AND permission LIKE \"voxelsniper.%\"
     AND world <> \"creative\";"')"
[[ "$bad_voxel" == "0" ]] || die "builder has $bad_voxel voxelsniper nodes outside world=creative"

# shellcheck disable=SC2016
default_edit="$(docker exec "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N luckperms -e "
  SELECT COUNT(*) FROM luckperms_group_permissions
   WHERE name = \"default\" AND (
     permission LIKE \"fawe.%\" OR permission LIKE \"worldedit.%\"
     OR permission LIKE \"voxelsniper.%\"
   );"')"
[[ "$default_edit" == "0" ]] || die "default has $default_edit FAWE/WorldEdit/VoxelSniper nodes (must be zero)"

# shellcheck disable=SC2016
builder_voxel_pct="$(docker exec "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N luckperms -e "
  SELECT COUNT(*) FROM luckperms_group_permissions
   WHERE name = \"builder\" AND permission = \"voxelsniper.%\" AND world = \"creative\";"')"
[[ "$builder_voxel_pct" == "1" ]] || die "builder missing voxelsniper.% in world=creative"

echo "OK: only admin gamemode-bypass false nodes; builder FAWE/Voxel creative-only; default has no edit tools"
log "Done. In game / console:  lp listgroups   lp group builder permission info"
echo "Promote a player:  docker exec $MC_CONTAINER rcon-cli \"lp user <name> parent add builder\""
echo "Note: admin mv.bypass.gamemode.* is set false, so admins are forced into each world's gamemode;"
echo "Multiverse-Inventories bypass is OFF so inventories still swap between survival and creative."
