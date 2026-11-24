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
# Safe to run again at any time: every node in groups.lp is (re)set in place, then
# only nodes that are in MariaDB but NOT in groups.lp are unset (no `clear`, so a
# live server never sees empty groups). Player memberships are untouched; world
# steps are idempotent.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
GROUPS_FILE="$HERE/groups.lp"
MC_CONTAINER="${MC_CONTAINER:-minecraft}"
DB_CONTAINER="${DB_CONTAINER:-mariadb}"
# Host path of the minecraft /data bind mount (smoke test overrides it).
MC_DATA_DIR="${MC_DATA_DIR:-$ROOT/minecraft}"
# Waiting for LuckPerms' async MariaDB writes (tests shorten these).
LP_WAIT_TIMEOUT="${LP_WAIT_TIMEOUT:-120}"
LP_POLL_INTERVAL="${LP_POLL_INTERVAL:-2}"
LP_STABLE_READS="${LP_STABLE_READS:-3}"
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

# db <mariadb flags...>  — runs the SQL on stdin against the luckperms database.
db() {
  # shellcheck disable=SC2016  # password comes from the container env
  docker exec -i "$DB_CONTAINER" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" "$@" luckperms' sh "$@"
}

# Expected group nodes from groups.lp as TSV `group<TAB>node<TAB>value<TAB>server<TAB>world`
# (value 1/0, LuckPerms' storage form). setweight / setdisplayname / parent add are
# nodes too (weight.N, displayname.X, group.P). Fails on anything it can't model.
expected_nodes() {
  awk '
    function bad(why) { printf "groups.lp:%d: %s: %s\n", NR, why, $0 > "/dev/stderr"; err = 1 }
    /^[[:space:]]*(#|$)/ || $1 != "lp" || $2 != "group" { next }
    $4 == "setweight"      { print $3 "\tweight." $5 "\t1\tglobal\tglobal"; next }
    $4 == "setdisplayname" { if (NF != 5) bad("display name with spaces unsupported")
                             print $3 "\tdisplayname." $5 "\t1\tglobal\tglobal"; next }
    $4 == "parent" && $5 == "add" && NF == 6 { print $3 "\tgroup." $6 "\t1\tglobal\tglobal"; next }
    $4 == "permission" && $5 == "set" {
      v = 1; i = 7
      if ($7 == "true") i = 8
      else if ($7 == "false") { v = 0; i = 8 }
      s = "global"; w = "global"
      for (; i <= NF; i++) {
        if ($i ~ /^world=/) w = substr($i, 7)
        else if ($i ~ /^server=/) s = substr($i, 8)
        else bad("unsupported context " $i)
      }
      print $3 "\t" $6 "\t" v "\t" s "\t" w; next
    }
    { bad("unsupported command (setup.sh diffs nodes instead of clearing)") }
    END { exit err }
  ' "$GROUPS_FILE" | sort -u
}

# Current nodes of the groups named in groups.lp, same TSV form, sorted.
current_nodes() {
  local in
  in="$(cut -f1 <<<"$EXPECTED" | sort -u | sed "s/.*/'&'/" | paste -sd, -)"
  db -N -B <<SQL | sort -u
SELECT name, permission, value, server, world FROM luckperms_group_permissions
 WHERE name IN ($in);
SQL
}

# missing_nodes <current>  — expected lines absent from current (value must match).
missing_nodes() { comm -23 <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$1"); }

# stale_nodes <current>  — current nodes whose group+node+server+world is not in
# groups.lp at all (a value mismatch shows up as missing instead).
stale_nodes() {
  awk -F'\t' 'NR == FNR { want[$1 FS $2 FS $4 FS $5] = 1; next }
              $1 != "" && !(($1 FS $2 FS $4 FS $5) in want)' \
    <(printf '%s\n' "$EXPECTED") <(printf '%s\n' "$1")
}

# wait_lp_settled <require_no_stale 0|1>
# LuckPerms writes to MariaDB asynchronously after the RCON commands return. Poll
# until every groups.lp node is present (and, if asked, no stale node is left)
# and the node set is unchanged across LP_STABLE_READS reads.
wait_lp_settled() {
  local strict="$1" cur sum last="" stable=0 missing stale elapsed=0
  while :; do
    cur="$(current_nodes)" || die "could not read LuckPerms nodes from $DB_CONTAINER"
    missing="$(missing_nodes "$cur")"
    stale=""
    (( strict )) && stale="$(stale_nodes "$cur")"
    sum="$(cksum <<<"$cur")"
    if [[ -z "$missing" && -z "$stale" ]]; then
      if [[ "$sum" == "$last" ]]; then stable=$((stable + 1)); else stable=1; fi
      if (( stable >= LP_STABLE_READS )); then
        echo "LuckPerms settled: $(grep -c . <<<"$cur") group nodes, all of groups.lp present"
        return 0
      fi
    else
      stable=0
      printf '  waiting (%ss): %d missing, %d stale\n' "$elapsed" \
        "$(grep -c . <<<"$missing")" "$(grep -c . <<<"$stale")"
    fi
    last="$sum"
    if (( elapsed >= LP_WAIT_TIMEOUT )); then
      [[ -z "$missing" ]] || printf 'missing node (group node value server world): %s\n' $'\n'"$missing" >&2
      [[ -z "$stale" ]] || printf 'stale node still present: %s\n' $'\n'"$stale" >&2
      die "LuckPerms did not settle in MariaDB within ${LP_WAIT_TIMEOUT}s"
    fi
    sleep "$LP_POLL_INTERVAL"
    elapsed=$((elapsed + LP_POLL_INTERVAL))
  done
}

[[ -f "$GROUPS_FILE" ]] || die "missing $GROUPS_FILE"
EXPECTED="$(expected_nodes)" || die "cannot model $GROUPS_FILE (see above)"
[[ -n "$EXPECTED" ]] || die "no group nodes in $GROUPS_FILE"

log "Waiting for $MC_CONTAINER RCON"
wait_ready "$MC_CONTAINER"

log "Applying $(grep -cvE '^\s*(#|$)' "$GROUPS_FILE") LuckPerms commands via $MC_CONTAINER"
grep -vE '^\s*(#|$)' "$GROUPS_FILE" | docker exec -i "$MC_CONTAINER" rcon-cli >/dev/null

log "Waiting for LuckPerms to write every groups.lp node to MariaDB"
wait_lp_settled 0
stale="$(stale_nodes "$(current_nodes)")"
if [[ -n "$stale" ]]; then
  log "Unsetting $(grep -c . <<<"$stale") node(s) not in groups.lp"
  while IFS=$'\t' read -r g node _ server world; do
    ctx=""
    [[ "$server" == global ]] || ctx+=" server=$server"
    [[ "$world" == global ]] || ctx+=" world=$world"
    printf 'lp group %s permission unset %s%s\n' "$g" "$node" "$ctx"
  done <<<"$stale" | tee /dev/stderr | docker exec -i "$MC_CONTAINER" rcon-cli >/dev/null
  rcon "$MC_CONTAINER" lp sync >/dev/null
  wait_lp_settled 1
else
  echo "No stale nodes"
fi

if (( DO_WORLD )); then
  # Multiverse list output varies by version; accept several forms.
  if rcon "$MC_CONTAINER" mv list | grep -qiE '(^|[^-])creative([^-]|$)'; then
    echo "World 'creative' already exists"
  else
    log "Creating Multiverse world 'creative' (normal terrain; takes a while)"
    rcon_ok "$MC_CONTAINER" mv create creative normal --seed 4354585255707245098
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
  # /survival + /creative use `mv tp ll:<world>`: the optional share last_location
  # must be active in the live config (synced from config/minecraft/plugins/).
  mvinv_cfg="$MC_DATA_DIR/plugins/Multiverse-Inventories/config.yml"
  awk '/^[^ #]/{p=($0 ~ /^share-handling:/)} p' "$mvinv_cfg" \
    | grep -qE '^ +- +last_location$' \
    || die "last_location is not in share-handling.active-optional-shares of $mvinv_cfg"
  echo "Multiverse-Inventories: last_location share active (/survival, /creative)"

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

log "LuckPerms groups in MariaDB"
db -t <<'SQL'
SELECT g.name AS `group`, COUNT(p.id) AS nodes
  FROM luckperms_groups g LEFT JOIN luckperms_group_permissions p ON p.name = g.name
 GROUP BY g.name ORDER BY g.name;
SELECT name AS `group`, permission, value, server, world
  FROM luckperms_group_permissions
 WHERE permission LIKE 'group.%' OR permission LIKE 'weight.%' OR permission = '*'
    OR permission LIKE 'fawe.%' OR permission LIKE 'voxelsniper.%'
    OR permission LIKE 'worldedit.%'
 ORDER BY name, permission, world;
SQL

log "Verifying: only the allowed false nodes; builder FAWE/Voxel only in world=creative; default has no edit tools"
# Re-confirm everything is still present right before the checks (world steps
# above can take minutes; this is quick when nothing changed).
wait_lp_settled 1
false_nodes="$(db -N -B <<'SQL'
SELECT name, permission, server, world FROM luckperms_group_permissions
 WHERE value = 0 ORDER BY name, permission;
SQL
)"
check_false_nodes <<<"$false_nodes"

bad_fawe="$(db -N -B <<'SQL'
SELECT COUNT(*) FROM luckperms_group_permissions
 WHERE name = 'builder' AND permission LIKE 'fawe.%' AND world <> 'creative';
SQL
)"
[[ "$bad_fawe" == "0" ]] || die "builder has $bad_fawe FAWE nodes outside world=creative"

bad_voxel="$(db -N -B <<'SQL'
SELECT COUNT(*) FROM luckperms_group_permissions
 WHERE name = 'builder' AND permission LIKE 'voxelsniper.%' AND world <> 'creative';
SQL
)"
[[ "$bad_voxel" == "0" ]] || die "builder has $bad_voxel voxelsniper nodes outside world=creative"

default_edit="$(db -N -B <<'SQL'
SELECT COUNT(*) FROM luckperms_group_permissions
 WHERE name = 'default' AND (
   permission LIKE 'fawe.%' OR permission LIKE 'worldedit.%'
   OR permission LIKE 'voxelsniper.%');
SQL
)"
[[ "$default_edit" == "0" ]] || die "default has $default_edit FAWE/WorldEdit/VoxelSniper nodes (must be zero)"

builder_voxel_pct="$(db -N -B <<'SQL'
SELECT COUNT(*) FROM luckperms_group_permissions
 WHERE name = 'builder' AND permission = 'voxelsniper.%' AND world = 'creative';
SQL
)"
[[ "$builder_voxel_pct" == "1" ]] || die "builder missing voxelsniper.% in world=creative"

# /survival and /creative (mv tp ll:<world>) must stay usable by everyone.
default_ll="$(db -N -B <<'SQL'
SELECT COUNT(*) FROM luckperms_group_permissions
 WHERE name = 'default' AND value = 1 AND world = 'global'
   AND permission IN ('multiverse.teleport.self.ll.survival', 'multiverse.teleport.self.ll.creative');
SQL
)"
[[ "$default_ll" == "2" ]] || die "default is missing multiverse.teleport.self.ll.{survival,creative} (/survival, /creative)"

echo "OK: only admin gamemode-bypass false nodes; builder FAWE/Voxel creative-only; default has no edit tools; default can /survival /creative"
log "Done. In game / console:  lp listgroups   lp group builder permission info"
echo "Promote a player:  docker exec $MC_CONTAINER rcon-cli \"lp user <name> parent add builder\""
echo "Note: admin mv.bypass.gamemode.* is set false, so admins are forced into each world's gamemode;"
echo "Multiverse-Inventories bypass is OFF so inventories still swap between survival and creative."
