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
  - **Creative** — a building server with **one creative world** (normal terrain).
    Everyone can build by hand; **builders** get **FastAsyncWorldEdit (FAWE)** and
    terrain tools. **No plots for now**: PlotSquared is broken on 26.3, and the
    owner may add plots later (§5.6).
- **One server:** survival and creative are separate **worlds on a single Paper
  server**, so chat, the tab list and `/tpa` are shared natively (§3.3).
- **Java and Bedrock, with vanilla clients only:** Java is the main edition.
  Bedrock players join through Geyser + Floodgate. Nobody needs client mods (§5.7).
- **Everything on Minecraft 26.3.**
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
- **Offline (non-Mojang) Java accounts**: not at launch. Java players must use
  Mojang accounts. This may be revisited later as a separate, tested step, using a
  login plugin plus SkinsRestorer (server-side only, so vanilla clients still
  work). It is held back for now because the main free login plugin (LibreLogin)
  hasn't had a release since Jan 2025, and a misconfigured login setup would let
  anyone join under staff names.
- **Plots** (PlotSquared) until it supports 26.3, and only if the owner wants them.
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
the Minecraft server**. The server, database, Geyser and backups stay the same.

| | Phase 1 — now | Phase 2 — later |
|---|---|---|
| Tunnel | **playit.gg agent** container (`playit`) | **frpc** container → **frps** on a new Oracle Cloud instance |
| Address players use | the playit-assigned address (e.g. `xxxx.joinmc.link`) | **`trapaholics.net`** |
| Cloud instance needed | no | yes (Oracle Always-Free; new IP) |
| Real player IPs | playit's PROXY protocol v2 (§5.2) | frp PROXY protocol v2 (§5.2) |
| DNS | not needed (optionally a CNAME/SRV to the playit address) | `trapaholics.net` A record → instance IP |

**Phase 1 → Phase 2 switch-over:** provision the instance and run frps → add the
`frpc` service and its config → test with a temporary subdomain → point the
`trapaholics.net` DNS at the instance → remove the `playit` service and revoke its
secret. Paper's PROXY protocol setting must match whichever tunnel is active.

### 3.2 Target topology (Phase 2)

In Phase 1, the cloud relay box below is replaced by playit.gg's network, and
`frpc` is replaced by the `playit` agent. Everything else is identical.

```
          Java players                         Bedrock players
   trapaholics.net:25565 (TCP)           trapaholics.net:19132 (UDP)
                 │                                   │
                 ▼                                   ▼
        ┌──────────────────────────────────────────────────┐
        │  Cloud relay (Oracle Cloud Free)                  │
        │  frps :7000 (control) · :25565/tcp · :19132/udp   │
        └────────────────────────┬─────────────────────────┘
                                 │ outbound tunnel (initiated from home)
                                 ▼
 ┌──────────────────── Debian home server (Docker) ───────────────────────┐
 │                                                                         │
 │  frpc ──► minecraft:25565 ◄── geyser:19132/udp (Bedrock → Java)         │
 │           (ONE Paper 26.3 server)                                       │
 │           worlds: survival, survival_nether, survival_the_end, creative │
 │                 │                                                       │
 │                 ▼                                                       │
 │           mariadb:3306  (LuckPerms, CoreProtect; internal network only) │
 └─────────────────────────────────────────────────────────────────────────┘
```

**Key idea:** **one Paper server** holds every world. Survival and creative are
separate worlds on that server, so **chat, the tab list, `/tpa` and every other
plugin are shared natively**. No proxy and no network plugins are needed.

### 3.3 Why one server (owner's decision, 2026-11-22)

The owner chose one server over separate survival and creative servers behind a
Velocity proxy.

**Gains:**
- Chat, tab list and `/tpa` are shared with no extra plugins.
- Simpler: one JVM, one set of configs, fewer containers and plugins to keep
  updated each Minecraft version.
- Less RAM overhead than three JVMs.

**Accepted trade-offs, and how they're handled:**
- **Shared main thread.** Paper ticks every world on one main thread, so heavy
  creative activity can lag survival players on this 4-core 2011 CPU.
  - **FastAsyncWorldEdit** is the main fix for edits: it computes changes off the
    main thread and spreads block placement across ticks. It doesn't freeze the
    server the way regular WorldEdit does.
  - Very large edits still cost something: chunk relighting, sending changed
    chunks to nearby players, and memory. So keep **per-rank FAWE limits** (max
    blocks per operation, radius, history), and watch spark.
  - Redstone or entity-heavy builds in creative also tick on the same thread.
    Paper's per-world entity and redstone limits can be tightened for `creative`.
- **Inventory separation.** Creative items must never reach survival. This is
  handled with **Multiverse-Inventories** groups (§5.5); test it before launch.
- **WorldEdit isolation.** FAWE is installed server-wide, so its use is
  restricted with LuckPerms **world contexts** (`world=creative`) (§6).
- **One restart or crash affects everyone.**
- **One version for every world.** That's fine now that plots are dropped.

> If creative lag ever hurts survival badly, the fallback is splitting creative
> into its own Paper server behind a Velocity proxy. PR #2 already contains that
> design, so it can be revived from git history.

---

## 4. Version Target

- **Server software:** one Paper server via the `itzg/minecraft-server` Docker image
  (no proxy; see §3.3), plus a Geyser Standalone container for Bedrock.
- **Minecraft version: 26.3** ✅ **decided** (Option A below). Newest MC release is
  26.3 (2026-09-15); 26.4 is still in snapshots and Paper has no builds for it.
- **Java:** 25 (needed by Paper 26.x; itzg image tag `java25`).

### Compatibility snapshot (researched 2026-11-22)

| Component | Version | Works on 26.3? |
|---|---|---|
| Paper | 26.3 (stable since ~build 175; build 258 latest) | ✅ |
| Velocity | 4.3.1 (clients 1.7.2–26.3) | ✅ (not used in the one-server design) |
| FastAsyncWorldEdit | 2.16.3 (26.1.1–26.3) | ✅ (needs a recent Paper build) |
| WorldEdit | 7.4.6 | ✅ |
| WorldGuard | 7.0.21 | ✅ |
| LuckPerms (Paper + Velocity) | 5.5.x (get it from luckperms.net) | ✅ |
| GriefPrevention | 16.18.8 | ✅ |
| Multiverse-Core | 5.8.2 | ✅ |
| Geyser / Floodgate | 2.12.1 (beta) / 2.2.7 | ✅ |
| **EssentialsX** | 2.22.0 stable = **up to 26.1.2 only** | ⚠️ 26.3 only in dev builds (2.22.1-dev) |
| HuskClaims | 1.5.10 (up to 1.21.7) | ❌ |
| **PlotSquared** | 7.6.1 (supports up to 26.2) | ❌ **open bug #4960** → **dropped for now** (no plots) |
| Geyser (Standalone) / Floodgate | 2.12.1 (beta) / 2.2.7 | ✅ 26.3 (the Geyser *Paper plugin* only declared up to 26.1.2, hence a standalone container) |
| Multiverse-Inventories | — | ❓ verify 26.3 support before building |
| SkinsRestorer | 15.12.6 | ✅ 26.3 (only needed if offline accounts are added later) |
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
  **Decision: everything runs on 26.3, and PlotSquared is dropped for now.** The
  creative server is a single creative world without plots. If plots are wanted
  later, add PlotSquared once it supports 26.3 (its code is GPL-3.0: the SpigotMC
  download is paid, but building from the GitHub source is free).
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
- Runs with `network_mode: "service:minecraft"`, so the tunnel's local target is
  `127.0.0.1:25565`, i.e. the Paper server. In the playit dashboard:
  - the **Minecraft Java** tunnel points at `127.0.0.1:25565`;
  - one **Minecraft Bedrock → Geyser or WaterdogPE** tunnel (experimental; agent
    1.2.0) points at Geyser's fixed IP `172.28.10.10:19133` with Proxy Protocol
    None. It carries only the UDP NetherNet game traffic; playit provides the
    signaling (NXS) and players join the tunnel hostname on port 19132 (§5.7).
- The `SECRET_KEY` lives in `.env` as `PLAYIT_SECRET_KEY`, **not** in
  `docker-compose.yml`. Compose reads it as `${PLAYIT_SECRET_KEY:?}`. The owner
  chose to keep the existing key; it was moved out of the compose file before the
  first git commit and has never been in git history (§12).
- **Real player IPs: use playit's PROXY protocol v2.**
  - In the playit dashboard (https://playit.gg/account/tunnels/ → the Java tunnel
    → **"Proxy Protocol"**), choose **Version 2**.
  - On Paper, enable PROXY protocol (`proxies.proxy-protocol: true` in
    `config/paper-global.yml`).
  - The playit agent must be **0.15.26 or newer**.
  - Without it, every player shows up as `127.x.x.x`, so IP bans and alt detection
    don't work.
  - Once it's on, Paper rejects any connection that doesn't send a PROXY header.
    That includes Geyser, so Geyser must be configured to send PROXY protocol to
    Paper (§5.7).
- playit free tier: shared routing (choosing a region is Premium), 4 ports. Using
  your own domain is a Premium feature. Without Premium, an SRV record at your own
  DNS pointing to the tunnel's hostname and port should still work, but this isn't
  in playit's docs.
- No game port is published on the host, so the only way in is through the tunnel.

#### Phase 2: frp (frps on relay ↔ frpc at home)
- Reuses the approach already started in `mc/` (`frpc.toml`, `snowdreamtech/frpc`).
- `frpc` forwards relay `:25565/tcp` → `minecraft:25565`, and `:19132/udp` →
  `geyser:19132`, on the home Docker network.
- **Real player IPs:** set `transport.proxyProtocolVersion = "v2"` on the frpc
  proxy and `proxies.proxy-protocol: true` in Paper's `paper-global.yml`.
  Once enabled, Paper rejects connections that don't come through frp
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

### 5.4 Minecraft server (one Paper 26.3 server)
- Container **`minecraft`**, itzg/minecraft-server (Java 25), `TYPE=PAPER`,
  `VERSION=26.3`, pinned stable build. Data in `./minecraft`.
- **`online-mode=true`**: Mojang authentication is done by Paper itself; there's
  no proxy. `white-list=false` (26.3 defaults it to true, so set it explicitly).
- **PROXY protocol on** (§5.2). RCON enabled, password from `.env`, not published.
- `MEMORY` ≈ **10G** (§8). Aikar flags.
- Server-wide plugins:

| Purpose | Plugin | Notes |
|---|---|---|
| Permissions | **LuckPerms** (MariaDB storage) | Per-world rules with `world=` contexts (§6) |
| Worlds | **Multiverse-Core 5.x** | Creates and manages the `creative` world; per-world gamemode |
| Inventory separation | **Multiverse-Inventories** (26.3 support to verify; fall back to another per-world inventory plugin or a small custom one) | Keeps survival and creative inventories, ender chests, XP, health/hunger and effects apart (§5.5) |
| Teleports, homes, spawn, utilities | **EssentialsX 2.22.1-dev** (+ EssentialsXSpawn) | `/tpa` and `/tpahere` work across worlds natively. Per-world spawns |
| World editing | **FastAsyncWorldEdit 2.16.x** | **Not** regular WorldEdit. Use is limited by world context (§6) |
| Terrain tools | **FastAsyncVoxelSniper 3.2.5** | Goes through FAWE |
| Protection | **WorldGuard 7.0.21** | Spawn areas in both survival and creative |
| Player claims | **GriefPrevention 16.18.8** | **Survival worlds only**; claims disabled in `creative` |
| Block logging / rollback | **CoreProtect** (26.3 source build, MariaDB) | Undo griefing in any world |
| Bedrock | **Floodgate** (Paper) | Paired with the Geyser container (§5.7) |
| Pre-generation | Chunky | Admin only |
| Performance | spark (built into Paper) | |

### 5.5 Worlds

| World | Gamemode | Difficulty | Who builds | FAWE / VoxelSniper | Claims |
|---|---|---|---|---|---|
| **`survival`** (default/spawn world) + `survival_nether` + `survival_the_end` | survival | **hard** | everyone | admins only | GriefPrevention |
| **`creative`** | creative (forced) | peaceful | everyone, by hand | **builders + admins** | none (CoreProtect for rollback) |

- `level-name=survival`, so the vanilla nether and end become `survival_nether` and
  `survival_the_end`, and portals link only within the survival group.
- `creative` uses **normal generated terrain**. Nether and end portals are disabled
  there, so nobody can walk from creative into the survival nether with creative
  items.
- **Moving between worlds:** simple commands such as `/survival` and `/creative`
  (Multiverse or EssentialsX command aliases, or a tiny custom plugin) that teleport
  to each world's spawn. Players can't `/tpa` from creative into survival while
  holding creative items, because inventories swap on world change (below).
- **Inventory groups (Multiverse-Inventories):**
  - group `survival` = `survival`, `survival_nether`, `survival_the_end`;
  - group `creative` = `creative`;
  - each group has its own inventory, armour, ender chest, XP, health, hunger and
    potion effects. Gamemode is forced per world for everyone, admins included.
  - **Test before launch:** an item taken in creative must never appear in survival
    after `/tpa`, `/survival`, death or relog, and ender chests must stay separate.
- New players spawn in `survival`. Pre-generate the survival world with Chunky
  before launch.
- **Plots later:** once PlotSquared supports 26.3, a plot world can be added as
  another world on this server (64×64 plots, 1 per player, `/plot auto` from the
  centre). The earlier plan is kept in git history.

### 5.6 FAWE limits and lag control
- FAWE limits per rank (`plugins/FastAsyncWorldEdit/config.yml` and LuckPerms
  meta): max blocks changed per operation, max radius, max history, and max
  concurrent operations. Builders get generous but bounded limits; admins get
  higher limits.
- Paper per-world settings for `creative` (in `config/paper-world-defaults.yml`
  plus a `creative`-specific override): tighter entity, redstone and hopper limits,
  so creative builds can't drag down the shared main thread.
- Watch with spark after launch. If creative still hurts survival, see the fallback
  note in §3.3.

### 5.7 Bedrock support (Geyser + Floodgate)
- **Geyser runs as its own container (`geyser`, Geyser Standalone)**, not as a Paper
  plugin. At research time Geyser's Paper plugin only declared support up to
  26.1.2, while the standalone/proxy build tracks the newest Java version (26.3).
  Verify again when implementing.
- Bedrock uses **NetherNet** only (`transport: nethernet`). Signaling is playit's
  **NXS** service (`signaling.mode: nxs`, endpoint `https://nethernet.playit.gg`,
  no `advertise-addresses`, STUN off); Geyser receives the UDP game traffic on
  **19133** from the playit tunnel, and players connect to the tunnel hostname on
  port **19132**. The NXS token is a secret: it lives in `.env` as
  `GEYSER_NXS_TOKEN` and the container entrypoint writes it into the live
  `geyser/config.yml`; the tracked template keeps it empty. Geyser connects to
  `minecraft:25565` as a Java client. **Floodgate** on Paper lets Bedrock players join without a Java account
  and shows their skins to Java players. The Floodgate `key.pem` is shared between
  Geyser and Floodgate; it's a secret and must never be committed.
- Because Paper requires PROXY protocol (§5.2), Geyser must send it to Paper
  (Geyser's `use-haproxy-protocol` option for the remote server). The playit
  Bedrock tunnel runs with Proxy Protocol None, so Bedrock players show the
  playit agent's address (`172.28.10.2`), not their real IP.
- Bedrock players appear with Floodgate's default `.` name prefix, so their names
  can't clash with Java names. They get the same LuckPerms groups.
- Geyser is labelled **beta** on Modrinth; pin a build and test it.

### 5.8 Database (MariaDB)
- One MariaDB container (`mariadb`) on an internal network for **LuckPerms** and
  **CoreProtect**. CoreProtect on MySQL/MariaDB handles a large log better than its
  default SQLite file.
- Not exposed to the host or internet. Credentials in `.env` (gitignored).

---

## 6. Permissions Model (LuckPerms)

Groups are defined once. Because everything is one server, rules are scoped
per **world** with LuckPerms `world=` contexts (`world=survival`,
`world=survival_nether`, `world=survival_the_end`, `world=creative`).

Three groups to start. More may be added later as more plugins are added.

| Group | Inherits | Survival worlds | Creative world | Everywhere |
|---|---|---|---|---|
| `default` | — | GriefPrevention claims | Build by hand. **No FAWE or VoxelSniper** | Chat, `/tpa`, `/tpahere`, `/tpaccept`, `/home` (limited), `/sethome`, `/spawn`, `/survival`, `/creative` |
| `builder` *(name may change)* | default | same as default (**no FAWE**) | **FAWE + FastAsyncVoxelSniper anywhere**, with builder limits | |
| `admin` | — | `*` | `*` | `*` |

- **FAWE and VoxelSniper nodes for `builder` are granted only with
  `world=creative`.** Survival players, builders included, never have them.
  Verify in game that `//set` is refused in survival for a builder.
- No explicit `false` nodes (an exact `false` beats admin's `*`), with one
  deliberate exception: `admin` has `mv.bypass.gamemode.<world>` and
  `mv.bypass.gamemode.*` set **false**, so Multiverse-Core forces admins into
  each world's gamemode like everyone else.
- The `builder` group's name is a placeholder; renaming it later
  (`/lp group builder rename <new>`) is cheap.
- Bedrock players (via Floodgate) get the same groups as Java players.
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
| Survival claims | **GriefPrevention** (survival worlds only) + **WorldGuard** for spawn areas |
| Survival difficulty | **Hard** |
| Creative layout | **Plot world** (FAWE for everyone inside own plot; closest unclaimed plot to the centre) **+ build world** (builders use FAWE anywhere) |
| Ranks | `default` (minimal), `builder` (name TBD; creative FAWE powers), `admin` (`*`). More may come later. |
| World | **Fresh** survival world; the old `prepucio/data/world` is not used |
| Tunnel | **playit.gg now** (Phase 1); frp + new Oracle Cloud instance + `trapaholics.net` later (Phase 2) |
| DNS | Owner controls `trapaholics.net` DNS |
| Access | **Open to anyone** (no whitelist) |
| Plots | ~~64×64, 1 per player~~ → **dropped for now** (see Version) |
| Creative terrain | **Normal terrain** |
| Terrain tools | **FastAsyncVoxelSniper** (works on 26.3); others added later by the owner |
| Real IPs (Phase 1) | playit **PROXY protocol v2** + Paper `proxies.proxy-protocol: true` |
| Version | **Everything on 26.3.** PlotSquared is dropped for now |
| Creative | **One `creative` world** (no plots) on the same server. Everyone builds by hand; builders get FAWE + FastAsyncVoxelSniper; CoreProtect for rollback |
| Server layout | ~~Network plugins over two servers~~ → **ONE Paper 26.3 server** with survival and creative worlds. Chat, tab and `/tpa` are shared natively; no Velocity (§3.3) |
| Editions | **Java + Bedrock** (Geyser + Floodgate), vanilla clients only |
| Accounts | **Mojang accounts only** at launch; offline accounts possibly later as a tested step |
| Delivery | The single-server rebuild (worlds, Bedrock, permissions) goes in a **follow-up PR on top of PR #2** |
| World editing | **FastAsyncWorldEdit only** (not regular WorldEdit), with per-rank limits (§5.6) |
| Host resources | The QEMU VM will scale down; the RAM plan in §8 stands. `jt` is in the `docker` group. |
| Repo | `~/mc` (renamed from `prepucio`), remote `github.com/jaimexu8/trapaholics` |
| Admin alerts | **Discord webhook** to an admin-only log channel in the server's Discord |
| Backups | Every 4 h; Drive after 24 h; **encrypted**; deleted from Drive **30 days** after upload; Drive has 5 TB, so storage isn't a concern |

---

## 8. Resource Plan

Host: **16 GB RAM, Intel Xeon E3-1220** (4 cores / 4 threads, 3.1 GHz base, Sandy
Bridge, 2011). A QEMU VM on the host will scale down.

| Container | Java heap (`MEMORY`) | Real usage (approx.) | Notes |
|---|---|---|---|
| minecraft | 10G | ~12 GB | All worlds on one server |
| geyser | ~512M | ~0.7 GB | Bedrock translation |
| mariadb | — | ~0.4 GB | Small config (`innodb_buffer_pool_size` ~128–256M) |
| playit / frpc | — | negligible | |
| **Total** | | **~13 GB** | Leaves ~3 GB for Debian, Docker and disk cache |

- JVM memory use is higher than the heap setting (roughly +15–25%). Lower the heap
  if the QEMU VM needs more room; don't let the host swap.
- Use Aikar's flags (itzg: `USE_AIKAR_FLAGS=true`).
- **CPU is the tighter limit.** All worlds share one main thread (§3.3). Mitigations:
  - `view-distance=10`, `simulation-distance=8` to start; raise only if spark shows
    headroom. Paper can lower these per world (e.g. for `creative`).
  - Pre-generate the survival world with Chunky before opening.
  - FAWE limits and creative per-world limits (§5.6).
- Disk: only ~5.7 GB free on `/home` now; several TB are coming soon.

---

## 9. Directory Layout (`~/mc`)

```
mc/
├── ARCHITECTURE.md          ← this file
├── DEPLOY.md                ← deploy steps
├── docker-compose.yml       ← minecraft, geyser, mariadb, playit (Phase 1) / frpc (Phase 2)
├── .env                     ← secrets (gitignored): playit secret, DB pw, RCON pw, Discord webhook, (Phase 2) frp token
├── config/                  ← tracked config templates (Paper, plugins, Geyser)
├── scripts/                 ← plugin builds, LuckPerms setup, backup/ (see §11)
├── systemd/                 ← backup timers
├── docs/BACKUPS.md
├── frpc.toml                ← Phase 2 tunnel client config
├── relay/                   ← Phase 2 cloud-side config (frps.toml, setup notes)
├── minecraft/               ← Paper data: all worlds + plugins (gitignored)
├── geyser/                  ← Geyser data incl. Floodgate key (gitignored)
├── mariadb/                 ← MariaDB datadir (gitignored; backed up via dump)
├── data/                    ← OLD prepucio server data (26.2 world), gitignored; delete once live
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

- **All worlds:** `survival`, `survival_nether`, `survival_the_end` and `creative`
  (everything under `./minecraft`).
- **All plugins:** the jars plus each plugin's data and config folders
  (EssentialsX userdata/homes/warps, Multiverse and inventory data, WorldGuard
  regions, claim data, FAWE schematics and history, etc.), plus `./geyser`
  (including the Floodgate key).
- **Permissions and logs:** a **`mysqldump` of MariaDB**, which holds the LuckPerms
  groups, users and tracks, and the CoreProtect block log. Copying the
  database's files while it is running is *not* a safe backup.
- **Server config:** `server.properties`, `bukkit.yml`, `spigot.yml`,
  `config/paper-*.yml`, `ops.json`, `whitelist.json`, ban lists.
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
  password, management secret) is gitignored. The new server takes its RCON
  password from `.env`.
- No game port is published on the host. Only the tunnel (playit, later frpc)
  reaches `minecraft:25565` and `geyser:19132`. MariaDB is on an internal network.
- `online-mode=true` on Paper: every Java player is verified by Mojang. Bedrock
  players are verified by Floodgate (Xbox Live auth through Geyser).
- The Floodgate `key.pem` lets whoever holds it log in as any Bedrock player.
  Keep it out of git; it's inside `./geyser` and `./minecraft/plugins/floodgate`,
  which are gitignored and in the backups.
- The server is **open to anyone** (no whitelist), so protection comes from:
  GriefPrevention claims in survival; WorldGuard at both spawns; CoreProtect
  rollback everywhere; Multiverse-Inventories keeping creative items out of
  survival; FAWE limited to builders in `creative`; and minimal `default`
  permissions. Consider a basic anti-bot / connection rate limit later.
- Phase 2: frp auth token required; relay control port firewalled.
- Backups contain secrets (`.env`, the Floodgate key) and player data. Local
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
- **`playit` service** → kept as the Phase 1 tunnel, but now attached to the Paper
  server (`network_mode: "service:minecraft"`) with its secret moved to `.env` and
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
- `ports: 25565:25565` on the backend → removed; only the tunnel reaches the server, and
  only via the tunnel.
- Single `data/` dir → replaced by `minecraft/` (all worlds), `geyser/` and `mariadb/`.

---

## 14. Roadmap

**Phase 1 — build on playit (now)**
1. ~~Confirm plugin versions~~ (done, §4). ~~Rename `prepucio/` → `~/mc`, git
   remote, secret moved to `.env`~~ (done).
2. Delete the old `data/` once the new setup is live (it frees ~280 MB).
3. Restructure `~/mc` into the layout in §9. Write the new
   `docker-compose.yml` (minecraft, geyser, mariadb, playit) and `.env`.
4. Paper + survival world first: verify Java players can join through the playit address.
5. Add MariaDB + LuckPerms (network-wide). Create the `default`, `builder` and
   `admin` groups.
6. Survival plugins: EssentialsX-dev, GriefPrevention, WorldGuard at spawn.
   Pre-generate the world.
7. PR #2 first built two servers behind Velocity (creative on 26.2 with plots).
   The follow-up PR rebuilds this as **one Paper 26.3 server**: survival and
   creative worlds, Multiverse-Inventories separation, builder-only FAWE in
   `creative`, and Bedrock via Geyser + Floodgate (§3.3, §5.4–5.7).
8. Backups (§11): `rclone` with the `gdrive` and `gdrive-crypt` remotes (save the
   crypt password off the server), `backup.sh` / `offload.sh` / `prune-drive.sh`,
   and systemd timers. Test the low-disk-space path, the 30-day pruning, and a full
   restore from Drive.
9. Open launch (no whitelist; `white-list=false` set explicitly).

**Phase 2 — switch to `trapaholics.net`**

10. Provision a new Oracle Cloud Always-Free instance. Install frps; set up the
    firewall (VCN security list + instance firewall) and the auth token.
11. Add the `frpc` service. Test through a temporary subdomain.
12. Point the `trapaholics.net` A record at the instance. Set Paper's
    PROXY protocol setting to match frp. Remove the `playit` service and revoke its key.
