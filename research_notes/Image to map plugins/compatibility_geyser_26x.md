# Image-to-map plugin compatibility (Paper 26.3 + Geyser/Floodgate)

Stack context for ranking: Paper 26.3-258, Java 25, Geyser Standalone + Floodgate, NOT Folia, plugin-only. Notes below are cross-cutting signals only - not a ranked recommendation list.

## Do Geyser/Floodgate render custom filled maps / map IDs / item-frame maps correctly for Bedrock in 2026? Known limitations?

### Takeaway
Geyser does translate Java map packets to Bedrock and historically fixed blank item-frame maps, but Bedrock map handling remains weak: dense or animated custom maps commonly disconnect, OOM, or incapacitate Bedrock clients. Floodgate is auth/identity only and does not fix map rendering.

### Cited Findings
- Geyser currently supports Minecraft Bedrock 26.40-26.65 and Minecraft Java 26.3 (aligns with this stack's Java version). - [Geyser supported versions](https://geysermc.org/wiki/geyser/supported-versions/)
- Historical bug: maps in item frames were invisible for Bedrock because map data/packets were not sent; resolved in Geyser PR era around May 2020 (#423). - [Geyser #385](https://github.com/GeyserMC/Geyser/issues/385)
- Geyser still implements `ClientboundMapItemDataPacket` translation (map ID, locked flag, color bytes via palette, decorations). - [JavaMapItemDataTranslator.java](https://github.com/GeyserMC/Geyser/blob/64bb3993/core/src/main/java/org/geysermc/geyser/translator/protocol/java/level/JavaMapItemDataTranslator.java)
- Geyser maintainer (onebeastchris) on ImageFrame maps (Jul-Oct 2026): Bedrock's handling of maps (requesting them from the server, etc.) is "frankly speaking atrocious"; continuous/video-like map updates likely remain infeasible; labeled as likely a can't-fix. - [Geyser #6569](https://github.com/GeyserMC/Geyser/issues/6569)
- Open report (Jul 2026, still open Oct 2026): ImageFrame maps left Bedrock players "incapacitated" (world not loading, items unusable) on Paper 1.21.11 + Geyser 2.10.1 + Floodgate; reporter said any ImageFrame map (not only GIFs) caused it. - [Geyser #6569](https://github.com/GeyserMC/Geyser/issues/6569)
- ImageFrame author (LOOHP): regular maps are "sent like regular maps"; GIF preference toggle may help animations but reporter said static maps still broke Bedrock; LOOHP asked for Geyser-side explanation. - [Geyser #6569](https://github.com/GeyserMC/Geyser/issues/6569)
- Many ImageFrames in render distance disconnect Bedrock with `End of stream` on Velocity+Geyser (Jul 2025, open); removing ImageFrame from those chunks fixed it. - [ImageFrame #123](https://github.com/LOOHP/ImageFrame/issues/123)
- Animated ImageFrame maps previously caused Geyser OOM / proxy overload when translating map packets (2024 reports). - [ImageFrame #45](https://github.com/LOOHP/ImageFrame/issues/45)
- ImageFrame ships Geyser-specific config: `Hooks.Geyser.DisableSmoothAnimationForBedrockPlayers` and `MapPacketSendingRateLimit` to mitigate Bedrock/network pain. - [ImageFrame config.yml](https://github.com/LOOHP/ImageFrame/blob/main/common/src/main/resources/config.yml)
- Bedrock item frames are block entities (not Java entities); co-located signs+item frames can fail to show on Bedrock as a client limitation (Apr 2026). - [Geyser #6279](https://github.com/GeyserMC/Geyser/issues/6279)
- Floodgate is a hybrid-auth companion to Geyser (Bedrock accounts joining without Java accounts); docs do not claim map rendering features. - [Floodgate wiki](https://github.com/GeyserMC/Geyser/wiki/Floodgate/f4fa39c2b1f9517af7da0c7729b1ad709a688a45)

### Inferences
- For this stack, treat "maps work on Java" as necessary but not sufficient for Bedrock: volume (tile count in view), animation frequency, and Geyser translation cost dominate failure modes.
- Prefer plugins that can throttle or disable map packet spam for Bedrock (or avoid animated maps entirely) over plugins that only claim Paper 26.3 support.
- Floodgate presence is unrelated to whether custom map pixels appear; it only affects Bedrock identity/API hooks some plugins may use.

### Gaps
- No official Geyser wiki page found that documents "custom plugin maps" as fully supported or lists a hard tile-count limit (unverified beyond issue comments).
- No independent 2026 confirmation that static vanilla-palette maps in item frames always render correctly at small scale on Bedrock 26.x under Geyser Standalone specifically (most recent severe reports used Geyser-Spigot or Velocity+Geyser).
- Whether Standalone vs Spigot Geyser placement changes map failure rates is unverified.

## Did Minecraft/Paper 26.x change map items, map IDs, or related APIs in ways that break older image-map plugins?

### Takeaway
Minecraft 26.3 made material map-item changes (explorer maps as distinct items; removal of `minecraft:map_color`) and Paper's MapMeta API still deprecates fragile `setMapId` usage. Older plugins that assume explorer maps are renamed filled maps, rely on map color tint, or hard-pin old minor versions can break; core `MapView`/`MapRenderer` APIs still exist on Paper 26.3.

### Cited Findings
- Paper 26.3 API still exposes `Server.createMap(World)`, `Server.getMap(int id)`, `MapView`, and `MapRenderer` for plugin map drawing. - [Paper MapView 26.3](https://jd.papermc.io/paper/26.3/org/bukkit/map/MapView.html); [Paper MapRenderer 26.3](https://jd.papermc.io/paper/26.3/org/bukkit/map/MapRenderer.html); [Paper Server 26.3](https://jd.papermc.io/paper/26.3/org/bukkit/Server.html)
- Paper `MapMeta.setMapId(int)` remains deprecated since 1.13.2 as poor API (invalid IDs can generate a different map); docs push `setMapView`/`getMapView`. - [Paper MapMeta 26.3](https://jd.papermc.io/paper/26.3/org/bukkit/inventory/meta/MapMeta.html)
- Paper `MapMeta` color APIs (`hasColor`/`getColor`/`setColor`) are deprecated with note "maps no longer have a color". - [Paper MapMeta 26.3](https://jd.papermc.io/paper/26.3/org/bukkit/inventory/meta/MapMeta.html)
- Minecraft Java 26.3 Snapshot 7: Explorer Maps are now their own items (not renamed Filled Maps), each with its own icon; Map/Empty Map icons updated; existing explorer maps convert on load. - [26.3 Snapshot 7 feedback](https://feedback.minecraft.net/hc/en-us/articles/47877771669133-Minecraft-Java-Edition-26-3-Snapshot-7)
- Same snapshot: removed data component `minecraft:map_color` (maps no longer drawn as tinted overlay); existing maps strip the component on load; resource-pack tint source `minecraft:map_color` removed. - [26.3 Snapshot 7 feedback](https://feedback.minecraft.net/hc/en-us/articles/47877771669133-Minecraft-Java-Edition-26-3-Snapshot-7)
- Same snapshot: `minecraft:exploration_map` loot function no longer changes item type (no longer map -> filled_map); only adds map data; if no structure found, item may lack `minecraft:map_id`. - [26.3 Snapshot 7 feedback](https://feedback.minecraft.net/hc/en-us/articles/47877771669133-Minecraft-Java-Edition-26-3-Snapshot-7)
- Same snapshot: only items in `#minecraft:extendable_maps` can be zoomed; explorer/buried treasure maps can no longer be zoomed out. - [26.3 Snapshot 7 feedback](https://feedback.minecraft.net/hc/en-us/articles/47877771669133-Minecraft-Java-Edition-26-3-Snapshot-7)
- Custom Images author noted Paper-specific oddity (Apr 2026 update notes): picking a map from an image in creative can show blank until restart on Paper (works immediately on Spigot). - [Custom Images update](https://www.spigotmc.org/resources/custom-images.53036/update?update=636739)
- BKCommonLib update notes for 26.3 mention breaking API changes and "new APIs for the new map item types (map displays)" (library ecosystem signal that map item typing changed). - [BKCommonLib updates](https://www.spigotmc.org/resources/bkcommonlib.39590/updates)
- Upstream ImageOnMap 4.2.2 publicly limited to Minecraft 1.17-1.18; Spigot review (Jan 2026) reported not working on Paper 1.21.5+. - [ImageOnMap Spigot](https://www.spigotmc.org/resources/imageonmap.26585/); [ImageOnMap releases](https://github.com/zDevelopers/ImageOnMap/releases)

### Inferences
- For image-to-map plugins that only create locked/virtual filled maps via Bukkit MapView, 26.3 explorer-map item splits may not matter unless the plugin interacts with cartography/explorer loot.
- Plugins that tint inventory map icons via map color, or assume exploration_map conversion semantics, need 26.3 updates.
- "Works on latest Paper" claims from late 2026 are a stronger ranking signal than 1.21-era jars; abandoned 1.17-1.18 plugins should be treated as incompatible for this stack.

### Gaps
- No Paper digests/changelog entry found that documents a breaking change to map ID allocation integers themselves for plugin MapViews (unverified).
- Exact Paper 26.3-258 vs 26.3 build used in plugin CI is rarely stated; "supports 26.3" usually means tested on some 26.3 build, not build 258 specifically.
- Whether packet-level ClientboundMapItemDataPacket layout changed in 26.x beyond prior versions was not verified in protocol docs during this pass.

## Which major plugins publicly list support for 26.x / latest Paper (late 2026)?

### Takeaway
Public 26.x / latest Paper claims (as of sources fetched late 2026): ImageFrame yes (26.3); Images/Custom Images yes (26.3); SydMontague ImageMaps yes (26.x); SushiImage (Map to Image) yes (tested through 26.3); Image2Map mod yes (26.3 Fabric, not Paper); MapImage lists through 26.2 (not 26.3); DrMap lists through 1.21.x only; original ImageOnMap no (use unofficial ImageOnMapReborn for 26.3 if considering that lineage).

### Cited Findings
- **ImageFrame** (LOOHP): Hangar pinned version 2026.1.5 for `1.16–26.3`; Modrinth version 2026.1.5 changelog "Support for Minecraft 26.3"; Spigot lists Minecraft 26.3 (2026.1.5) Sep 18, 2026; Modrinth platforms include Paper/Purpur/Spigot/Folia. - [Hangar ImageFrame](https://hangar.papermc.io/LOOHP/ImageFrame); [Modrinth ImageFrame 2026.1.5](https://modrinth.com/mod/imageframe/version/dKkWOwRr); [Spigot ImageFrame](https://www.spigotmc.org/resources/imageframe-load-images-on-maps-item-frames-support-gifs-map-markers-survival-friendly.106031/)
- **ImageOnMap** (zDevelopers): latest release 4.2.2 only compatible with Minecraft 1.17 to 1.18.1 - does **not** claim 26.x. - [ImageOnMap releases](https://github.com/zDevelopers/ImageOnMap/releases); [Spigot ImageOnMap](https://www.spigotmc.org/resources/imageonmap.26585/)
- **ImageOnMapReborn** (unofficial successor, Optiblur): README claims Paper/Purpur/Spigot 1.20.1+ tested on Paper 1.20.1, 1.21.11, and **26.3**; Java 25+ for 26.x; Folia not supported. - [ImageOnMapReborn README](https://github.com/Optiblur/ImageOnMapReborn)
- **DrMap**: Modrinth 1.1.0 (Jan 2, 2026) game versions **1.17–1.21.11** on Paper/Purpur/Spigot - **no 26.x** listed; Spigot page last update Jun 26, 2025 (1.0.10) with tested majors through 1.21. - [DrMap 1.1.0](https://modrinth.com/plugin/drmap/version/1.1.0); [Spigot DrMap](https://www.spigotmc.org/resources/drmap.87368/)
- **ImageMaps (SydMontague)**: GitHub release 1.0.12 notes "proper 26.x compatibility". - [SydMontague/ImageMaps releases](https://github.com/SydMontague/ImageMaps/releases)
- **ImageMaps (RealDoggoHitman / Modrinth)**: Modrinth project compatibility lists 26.3 / Folia / Paper; version 1.0 file page also shows older 1.20–1.21.4 loaders (listing may be inflated or multi-tagged - treat carefully). - [Modrinth ImageMaps](https://modrinth.com/mod/imagemaps); [ImageMaps 1.0](https://modrinth.com/plugin/imagemaps/version/1.0)
- **Images / Custom Images** (Andavin): Spigot update "Update for 26.3" version 2.5.12 released Oct 13, 2026; prior updates for 26.2 and 26.1.2. - [Custom Images updates](https://www.spigotmc.org/resources/custom-images.53036/updates)
- **MapImages / MapImage** (tommustbe12com): Modrinth lists Minecraft **26.2** 26.1.x 1.21.x 1.20.x on Bukkit/Paper/Spigot - **no explicit 26.3** on the project page at fetch time. - [Modrinth MapImage](https://modrinth.com/mod/mapimage)
- **Image2Map** (Patbox): Fabric/Quilt mod with Modrinth compatibility including **26.3**; author FAQ: will not port to Forge/Bukkit/Paper ("no lol"). Out of scope for plugin-only Paper. - [Modrinth Image2Map](https://modrinth.com/project/13RpG7dA); [Patbox/Image2Map](https://github.com/patbox/image2map/)
- **SushiImage** (Spigot resource "Map to Image", permission `sushiimage.admin`): tested majors include 26.1, 26.2, **26.3**; update 0.5.1 "26.3 update" Oct 15, 2026. Title still says 1.20.6-26.2 but page body lists 26.3 tested. - [Map to Image / SushiImage](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/)

### Inferences
- Strongest public late-2026 Paper 26.3 claims among listed names: ImageFrame, Custom Images (Images), SushiImage, SydMontague ImageMaps; ImageOnMapReborn if accepting unofficial successor.
- DrMap and original ImageOnMap should rank down for this exact stack unless independent testing proves otherwise.
- Image2Map is a Fabric server mod, not a Paper plugin - exclude for plugin-only constraint despite excellent 26.3 currency.

### Gaps
- Hangar/Modrinth "compatibility" tags are self-declared; runtime verification on Paper 26.3-258 was not performed.
- Naming collisions: multiple "ImageMaps" / "MapImage" projects; confirm jar author before ranking.
- Whether MapImage has a quieter 26.3 build not reflected on Modrinth is unknown.

## Folia support claims (maintenance-quality signal; this server is NOT Folia)

### Takeaway
ImageFrame and some ImageMaps listings claim Folia; ImageOnMapReborn and MapImage do not; Custom Images Folia request was closed without a public affirmation; Folia claims are a maintenance signal only and sometimes still need config workarounds.

### Cited Findings
- ImageFrame Hangar page lists **Supports Folia**; Modrinth platforms include Folia. - [Hangar ImageFrame](https://hangar.papermc.io/LOOHP/ImageFrame); [Modrinth ImageFrame](https://modrinth.com/project/imageframe)
- ImageFrame Folia users still hit region-thread errors with animated maps unless `HandleAnimatedMapsOnMainThread: true` (May 2025 issue, resolved by config). - [ImageFrame #112](https://github.com/LOOHP/ImageFrame/issues/112)
- Modrinth ImageMaps (RealDoggoHitman) lists Folia + Paper. - [Modrinth ImageMaps](https://modrinth.com/mod/imagemaps)
- ImageOnMapReborn README: **Folia is not supported**. - [ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- MapImage Modrinth platforms: Bukkit, Paper, Spigot - **no Folia**. - [Modrinth MapImage](https://modrinth.com/mod/mapimage)
- DrMap Modrinth platforms: Paper, Purpur, Spigot - **no Folia**. - [DrMap 1.1.0](https://modrinth.com/plugin/drmap/version/1.1.0)
- Custom Images / Images: GitHub issue requesting Folia support (#175, Apr 2026) was closed by author with no implementation detail in the issue body. - [Images #175](https://github.com/Andavin/Images/issues/175)
- Image2Map: Fabric/Quilt only - Folia N/A. - [Modrinth Image2Map](https://modrinth.com/project/13RpG7dA)
- SushiImage Spigot page does not advertise Folia in the fetched description. - [Map to Image](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/)
- SydMontague ImageMaps: no Folia claim found on the GitHub releases page in this pass (unverified beyond release notes). - [SydMontague releases](https://github.com/SydMontague/ImageMaps/releases)

### Inferences
- Folia badge on ImageFrame correlates with active multi-platform maintenance, but does not guarantee zero Folia bugs without config.
- Absence of Folia support is weak negative signal for non-Folia servers; stronger negative is absence of any 26.x update.

### Gaps
- No systematic Folia CI badges verified for these plugins beyond storefront tags.
- Whether SydMontague ImageMaps or SushiImage run on Folia is unknown from public pages checked.

## Security concerns common to URL-fetch image map plugins (SSRF, large downloads)

### Takeaway
URL-based image maps are a classic server-side request/download risk: SSRF to internal networks, path traversal to local files, unbounded download size/time, and malicious GIF memory bombs. Prefer plugins with hostname allowlists, private-address blocking, size/time/pixel caps, and restricted URL permissions.

### Cited Findings
- ImageOnMap 4.2.0 added `images-hostnames-whitelist` (empty/absent = allow all) plus `imageonmap.bypasswhitelist` permission. - [ImageOnMap 4.2.0 notes](https://github.com/zDevelopers/ImageOnMap/releases); [Bukkit ImageOnMap](https://dev.bukkit.org/projects/imageonmap)
- ImageOnMapReborn documents stronger defaults/options: `download.block-private-addresses: true`, `download.max-size-mb: 25`, timeouts, `max-image-pixels`, GIF frame/memory hardening in 1.2.1; whitelist still present (`images-hostnames-whitelist`). - [ImageOnMapReborn README](https://github.com/Optiblur/ImageOnMapReborn)
- Custom Images 2.5.10 fixed path traversal outside plugin folder; blocked URLs looping back to same server / local machine webservers; disabled `file:` URLs; URL create now requires `images.command.create.url`. - [Custom Images 2.5.10](https://www.spigotmc.org/resources/custom-images.53036/update?update=605199)
- SydMontague ImageMaps 1.0.6 fixed download accepting any content if server claimed image Content-Type (could deliver arbitrary data including executables to disk; risk described as low without further exploit). - [SydMontague ImageMaps 1.0.6](https://github.com/SydMontague/ImageMaps/releases)
- Mapify (related pattern, not in core list) documents domain whitelist, HTTPS-only toggle, and FAQ that open domains can allow malicious downloads onto the server. - [funnyboy-roks/mapify](https://github.com/funnyboy-roks/mapify/)
- RuinedImage (adjacent Paper 26.x plugin) markets HTTPS-only downloads and private-network URL protection by default (shows security is a known product differentiator in 2026). - [RuinedImage Modrinth](https://modrinth.com/plugin/ruinedimage)
- ImageFrame loads images from URLs and has `MaxProcessingTime` (default 60s) rejecting slow loads; also player creation limits and max frame size options (DoS/resource controls, not full SSRF docs). - [ImageFrame config.yml](https://github.com/LOOHP/ImageFrame/blob/main/common/src/main/resources/config.yml); [Hangar ImageFrame](https://hangar.papermc.io/LOOHP/ImageFrame)
- SushiImage added `max-map-tiles` and `max-render-distance-blocks` safety guards to prevent accidental huge map walls / crashes. - [SushiImage updates](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/updates)
- MapImage requires server internet access on every restart to re-fetch URLs (persistent URL dependency increases exposure window). - [Modrinth MapImage](https://modrinth.com/mod/mapimage)

### Inferences
- For player-facing URL commands, treat missing private-IP blocking + missing size caps as recommendation blockers regardless of 26.x support.
- Admin-only URL fetch reduces abuse surface but does not remove SSRF if an admin token/account is compromised or a malicious URL is pasted.
- Prefer local-folder image workflows (upload then place) or strict allowlists for production Geyser servers.

### Gaps
- Full security audit of ImageFrame/DrMap/SushiImage HTTP clients (redirect following to link-local, DNS rebinding) was not performed.
- Default configs for ImageFrame hostname restrictions (if any beyond processing time) were not exhaustively compared to ImageOnMapReborn.
- No CVE IDs found specifically for these plugins during this pass.

## Cross-cutting ranking signals for THIS stack (summary for synthesizer)

### Takeaway
Paper 26.3 currency is table-stakes; Geyser Bedrock map fragility is the differentiator that can make a "fully supported" plugin unusable; Folia badges are secondary maintenance signals; URL SSRF/size controls should veto insecure candidates.

### Cited Findings
- Geyser Java target is 26.3 - version alignment with Paper 26.3 is good for this stack. - [Geyser supported versions](https://geysermc.org/wiki/geyser/supported-versions/)
- Dense/animated custom maps repeatedly harm Bedrock via Geyser even when Java is fine. - [Geyser #6569](https://github.com/GeyserMC/Geyser/issues/6569); [ImageFrame #123](https://github.com/LOOHP/ImageFrame/issues/123); [ImageFrame #45](https://github.com/LOOHP/ImageFrame/issues/45)
- Minecraft 26.3 removed map_color and split explorer map item types - older map plugins may need updates beyond "still compiles". - [26.3 Snapshot 7](https://feedback.minecraft.net/hc/en-us/articles/47877771669133-Minecraft-Java-Edition-26-3-Snapshot-7)

### Inferences
- When ranking for Paper 26.3 + Geyser Standalone + Floodgate: (1) explicit 26.3 Paper jar, (2) Bedrock mitigations or low packet volume design, (3) URL security controls, (4) Folia/maintenance signals, (5) exclude Fabric-only Image2Map for plugin-only.
- Unverified runtime on build 258 and Standalone Geyser should be flagged in any final recommendation.

### Gaps
- Head-to-head Bedrock testing of Custom Images vs ImageFrame vs SydMontague ImageMaps vs SushiImage on Geyser Standalone was not done in this research pass.
