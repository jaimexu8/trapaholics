# Deploying the Phase 1 one-server stack

Step-by-step go-live on the Debian host (`ssh moth`, user `jt`, repo at
`/home/jt/mc`). Design background: [ARCHITECTURE.md](ARCHITECTURE.md). Backups
are a separate system (PR #1): scripts in `scripts/backup/`, systemd units in
`systemd/`, full guide in [docs/BACKUPS.md](docs/BACKUPS.md). Step 12 below sets
them up.

What runs (all from `docker-compose.yml`, every version pinned):

| Container | What | Data dir |
|---|---|---|
| `minecraft` | Paper 26.3 build 258, 10 GB heap, all worlds | `./minecraft` |
| `geyser` | Geyser Standalone 2.12.1-b1307 on the `mc` network (fixed IP `172.28.10.10`) | `./geyser` |
| `mariadb` | MariaDB 12.3.3 (LTS), databases `luckperms` + `coreprotect` | `./mariadb` |
| `playit` | playit agent 1.2.0, shares **minecraft's** network namespace only | — |

No host ports are published. The only way in is the playit tunnel.

Worlds on the single Paper server: `survival` (+ `survival_nether`,
`survival_the_end`) and `creative`. Chat, tab list and `/tpa` are shared
natively. There is no Velocity.

**Networking (important):**

- `geyser` is on the normal Compose `mc` network with the fixed IP
  `172.28.10.10` and connects to Paper at `minecraft:25565` (with PROXY). A
  `minecraft` restart does **not** affect Geyser's networking.
- Only `playit` uses `network_mode: service:minecraft`. Inside that namespace
  the Java tunnel targets `127.0.0.1:25565`, and the Bedrock NetherNet tunnels
  target geyser at **`172.28.10.10`** (TCP `19132` signaling, UDP `19133`
  media). minecraft (`172.28.10.2`) is on the `mc` network, so that IP is
  reachable from playit. Use the IP, not the name `geyser`.
- **Ops rule: whenever `minecraft` restarts, restart `playit` too.** playit
  lives in minecraft's network namespace. When minecraft restarts (a manual
  restart, a recreate, or a crash restart by Docker), playit keeps the dead
  namespace and every tunnel goes silent. `depends_on.restart: true` only covers
  restarts done through `docker compose`. Always run
  `docker compose restart minecraft playit`, or `docker compose restart playit`
  after a crash.

---

## 0. Prerequisites

- Docker Engine + the Compose plugin (`docker compose version`), and `jt` in the
  `docker` group.
- ~3 GB free for images, the plugin build cache (`.build/`) and fresh worlds.
- Internet access from the host (Paper, plugins and Maven dependencies are
  downloaded on first start/build).

## 1. Stop the old stack *before* pulling

The previous layout had `velocity` / `survival` / `creative` (or the even older
`mc` + `playit` prepucio compose). Stop it while that file is still on disk, so
two playit agents never run with the same key:

```bash
cd ~/mc
docker compose down          # with the OLD compose file
docker ps -a                 # nothing from the old stack should remain
```

If you already pulled, remove leftovers by name (`docker rm -f velocity survival
creative …`).

## 2. Pull the new layout

```bash
cd ~/mc
git fetch origin && git checkout main && git pull
```

## 3. Secrets (`.env`)

`.env` already holds `PLAYIT_SECRET_KEY` and `DISCORD_WEBHOOK_URL`. Add the new
variables listed in `.env.example`, using random hex values. Drop any stale
`VELOCITY_*` / `RCON_PASSWORD_SURVIVAL` / `RCON_PASSWORD_CREATIVE` lines:

```bash
cd ~/mc
for v in MARIADB_ROOT_PASSWORD LUCKPERMS_DB_PASSWORD COREPROTECT_DB_PASSWORD \
         RCON_PASSWORD; do
  grep -q "^$v=." .env || echo "$v=$(openssl rand -hex 24)" >> .env
done
chmod 600 .env
diff <(grep -oE '^[A-Z_]+=' .env.example | sort) <(grep -oE '^[A-Z_]+=' .env | sort) \
  && echo "all variables present"
```

Keep hex (or other `[A-Za-z0-9]`) values. Store a copy of `.env` in your password
manager.

> If you change `LUCKPERMS_DB_PASSWORD`, `COREPROTECT_DB_PASSWORD` or
> `MARIADB_ROOT_PASSWORD` **after** `./mariadb` was initialised, MariaDB keeps
> the old ones: change them in SQL too (`ALTER USER`), or re-run
> `01-databases.sh` (step 7).

## 4. Create the data dirs (owned by you)

If Docker creates missing bind-mount dirs itself, they end up owned by root.
Create them yourself first. Geyser runs as uid/gid `1000:1000`, so `./geyser`
must be writable by that user:

```bash
cd ~/mc
mkdir -p minecraft geyser mariadb
# On the Debian host `jt` is usually uid 1000; if not, chown explicitly:
sudo chown -R 1000:1000 geyser
chmod -R u+rwX geyser
```

## 5. Build the source-built / CI plugins

```bash
cd ~/mc
scripts/build-plugins.sh
```

This builds a small builder image (Maven + JDK 25), then:

- builds **CoreProtect CE 25.0** (commit `a561c56`, targets 26.3) with
  `-Dproject.branch=development` (required for master CE builds) → `plugins-built/minecraft/`
- downloads **EssentialsX + EssentialsXSpawn 2.22.1-dev+28-f8724e2** (CI #1833) with sha256
- downloads **Floodgate Spigot 2.2.5-b141** with sha256 → `plugins-built/minecraft/`
- downloads **Geyser Standalone 2.12.1-b1307** with sha256 → `plugins-built/geyser/`

Pins are in `scripts/plugins/versions.env`. Re-run after changing a pin.
`--clean` wipes checkouts and caches.

All other plugins are downloaded by the `minecraft` container from Modrinth,
pinned by version ID in `docker-compose.yml`.

## 6. Seed the Geyser config (before first start)

```bash
cd ~/mc
cp -n config/geyser/config.yml geyser/config.yml
```

`bedrock.signaling.advertise-addresses` holds the placeholder
`replace-with-playit-nethernet-udp-address.invalid`. It never resolves, so
Geyser will not start NetherNet signaling until you replace it with the playit
UDP media address in step 9. That's expected for now.

Do **not** start `playit` yet. The Floodgate key does not exist until Paper has
started once (next steps).

## 7. Start everything except the tunnel

```bash
cd ~/mc
docker compose config -q && echo compose OK
docker compose up -d mariadb
docker compose ps mariadb          # repeat until (healthy)
```

### MariaDB databases (required when `./mariadb` already existed)

MariaDB runs `/docker-entrypoint-initdb.d` **only** on an empty datadir. If
`./mariadb` already held data before this deploy (a reused volume, or a restore),
the `luckperms` / `coreprotect` databases and users were never created. Run the
idempotent init script by hand. It's safe to run on a fresh datadir too, and it
also re-applies the passwords from `.env`:

```bash
docker exec mariadb /docker-entrypoint-initdb.d/01-databases.sh
docker exec mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N -e "SHOW DATABASES;"' \
  | grep -xE 'luckperms|coreprotect'
# Expect both names. Re-run any time after rotating a DB password in .env.
```

Then start Paper + Geyser:

```bash
docker compose up -d minecraft
docker compose logs -f minecraft        # until "Done (…)! For help, type "help""
docker compose ps minecraft             # (healthy)
```

Start `geyser` after the Floodgate key is in place (below).

### Floodgate key (share with Geyser, never commit)

Floodgate on Paper generates `minecraft/plugins/floodgate/key.pem` on first
start. Geyser Standalone needs the **same** file next to its config:

```bash
# After minecraft has created the key:
cp minecraft/plugins/floodgate/key.pem geyser/key.pem
chmod 600 minecraft/plugins/floodgate/key.pem geyser/key.pem
# Ensure geyser (uid 1000) can still read it:
sudo chown 1000:1000 geyser/key.pem geyser/config.yml
docker compose up -d geyser
docker compose logs geyser | grep -iE 'Done|error|exception'
```

Geyser should log `Done`. NetherNet signaling stays off until step 9 replaces
the advertise-address placeholder.

### CoreProtect → MySQL (required check)

```bash
docker exec mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -N coreprotect -e "SHOW TABLES;"' | head
# Expect co_block, co_user, … . An empty result means CoreProtect fell back to SQLite.
ls minecraft/plugins/CoreProtect/database.db 2>/dev/null && echo "WARNING: SQLite file present"
```

If the tables are missing, re-run `01-databases.sh` (above). It re-applies the
`coreprotect` password from `.env`, which `CFG_COREPROTECT_DB_PASSWORD` also
feeds into CoreProtect's config. Then run `docker compose restart minecraft playit`
and check again.

### Plugins

```bash
docker logs minecraft 2>&1 | grep -E 'ERROR|Error occurred|Could not load'
docker exec minecraft rcon-cli plugins
```

Expected (names may vary slightly): CoreProtect, Essentials, EssentialsSpawn,
FastAsyncVoxelSniper, FastAsyncWorldEdit, Floodgate, GriefPrevention, LuckPerms,
Multiverse-Core, Multiverse-Inventories, Multiverse-NetherPortals, WorldGuard,
Chunky. **No** ViaVersion, PlotSquared, regular WorldEdit, or Velocity plugins.

Harmless log lines you may see:

- Essentials' "LuckPerms without Vault".
- An `Unable to write eula` line on the very first start of a fresh data dir.

## 8. LuckPerms + creative world + WorldGuard spawns

```bash
cd ~/mc
scripts/luckperms/setup.sh
# Restart once: FAWE writes config.yml, then the limits patch applies, and the
# creative paper-world.yml + spigot.yml hopper settings load. (playit is not up yet;
# later, always restart it together with minecraft.)
docker compose restart minecraft
# After restart, wait for RCON, then re-apply groups if you like:
scripts/luckperms/setup.sh --no-world
```

`setup.sh` does:

- Applies `scripts/luckperms/groups.lp` (`default`, `builder`, `admin`) over RCON.
- Creates Multiverse world `creative` (normal terrain), forces creative + peaceful,
  `portal-form none`, unlinks nether/end portals via Multiverse-NetherPortals, and
  **reads back** gamemode / difficulty / portal-form from Multiverse's `worlds.yml`.
- Appends the creative Paper per-world limits (`config/paper/creative-paper-world.yml`)
  to the `paper-world.yml` Paper wrote for the world. On 26.3 every dimension lives
  under the level folder, so that's
  `minecraft/survival/dimensions/minecraft/creative/paper-world.yml`. Paper's own
  `_version` line is kept. Creative hopper rate/amount and spawner nerfing are
  Spigot settings, applied by the itzg patch
  `config/patches/minecraft/spigot-creative.json` (`spigot.yml`
  `world-settings.creative`) on every start.
- Seeds the WorldGuard **spawn** region for both `survival` and `creative` from
  `config/worldguard/spawn-regions.yml`, runs `wg reload`, then has WorldGuard
  re-save the regions and checks that the spawn region and its flags came back.
- Verifies: **no** LuckPerms `false` nodes; builder FAWE/VoxelSniper only in
  `world=creative`; default has no FAWE/WorldEdit/VoxelSniper nodes.

Check:

```bash
docker exec minecraft rcon-cli "lp listgroups"
docker exec minecraft rcon-cli "lp group builder permission info"
grep -A3 '^  builder:' minecraft/plugins/FastAsyncWorldEdit/config.yml
docker exec minecraft rcon-cli "mvinv list"
grep -A3 'spawn:' minecraft/plugins/WorldGuard/worlds/{survival,creative}/regions.yml
```

(WorldGuard's `rg` commands reply asynchronously, so `rg info` over RCON prints
nothing. Use them in-game, or read `regions.yml`.)

### What the groups can do

| Group | Survival worlds | Creative world | Everywhere |
|---|---|---|---|
| `default` | GriefPrevention claims; no FAWE | Build by hand only; no FAWE / VoxelSniper | Chat, `/tpa` `/tpahere` `/tpaccept`, `/home` `/sethome` (Essentials `sethome-multiple.default`), `/spawn`, `/survival`, `/creative` |
| `builder` (inherits default) | same as default (**no FAWE**) | `fawe.limit.builder` + `fawe.permpack.basic` + `fawe.bypass.regions` + FastAsyncVoxelSniper (`voxelsniper.%`); `/speed` | |
| `admin` | `*` | `*` | `*` |

Multiverse 5 nodes for world switch (finer teleport on by default):
`multiverse.access.<world>` and `multiverse.teleport.self.w.<world>`.

**Admin gamemode vs inventories:** admin `*` includes Multiverse-Core
`mv.bypass.gamemode.*`, so admins keep their gamemode when changing worlds.
Multiverse-Inventories `share-handling.enable-bypass-permissions` is **false**,
so admin `*` does **not** skip the survival ↔ creative inventory swap.

FAWE limits (tune in `config/patches/minecraft/fawe-limits.json`, then restart
`minecraft`):

| | `default` (unused for FAWE) | `builder` |
|---|---|---|
| max-changes | 50 000 | 2 000 000 |
| max-radius / brush | 16 / 8 | 128 / 32 |
| history | 16 MB | 256 MB |
| concurrent actions | 1 | 2 |

### Staff

Join once through playit (so LuckPerms knows your UUID), then:

```bash
docker exec minecraft rcon-cli "lp user <name> parent add admin"
docker exec minecraft rcon-cli "lp user <name> parent add builder"
```

Avoid OPs. Keep `ops.json` for the owner only, as a break-glass fallback.

> ⚠️ **Don't give one user both `admin` and `builder`**, and never add explicit
> `false` nodes to `default` or `builder`. In LuckPerms an exact `false` beats
> admin's `*`. `groups.lp` contains **no** `false` nodes.

> **Note:** `essentials.tp` is intentionally **not** granted to `builder`. That
> node allows `/tp` to any player without asking. Use `/tpa` / `/tpahere`.

## 9. playit tunnels (PROXY + Bedrock NetherNet), then start the agent

Paper has `proxies.proxy-protocol: true`. From now on it **rejects every
connection that doesn't start with a PROXY header**, so set playit up **before**
starting the agent.

**Never** create a playit tunnel to RCON (`25575`). RCON stays internal
(`docker exec minecraft rcon-cli` only).

### Pre-flight: Paper must already require PROXY (required)

The itzg patch in `config/patches/minecraft/paper-global.json` only applies once
Paper has written `config/paper-global.yml`, so after the first boot. Do **not**
start playit until this prints `true`:

```bash
awk '/^proxies:/{p=1} p&&/proxy-protocol:/{print $2; exit}' minecraft/config/paper-global.yml
```

If it prints `false` or nothing, restart `minecraft` once and check again.
Otherwise, if playit sends PROXY headers into a Paper that doesn't expect them,
every join fails.

### Java tunnel (required)

`playit` uses `network_mode: "service:minecraft"`, so the Java local target is
loopback inside that namespace.

1. https://playit.gg/account/tunnels/ → your **Minecraft Java** tunnel (or create one).
2. Local address: `127.0.0.1`, port `25565`.
3. **Proxy Protocol → Version 2**, then save. Do this **before** `docker compose up -d playit`.

Compose sets `USES_PROXY_PROTOCOL=true` on `minecraft` so the itzg healthcheck
sends a PROXY header (`mc-health --use-proxy`). Without that, Paper rejects the
probe and the container stays unhealthy once `proxies.proxy-protocol` is on.

### Bedrock NetherNet tunnels (required)

Bedrock clients from **26.60** on no longer connect over RakNet, so NetherNet is
the only Bedrock route here (Geyser `bedrock.transport: nethernet`,
`config-version: 12`). RakNet is not offered. NetherNet needs **two** paths, and
playit must carry both:

| Path | Protocol | playit local address | Local port |
|---|---|---|---|
| Signaling (what the player types in) | **TCP** | `172.28.10.10` | `19132` |
| Media (WebRTC) | **UDP** | `172.28.10.10` | `19133` |

1. https://playit.gg/account/tunnels/ → create the **Bedrock NetherNet** tunnel
   type. If the dashboard creates it as one tunnel with both a TCP and a UDP
   part, set both local endpoints as in the table. If it doesn't, create one
   TCP tunnel (signaling) and one UDP tunnel (media). Leave Proxy Protocol
   **off** on these for now (see "Bedrock real IPs" below).
2. Write down the two **public** addresses playit assigns:
   - the TCP signaling address `host:port`, which you give to Bedrock players
   - the UDP media address `host:port`
3. Put the **UDP media** address into `geyser/config.yml`, including its port
   (without a port Geyser would advertise 19133, which is wrong behind playit):

   ```yaml
   bedrock:
     signaling:
       advertise-addresses:
         - "<udp-host>:<udp-port>"
   ```

4. `docker compose restart geyser`, then check:

   ```bash
   grep -q 'replace-with-playit' geyser/config.yml && echo "STILL PLACEHOLDER"
   docker compose logs geyser | grep 'Built-in signaling started on http://0.0.0.0:19132'
   ```

### Bedrock real IPs (optional, OFF by default)

Geyser's `advanced.bedrock.haproxy-protocol-whitelisted-ips` is **empty** in the
template. Listing any address turns HAProxy protocol on, and
`webrtc-proxy-protocol-relays` then makes a PROXY header **mandatory** on the
media port. With both lists empty, Bedrock players show up with the playit
agent's address (`172.28.10.2`, minecraft's IP on `mc`). Bedrock still works
fine that way.

Turn real Bedrock IPs on **only after confirming** that playit sends PROXY v2
on the NetherNet tunnel type, both the TCP and the UDP part:

1. Enable Proxy Protocol v2 on the Bedrock NetherNet tunnel(s) in playit.
2. In `geyser/config.yml`:

   ```yaml
   advanced:
     bedrock:
       haproxy-protocol-whitelisted-ips: [172.28.10.2]   # signaling (TCP)
       webrtc-proxy-protocol-relays: [172.28.10.2]       # media (UDP)
   ```

3. `docker compose restart geyser`, and run the Bedrock join test from step 11.
   If joins fail, empty both lists again, turn PROXY off on the tunnel and
   restart geyser.

### Start the agent

```bash
cd ~/mc
awk '/^proxies:/{p=1} p&&/proxy-protocol:/{print $2; exit}' minecraft/config/paper-global.yml  # must print true
docker compose up -d playit
docker compose logs -f playit      # tunnels connected
```

From now on: **`docker compose restart minecraft playit`**, never minecraft
alone (see "Networking" at the top).

## 10. Survival spawn, WorldGuard, Chunky pregen

`setup.sh` (step 8) creates and verifies a **spawn** region (±48 blocks around
0,0, no PvP/explosions/fire/mob spawning) in both `survival` and `creative`.
It's a **required** step: if `setup.sh` failed or was run with `--no-world`,
don't open the server until both `regions.yml` files contain `spawn:`. Once
you've built a real hub, adjust the region in-game with `/rg redefine spawn`.

Pre-generate survival before opening (Chunky; this CPU hates live generation):

```bash
docker exec minecraft rcon-cli "chunky world survival"
docker exec minecraft rcon-cli "chunky center 0 0"
docker exec minecraft rcon-cli "chunky radius 3000"
docker exec minecraft rcon-cli "chunky start"
docker exec minecraft rcon-cli "chunky progress"
# optional:
docker exec minecraft rcon-cli "chunky world survival_nether" && \
docker exec minecraft rcon-cli "chunky radius 1000" && docker exec minecraft rcon-cli "chunky start"
```

Watch disk space (`df -h /home`). Chunky pauses on shutdown and resumes with
`chunky continue`.

## 11. Pre-launch checks (inventory + Bedrock + real IP)

### Inventory separation

Do this with two accounts or by switching worlds carefully:

1. Join as a normal player. Take a unique item in **creative** (e.g. rename a
   diamond with an anvil).
2. Run `/survival`. Confirm the item is **gone** from inventory, armour, and
   ender chest. XP / effects should reset to the survival group's state.
3. Run `/creative` again — the creative item returns.
4. From creative, `/tpa` a friend in survival and accept — inventories must still
   not leak (Multiverse-Inventories swaps on world change).
5. Die in creative and respawn — still no leak into survival.
6. Relog in each world — inventories stay separated.
7. As `builder`: `//set stone` works in **creative**, is refused in **survival**.
8. As `default`: `//set` refused in both worlds.
9. Chat and tab list show players in both worlds; `/tpa` works across worlds.

### Bedrock join (current client) + real IP — required

10. **Bedrock, current client.** On a phone or console with the newest Bedrock
    release (26.60 or later), from **outside** your home network (mobile data),
    add a server with the playit **TCP signaling** address and port from step 9
    and join. Check:
    - Geyser logs the player: `docker compose logs geyser | tail -20`
      (a `... has connected to the Java server` line).
    - The player appears in `docker exec minecraft rcon-cli list` with
      Floodgate's `.` prefix and lands in `survival`.
    - Walk, place a block, chat, `/creative`, `/survival`.
    If the client hangs on "Locating server", the UDP media path or
    `advertise-addresses` is wrong (step 9).
11. **Real-IP check.** Join over Java from outside your network and look up your
    public IP (e.g. `curl -s https://ifconfig.me` on that device). Then run
    `grep 'logged in with entity id' minecraft/logs/latest.log | tail -3`. The
    line must show **your public IP**, not `127.0.0.1` or `172.28.10.x`. If it
    shows a local address, Proxy Protocol v2 is off on the Java tunnel. For
    Bedrock, the IP is the agent's `172.28.10.2` unless you turned on "Bedrock
    real IPs" in step 9. If you did, Bedrock must show your public IP too.

## 12. Backups

The backup system comes from PR #1: `scripts/backup/` (`backup.sh`, `offload.sh`,
`prune-drive.sh`, `backup.conf`), `systemd/` (three `.service` + `.timer` pairs)
and **[docs/BACKUPS.md](docs/BACKUPS.md)**. It expects containers `minecraft`,
`geyser`, `mariadb` and dumps databases **`luckperms`** and **`coreprotect`**.

1. Install tools: `sudo apt-get install -y rclone zstd curl`.
2. Create rclone remotes `gdrive` and `gdrive-crypt` as in docs/BACKUPS.md §2.
   Store the crypt password and salt in your password manager.
3. `.env` must contain `DISCORD_WEBHOOK_URL` and `MARIADB_ROOT_PASSWORD`.
4. Enable the three timers:

   ```bash
   cd ~/mc
   sudo cp systemd/trapaholics-*.service systemd/trapaholics-*.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now trapaholics-backup.timer
   sudo systemctl enable --now trapaholics-offload.timer
   sudo systemctl enable --now trapaholics-prune-drive.timer
   systemctl list-timers 'trapaholics-*'
   ```

5. Run one backup by hand:
   `sudo systemctl start trapaholics-backup.service && journalctl -u trapaholics-backup -n 50`.

## 13. After go-live

- The old **`data/`** dir (26.2 world from `prepucio/`) is unused. Once the new
  stack is live and backed up, archive it if you want, then `rm -rf ~/mc/data`.
- **Plots later:** when PlotSquared supports 26.3, add a plot world as another
  Multiverse world on this same server (see ARCHITECTURE §5.5 / git history for
  the earlier plan). No Velocity required.

---

## Operations cheat sheet

```bash
docker compose ps
docker compose logs -f <service>
docker exec minecraft rcon-cli <command>
docker compose restart minecraft playit   # always bounce playit with minecraft
docker compose up -d                        # apply compose/template changes
```

- **Config templates:** files under `config/minecraft/` are copied into the data
  dir on start when newer than the live file; `${CFG_*}` placeholders are filled.
  `config/patches/minecraft/` is re-applied on **every** start.
- **Geyser config** is not managed by itzg — edit `geyser/config.yml` (seeded from
  `config/geyser/config.yml`) and `docker compose restart geyser`. Geyser runs as
  `1000:1000`; keep `./geyser` owned accordingly.
- **Never tunnel RCON (25575).** It stays inside Docker (`docker exec minecraft rcon-cli`).
- **Smoke test** (on a dev machine, never next to live data):
  `scripts/smoke/run-local.sh`. It refuses to run if `./minecraft`, `./geyser`,
  `./mariadb` or the real stack exist.
- **Bumping versions:** change the pin (image tag, `PAPER_BUILD`, Modrinth version
  ID, or `scripts/plugins/versions.env`), back up, run `scripts/build-plugins.sh`
  if needed, then `docker compose up -d`. World upgrades are one-way.
