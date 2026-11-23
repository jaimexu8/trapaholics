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
| `geyser` | Geyser Standalone 2.12.1-b1307 (same netns as `minecraft`) | `./geyser` |
| `mariadb` | MariaDB 12.3.3 (LTS), databases `luckperms` + `coreprotect` | `./mariadb` |
| `playit` | playit agent 1.2.0, shares minecraft's network | — |

No host ports are published. The only way in is the playit tunnel.

Worlds on the single Paper server: `survival` (+ `survival_nether`,
`survival_the_end`) and `creative`. Chat, tab list and `/tpa` are shared
natively. There is no Velocity.

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
> the old ones: change them in SQL too (`ALTER USER`).

## 4. Create the data dirs (owned by you)

If Docker creates missing bind-mount dirs itself, they end up owned by root.
Create them yourself first:

```bash
cd ~/mc
mkdir -p minecraft geyser mariadb
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

Do **not** start `playit` yet. The Floodgate key does not exist until Paper has
started once (next steps).

## 7. Start everything except the tunnel

```bash
cd ~/mc
docker compose config -q && echo compose OK
docker compose up -d mariadb minecraft
# Wait until Paper is up, then start Geyser (shares minecraft's network namespace).
docker compose up -d geyser
docker compose ps
docker compose logs -f minecraft        # until "Done (…)! For help, type "help""
```

### Floodgate key (share with Geyser, never commit)

Floodgate on Paper generates `minecraft/plugins/floodgate/key.pem` on first
start. Geyser Standalone needs the **same** file next to its config:

```bash
# After minecraft has created the key:
cp minecraft/plugins/floodgate/key.pem geyser/key.pem
chmod 600 minecraft/plugins/floodgate/key.pem geyser/key.pem
docker compose restart geyser
```

Confirm Geyser is happy:

```bash
docker compose logs geyser | grep -iE 'Done|floodgate|error|proxy|19132'
# From inside minecraft's netns, UDP 19132 should be listening:
docker exec minecraft sh -c 'cat /proc/net/udp /proc/net/udp6 2>/dev/null | head'
```

### Both databases

```bash
docker exec mariadb sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SHOW DATABASES;"'
# Expect: luckperms and coreprotect (plus system DBs).
```

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

## 8. LuckPerms + creative world

```bash
cd ~/mc
scripts/luckperms/setup.sh
docker compose restart minecraft   # once: FAWE writes config.yml, then the limits patch applies
# After restart, wait for RCON, then re-apply groups if you like:
scripts/luckperms/setup.sh --no-world
```

`setup.sh` does:

- Applies `scripts/luckperms/groups.lp` (`default`, `builder`, `admin`) over RCON.
- Creates Multiverse world `creative` (normal terrain), forces creative + peaceful,
  unlinks nether/end portals via Multiverse-NetherPortals, copies Paper per-world
  limits into `minecraft/creative/paper-world.yml`.
- Verifies: **no** LuckPerms `false` nodes; builder FAWE nodes only have
  `world=creative`.

Check:

```bash
docker exec minecraft rcon-cli "lp listgroups"
docker exec minecraft rcon-cli "lp group builder permission info"
grep -A3 '^  builder:' minecraft/plugins/FastAsyncWorldEdit/config.yml
docker exec minecraft rcon-cli "mvinv list"     # or: mi list / mvinv info
```

### What the groups can do

| Group | Survival worlds | Creative world | Everywhere |
|---|---|---|---|
| `default` | GriefPrevention claims; no FAWE | Build by hand only; no FAWE / VoxelSniper | Chat, `/tpa` `/tpahere` `/tpaccept`, `/home` `/sethome` (Essentials `sethome-multiple.default`), `/spawn`, `/survival`, `/creative` |
| `builder` (inherits default) | same as default (**no FAWE**) | `fawe.limit.builder` + `fawe.permpack.basic` + `fawe.bypass.regions` + FastAsyncVoxelSniper; `/speed`, `/tp` | |
| `admin` | `*` | `*` | `*` |

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

## 9. Enable PROXY protocol in playit, then start the tunnel

Paper has `proxies.proxy-protocol: true`. From now on it **rejects every
connection that doesn't start with a PROXY header**, so set playit up **before**
starting the agent.

`playit` and `geyser` both use `network_mode: "service:minecraft"`, so local
targets are loopback inside that namespace.

### Java tunnel (required)

1. https://playit.gg/account/tunnels/ → your **Minecraft Java** tunnel (or create one).
2. Local address: `127.0.0.1`, port `25565`.
3. **Proxy Protocol → Version 2**, then save. Do this **before** `docker compose up -d playit`.

### Bedrock UDP tunnel (free plan)

playit's free plan includes **4 ports** and supports a **Minecraft Bedrock**
(UDP / classic) tunnel as well as the newer NetherNet type. This stack uses
Geyser `transport: both` so classic **UDP 19132** (RakNet) works. NetherNet
uses a separate UDP port `19133` inside the container and is not required for
the free-plan UDP tunnel.

1. Create a tunnel of type **Minecraft Bedrock** (UDP), not only NetherNet.
2. Local address: `127.0.0.1`, port `19132` (Geyser RakNet in the same netns as playit).
3. Optionally set **Proxy Protocol → Version 2** so Bedrock real IPs are
   forwarded; Geyser already whitelists `127.0.0.0/8` for HAProxy headers from
   the local agent (`config/geyser/config.yml`).
4. (Optional) A second UDP tunnel to `127.0.0.1:19133` is only needed if you
   want NetherNet as well.

Then start the agent:

```bash
cd ~/mc
docker compose up -d playit
docker compose logs -f playit      # tunnel connected
```

Join through the playit Java address. You should land in **survival**.
`/creative` and `/survival` switch worlds. Your real IP should appear in the
Paper log, not `127.0.0.1`.

## 10. Survival spawn, WorldGuard, Chunky pregen

Protect spawn with WorldGuard in game (as admin): select it with a wooden axe /
FAWE wand and run `/rg define spawn`. Add flags as you like (e.g.
`/rg flag spawn pvp deny`). Repeat a spawn region in `creative` if you want a
protected hub there.

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

## 11. Inventory-separation test checklist (before launch)

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
docker compose restart minecraft
docker compose up -d                        # apply compose/template changes
```

- **Config templates:** files under `config/minecraft/` are copied into the data
  dir on start when newer than the live file; `${CFG_*}` placeholders are filled.
  `config/patches/minecraft/` is re-applied on **every** start.
- **Geyser config** is not managed by itzg — edit `geyser/config.yml` (seeded from
  `config/geyser/config.yml`) and `docker compose restart geyser`.
- **Bumping versions:** change the pin (image tag, `PAPER_BUILD`, Modrinth version
  ID, or `scripts/plugins/versions.env`), back up, run `scripts/build-plugins.sh`
  if needed, then `docker compose up -d`. World upgrades are one-way.
