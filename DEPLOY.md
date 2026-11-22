# Deploying the Phase 1 network

Step-by-step go-live on the Debian host (`ssh moth`, user `jt`, repo at
`/home/jt/mc`). Design background: [ARCHITECTURE.md](ARCHITECTURE.md). Backups
are a separate system (PR #1): scripts in `scripts/backup/`, systemd units in
`systemd/`, full guide in [docs/BACKUPS.md](docs/BACKUPS.md). Step 11 below sets them up.

What runs (all from `docker-compose.yml`, every version pinned):

| Container | What | Data dir |
|---|---|---|
| `velocity` | Velocity 4.3.1 proxy (build 45), LuckPerms-Velocity | `./velocity` (mounted at `/server`) |
| `survival` | Paper 26.3 build 258, 6 GB heap | `./survival` |
| `creative` | Paper **26.2** build 135 + ViaVersion, 4 GB heap | `./creative` |
| `mariadb` | MariaDB 12.3.3 (LTS), database `luckperms` | `./mariadb` |
| `playit` | playit agent 1.2.0, shares velocity's network | — |

No host ports are published. The only way in is the playit tunnel.

---

## 0. Prerequisites

- Docker Engine + the Compose plugin (`docker compose version`), and `jt` in the
  `docker` group.
- ~3 GB free for images, the plugin build cache (`.build/`) and fresh worlds.
- Internet access from the host (Paper, plugins and Maven/Gradle dependencies are
  downloaded on first start/build).

## 1. Stop the old stack *before* pulling

The old `docker-compose.yml` defines a service `mc` (Paper 26.2 on
`./data`, port 25565) plus `playit`. Stop it while that file is still on disk,
so that the old containers are removed and two playit agents never run with the same key:

```bash
cd ~/mc
docker compose down          # with the OLD compose file
docker ps -a                 # nothing from the old stack should remain
```

If you already pulled, remove the leftovers by name (`docker ps -a`, then
`docker rm -f <name>` for the old `*-mc-1` / `*-playit-1` containers).

## 2. Pull the new layout

```bash
cd ~/mc
git fetch origin && git checkout main && git pull
```

## 3. Secrets (`.env`)

`.env` already holds `PLAYIT_SECRET_KEY` and `DISCORD_WEBHOOK_URL`. Add the new
variables listed in `.env.example`, using random hex values:

```bash
cd ~/mc
for v in VELOCITY_FORWARDING_SECRET MARIADB_ROOT_PASSWORD LUCKPERMS_DB_PASSWORD \
         RCON_PASSWORD_SURVIVAL RCON_PASSWORD_CREATIVE; do
  grep -q "^$v=." .env || echo "$v=$(openssl rand -hex 24)" >> .env
done
chmod 600 .env
diff <(grep -oE '^[A-Z_]+=' .env.example | sort) <(grep -oE '^[A-Z_]+=' .env | sort) \
  && echo "all variables present"
```

Keep hex (or other `[A-Za-z0-9]`) values. They are substituted into YAML/TOML.
Store a copy of `.env` in your password manager.

> If you change `LUCKPERMS_DB_PASSWORD` or `MARIADB_ROOT_PASSWORD` **after**
> `./mariadb` was initialised, MariaDB keeps the old ones: change them in SQL too
> (`ALTER USER`).

## 4. Create the data dirs (owned by you)

If Docker creates missing bind-mount dirs itself, they end up owned by root. Create them yourself first:

```bash
cd ~/mc
mkdir -p velocity survival creative mariadb
```

## 5. Build the source-built plugins

```bash
cd ~/mc
scripts/build-plugins.sh
```

This builds a small builder image (Maven + JDK 25, plus JDK 21 for
PlotSquared's Gradle toolchain), then:

- builds **PlotSquared 7.6.1** (GPL source, commit `41f9e95`) → `plugins-built/creative/`
- builds **CoreProtect CE 25.0** (commit `a561c56`, targets 26.3) → `plugins-built/survival/`
- downloads **EssentialsX + EssentialsXSpawn 2.22.1-dev+28-f8724e2** (CI build #1833)
  and checks their sha256 → both dirs

The first run takes several minutes (it downloads dependencies into
`.build/cache`). Pins are in `scripts/plugins/versions.env`, and the result is listed
in `plugins-built/MANIFEST.txt`. Re-run the script after changing a pin.
`--clean` wipes the checkouts and caches.

All other plugins are downloaded by the containers from Modrinth, pinned by
version ID in `docker-compose.yml`.

## 6. Start everything except the tunnel

```bash
cd ~/mc
docker compose config -q && echo compose OK
docker compose up -d mariadb velocity survival creative
docker compose ps                      # wait for (healthy)
docker compose logs -f survival        # until "Done (…)! For help, type "help""
```

Check that there are no plugin errors:

```bash
for c in survival creative velocity; do
  echo "== $c"; docker logs "$c" 2>&1 | grep -E 'ERROR|Error occurred|Could not load' ; done
docker exec survival rcon-cli plugins
docker exec creative rcon-cli plugins
```

Expected plugins:

- **survival:** CoreProtect, Essentials, EssentialsSpawn, GriefPrevention, LuckPerms,
  WorldEdit, WorldGuard, Chunky
- **creative:** CoreProtect, Essentials, FastAsyncVoxelSniper, FastAsyncWorldEdit,
  LuckPerms, Multiverse-Core, PlotSquared, ViaVersion, WorldGuard

You'll also see these log lines, and they're harmless:

- Paper's "SERVER IS RUNNING IN OFFLINE/INSECURE MODE" warning (expected behind
  Velocity).
- Essentials' "LuckPerms without Vault".
- Creative's "2 releases behind" notice.
- An `Unable to write eula` line on the very first start of a fresh data dir. The
  image then fixes ownership and continues.

## 7. Permissions and the creative build world

```bash
cd ~/mc
scripts/luckperms/setup.sh
docker compose restart creative
```

`setup.sh` does three things:

- Applies `scripts/luckperms/groups.lp` (groups `default`, `builder`, `admin`)
  through the survival console. LuckPerms stores the groups in MariaDB, so all three servers share them.
- Creates the Multiverse world `build` (normal terrain) on creative.
- Protects `build` with WorldGuard (`__global__`: `passthrough deny`, members
  `g:builder g:admin`).

At the end it prints the groups from the database. The script is safe to re-run.
It rebuilds the groups from `groups.lp` each time and doesn't touch players.

The **restart of creative** is needed once. FAWE writes its `config.yml` on its
first start, and the FAWE limits patch
(`config/patches/creative/fawe-limits.json`) is applied on every start after that.

Check:

```bash
docker attach survival      # console; type:  lp listgroups   (detach: Ctrl-P Ctrl-Q)
grep -A3 '^  builder:' creative/plugins/FastAsyncWorldEdit/config.yml
```

### What the groups can do

| Group | Survival | Creative | Network |
|---|---|---|---|
| `default` | `/tpa` `/tpahere` `/tpaccept` `/tpdeny`, `/home` `/sethome` (3 homes: Essentials `sethome-multiple.default`), `/spawn`, GriefPrevention claims | PlotSquared basics (the `plots.permpack.basic` nodes except download/save/buy/merge, listed one by one) + `plots.plot.1` (one plot via `/plot auto`), build in own plot; in world `plots`: `fawe.plotsquared` + basic WorldEdit (`//set`, `//replace`, selections, copy/paste, undo…), masked to own plots by FAWE region restrictions; FAWE `limits.default` | `/server`, `/msg` `/r` `/list` |
| `builder` (inherits default) | same as default | `fawe.limit.builder` (higher limits); in world `build`: WorldGuard region member + `worldguard.region.bypass.build`, `fawe.permpack.basic` (FAWE's full builder command set, without admin nodes like `worldedit.reload`), `fawe.bypass.regions` (FAWE anywhere), FastAsyncVoxelSniper (`voxelsniper.sniper`, `voxelsniper.brush.*`); `/speed`, `/tp` | |
| `admin` | `*` | `*` | `*` (also on Velocity) |

FAWE limits (tune in `config/patches/creative/fawe-limits.json`, then restart creative):

| | `default` | `builder` |
|---|---|---|
| max-changes (blocks per edit) | 100 000 | 2 000 000 |
| max-checks | 1 000 000 | 10 000 000 |
| max-radius / brush radius | 32 / 10 | 128 / 32 |
| max-iterations | 500 | 2 000 |
| max-entities / blockstates | 64 / 256 | 512 / 4 096 |
| history | 32 MB | 256 MB |
| concurrent actions | 1 | 2 |

### Staff

Join once through playit (so LuckPerms knows your UUID), then:

```bash
docker exec survival rcon-cli "lp user <name> parent add admin"
docker exec survival rcon-cli "lp user <name> parent add builder"   # promote a builder
```

Avoid OPs. Keep `ops.json` for the owner only, as a break-glass fallback.

> ⚠️ **Don't give one user both `admin` and `builder`**, and never add explicit
> `false` nodes to `default` or `builder`. In LuckPerms an exact `false` node
> beats admin's `*` wildcard, so the negation would take that permission away
> from the admin too. Every player keeps `default` as a parent, so this applies to
> `default` as well. `groups.lp` currently contains **no** `false` nodes: it simply
> leaves out what a group shouldn't have. To make a builder an admin, swap the groups:
> `lp user <name> parent remove builder` then `lp user <name> parent add admin`.

## 8. Enable PROXY protocol in playit, then start the tunnel

Velocity has `haproxy-protocol = true`. From now on it **rejects every
connection that doesn't start with a PROXY header**, so set playit up first:

1. https://playit.gg/account/tunnels/ → the Minecraft Java tunnel.
2. Local address: `127.0.0.1`, port `25565` (playit shares velocity's network namespace).
3. **Proxy Protocol → Version 2**, then save.

Then start the agent:

```bash
cd ~/mc
docker compose up -d playit
docker compose logs -f playit      # tunnel connected
```

Join through the playit address. You should land on **survival**. `/server creative`
switches servers (26.3 clients work there through ViaVersion). In the Velocity log,
your real IP should appear, not `127.0.0.1`.

## 9. Survival spawn and pre-generating the world

Protect spawn with WorldGuard in game (as admin): select it with `//wand` and run `/rg define spawn`. Add flags as you like (e.g. `/rg flag spawn pvp deny`).

Pre-generate chunks before opening, because generation is expensive on this CPU (Chunky is
installed on survival only):

```bash
docker exec survival rcon-cli "chunky world world"
docker exec survival rcon-cli "chunky center 0 0"
docker exec survival rcon-cli "chunky radius 3000"
docker exec survival rcon-cli "chunky start"
docker exec survival rcon-cli "chunky progress"        # check now and then
# optional, after the overworld:
docker exec survival rcon-cli "chunky world world_nether" && \
docker exec survival rcon-cli "chunky radius 1000" && docker exec survival rcon-cli "chunky start"
```

Watch disk space (`df -h /home`): a radius of 3000 is several GB. Chunky pauses
on shutdown and resumes with `chunky continue`.

## 10. After go-live

- The old **`data/`** dir (the 26.2 world from `prepucio/`) is no longer used by
  anything. Once the new network is live and backed up (step 11), archive it if you want
  (e.g. to Drive), then delete it: `rm -rf ~/mc/data`. That frees about 280 MB.

## 11. Backups

The backup system comes from PR #1: `scripts/backup/` (`backup.sh`, `offload.sh`,
`prune-drive.sh`, `backup.conf`), `systemd/` (three `.service` + `.timer` pairs)
and **[docs/BACKUPS.md](docs/BACKUPS.md)**, the authoritative guide. In short:

1. Install the tools: `sudo apt-get install -y rclone zstd curl`.
2. Create the rclone remotes `gdrive` (Google OAuth, headless) and `gdrive-crypt`
   (crypt over `gdrive:mc-backups`), as in docs/BACKUPS.md §2. Store the crypt
   password and salt in your password manager, because without them the Drive
   backups can't be restored. Then `chmod 600 ~/.config/rclone/rclone.conf`.
3. `.env` must contain **`DISCORD_WEBHOOK_URL`** (alerts) and
   **`MARIADB_ROOT_PASSWORD`** (`mariadb-dump` of `luckperms`). Both are already
   there after step 3.
4. Enable the three timers. Only the timers: the services have no `[Install]` section.

   ```bash
   cd ~/mc
   sudo cp systemd/trapaholics-*.service systemd/trapaholics-*.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now trapaholics-backup.timer
   sudo systemctl enable --now trapaholics-offload.timer
   sudo systemctl enable --now trapaholics-prune-drive.timer
   systemctl list-timers 'trapaholics-*'
   ```

5. Run one backup by hand and check that it works:
   `sudo systemctl start trapaholics-backup.service && journalctl -u trapaholics-backup -n 50`.
   Practise a restore before opening (docs/BACKUPS.md, "Restore procedure").

---

## Operations cheat sheet

```bash
docker compose ps
docker compose logs -f <service>
docker exec survival rcon-cli <command>     # also creative; velocity has no RCON:
docker attach velocity                      #   console, detach with Ctrl-P Ctrl-Q
docker compose restart creative             # restart one server, others stay up
docker compose up -d                        # apply compose/template changes
```

- **Config templates:** files under `config/<service>/` are copied into the data
  dir on start, with `${CFG_*}` placeholders filled from the environment.
  Files under `config/patches/<service>/` are re-applied on **every** start.
  Make lasting changes in git, not only on the live files.

> ⚠️ **Template sync only copies a template that is newer than the live file.**
> After a `git pull`, a changed template is usually newer and gets copied. But
> if the live file was modified more recently (by you, or by a plugin rewriting
> its config), the template is **silently skipped**. That matters for
> `config/velocity/velocity.toml` (e.g. `haproxy-protocol` when switching to
> frp in Phase 2) and the PlotSquared `worlds.yml` seed. To apply a changed
> template, remove the live copy and restart the service. The template is then copied in fresh:
>
> ```bash
> rm velocity/velocity.toml && docker compose restart velocity
> ```
>
> Or edit the live file by hand to match. Check the result with
> `docker compose logs velocity | grep -i interpolat` and by reading the live file.
> Settings applied through `config/patches/` (Velocity forwarding in Paper,
> generators, FAWE limits) don't have this problem.
- **Velocity forwarding secret:** comes from `VELOCITY_FORWARDING_SECRET` (env) on
  all three servers. `velocity/forwarding.secret` is ignored.
- **Bumping versions:** change the pin (image tag, `PAPER_BUILD`, Modrinth
  version ID, or `scripts/plugins/versions.env`), back up, then
  `scripts/build-plugins.sh` if needed and `docker compose up -d <service>`. Test on
  creative first. World upgrades are one-way.

## Creative 26.2 → 26.3 upgrade path

Creative runs 26.2 only because PlotSquared 7.6.1 is broken on 26.3
([PlotSquared#4960](https://github.com/IntellectualSites/PlotSquared/issues/4960)).
When a PlotSquared release fixes it:

1. **Back up** (full backup, or at least `./creative` and a DB dump). The upgrade is one-way.
2. `scripts/plugins/versions.env`: set `PLOTSQUARED_REF` and `PLOTSQUARED_COMMIT` to
   the fixed tag. In `scripts/build-plugins.sh`, also copy the CoreProtect 25 jar into
   `plugins-built/creative/`. Run `scripts/build-plugins.sh`.
3. `docker-compose.yml`, `creative` service:
   - `VERSION: "26.3"` and `PAPER_BUILD` = the same build as survival.
   - In `MODRINTH_PROJECTS`: **remove** `viaversion:…` and `coreprotect:3sehX6Sg`
     (it's now built from source), and change WorldGuard to `worldguard:fiHLM6oY`
     (7.0.21).
   - Check that FAWE, Multiverse-Core, FastAsyncVoxelSniper and LuckPerms pins still
     list 26.3 on Modrinth. The current ones already do.
4. `docker compose up -d creative`, then check the log for plugin errors and test
   `/plot auto` and FAWE in a plot.
5. Update ARCHITECTURE.md §4/§5.6 ("creative on 26.3").
