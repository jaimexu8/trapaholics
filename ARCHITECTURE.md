# trapaholics.net — Minecraft Server Architecture

> Status: **DRAFT / basis document** — last updated 2026-11-22
> Owner: jaimexu
> Scope: hosting a Paper-based Minecraft Java network on the Debian home server.
> **Phase 1:** players connect through **playit.gg**.
> **Phase 2:** players connect at `trapaholics.net` through a self-hosted cloud
> reverse proxy (frp on a new Oracle Cloud instance). See §3.1.
>
> **Location:** `~/mc` on the server (`/home/jt/mc`); git remote
> `https://github.com/jaimexu8/trapaholics.git`. On 2026-11-22 the old NeoForge
> `~/mc` directory was deleted and `~/prepucio` was renamed to `~/mc`. Mentions
> below of "old `mc/`" or "`prepucio/`" refer to those directories before the rename.

---

## 1. Goals & Non-Goals

### Goals
- Public Java Edition server, **open to anyone** (no whitelist). Reachable through
  playit.gg at first (Phase 1), and later at **`trapaholics.net`** with no port
  number needed (Phase 2).
- Two separate game modes for players:
  - **Survival** — mostly vanilla gameplay on **hard** difficulty, with
    quality-of-life plugins: TPA, homes, spawn, and player land claims
    (GriefPrevention), with WorldGuard protecting spawn.
  - **Creative** — a building server with two worlds: a **plot world** where every
    player can use **FastAsyncWorldEdit (FAWE)** inside their own plot, and an open
    **build world** where only builders can use FAWE and terrain tools, anywhere.
- **LuckPerms** as the single source of truth for roles and permissions.
- Run on the **newest Minecraft version that has solid plugin support** (see §4).
- Everything runs in Docker on the home server, reproducible from this directory.
- **Automatic full backups every 4 hours**, kept on the server for 24 hours,
  then **encrypted** and moved to Google Drive (`mc-backups/`), where they are
  deleted after 30 days. See §11.

### Custom plugins
- The owner is comfortable **writing small custom plugins** (Paper API) for features
  the server needs when no maintained plugin supports the target version, or when
  the feature is simple to build (e.g. TPA, homes, spawn, a server-selector).
  Prefer an existing maintained plugin for anything complex or security-critical
  (permissions, region protection, world editing).

### Non-Goals (for now)
- Bedrock / console support (Geyser/Floodgate support 26.3 and could be added later — see §4).
- Modded gameplay (the old `mc/` NeoForge setup is **not** being carried forward).
- Minigames, economy, or ranks-for-purchase.

---

## 2. Constraints

| Constraint | Consequence |
|---|---|
| Home network **cannot port-forward** (CGNAT / no router access) | All inbound traffic must arrive via an outbound tunnel from the home server to a public relay. |
| No working cloud instance yet (the old Oracle instance `164.152.19.87` is gone) | **Phase 1 uses playit.gg** as the tunnel. Phase 2 switches to frp on a newly provisioned Oracle Cloud instance with a new IP. |
| Domain `trapaholics.net` must be used (owner controls its DNS) | In Phase 2, DNS points at the cloud instance, not the home IP. |
| Single physical host: **16 GB RAM, Intel Xeon E3-1220 (4 cores / 4 threads, 3.1 GHz, 2011-era)** | Proxy, both game servers and the database share this. Memory and view distance are sized accordingly (§8). Single-core speed is modest, so the main server thread is the bottleneck. |
| **Only ~5.7 GB free on `/home` right now** (several TB coming soon) | Enough to start, but backups will be offloaded to Drive almost immediately until the extra space arrives (§11). |

---

## 3. High-Level Topology

### 3.1 Connection phases

The only thing that changes between phases is **which tunnel container feeds
Velocity**. Velocity, the game servers, the database and backups stay the same.

| | Phase 1 — now | Phase 2 — later |
|---|---|---|
| Tunnel | **playit.gg agent** container (`playit`) | **frpc** container → **frps** on a new Oracle Cloud instance |
| Address players use | the playit-assigned address (e.g. `xxxx.joinmc.link`) | **`trapaholics.net`** |
| Cloud instance needed | no | yes (Oracle Always-Free; new IP) |
| Real player IPs | playit's PROXY protocol, if available on the plan (§5.2) | frp PROXY protocol v2 (§5.2) |
| DNS | not needed (optionally a CNAME/SRV to the playit address) | `trapaholics.net` A record → instance IP |

**Phase 1 → Phase 2 switch-over:** provision the instance and run frps → add the
`frpc` service and its config → test with a temporary subdomain → point the
`trapaholics.net` DNS at the instance → remove the `playit` service and revoke its
secret. The Velocity `haproxy-protocol` setting must match whichever tunnel is
active. Both tunnels can run side by side during testing only if both send (or
both don't send) PROXY headers.

### 3.2 Target topology (Phase 2)

In Phase 1, the cloud relay box below is replaced by playit.gg's network, and
`frpc` is replaced by the `playit` agent. Everything else is identical.

```
                    Players (Java Edition)
                             │  trapaholics.net:25565
                             ▼
        ┌──────────────────────────────────────────┐
        │  Cloud relay (Oracle Cloud Free / EC2)    │
        │  public IP  ←  DNS A record               │
        │  frps  :7000 (tunnel control, restricted) │
        │        :25565 (public game port)          │
        └──────────────────┬───────────────────────┘
                           │  outbound TCP tunnel (initiated from home)
                           ▼
 ┌───────────────────── Debian home server (Docker) ─────────────────────┐
 │                                                                        │
 │   frpc ──► velocity:25565  (Velocity proxy — the only "front door")    │
 │                 │                                                      │
 │        ┌────────┴─────────┐          (internal Docker network only)    │
 │        ▼                  ▼                                            │
 │   survival:25565     creative:25565        Paper backends              │
 │   (Paper)            (Paper)                                           │
 │        │                  │                                            │
 │        └──────┬───────────┘                                            │
 │               ▼                                                        │
 │          mariadb:3306   (shared LuckPerms storage, optional others)    │
 └────────────────────────────────────────────────────────────────────────┘
```

**Key idea:** survival and creative are **two separate Paper servers** joined by a
**Velocity proxy**. Players connect once (playit address, later `trapaholics.net`) and move between
servers with `/server survival` / `/server creative` (or a lobby/compass item later).

### Why a proxy + two backends (instead of one server with Multiverse)?
- **Plugin isolation:** FAWE/VoxelSniper only exist on creative; survival never loads
  them, so there is no risk of a permission leak giving survival players WorldEdit.
- **Performance isolation:** a huge FAWE operation lags only the creative server.
- **Separate inventories/stats for free** — no inventory-separation plugin needed.
- **Independent restarts / upgrades** — creative can be restarted without kicking
  survival players.
- Cost: one extra JVM (~512 MB for Velocity) and a slightly more complex setup.

> Alternative considered: one Paper server + Multiverse-Core + Multiverse-Inventories
> + per-world LuckPerms contexts. Simpler, lighter on RAM, but weaker isolation.
> Kept as a fallback if 16 GB turns out to be too tight.

---

## 4. Version Target

- **Server software:** Paper (backends) + Velocity (proxy), via the `itzg/minecraft-server`
  and `itzg/mc-proxy` Docker images.
- **Minecraft version: 26.3** ✅ **decided** (Option A below). Newest MC release is
  26.3 (2026-09-15); 26.4 is still in snapshots and Paper has no builds for it.
- **Java:** 25 (needed by Paper 26.x; itzg image tag `java25`).

### Compatibility snapshot (researched 2026-11-22)

| Component | Version | Works on 26.3? |
|---|---|---|
| Paper | 26.3 (stable since ~build 175; build 258 latest) | ✅ |
| Velocity | 4.3.1 (clients 1.7.2–26.3) | ✅ |
| FastAsyncWorldEdit | 2.16.3 (26.1.1–26.3) | ✅ (needs a recent Paper build) |
| WorldEdit | 7.4.6 | ✅ |
| WorldGuard | 7.0.21 | ✅ |
| LuckPerms (Paper + Velocity) | 5.5.x (get it from luckperms.net) | ✅ |
| GriefPrevention | 16.18.8 | ✅ |
| Multiverse-Core | 5.8.2 | ✅ |
| Geyser / Floodgate | 2.12.1 (beta) / 2.2.7 | ✅ |
| **EssentialsX** | 2.22.0 stable = **up to 26.1.2 only** | ⚠️ 26.3 only in dev builds (2.22.1-dev) |
| HuskClaims | 1.5.10 (up to 1.21.7) | ❌ |
| **PlotSquared** | 7.6.1 (supports up to 26.2) | ❌ **open bug #4960**: chat output and titles break on 26.3; also #4959 (cushions not protected) |
| **FastAsyncVoxelSniper** | 3.2.5 (lists 26.3; works with FAWE) | ✅ |
| VoxelSniper-Reimagined | 8.14.0 (2024, not maintained) | ❌ |
| CoreProtect | v24.1 public release = up to 26.2; v25 (26.3) on Patreon or built from source | ⚠️ build from GitHub source |
| Arceon | 0.5.7 (paid) | ✅ claims 1.20–26.3 |

### Decision — Option A chosen
- **Option A — 26.3 ✅ chosen:** newest release, Paper stable, every core
  plugin except EssentialsX has a stable release. Run the EssentialsX 2.22.1-dev
  build until 2.22.1 ships, or use a standalone TPA/homes plugin instead.
- **Option B — 26.1.2:** the newest version where *everything* (incl. EssentialsX)
  is stable. Safer, but one version behind; the existing 26.2 world in
  `prepucio/data` **cannot be downgraded** to it.
- **Option C — 26.3 + custom plugin:** replace EssentialsX with a small home-made
  plugin for TPA, homes and spawn (see "Custom plugins" in §1).
- EssentialsX dev build status (2026-11-22): build #1833, `2.22.1-dev+28-f8724e2`,
  from https://ci.ender.zone/job/EssentialsX/. EssentialsXSpawn and EssentialsXChat
  are built with it. No 26.3 bugs have been reported against it, and there's no
  release date for 2.22.1.
- What 26.3 "Wilderness Bound" adds (mid-sized update, no new mob): the Dappled
  Forest biome (poplar wood set), Abandoned Camp structures, wool and concrete
  stairs/slabs, cushions, straw beds, and new `/compute` and `/posteffect`
  commands. The new biome and structures only generate in chunks that haven't been
  explored yet. Note: on 26.3, new servers have `white-list=true` by default.
- 26.2 (what `prepucio/` runs now) has the same EssentialsX gap as 26.3 and is
  older, so there's no reason to stay on it.
- When EssentialsX 2.22.1 is released, swap the dev jars for the release. If the
  dev build ever breaks, fall back to Option C (custom plugin).
- **PlotSquared does not work on 26.3 yet** (issue #4960, open as of 2026-11-22).
  This affects the creative plot world; see the creative decision in §7.
  PlotSquared's code is GPL-3.0: the SpigotMC download is paid, but building it
  from the GitHub source is free and allowed.
- Pin exact versions (`VERSION`, Paper build, plugin jars) in compose/env — never
  use `latest` for game servers, to avoid surprise world upgrades.

> ⚠️ Minecraft world upgrades are one-way. Back up before bumping `VERSION`.

---

## 5. Components

### 5.1 Cloud relay (Phase 2 — new Oracle Cloud instance)
- Not needed in Phase 1.
- A **new** Oracle Cloud Always-Free instance will be provisioned, with a new public
  IP. The old instance at `164.152.19.87` (in `mc/frpc.toml`) no longer exists.
  EC2 `t4g.nano`/`t3.micro` is the alternative.
- The smallest shape is enough; the relay only forwards TCP.
- Runs **`frps`** (frp server).
- Firewall / security group:
  - `25565/tcp` — open to the world (game traffic).
  - `7000/tcp` — frp control port; restricted to the home IP if possible, and
    always protected with an frp **auth token**.
  - `22/tcp` — SSH, key-only, ideally restricted by IP.
  - Oracle Cloud note: open ports in **both** the VCN security list and the
    instance's `iptables`/`firewalld`.

### 5.2 Tunnel

#### Phase 1: playit.gg (current)
- `ghcr.io/playit-cloud/playit-agent` container, carried over from `prepucio/`.
- Runs with `network_mode: "service:velocity"` so the tunnel's local target is
  `127.0.0.1:25565`, i.e. Velocity. In the playit dashboard, the Minecraft Java
  tunnel points at `127.0.0.1:25565`.
- The `SECRET_KEY` lives in `.env` as `PLAYIT_SECRET_KEY`, **not** in
  `docker-compose.yml`. Compose reads it as `${PLAYIT_SECRET_KEY}`. The owner
  chose to keep the existing key; it was moved out of the compose file before the
  first git commit and has never been in git history (§12).
- **Real player IPs: use playit's PROXY protocol v2.**
  - In the playit dashboard (https://playit.gg/account/tunnels/ → the tunnel →
    **"Proxy Protocol"**), choose **Version 2**.
  - In `velocity.toml`, set `[advanced] haproxy-protocol = true`.
  - The playit agent must be **0.15.26 or newer**. Pin an image tag that meets this
    (the old compose used `playit-agent:1.0`).
  - playit's docs don't list this as a Premium feature, so it should work on the
    free plan. Confirm the setting appears in the dashboard.
  - Without it, every player shows up as `127.x.x.x`, so IP bans and alt detection
    don't work.
  - Once it's on, Velocity rejects any connection that doesn't come through playit,
    including direct LAN joins.
- playit free tier: shared routing (choosing a region is Premium), 4 ports. Using
  your own domain is a Premium feature. Without Premium, an SRV record at your own
  DNS pointing to the tunnel's hostname and port should still work, but this isn't
  in playit's docs.
- Velocity has no port published on the host, so the only way in is through the
  tunnel.

#### Phase 2: frp (frps on relay ↔ frpc at home)
- Reuses the approach already started in `mc/` (`frpc.toml`, `snowdreamtech/frpc`).
- `frpc` forwards relay `:25565` → `velocity:25565` on the home Docker network.
- **Real player IPs:** set `transport.proxyProtocolVersion = "v2"` on the frpc
  proxy and `haproxy-protocol = true` (under `[advanced]`) in `velocity.toml`.
  Once enabled, Velocity rejects connections that don't come through frp
  (including direct LAN joins). This lets bans, logs and anti-alt checks see real
  player IPs instead of the tunnel's address.
- Add an auth token to both sides (the current `mc/frpc.toml` has none).

### 5.3 DNS
- Phase 1: no DNS needed. Optionally, a `_minecraft._tcp` SRV record on a
  subdomain can point at the playit address, so players can type a nicer name
  before Phase 2.
- Phase 2: `trapaholics.net` **A record** → the new instance's public IP.
- Optional: `mc.trapaholics.net` A record + `_minecraft._tcp` SRV record if the
  game should ever move off port 25565 or if the apex is needed for a website.

### 5.4 Velocity proxy (home)
- The only container the tunnel can reach (`playit` in Phase 1, `frpc` in Phase 2).
- `player-info-forwarding-mode = "modern"`; shared `forwarding.secret` with backends.
- Backends set `online-mode=false` in `server.properties` and enable Velocity in
  `config/paper-global.yml` (`proxies.velocity.enabled: true`, `online-mode: true`,
  same secret). **Backends must never be exposed outside the Docker network.**
- Server list: `survival` (default/try first), `creative`.
- Plugins: LuckPerms-Velocity (network-wide groups), optionally a server-selector
  or MOTD plugin later.

### 5.5 Survival backend (Paper)
| Purpose | Plugin (proposed) | Notes |
|---|---|---|
| Permissions | LuckPerms | Shared DB with other servers |
| Teleport / homes / spawn / warps | EssentialsX 2.22.1-dev (+ EssentialsXSpawn) | `/tpa`, `/tpahere`, `/home`, `/spawn` |
| Player land claims | **GriefPrevention** | Players claim their own land with a golden shovel. Claim blocks build up with playtime. |
| Admin protection | WorldGuard (+ WorldEdit as its dependency) | Spawn and other shared areas, set up by admins |
| Performance | spark | Already used in `prepucio/` |
| Nice-to-have | SushiImage | Carried over from `prepucio/` (image maps) |

- Gamemode survival, **difficulty hard** (confirmed).
- **Fresh world**: the old `prepucio/data/world` is not carried over. Pre-generate
  a radius around spawn (e.g. with Chunky) before launch, because chunk generation
  is expensive on this CPU.
- 26.3 sets `white-list=true` by default; set **`white-list=false`** (open server)
  explicitly.
- Regular WorldEdit (not FAWE) here only as WorldGuard's dependency; WorldEdit
  permissions granted to admins only.

### 5.6 Creative backend (Paper)
| Purpose | Plugin (proposed) | Notes |
|---|---|---|
| Permissions | LuckPerms | Shared DB |
| Building | **FastAsyncWorldEdit** | Replaces WorldEdit on this server |
| Plots | **PlotSquared** (26.3 support to confirm) | Plot world, plot claiming, keeps FAWE inside the player's own plot |
| Multiple worlds | Multiverse-Core (or PlotSquared's own world handling) | Plot world + build world on one server |
| Build-world protection | WorldGuard | Stops non-builders from changing the build world |
| Terrain tools | **FastAsyncVoxelSniper 3.2.5** | Maintained VoxelSniper fork that supports 26.3 and goes through FAWE. Builder-only, build world only. Other tools may be added later |
| Block logging / rollback | **CoreProtect** (built from GitHub source for 26.3) | Undo griefing; the server is open to anyone. Also useful on survival |
| Utilities | EssentialsX 2.22.1-dev | `/tp`, `/speed`, `/gamemode` |
| Performance | spark | |

- `gamemode=creative`, `force-gamemode=true`.
- **Version: Paper 26.2 (temporary).** PlotSquared is broken on 26.3 (#4960), so
  creative runs Paper 26.2 with **ViaVersion**, which lets 26.3 clients join a
  26.2 server. Players coming through Velocity on 26.3 switch to creative without
  noticing; only 26.3-only blocks (cushions, poplar) don't exist there. Every
  creative plugin jar must be the **26.2-compatible** build. Once PlotSquared
  supports 26.3: back up, bump `VERSION`, update the jars, and remove ViaVersion.
  Upgrading is one-way, which is fine here.

#### Creative worlds

| World | Who can build | FAWE | Notes |
|---|---|---|---|
| **`plots`** (default spawn world) | Plot owners (and anyone they add) | **Everyone**, but **only inside their own plot** | Flat plot grid managed by PlotSquared |
| **`build`** | **Builders and admins only** | **Builders: anywhere in the world** | Open world with **normal generated terrain** for large terrain projects. Default players can visit but not change anything. |

- **Getting a plot:** a player runs a request command (PlotSquared's `/plot auto`)
  and is given the **closest unclaimed plot to the centre** of the plot world.
  PlotSquared's auto-claim already works outward from the centre; confirm this
  once it's set up. If it doesn't match exactly, a small custom plugin or command
  wrapper can handle it (§1, Custom plugins).
- **Plot size: 64×64 blocks.** Roads between plots are a PlotSquared setting
  (e.g. 7 blocks wide).
- **Plot limit: 1 per player** (`plots.plot.1` for `default`). Easy to raise later
  through LuckPerms.
- **Keeping FAWE inside plots:** FAWE's PlotSquared integration (its "region
  restrictions") limits each player's edits to plots they own or have been added
  to. Players without the bypass permission can't edit outside their plots.
- **Build world:** WorldGuard's `__global__` region denies building to everyone
  except the `builder` and `admin` groups, and FAWE's region restrictions are
  bypassed for builders in that world, so they can edit anywhere there.
- **FAWE limits** (`plugins/FastAsyncWorldEdit/config.yml`): tight limits for
  default players (max blocks changed per command, radius, history size) and
  higher limits for builders. These matter on a 4-core 2011-era CPU, where one
  huge edit can lag the whole creative server.

### 5.7 Database (MariaDB)
- One MariaDB container on the internal network for **LuckPerms** (required for
  shared permissions across Velocity + both backends).
- Not exposed to host or internet. Credentials via `.env` (gitignored).
- Optionally reused later by CoreProtect, claims plugin, etc.

---

## 6. Permissions Model (LuckPerms)

Groups are defined **once** in the shared DB; server-specific permissions use the
LuckPerms `server` context (`server=survival` / `server=creative`), matching each
backend's `server` name in `plugins/LuckPerms/config.yml`.

Three groups to start. More may be added later as more plugins are added.

| Group | Inherits | Survival | Creative | Network |
|---|---|---|---|---|
| `default` | — | Minimal: `/tpa`, `/tpahere`, `/home` (limited), `/spawn`, GriefPrevention claims | Claim a plot (`/plot auto`), build in own plot, **FAWE inside own plot only** (tight limits). Visit the build world without building. | `/server` |
| `builder` *(name may change)* | default | same as default | **Build world: build + FAWE anywhere**, terrain tools, higher FAWE limits | |
| `admin` | — | `*` (all permissions) | `*` | `*` |

- The `builder` group's name is a placeholder. Because permissions are attached to
  the group, renaming it later (`/lp group builder rename <new>`) is cheap.
- Builder powers are limited to the creative server with the LuckPerms
  `server=creative` context (and `world=build` where needed), so they never apply
  on survival.
- `admin` gets `*` on every server, including Velocity.
- Avoid OPs; use `ops.json` only for the owner as a break-glass fallback.
- Promotion is manual: `/lp user <name> parent add builder`.

---

## 7. Open Questions

### Still open
- Nothing blocking. Remaining host setup: install `rclone` and link Google Drive
  (§11) before backups go live.

### Decided (2026-11-22)
| Topic | Decision |
|---|---|
| MC version | **26.3**, EssentialsX 2.22.1-dev until the release ships (§4) |
| Survival claims | **GriefPrevention** for players + **WorldGuard** for spawn/admin areas |
| Survival difficulty | **Hard** |
| Creative layout | **Plot world** (FAWE for everyone inside own plot; closest unclaimed plot to the centre) **+ build world** (builders use FAWE anywhere) |
| Ranks | `default` (minimal), `builder` (name TBD; creative FAWE powers), `admin` (`*`). More may come later. |
| World | **Fresh** survival world; the old `prepucio/data/world` is not used |
| Tunnel | **playit.gg now** (Phase 1); frp + new Oracle Cloud instance + `trapaholics.net` later (Phase 2) |
| DNS | Owner controls `trapaholics.net` DNS |
| Access | **Open to anyone** (no whitelist) |
| Plots | **64×64** blocks, **1 plot per player** (may change later) |
| Build world | **Normal terrain** |
| Terrain tools | **FastAsyncVoxelSniper** (works on 26.3); others added later by the owner |
| Real IPs (Phase 1) | playit **PROXY protocol v2** + Velocity `haproxy-protocol = true` |
| Creative version | **Paper 26.2 + ViaVersion** until PlotSquared fixes #4960, then upgrade to 26.3. Survival is on 26.3. |
| Host resources | The QEMU VM will scale down; the RAM plan in §8 stands. `jt` is in the `docker` group. |
| Repo | `~/mc` (renamed from `prepucio`), remote `github.com/jaimexu8/trapaholics` |
| Admin alerts | **Discord webhook** to an admin-only log channel in the server's Discord |
| Backups | Every 4 h; Drive after 24 h; **encrypted**; deleted from Drive **30 days** after upload; Drive has 5 TB, so storage isn't a concern |

---

## 8. Resource Plan

Host: **16 GB RAM, Intel Xeon E3-1220** (4 cores / 4 threads, 3.1 GHz base, Sandy
Bridge, 2011).

| Container | Java heap (`MEMORY`) | Real usage (approx.) | Notes |
|---|---|---|---|
| velocity | 512M | ~0.8 GB | |
| survival | 6G | ~7 GB | Main world; the most players |
| creative | 4G | ~5 GB | FAWE uses a lot of memory on big edits; limits keep it in check |
| mariadb | — | ~0.4 GB | Small config (`innodb_buffer_pool_size` ~128–256M) |
| playit / frpc | — | negligible | |
| **Total** | | **~13 GB** | Leaves ~3 GB for Debian, Docker and disk cache |

- JVM memory use is higher than the heap setting (roughly +15–25%), hence the
  "real usage" column. Don't raise heaps further without watching `free -h`;
  swapping would ruin tick times.
- Use Aikar's flags (itzg: `USE_AIKAR_FLAGS=true`).
- **CPU is the tighter limit**, not RAM. Each Paper server runs its world on one
  main thread, and this CPU's single-core speed is modest. Mitigations:
  - Start with `view-distance=10`, `simulation-distance=8` on survival (the old
    prepucio had 12/10), and raise them only if spark shows headroom.
  - Pre-generate the survival world with Chunky before opening it to players.
  - Strict FAWE limits on creative (§5.6).
  - Paper's performance options (`paper-world-defaults.yml`: entity limits,
    hopper/redstone tuning) as needed, measured with spark.
- Disk: only ~5.7 GB free now, so expect early backups to move to Drive almost
  immediately (§11.5). Several TB are coming soon.

---

## 9. Directory Layout (`~/mc`)

```
mc/
├── ARCHITECTURE.md          ← this file
├── docker-compose.yml       ← velocity, survival, creative, mariadb, playit (Phase 1) / frpc (Phase 2)
├── .env                     ← secrets (gitignored): playit secret, forwarding secret, DB pw, RCON pw, (Phase 2) frp token
├── frpc.toml                ← Phase 2 tunnel client config (from mc/frpc.toml, + token + proxy protocol)
├── relay/                   ← Phase 2 cloud-side config (frps.toml, setup notes)
├── velocity/                ← Velocity data (velocity.toml, forwarding.secret, plugins/)
├── survival/                ← Paper data (fresh world)
├── data/                    ← OLD prepucio server data (26.2 world), gitignored; not used, delete once the new setup is live
├── creative/                ← Paper data
├── scripts/                 ← backup.sh, offload.sh, prune-drive.sh (see §11)
└── backups/                 ← local backup archives (≤ ~24 h old), gitignored
```

---

## 10. Operations

- **Backups:** see §11.
- **Restarts:** `restart: unless-stopped`; scheduled daily restart optional.
- **Updates:** pin versions; bump on a branch / copy, test on creative first,
  back up, then survival.
- **Console access:** `docker exec -i <container> rcon-cli`.
- **Monitoring:** spark for lag; optionally uptime check on the relay.

---

## 11. Backups (required)

Automatic backups are **mandatory**. Every backup is a full snapshot of the whole
network, so a single archive can rebuild the server from scratch.

### 11.1 Requirements

| # | Requirement |
|---|---|
| B1 | A **full backup** is created **every 4 hours** and stored locally on the server. |
| B2 | A backup that is **older than 24 hours** is uploaded automatically to the owner's **Google Drive**, into a folder named **`mc-backups`**. |
| B3 | Once a backup has been **verified in Google Drive**, it is deleted from the local server. |
| B4 | If there **isn't enough disk space** for a new backup, the **oldest local backups are moved to Google Drive** (upload, verify, delete) one at a time until there is room. Then the new backup is created. |
| B5 | A local backup is **never deleted unless it has been uploaded and verified** first. |
| B6 | Every backup is **encrypted before it leaves the server**. Google only ever stores encrypted data. |
| B7 | A backup is **permanently deleted from Google Drive 30 days after it was uploaded**. |

### 11.2 What a backup contains

Everything needed to restore the whole network:

- **All worlds:** survival (overworld, nether, end) and creative.
- **All plugins:** the jars plus each plugin's data and config folders
  (EssentialsX userdata/homes/warps, WorldGuard regions, claim data, FAWE
  schematics and history, etc.), on all three servers.
- **Permissions:** a **`mysqldump` of MariaDB**, which holds the LuckPerms groups,
  users and tracks, plus anything else stored in that database. Copying the
  database's files while it is running is *not* a safe backup.
- **Server config:** `server.properties`, `bukkit.yml`, `spigot.yml`,
  `config/paper-*.yml`, `ops.json`, `whitelist.json`, ban lists, `velocity.toml`,
  `forwarding.secret`.
- **Infrastructure:** `docker-compose.yml`, `frpc.toml`, `relay/`, `scripts/`, `.env`.
- Optional exclusions to save space, since Paper can re-download them:
  `libraries/`, `cache/`, `versions/`, and old `logs/`.

### 11.3 Making a consistent backup (every 4 hours)

A systemd timer runs `scripts/backup.sh` on the host at 00:00, 04:00, 08:00,
12:00, 16:00 and 20:00. The script holds a lock (`flock`) so two runs can't overlap.

1. **Check space first** (B4). Estimate how much space the backup needs: the
   size of the newest existing backup × 1.25, or the live data size if this is
   the first backup. While free space on the backup disk is below the estimate
   plus a safety margin (e.g. 5 GB), **offload the oldest local backup** (§11.4)
   regardless of its age. If space still can't be freed (Drive is unreachable,
   or there are no backups left to move), **abort without deleting anything**
   and send an alert.
2. On each Paper server, over RCON: `save-off`, then `save-all flush`. This stops
   autosave and writes every chunk to disk.
3. Run `mysqldump --single-transaction` for the LuckPerms database into the
   staging area.
4. Write a compressed archive (`tar` + `zstd`) to `backups/`, named
   `trapaholics-YYYY-MM-DD_HHMM.tar.zst`, plus a matching `.sha256` checksum file.
5. `save-on` on each Paper server. Do this in a `trap` so autosave is turned back
   on even if the script fails partway.
6. Briefly test the archive (`zstd -t`) and log the result.

Players stay connected the whole time; autosave is only paused while the
archive is written.

### 11.4 Moving backups to Google Drive

- **Tool:** `rclone`, with two remotes:
  - `gdrive` — the Google Drive connection, set up through Google OAuth
    (`rclone config`) under the owner's Google account.
  - `gdrive-crypt` — an rclone **`crypt`** remote layered on top of
    `gdrive:mc-backups`. Anything written to `gdrive-crypt:` is encrypted on the
    server first (rclone crypt: XSalsa20-Poly1305 for file contents), so only
    encrypted data is sent to Google (B6). All uploads go through `gdrive-crypt`,
    never straight to `gdrive`.
  - File names: `filename_encryption = off`, so files in Drive still show their
    backup date (e.g. `trapaholics-2026-11-22_0400.tar.zst.bin`). Only the
    timestamp is visible; the contents stay encrypted. Switch to `standard` if
    even the dates should be hidden.
- **Scheduled offload:** an hourly systemd timer runs `scripts/offload.sh`. For
  each local archive older than 24 hours (oldest first):
  1. `rclone copy <file> gdrive-crypt:` — encrypt and upload.
  2. `rclone cryptcheck <file> gdrive-crypt:` — confirm that the encrypted copy
     in Drive matches the local file. A plain hash check doesn't work through
     `crypt`, which is why this step is needed.
  3. Only if the check passes: record the upload time (§11.6) and delete the
     local archive and its `.sha256`. That covers B3 and B5.
- **Moving early to make space:** `backup.sh` runs the same three steps for a
  single file, the oldest local backup, ignoring the 24-hour rule.
- **If an upload fails:** the file stays local, the error is logged, and the next
  run tries again. Repeated failures send an alert.
- **Bandwidth:** cap uploads (`--bwlimit`) so they don't cause lag for players on
  the home connection.

### 11.5 Disk-space behaviour

```
new backup due
   │
   ├─ enough free space? ── yes ──▶ create backup
   │
   no
   │
   ├─▶ offload oldest local backup to gdrive:mc-backups (upload → verify → delete)
   │        └─ loop until enough space, or until nothing is left to move
   │
   └─ still not enough (or Drive unreachable) ──▶ skip this backup, keep all
                                                  local files, alert
```

### 11.6 Google Drive

- Folder: **`mc-backups`** in the owner's Drive. It only ever holds encrypted
  files; they can't be opened from the Drive web UI, only restored through rclone.
- **30-day retention (B7):** the clock starts when a backup is **uploaded**, not
  when it was created. That matters because backups moved early for disk space
  reach Drive sooner than 24 hours.
  - `offload.sh` appends `<filename> <upload time, UTC>` to an upload log
    (`backups/.uploaded.log`) after each verified upload.
  - A daily systemd timer runs `scripts/prune-drive.sh`. It permanently deletes
    every file whose upload time is 30 or more days ago
    (`rclone deletefile gdrive-crypt:<file> --drive-use-trash=false`) and removes
    its line from the log.
  - `--drive-use-trash=false` matters: by default Drive moves deleted files to the
    Trash, where they keep using storage for another 30 days.
  - Safety net, in case the log is lost: also delete anything whose modification
    time in Drive is older than 31 days (`rclone delete gdrive-crypt:
    --min-age 31d --drive-use-trash=false`). rclone keeps the backup's creation
    time as the Drive modification time, so 31 days covers the 24-hour local stay.
- **Storage:** the owner's Drive has **5 TB**. With 6 backups a day × 30 days
  ≈ 180 archives in Drive at any time, that is roughly 28 GB per backup before
  space runs out, so Drive capacity is **not a design concern**. The owner will
  revisit it if that ever changes.
- **Secrets:**
  - `~/.config/rclone/rclone.conf` holds the Drive OAuth token **and** the crypt
    password and salt. rclone only *obscures* these; it does not encrypt them.
    Make the file `chmod 600`, and never commit it or put it inside the backups.
  - **Store the crypt password and salt somewhere off the server** (a password
    manager). If the server dies and they are lost, **every Drive backup becomes
    unrecoverable**.
  - Optionally, lock `rclone.conf` itself with `RCLONE_CONFIG_PASS`; the timers
    would then read that password from a root-only file.

### 11.7 Monitoring and restore

- Log every run (backup created, size, how long it took, which files were moved
  to Drive) to the systemd journal.
- Alert on a failed backup, a failed upload, or a skipped backup because of low
  space. Alerts go to the **admin log channel** in the server's Discord through a
  **Discord webhook**. The webhook URL is a secret: it lives in `.env`
  (`DISCORD_WEBHOOK_URL`), never in scripts or git. The same channel can later get
  other admin logs (e.g. server start/stop).
- Alert when `prune-drive.sh` fails.
- **Restore steps (to write down and test):**
  1. Recreate the rclone remotes with the saved crypt password and salt (on a
     new machine if needed).
  2. Download and decrypt: `rclone copy gdrive-crypt:<backup> ./restore/`. A local
     backup under 24 hours old can be used directly.
  3. Check the archive against its `.sha256` file.
  4. Stop the containers → extract the archive → load the database dump into
     MariaDB → `docker compose up -d`.
- Practise a restore from a Drive copy before launch, and again every so often.
  That also confirms the saved crypt password actually works.

---

## 12. Security Notes

- The playit `SECRET_KEY` was moved from `docker-compose.yml` to `.env` (mode 600,
  gitignored) before the first commit, so it is not in git. The owner chose
  **not** to rotate it; it had been stored in plain text in the old compose file.
  Revoke it at the Phase 2 switch-over. The old `data/server.properties` (RCON
  password, management secret) is gitignored. New servers take RCON passwords
  from `.env`.
- Backends + MariaDB on an internal Docker network only. Only the tunnel
  (playit, later frpc) can reach Velocity, and no game port is published on the
  host.
- The server is **open to anyone** (no whitelist), so protection comes from
  GriefPrevention claims, WorldGuard at spawn, PlotSquared plots, WorldGuard on the
  build world, and minimal `default` permissions. Consider a block-logging plugin
  (e.g. CoreProtect, if it supports 26.3) to undo griefing, and a basic anti-bot /
  connection rate limit at Velocity.
- Velocity modern forwarding secret must be strong and identical on all three.
- `online-mode` stays **true** at the Velocity layer (Mojang auth enforced).
- Phase 2: frp auth token required; relay control port firewalled.
- Backups contain secrets (`.env`, `forwarding.secret`) and player data. Local
  archives aren't encrypted, so keep `backups/` readable only by its owner
  (`chmod 700`). Copies in Drive are always encrypted (§11.4).

---

## 13. Migration From Existing Directories

### From `mc/` (keep)
- **frp tunnel pattern** (`frpc` container + `frpc.toml`) → the Phase 2 transport.
  The server address changes to the new Oracle instance's IP.
- `restart: always`, `tty`/`stdin_open` for console attach.

### From `mc/` (drop)
- `TYPE: NEOFORGE`, `VERSION: 1.21.1` — modded server, not what we want.

### From `prepucio/` (keep)
- `TYPE: PAPER`, itzg image, Paper 26.x baseline.
- **`playit` service** → kept as the Phase 1 tunnel, but now attached to Velocity
  (`network_mode: "service:velocity"`) with its secret moved to `.env` and
  replaced with a new one.
- Plugins: EssentialsX (upgraded to the 2.22.1-dev build), spark, SushiImage;
  WorldEdit (survival, admin only, as WorldGuard's dependency).
- Server settings: difficulty hard. View/simulation distance lowered to 10/8 for
  this CPU (§8).
- Plugin configs worth looking through for reuse: `data/plugins/Essentials/config.yml`
  and `kits.yml`.

### From `prepucio/` (drop / change)
- **The old world (`data/world`) is not used**; survival starts fresh. Keep the old
  `data/` folder archived (or put it in Drive) until the new setup is live, then
  delete it. It also frees disk space.
- `VERSION: "26.2"` → 26.3.
- `ports: 25565:25565` on the backend → removed; only Velocity is reached, and
  only via the tunnel.
- Single `data/` dir → split into `velocity/`, `survival/` and `creative/`.

---

## 14. Roadmap

**Phase 1 — build on playit (now)**
1. ~~Confirm plugin versions~~ (done, §4). ~~Rename `prepucio/` → `~/mc`, git
   remote, secret moved to `.env`~~ (done).
2. Delete the old `data/` once the new setup is live (it frees ~280 MB).
3. Restructure `~/mc` into the layout in §9. Write the new
   `docker-compose.yml` (velocity, survival, creative, mariadb, playit) and `.env`.
4. Velocity + survival first: verify players can join through the playit address.
5. Add MariaDB + LuckPerms (network-wide). Create the `default`, `builder` and
   `admin` groups.
6. Survival plugins: EssentialsX-dev, GriefPrevention, WorldGuard at spawn.
   Pre-generate the world.
7. Creative (**Paper 26.2 + ViaVersion**, §5.6): FAWE, PlotSquared plot world,
   build world with WorldGuard + builder permissions, FastAsyncVoxelSniper, FAWE
   limits.
8. Backups (§11): `rclone` with the `gdrive` and `gdrive-crypt` remotes (save the
   crypt password off the server), `backup.sh` / `offload.sh` / `prune-drive.sh`,
   and systemd timers. Test the low-disk-space path, the 30-day pruning, and a full
   restore from Drive.
9. Open launch (no whitelist; `white-list=false` set explicitly).

**Phase 2 — switch to `trapaholics.net`**

10. Provision a new Oracle Cloud Always-Free instance. Install frps; set up the
    firewall (VCN security list + instance firewall) and the auth token.
11. Add the `frpc` service. Test through a temporary subdomain.
12. Point the `trapaholics.net` A record at the instance. Set Velocity
    `haproxy-protocol` to match frp. Remove the `playit` service and revoke its key.
