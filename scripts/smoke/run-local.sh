#!/usr/bin/env bash
# Isolated local smoke test for the one-server stack (minecraft + geyser + mariadb).
#
# Safety: this can never touch production.
#   - compose project `trapaholics-smoke` + scripts/smoke/docker-compose.smoke.yml
#     (no fixed container names; data only under the gitignored .smoke-data/)
#   - refuses to run if ./minecraft, ./geyser or ./mariadb exist, if compose
#     project `trapaholics` has containers, or if containers named minecraft /
#     geyser / mariadb / playit exist
#   - throwaway .env under .smoke-data/ (never reads the real .env); playit is
#     never started
#
# Checks: compose config; all plugins enabled; luckperms + coreprotect DBs exist
# and CoreProtect uses MySQL; Geyser NetherNet signaling (built-in here; playit
# NXS in production) listens on TCP 19132 and media on UDP 19133; Geyser reaches
# Paper over PROXY with no rejections;
# scripts/luckperms/setup.sh passes its own checks. Then tears down and deletes
# .smoke-data/.
#
# Usage: scripts/smoke/run-local.sh            (KEEP=1 to leave the stack up)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

PROJECT=trapaholics-smoke
SMOKE_DATA="$ROOT/.smoke-data"
SMOKE_ENV="$SMOKE_DATA/.env"
COMPOSE=(docker compose -p "$PROJECT" --env-file "$SMOKE_ENV"
         -f docker-compose.yml -f scripts/smoke/docker-compose.smoke.yml)

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'SMOKE FAIL: %s\n' "$*" >&2; exit 1; }

# ---- refuse anything that could be production -------------------------------
for p in minecraft geyser mariadb; do
  [[ ! -e "$ROOT/$p" ]] || die "./$p exists: refusing to smoke next to production data"
done
command -v docker >/dev/null || die "docker not found"
if [[ -n "$(docker ps -aq --filter label=com.docker.compose.project=trapaholics)" ]]; then
  die "compose project 'trapaholics' has containers: refusing to run beside the real stack"
fi
for p in minecraft geyser mariadb playit; do
  if docker ps -a --format '{{.Names}}' | grep -qx "$p"; then
    die "a container named '$p' exists: refusing to run beside the real stack"
  fi
done
[[ ! -e "$SMOKE_DATA" ]] || die ".smoke-data/ already exists (stale run?). Remove it first."

case "$(uname -m)" in
  arm64|aarch64) SMOKE_PLATFORM=linux/arm64 ;;
  x86_64|amd64)  SMOKE_PLATFORM=linux/amd64 ;;
  *) die "unsupported host arch $(uname -m)" ;;
esac

cleanup() {
  local rc=$?
  if [[ "${KEEP:-0}" == 1 ]]; then
    echo "KEEP=1: leaving $PROJECT up and .smoke-data/ in place"
    return
  fi
  log "Tearing down $PROJECT"
  "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
  # Data may be owned by container uids on Linux: delete it from a container.
  if [[ -d "$SMOKE_DATA" ]] && ! rm -rf "$SMOKE_DATA" 2>/dev/null; then
    docker run --rm -v "$SMOKE_DATA:/d" alpine:3.20 sh -c 'rm -rf /d/* /d/.[!.]*' || true
    rm -rf "$SMOKE_DATA" || true
  fi
  exit "$rc"
}
trap cleanup EXIT

# ---- prepare ----------------------------------------------------------------
log "Building plugins (pinned, sha256-verified)"
bash scripts/build-plugins.sh

mkdir -p "$SMOKE_DATA/minecraft" "$SMOKE_DATA/geyser" "$SMOKE_DATA/mariadb"
cat >"$SMOKE_ENV" <<EOF
COMPOSE_PROJECT_NAME=$PROJECT
SMOKE_PLATFORM=$SMOKE_PLATFORM
RCON_PASSWORD=smokercon0000
LUCKPERMS_DB_PASSWORD=smokelp0000
COREPROTECT_DB_PASSWORD=smokecp0000
MARIADB_ROOT_PASSWORD=smokeroot0000
PLAYIT_SECRET_KEY=not-a-real-key
EOF

# Geyser config from the template. Production uses playit NXS signaling (needs
# a real playit token), so locally switch to built-in signaling advertised on
# loopback (host:port form) to get signaling up without playit.
sed -e 's/^    mode: nxs$/    mode: builtin/' \
    -e 's/^    advertise-addresses: \[\]$/    advertise-addresses: ["127.0.0.1:19133"]/' \
  config/geyser/config.yml >"$SMOKE_DATA/geyser/config.yml"
if ! grep -q '^    mode: builtin$' "$SMOKE_DATA/geyser/config.yml" \
   || ! grep -q '"127.0.0.1:19133"' "$SMOKE_DATA/geyser/config.yml"; then
  die "signaling mode / advertise-addresses not found in config/geyser/config.yml"
fi

log "compose config -q"
"${COMPOSE[@]}" config -q

log "Starting mariadb + minecraft (no playit)"
"${COMPOSE[@]}" up -d mariadb minecraft
MC="$("${COMPOSE[@]}" ps -q minecraft)"
DB="$("${COMPOSE[@]}" ps -q mariadb)"
[[ -n "$MC" && -n "$DB" ]] || die "containers did not start"

log "Waiting for Paper (healthcheck uses PROXY)"
for _ in $(seq 1 120); do
  [[ "$(docker inspect -f '{{.State.Health.Status}}' "$MC")" == healthy ]] && break
  sleep 5
done
[[ "$(docker inspect -f '{{.State.Health.Status}}' "$MC")" == healthy ]] \
  || { docker logs --tail 80 "$MC" >&2; die "Paper never became healthy"; }

log "Re-run the MariaDB init script by hand (must be idempotent)"
docker exec "$DB" /docker-entrypoint-initdb.d/01-databases.sh
# shellcheck disable=SC2016
dbs="$(docker exec "$DB" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N -e "SHOW DATABASES;"')"
grep -qx luckperms <<<"$dbs" || die "database luckperms missing"
grep -qx coreprotect <<<"$dbs" || die "database coreprotect missing"
echo "databases: luckperms coreprotect OK"

log "Plugins"
plugins="$(docker exec "$MC" rcon-cli plugins | sed 's/\x1b\[[0-9;]*m//g')"
echo "$plugins"
for p in CoreProtect Essentials EssentialsSpawn FastAsyncVoxelSniper FastAsyncWorldEdit \
         floodgate GriefPrevention LuckPerms Multiverse-Core Multiverse-Inventories \
         Multiverse-NetherPortals WorldGuard Chunky; do
  grep -qiE "(^|[ ,:])$p(,|$| )" <<<"$plugins" || die "plugin $p not enabled"
done
if docker logs "$MC" 2>&1 | grep -E 'Error occurred while enabling|Could not load|disabling plugin'; then
  die "a plugin failed to load/enable"
fi
for p in ViaVersion PlotSquared Velocity; do
  ! grep -qi "$p" <<<"$plugins" || die "unexpected plugin $p"
done

log "CoreProtect uses MySQL"
# shellcheck disable=SC2016
cp_tables="$(docker exec "$DB" sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N coreprotect -e "SHOW TABLES;"' | wc -l)"
(( cp_tables > 5 )) || die "CoreProtect created no tables in MariaDB (still SQLite?)"
echo "coreprotect tables in MariaDB: $cp_tables"

log "Floodgate key -> geyser"
for _ in $(seq 1 30); do
  docker exec "$MC" test -f /data/plugins/floodgate/key.pem && break
  sleep 2
done
cp "$SMOKE_DATA/minecraft/plugins/floodgate/key.pem" "$SMOKE_DATA/geyser/key.pem"

log "Starting geyser"
"${COMPOSE[@]}" up -d geyser
GY="$("${COMPOSE[@]}" ps -q geyser)"
# Only judge the current container start (restart: unless-stopped may have
# recovered from a transient Mojang API timeout during an earlier start).
geyser_log() { docker logs --since "$(docker inspect -f '{{.State.StartedAt}}' "$GY")" "$GY" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'; }
for _ in $(seq 1 60); do
  geyser_log | grep -q 'Done (' && break
  sleep 2
done
sleep 10   # let a few MOTD passthrough pings run
glog="$(geyser_log)"
echo "$glog" | tail -40
grep -q 'Done (' <<<"$glog" || die "Geyser did not finish starting"
grep -q 'Built-in signaling started on http://0.0.0.0:19132, with NetherNet on UDP port 19133' <<<"$glog" \
  || die "NetherNet built-in signaling (TCP 19132) / media (UDP 19133) did not start"
! grep -qiE 'Unrecognized VM option|Exception|signaling (is )?(disabled|not start)' <<<"$glog" \
  || die "Geyser logged an error"

log "Listening sockets inside geyser (hex 4ABC = 19132)"
# NetherNet media (UDP 19133) is opened per WebRTC session, so nothing is bound
# there while idle; the Geyser startup line checked above confirms the port.
# shellcheck disable=SC2016
socks="$(docker exec "$GY" sh -c 'cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk "\$4==\"0A\"{print \$2}"')"
grep -qiE ':4ABC$' <<<"$socks" || die "nothing listening on TCP 19132 (signaling)"
echo "TCP 19132 (signaling) listening; media configured on UDP 19133"

log "Signaling reachable from minecraft's netns (where playit runs) at 172.28.10.10:19132"
docker exec "$MC" bash -c 'exec 3<>/dev/tcp/172.28.10.10/19132' \
  || die "172.28.10.10:19132 not reachable from minecraft's network namespace"

log "Geyser -> Paper over PROXY"
grep -q 'configured to use proxy protocol when connecting to the Java server' <<<"$glog" \
  || die "Geyser is not using PROXY protocol toward Paper"
# Negative control: a plain (non-PROXY) status ping must get no answer.
plain="$(docker exec "$GY" sh -c 'printf "\020\000\377\005\011minecraft\143\335\001\001\000" | nc -w 3 minecraft 25565 | wc -c')"
[[ "$plain" -eq 0 ]] || die "Paper answered a ping WITHOUT a PROXY header ($plain bytes)"
# Positive: capture Paper's answer to Geyser's own MOTD-passthrough ping (sent
# every 3 s with a PROXY v2 header) inside geyser's network namespace.
reply="$(docker run --rm --net "container:$GY" nicolaka/netshoot:v0.13 \
  tcpdump -nn -A -c 2 -s 0 'tcp src port 25565 and (tcp[tcpflags] & tcp-push != 0)' 2>/dev/null)"
grep -q '"description":"trapaholics"' <<<"$reply" \
  || die "Paper did not answer Geyser's PROXY ping with a status response"
mlog="$(docker logs --since "$(docker inspect -f '{{.State.StartedAt}}' "$GY")" "$MC" 2>&1)"
if grep -iE 'DecoderException|invalid proxy|proxy.*(reject|fail|invalid)|lost connection' <<<"$mlog"; then
  die "Paper logged PROXY/connection errors"
fi
echo "Geyser PROXY v2 ping answered by Paper; plain ping refused; no rejections logged"

log "scripts/luckperms/setup.sh (full run, smoke containers)"
MC_CONTAINER="$MC" DB_CONTAINER="$DB" MC_DATA_DIR="$SMOKE_DATA/minecraft" \
  bash scripts/luckperms/setup.sh

log "smoke OK"
