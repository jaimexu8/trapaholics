#!/usr/bin/env bash
# Local smoke test for the one-server stack. NEVER starts playit.
# Uses a throwaway .smoke-env and reduced heap. Deletes smoke data on exit
# when SMOKE_KEEP is unset.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ENV_FILE="$ROOT/.smoke-env"
OVERRIDE="$ROOT/.smoke-compose.override.yml"
KEEP="${SMOKE_KEEP:-0}"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  log "Tearing down smoke stack"
  docker compose --env-file "$ENV_FILE" -f docker-compose.yml -f "$OVERRIDE" down -v --remove-orphans >/dev/null 2>&1 || true
  if [[ "$KEEP" != "1" ]]; then
    rm -rf "$ROOT/minecraft" "$ROOT/geyser" "$ROOT/mariadb" "$ROOT/plugins-built" \
           "$ENV_FILE" "$OVERRIDE" "$ROOT/.smoke-data"
  fi
}
trap cleanup EXIT

log "Writing throwaway .smoke-env (never commit)"
cat >"$ENV_FILE" <<'EOF'
PLAYIT_SECRET_KEY=smokeplayitsecretkey00000000000001
MARIADB_ROOT_PASSWORD=smokerootpassword00000000000001
LUCKPERMS_DB_PASSWORD=smokeluckpermspass000000000001
COREPROTECT_DB_PASSWORD=smokecoreprotectpass000000001
RCON_PASSWORD=smokerconpassword00000000000001
DISCORD_WEBHOOK_URL=https://example.invalid/webhook/smoke
EOF
chmod 600 "$ENV_FILE"

cat >"$OVERRIDE" <<'EOF'
# Reduced heap for local smoke only — not used in production.
services:
  minecraft:
    environment:
      MEMORY: 2G
  playit:
    profiles: ["never"]
EOF

log "Building plugins"
scripts/build-plugins.sh

log "Preparing data dirs + geyser config"
mkdir -p minecraft geyser mariadb
cp -f config/geyser/config.yml geyser/config.yml

log "compose config -q"
docker compose --env-file "$ENV_FILE" -f docker-compose.yml -f "$OVERRIDE" config -q
echo "compose OK"

log "Starting mariadb + minecraft"
docker compose --env-file "$ENV_FILE" -f docker-compose.yml -f "$OVERRIDE" up -d mariadb minecraft

log "Waiting for Paper RCON"
for i in $(seq 1 120); do
  if docker exec minecraft rcon-cli list >/dev/null 2>&1; then
    echo "RCON ready after ~$((i*5))s"
    break
  fi
  sleep 5
  if [[ "$i" -eq 120 ]]; then die "Paper did not become ready"; fi
done

log "Floodgate key → geyser"
[[ -f minecraft/plugins/floodgate/key.pem ]] || die "Floodgate key.pem missing"
cp -f minecraft/plugins/floodgate/key.pem geyser/key.pem
chmod 600 geyser/key.pem

log "Starting geyser"
docker compose --env-file "$ENV_FILE" -f docker-compose.yml -f "$OVERRIDE" up -d geyser
sleep 15

log "Databases"
docker exec mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N -e "SHOW DATABASES;"' | tee /tmp/smoke-dbs.txt
grep -qx luckperms /tmp/smoke-dbs.txt || die "luckperms DB missing"
grep -qx coreprotect /tmp/smoke-dbs.txt || die "coreprotect DB missing"

log "Plugin load errors (if any)"
docker logs minecraft 2>&1 | grep -E 'ERROR|Error occurred|Could not load' | head -40 || true
docker exec minecraft rcon-cli plugins | tee /tmp/smoke-plugins.txt

log "LuckPerms + creative world"
scripts/luckperms/setup.sh

log "Restart minecraft once for FAWE limits patch, then re-apply LP"
docker compose --env-file "$ENV_FILE" -f docker-compose.yml -f "$OVERRIDE" restart minecraft
for i in $(seq 1 90); do
  docker exec minecraft rcon-cli list >/dev/null 2>&1 && break
  sleep 5
done
scripts/luckperms/setup.sh --no-world
# Geyser may need a kick after minecraft restart (shared netns survives, but Java target bounced)
docker compose --env-file "$ENV_FILE" -f docker-compose.yml -f "$OVERRIDE" restart geyser || true
sleep 10

log "Creative world + inventory groups"
docker exec minecraft rcon-cli "mv list" | tee /tmp/smoke-mv.txt
docker exec minecraft rcon-cli "mv info creative" | tee /tmp/smoke-mv-creative.txt || true
docker exec minecraft rcon-cli "mvinv list" 2>/dev/null | tee /tmp/smoke-mvinv.txt \
  || docker exec minecraft rcon-cli "mi list" 2>/dev/null | tee /tmp/smoke-mvinv.txt \
  || true

log "lp listgroups"
docker exec minecraft rcon-cli "lp listgroups" | tee /tmp/smoke-lp-groups.txt

log "Geyser logs (proxy / bind / errors)"
docker logs geyser 2>&1 | tee /tmp/smoke-geyser.log | tail -80
grep -qiE 'Done \(' /tmp/smoke-geyser.log || die "Geyser did not report Done"
grep -qiE 'refused|rejected|proxy protocol' /tmp/smoke-geyser.log \
  && grep -qiE 'ERROR|Exception' /tmp/smoke-geyser.log \
  && die "Geyser log shows proxy/connection errors" || true

log "Smoke checks finished OK (headless client permission tests skipped unless SMOKE_CLIENT=1)"
if [[ "${SMOKE_CLIENT:-0}" == "1" ]]; then
  echo "SMOKE_CLIENT=1 requested but mineflayer offline-mode harness is not wired in this script; see PR."
fi

# Leave artefacts in /tmp for the PR description; cleanup trap removes bind mounts.
cat <<EOF

SMOKE SUMMARY
- compose config: OK (2G heap override)
- DBs: $(tr '\n' ' ' </tmp/smoke-dbs.txt)
- plugins: see /tmp/smoke-plugins.txt
- mv list: see /tmp/smoke-mv.txt
- mvinv: see /tmp/smoke-mvinv.txt
- lp groups: see /tmp/smoke-lp-groups.txt
EOF
