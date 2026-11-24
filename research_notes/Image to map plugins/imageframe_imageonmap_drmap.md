# Image URL to map plugins: ImageFrame, ImageOnMap, DrMap

Research date context: late 2026 (today's date in session: 2026-11-23). Target: Paper API / Minecraft **26.3**, Geyser/Floodgate, plugin-only, not Folia. Sources fetched from Modrinth, Hangar, SpigotMC, GitHub, and GitHub API; claims without a source are marked as Gaps or Unverified.

---

## Supported platforms and latest Minecraft version

### Takeaway
ImageFrame officially supports Paper/Spigot/Purpur/**Folia** through **Minecraft 26.3**. Upstream ImageOnMap stopped at 1.17–1.18; the maintained successor ImageOnMapReborn supports Paper/Purpur/Spigot through **26.3** (explicitly not Folia). DrMap’s published listings stop at **1.21.x** (Modrinth through 1.21.11); a Discord-attached build for 26.1+ was mentioned by the author but is not a normal release page.

### Cited Findings
- ImageFrame Modrinth compatibility: Minecraft Java **26.3, 26.2, 26.1.x, 1.21.x … 1.16.x, 1.13.x**; platforms **Folia, Paper, Purpur, Spigot**. — [Modrinth ImageFrame](https://modrinth.com/project/imageframe); [Modrinth API](https://api.modrinth.com/v2/project/imageframe)
- Hangar ImageFrame pinned version **2026.1.5** lists platforms **Paper 1.16–26.3**; changelog: “Support for Minecraft 26.3”; published **2026-09-18**. — [Hangar 2026.1.5](https://hangar.papermc.io/LOOHP/ImageFrame/versions/2026.1.5); [Hangar project](https://hangar.papermc.io/LOOHP/ImageFrame)
- Hangar API `supportedPlatforms.PAPER` includes **26.1, 26.1.1, 26.1.2, 26.2, 26.3** and earlier 1.16–1.21.x versions; project tag **SUPPORTS_FOLIA**. — [Hangar API](https://hangar.papermc.io/api/v1/projects/LOOHP/ImageFrame)
- ImageFrame still documents both **year-based 26.x** and legacy **1.21.x** labels on the same project pages. — [Modrinth ImageFrame](https://modrinth.com/project/imageframe)
- Upstream ImageOnMap latest release **4.2.2** (2022-01-15) is “only compatible with Minecraft **1.17 to 1.18.1**”; Spigot native major MC version **1.18**. — [GitHub releases](https://github.com/zDevelopers/ImageOnMap/releases); [SpigotMC ImageOnMap](https://www.spigotmc.org/resources/imageonmap.26585/)
- ImageOnMapReborn (Optiblur): **Paper / Purpur / Spigot**; **1.20.1 and newer**, tested on Paper **1.20.1, 1.21.11 and 26.3**; **Folia is not supported**. Spigot resource lists Tested Major MC Versions including **26.3**. — [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn); [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/)
- DrMap Modrinth: platforms **Paper, Purpur, Spigot**; game versions **1.17–1.21.11** only (no 26.x in API `game_versions`). — [Modrinth DrMap](https://modrinth.com/plugin/drmap); [Modrinth API](https://api.modrinth.com/v2/project/drmap)
- DrMap Spigot resource **1.0.10**: Native Major MC Version **1.17**; tested through **1.21**; update note “Updated to work on **1.21.6**” (2025-06-26). — [SpigotMC DrMap](https://www.spigotmc.org/resources/drmap.87368/); [Spigot discussion update](https://www.spigotmc.org/threads/drmap.480868/)
- Author post on Spigot discussion (2026-06-04): “For **26.1+** try [Discord CDN attachment…]”. — [Spigot DrMap thread](https://www.spigotmc.org/threads/drmap.480868/)
- Geyser (context) currently supports Bedrock **26.40–26.65** and Java **26.3**. — [Geyser supported versions](https://geysermc.org/wiki/geyser/supported-versions/)

### Inferences
- For a Paper **26.3** server today, ImageFrame and ImageOnMapReborn are the only ones with clear first-party “works on 26.3” documentation; DrMap requires verifying the Discord/CDN build or testing 1.1.0 yourself.
- Versioning transition: ImageFrame adopted **2026.x** plugin versioning and lists **26.x** MC versions; ImageOnMapReborn and DrMap still lean on **1.20/1.21** labels while Reborn also claims **26.x**.

### Gaps
- Exact DrMap Discord CDN jar version, changelog, and whether it supports **26.3** (vs only 26.1) were not fetchable from a durable release page (CDN link truncated in search snippets).
- No Hangar listing for DrMap or ImageOnMap/ImageOnMapReborn was found in this pass.
- Fabric/Quilt: ImageFrame server plugin is Bukkit-family only; ImageFrame **Client** mod is Fabric/Quilt (client-side HD viewing) - not a server alternative. — [ImageFrame Client](https://modrinth.com/project/7JSyQd4e)

---

## Last release date and maintenance status

### Takeaway
ImageFrame is actively maintained (release **2026.1.5**, Sep 2026; GitHub push Oct 2026). Upstream ImageOnMap is effectively abandoned for modern MC (last release Jan 2022; last push Dec 2024). ImageOnMapReborn is newly active (created Oct 2026; Spigot **1.2.2** on 2026-11-20). DrMap sees intermittent updates (Modrinth **1.1.0** 2026-01-02; Spigot still shows **1.0.10** 2025-06-26) and an informal 26.1+ Discord build in Jun 2026.

### Cited Findings
- ImageFrame Modrinth/Hangar latest: **2026.1.5**, updated **2026-09-18**; Modrinth project `updated` **2026-09-18**. — [Modrinth version](https://modrinth.com/mod/imageframe/version/dKkWOwRr); [Hangar 2026.1.5](https://hangar.papermc.io/LOOHP/ImageFrame/versions/2026.1.5); [Modrinth API](https://api.modrinth.com/v2/project/imageframe)
- ImageFrame GitHub: `pushed_at` **2026-10-29**, `updated_at` **2026-11-06**, `archived: false`, open issues **68**, stars **107**. — [GitHub API LOOHP/ImageFrame](https://api.github.com/repos/LOOHP/ImageFrame)
- ImageOnMap Spigot last update **2022-01-15** (v4.2.2); CurseForge/Bukkit last released file **Jan 2022**. — [SpigotMC ImageOnMap](https://www.spigotmc.org/resources/imageonmap.26585/); [CurseForge ImageOnMap](https://www.curseforge.com/minecraft/bukkit-plugins/imageonmap/gallery)
- ImageOnMap GitHub: `pushed_at` **2024-12-31**, open issues **105**, stars **192**, default branch `indev`, not archived. — [GitHub API zDevelopers/ImageOnMap](https://api.github.com/repos/zDevelopers/ImageOnMap)
- ImageOnMapReborn README: “ImageOnMap … has not been updated since **2021**” (successor framing). — [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- ImageOnMapReborn Spigot: first release **2026-10-19**; last update **2026-11-20** (v**1.2.2**); GitHub `pushed_at` **2026-11-22**, open issues **0**, stars **5**. — [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/); [GitHub API Optiblur/ImageOnMapReborn](https://api.github.com/repos/Optiblur/ImageOnMapReborn)
- Other ImageOnMap forks exist (community/private): e.g. whimc/QRF-ImageOnMap commit “Update ImageOnMap to 5.1.1 for Paper **1.21.11**” (2026-06-10); StrawberryMaster/ImageOnMap (1.21 experimental); turu64/ImageOnMap (MOFUCRAFT hard-fork, 1.21.4+). — [whimc commit](https://github.com/whimc/QRF-ImageOnMap/commit/9a93fd580970737778510670f3efb3514d407c8a); [StrawberryMaster](https://github.com/StrawberryMaster/ImageOnMap); [turu64](https://github.com/turu64/ImageOnMap)
- DrMap Spigot last update **2025-06-26** (1.0.10); Modrinth last update **2026-01-02** (1.1.0); GitHub `pushed_at` **2026-06-05**, open issues **0**, stars **3**. — [SpigotMC DrMap](https://www.spigotmc.org/resources/drmap.87368/); [Modrinth API](https://api.modrinth.com/v2/project/drmap); [GitHub API akdukaan/DrMap](https://api.github.com/repos/akdukaan/DrMap)

### Inferences
- ImageFrame is the clearest “currently maintained + 26.3 listed” option among the three names.
- For “ImageOnMap” as a product category in 2026, treat **ImageOnMapReborn** as the practical maintained line; treat **zDevelopers/ImageOnMap** as legacy/historical.
- DrMap maintenance is lighter and distribution is fragmented (Spigot vs Modrinth version skew; 26.x via Discord).

### Gaps
- Whether zDevelopers intends a 5.0 / 26.x official release remains unverified (5.0 was mentioned historically on older release notes; no 2025–2026 official release found).
- SpigotMC total download count for ImageFrame not captured in this pass (Modrinth/Hangar numbers below).

---

## Command syntax for creating maps from an image URL (size options)

### Takeaway
ImageFrame uses `/imageframe create <name> <url> <width> <height>` (plus `selection` / `combined` modes). ImageOnMap / ImageOnMapReborn use `/tomap <url> [resize|…] [width height]`. DrMap uses `/drmap create <url> height:N width:M` while holding an empty map.

### Cited Findings
**ImageFrame**
- `/imageframe create <name> <url> <width> <height>` - create image map (gives map items).
- `/imageframe create <name> <url> selection` - create and place into selected item frames.
- `/imageframe create <name> <url> <width> <height> combined` - create Combined ImageMap item.
- Alias style documented: `/if get …`. — [Hangar ImageFrame commands](https://hangar.papermc.io/LOOHP/ImageFrame); [Modrinth ImageFrame](https://modrinth.com/project/imageframe)

**ImageOnMap (upstream)**
- `/tomap <URL>` - render and give map(s); PNG/JPEG/GIF.
- `resize` after URL for single map; `resize <width> <height>` for multi-map (example `/tomap url resize 2 4`).
- Alternatives: `resize-stretched`, `resize-covered`.
- Permission: `imageonmap.new` (legacy `imageonmap.userender`). — [GitHub README](https://github.com/zDevelopers/ImageOnMap); [SpigotMC ImageOnMap](https://www.spigotmc.org/resources/imageonmap.26585/)

**ImageOnMapReborn**
- `/tomap <link|file:name> [resize|resize-stretched|resize-covered] [width height] [dither|nodither]`
- No mode: keep native size, cut into as many maps as needed (centered).
- `resize` = one map; `resize 4 3` = 4×3 poster (`4x3` / `4*3` also accepted).
- `/maptool new …` same as `/tomap`. — [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn); [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/)

**DrMap**
- `/drmap create <url> [params]` example: `/drmap create https://i.imgur.com/URVT1ul.png height:2 width:3`
- Params: **height**, **width**, **background** color.
- Must hold empty map when creating (wiki/FAQ pattern). — [Modrinth DrMap](https://modrinth.com/plugin/drmap); [SpigotMC DrMap](https://www.spigotmc.org/resources/drmap.87368/); [MineLacs wiki example](https://minelacs.gitbook.io/minelacs-wiki/sezon/ml-vanila-2/izobrazheniya-na-mapakh)

### Inferences
- All three support single-frame and WxH multi-frame sizing via command parameters.
- ImageFrame uniquely requires a **name** at create time; the others name/manage afterward (GUI / maptool).

### Gaps
- Exact meaning of ImageFrame `<width> <height>` units (maps vs pixels) is documented as multi-map span on Hangar but the Hangar page does not spell “maps × maps” in one explicit sentence; feature section says images “span across multiple maps.”
- DrMap default when height/width omitted (1×1 vs auto) not explicitly confirmed on Modrinth body beyond param options.

---

## Multi-frame / multi-map support for item frames

### Takeaway
All three support multi-map posters for item-frame walls. ImageFrame and ImageOnMap(Reborn) have first-class “combined/splatter” single items; DrMap uses multi-map handouts plus optional magic place of remaining frames.

### Cited Findings
- ImageFrame: custom width/height across multiple maps; Combined ImageMap auto-searches item-frame wall/floor/ceiling; selection tool for frames; break returns combined item. — [Hangar ImageFrame](https://hangar.papermc.io/LOOHP/ImageFrame)
- ImageOnMap: large images auto-split (example 1024×1024 → 16 maps); “splatter maps” deploy/remove big posters in one click (3.0+). — [GitHub ImageOnMap](https://github.com/zDevelopers/ImageOnMap)
- ImageOnMapReborn: splatter/poster item; right-click **bottom-left** empty item frame to hang whole poster; sneak+hit to remove; works walls/floors/ceilings. — [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- DrMap: height/width multi-map create; `drmap.place.magic` “quick-place the rest of the item frames from the same image” (GriefPrevention/WorldGuard respected; other claims maybe not). — [Modrinth DrMap](https://modrinth.com/plugin/drmap); [Spigot update 1.0.8 notes via Modrinth](https://modrinth.com/plugin/drmap/version/1.0.8)

### Inferences
- For “one item places the whole mural,” ImageFrame combined maps and ImageOnMap splatter maps are closest; DrMap magic-place is adjacent but still frame-by-frame workflow with assist.

### Gaps
- Side-by-side placement origin convention differs (ImageFrame combined: clicked frame as **top-left**; ImageOnMapReborn splatter: **bottom-left**) - operators must not mix muscle memory.

---

## Auto-placement into item frames vs giving map items

### Takeaway
ImageFrame can either give maps, place into a prior selection, or give a combined placeable item. ImageOnMap/Reborn primarily give maps/splatter items for player placement. DrMap writes onto empty maps in hand and places into frames via normal/manual/magic place permissions - not “create directly onto frames.”

### Cited Findings
- ImageFrame create modes: default maps to player; `selection` places on selected frames; `combined` gives Combined ImageMap that auto-finds space on click. — [Hangar ImageFrame](https://hangar.papermc.io/LOOHP/ImageFrame)
- ImageOnMap quick guide: ensure free inventory slot; `/tomap URL`; place in item frame yourself; splatter for multi-frame one-click. — [GitHub ImageOnMap](https://github.com/zDevelopers/ImageOnMap)
- ImageOnMapReborn: `/tomap` creates maps/poster; player hangs poster; `/givemap` for console/command blocks. — [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/)
- DrMap: create fills empty maps; permissions `drmap.place`, `drmap.place.magic`, `drmap.rotate`, `drmap.cartography`. — [Modrinth DrMap](https://modrinth.com/plugin/drmap)

### Inferences
- Closest to “URL → already on the wall” without a placeable intermediate is ImageFrame `selection` after `/imageframe select`.

### Gaps
- Whether DrMap can create without an empty map in creative was not verified beyond survival-friendly reviews claiming empty-map usage.

---

## Persistence across server restarts

### Takeaway
ImageFrame persists via plugin storage (file default, optional MySQL) plus map cache modes. ImageOnMap/Reborn save image data under the plugin folder and reload after restart (Reborn advertises improved post-restart reliability). DrMap relies on Minecraft map item/world map data plus plugin metadata for `/drmap info` - durable as long as world `map_*.dat` persists.

### Cited Findings
- ImageOnMap: “These images will be saved on your server and reloaded at restart.” — [GitHub ImageOnMap](https://github.com/zDevelopers/ImageOnMap); [SpigotMC ImageOnMap](https://www.spigotmc.org/resources/imageonmap.26585/)
- ImageOnMapReborn: “More reliable loading of pictures after a restart (no more blank maps until you switch hotbar slots)”; maps live in `world/data/map_*.dat`; plugin stores lists under `plugins/ImageOnMapReborn/`; animated GIFs “in sync and after restarts.” — [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn); [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/)
- ImageFrame config `Storage.Type`: `file` (default) or `jdbc` (MySQL); `CacheControlMode`: `DYNAMIC` or `MANUAL_PERSISTENT` (default); multi-server MySQL documented on Hangar. — [config.yml](https://raw.githubusercontent.com/LOOHP/ImageFrame/main/common/src/main/resources/config.yml); [Hangar ImageFrame](https://hangar.papermc.io/LOOHP/ImageFrame)
- DrMap `/drmap info` reports creator, time, image portion, URL - implies persisted metadata with the map; erase returns empty map. — [SpigotMC DrMap](https://www.spigotmc.org/resources/drmap.87368/)

### Inferences
- All three are intended to survive restarts for static images; animated playback persistence is explicitly claimed for ImageFrame and ImageOnMapReborn, not for DrMap (no animation).

### Gaps
- DrMap’s exact on-disk schema (PDC/NBT vs plugin YAML) was not located in the minimal GitHub README.

---

## GIF / animated image support

### Takeaway
ImageFrame: full animated GIF support (async, up to 1/20s). ImageOnMap upstream: GIF load as **static**. ImageOnMapReborn: animated GIFs (permission + config limits; security hardening in 1.2.1). DrMap: GIF may load but **will not animate**.

### Cited Findings
- ImageFrame: PNG, JPEG, WEBP & GIFs; GIFs animated up to 1/20 second; animation async; permission `imageframe.create.animated`. — [Hangar ImageFrame](https://hangar.papermc.io/LOOHP/ImageFrame)
- ImageOnMap README: “PNG, JPEG and **static GIF** are supported.” — [GitHub ImageOnMap](https://github.com/zDevelopers/ImageOnMap)
- ImageOnMapReborn: “Animated GIFs become animated maps”; config `animated-gifs.enabled`, `max-frames` (100), `max-maps` (16), `max-fps` (10); permission `imageonmap.animated`; 1.2.1 GIF memory/DoS mitigations. — [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/)
- DrMap Spigot: “You should also be able to create images with gifs, but **they won't animate**.” — [SpigotMC DrMap](https://www.spigotmc.org/resources/drmap.87368/)

### Inferences
- For animated displays on Paper 26.3, ImageFrame and ImageOnMapReborn are the candidates; DrMap is still-image only.

### Gaps
- Whether ImageFrame Client HD mod helps GIFs: Client page says main features work with **static images only (not GIFs)**. — [ImageFrame Client](https://modrinth.com/project/7JSyQd4e)

---

## Permissions and rate/size limits

### Takeaway
ImageFrame: create defaults to **op**; rich permission tree; config MaxSize **100**, PlayerCreationLimit default **10**, MaxImageFileSize **50 MiB**, optional URL whitelist, MapPacketSendingRateLimit. ImageOnMap/Reborn: user perms default true; quotas via config + `imageonmap.maplimit.*` / `imagelimit.*`; Reborn adds download/pixel/GIF limits and SSRF block. DrMap: simpler command/place permissions; no detailed size-limit docs found on listing pages.

### Cited Findings
**ImageFrame**
- Key perms: `imageframe.create` (default op), `imageframe.create.animated` (op), `imageframe.select`, `imageframe.get`, etc. — [Hangar ImageFrame](https://hangar.papermc.io/LOOHP/ImageFrame)
- Config defaults: `MaxSize: 100`; `MaxImageFileSize: 52428800`; `MaxProcessingTime: 60`; `ParallelProcessingLimit: 1`; `PlayerCreationLimit.default: 10`; `MapMarkerLimit: 20`; `MapPacketSendingRateLimit: -1` (disabled); `RestrictImageUrl.Enabled: false` with sample whitelist (imgur, discord CDN, etc.); createlimit groups via `imageframe.createlimit.<group>`. — [config.yml](https://raw.githubusercontent.com/LOOHP/ImageFrame/main/common/src/main/resources/config.yml)

**ImageOnMap**
- Most user permissions default everyone; admin/give/`*other` for ops; `images-hostnames-whitelist`; `imageonmap.mapLimit.XX` / `imageonmap.imageLimit.XX` (4.2.0+). — [GitHub ImageOnMap](https://github.com/zDevelopers/ImageOnMap); [GitHub releases 4.2.0 notes](https://github.com/zDevelopers/ImageOnMap/releases)

**ImageOnMapReborn**
- Same permission names as ImageOnMap plus `imageonmap.animated`, `imageonmap.localfiles`, `imageonmap.notifyupdate`, bypasses.
- New-install defaults: `map-player-limit: 200`, `max-image-pixels: 16000000`; `download.timeout-seconds` 20 / whole download 3× timeout; `download.max-size-mb` 25; `download.block-private-addresses: true`; GIF frame/map/fps caps. — [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/)

**DrMap**
- `drmap.command.create|info|erase|reload`; `drmap.place`, `drmap.place.magic`, `drmap.rotate`, `drmap.cartography`. — [Modrinth DrMap](https://modrinth.com/plugin/drmap)

### Inferences
- ImageOnMap(Reborn) is the most player-friendly default permission model; ImageFrame expects LuckPerms (or similar) grants for non-ops.
- ImageOnMapReborn documents the strongest explicit SSRF/download abuse controls among the three.

### Gaps
- DrMap config.yml size/rate limits not published on Modrinth/Spigot body (may exist in jar).
- Exact units of ImageFrame `MaxSize: 100` (likely max maps per side/area) not spelled out in the YAML comment beyond “Max size of an image map.”

---

## Folia support and Geyser/Bedrock compatibility

### Takeaway
Only ImageFrame claims Folia support. ImageOnMapReborn and DrMap do not list Folia. For Geyser: ImageFrame has known Bedrock disconnect/incapacitation issues with many maps (open issues on ImageFrame and Geyser); config hook `Hooks.Geyser.DisableSmoothAnimationForBedrockPlayers` exists but does not fully solve non-animated map problems per reporters. No dedicated DrMap/ImageOnMap Geyser compatibility pages found.

### Cited Findings
- ImageFrame loaders include **folia**; Hangar tag SUPPORTS_FOLIA. — [Modrinth API](https://api.modrinth.com/v2/project/imageframe); [Hangar API](https://hangar.papermc.io/api/v1/projects/LOOHP/ImageFrame)
- ImageOnMapReborn: “Folia is not supported.” — [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn); [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/)
- DrMap Modrinth loaders: paper, purpur, spigot only (no folia). — [Modrinth API](https://api.modrinth.com/v2/project/drmap)
- ImageFrame config: `Hooks.Geyser.DisableSmoothAnimationForBedrockPlayers` (default false). — [config.yml](https://raw.githubusercontent.com/LOOHP/ImageFrame/main/common/src/main/resources/config.yml)
- ImageFrame issue #123 (2025-07): too many ImageFrames in render distance disconnects Bedrock (`End of stream`) via Velocity+Geyser. — [ImageFrame #123](https://github.com/LOOHP/ImageFrame/issues/123)
- ImageFrame issue #45: animated maps crash/OOM Geyser/proxy; request to disable animation for Bedrock. — [ImageFrame #45](https://github.com/LOOHP/ImageFrame/issues/45)
- Geyser issue #6569 (2026-07, still discussed Oct 2026): Bedrock players incapacitated by ImageFrame maps (including non-animated); Geyser maintainer comment: Bedrock map handling “atrocious,” likely can’t-fix for video-like map spam; LOOHP suggested `/imageframe preference view_animated_maps false` which did not fix non-animated case per reporter. — [Geyser #6569](https://github.com/GeyserMC/Geyser/issues/6569)
- ImageFrame issue #156: visual mismatch of combined maps on Bedrock vs Java. — [ImageFrame #156](https://github.com/LOOHP/ImageFrame/issues/156)

### Inferences
- Target server is **not Folia**, so Folia support is a bonus for ImageFrame only, not a requirement filter.
- For Geyser/Floodgate, ImageFrame is the most documented risk; treat large mural/GIF walls as Bedrock-hostile unless carefully limited. ImageOnMapReborn/DrMap likely still hit vanilla Bedrock map limits via Geyser, but that specific failure mode was not evidenced in this research pass.

### Gaps
- No primary-source Geyser issues filed specifically against ImageOnMapReborn or DrMap were found.
- Floodgate-specific behavior (UUID/auth) is orthogonal; no plugin claimed Floodgate incompatibility.

---

## License / open source status and repo URLs

### Takeaway
All three main lines are open source under GPL-family licenses (ImageOnMap historically CeCILL-B / also described as GPL on Spigot; Reborn GPL-3.0; ImageFrame GPL-3.0; DrMap GPL-3.0-only on Modrinth).

### Cited Findings
- ImageFrame: **GPL-3.0-only**; repo https://github.com/LOOHP/ImageFrame — [Modrinth](https://modrinth.com/project/imageframe); [GitHub API license](https://api.github.com/repos/LOOHP/ImageFrame)
- ImageOnMap: README “CeCILL-B (BSD-style in French law)”; Spigot text also says GPL v3+; GitHub license field `Other`; repo https://github.com/zDevelopers/ImageOnMap — [GitHub README](https://github.com/zDevelopers/ImageOnMap); [SpigotMC](https://www.spigotmc.org/resources/imageonmap.26585/)
- ImageOnMapReborn: **GPL-3.0**; repo https://github.com/Optiblur/ImageOnMapReborn; states rewrite contains no ImageOnMap/QuartzLib code, compatible data format. — [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- DrMap: Modrinth **GPL-3.0-only**; repo https://github.com/akdukaan/DrMap; GitHub API `license: null` (LICENSE file may be missing despite Modrinth declaration). — [Modrinth API](https://api.modrinth.com/v2/project/drmap); [GitHub API](https://api.github.com/repos/akdukaan/DrMap)

### Inferences
- Prefer Modrinth/Hangar license metadata + repo LICENSE for compliance; reconcile ImageOnMap CeCILL-B vs Spigot GPL wording if redistributing upstream jars.

### Gaps
- DrMap GitHub has no SPDX license object; confirm LICENSE file presence before compliance-critical redistribution.

---

## Popularity signals and open issue health

### Takeaway
ImageFrame is by far the most popular and actively discussed. Upstream ImageOnMap has large historical download/star counts but a large stale issue backlog. ImageOnMapReborn is new/small. DrMap is niche (~2k Modrinth downloads).

### Cited Findings
- ImageFrame Modrinth: **~274,886 downloads**, **679** followers. — [Modrinth API](https://api.modrinth.com/v2/project/imageframe)
- ImageFrame Hangar: **22,414** downloads, **126** stars, **45** watchers, **120,830** views. — [Hangar API](https://hangar.papermc.io/api/v1/projects/LOOHP/ImageFrame)
- ImageFrame GitHub: **107** stars, **41** forks, **68** open issues. — [GitHub API](https://api.github.com/repos/LOOHP/ImageFrame)
- ImageOnMap Spigot: **659,062** total downloads; last update 2022. — [SpigotMC ImageOnMap](https://www.spigotmc.org/resources/imageonmap.26585/)
- ImageOnMap CurseForge/Bukkit: ~**168k** downloads (page figures). — [CurseForge](https://www.curseforge.com/minecraft/bukkit-plugins/imageonmap/gallery); [BukkitDev](https://dev.bukkit.org/projects/imageonmap)
- ImageOnMap GitHub: **192** stars, **107** forks, **105** open issues. — [GitHub API](https://api.github.com/repos/zDevelopers/ImageOnMap)
- ImageOnMapReborn: Spigot v1.2.1 downloads **58** (history page); v1.2.2 downloads **18** at fetch time; GitHub **5** stars, **0** open issues. — [Spigot history](https://www.spigotmc.org/resources/imageonmapreborn.139800/history); [Spigot resource](https://www.spigotmc.org/resources/imageonmapreborn.139800/); [GitHub API](https://api.github.com/repos/Optiblur/ImageOnMapReborn)
- DrMap Modrinth: **2,215** downloads, **8** followers. — [Modrinth API](https://api.modrinth.com/v2/project/drmap)
- DrMap Spigot: **2,307** total downloads; **5/5** from 6 ratings; version 1.0.10 downloads **312**. — [SpigotMC DrMap](https://www.spigotmc.org/resources/drmap.87368/)
- DrMap GitHub: **3** stars, **4** forks, **0** open issues. — [GitHub API](https://api.github.com/repos/akdukaan/DrMap)

### Inferences
- Popularity ≠ 26.3 fitness: ImageOnMap’s download lead is historical.
- ImageFrame’s 68 open issues include nontrivial Geyser/Bedrock traffic - “healthy” activity but not zero risk.

### Gaps
- Hangar/Modrinth download totals are not directly additive (same users may download both).
- Spigot ImageFrame download total not fetched this pass.

---

## Known problems (API breakage, security/URL fetch, performance, abandoned forks)

### Takeaway
Upstream ImageOnMap is abandoned past 1.18 with many forks of uneven quality. ImageOnMapReborn documents URL SSRF blocking and GIF memory attacks it patched. ImageFrame has URL whitelist options and known Geyser/performance packet issues with many/animated maps. DrMap is small/simple but lacks a clear official 26.3 release channel.

### Cited Findings
- ImageOnMap 4.2.x limited to 1.17–1.18.1; older forks proliferated for 1.21 (OKOCRAFT/MOFUCRAFT/StrawberryMaster/whimc). — [GitHub releases](https://github.com/zDevelopers/ImageOnMap/releases); fork READMEs cited above
- ImageFrame migration command supports migrating from **ImageOnMap** and **DrMap** (`/imageframe adminmigrate`). — [Hangar ImageFrame](https://hangar.papermc.io/LOOHP/ImageFrame)
- ImageOnMapReborn 1.2.1: malicious GIF could reserve gigabytes; slow downloads could block `/tomap`; mitigations + private-address block. — [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/)
- ImageFrame optional `RestrictImageUrl` whitelist; upload webserver option (`UploadService`, default port 8517) - ops must secure if enabled. — [config.yml](https://raw.githubusercontent.com/LOOHP/ImageFrame/main/common/src/main/resources/config.yml)
- ImageFrame + Geyser: disconnects / incapacitation / proxy OOM with many maps or animations (issues cited above). — [Geyser #6569](https://github.com/GeyserMC/Geyser/issues/6569); [ImageFrame #123](https://github.com/LOOHP/ImageFrame/issues/123); [ImageFrame #45](https://github.com/LOOHP/ImageFrame/issues/45)
- DrMap Spigot vs Modrinth version drift (1.0.10 vs 1.1.0) and informal Discord jar for 26.1+ increase supply-chain/clarity risk. — [SpigotMC](https://www.spigotmc.org/resources/drmap.87368/); [Modrinth 1.1.0](https://modrinth.com/plugin/drmap/version/1.1.0); [Spigot thread](https://www.spigotmc.org/threads/drmap.480868/)
- ImageFrame Client complementary Fabric/Quilt mod for HD/full-color static maps (server plugin alone uses vanilla map color limits). — [ImageFrame Client](https://modrinth.com/project/7JSyQd4e)

### Inferences
- For Paper 26.3 + Geyser: ImageFrame is feature-richest and best version-aligned, but Bedrock risk is a first-class decision factor.
- ImageOnMapReborn is the sane “ImageOnMap lineage” pick for 26.3 if command familiarity with `/tomap` matters.
- DrMap fits “simple survival empty-map art” but is weakest on documented 26.3 + animation + popularity/support surface.

### Gaps
- No independent third-party security audit found for any of the three.
- Performance benchmarks (TPS impact of N animated maps) not published in primary docs beyond rate-limit knobs.
- Unverified whether DrMap 1.1.0 jar from Modrinth runs unmodified on Paper 26.3 (author FAQ says latest often works before page updates, but API game_versions omit 26.x).

---

## Cross-plugin fit snapshot for Paper 26.3 + Geyser (synthesis from cited findings)

### Takeaway
Best documented 26.3 support: **ImageFrame** and **ImageOnMapReborn**. Best Folia: ImageFrame only (N/A for this target). Best Geyser caution: ImageFrame has the most negative evidence. Best simple survival empty-map workflow: DrMap, if a verified 26.3-capable jar is obtained.

### Cited Findings
- ImageFrame 2026.1.5 supports MC 26.3 on Paper family including Folia. — [Hangar 2026.1.5](https://hangar.papermc.io/LOOHP/ImageFrame/versions/2026.1.5)
- ImageOnMapReborn tested on Paper 26.3; Folia unsupported. — [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/)
- DrMap published versions target ≤1.21.11; 26.1+ only via author Discord CDN note. — [Modrinth API](https://api.modrinth.com/v2/project/drmap); [Spigot thread](https://www.spigotmc.org/threads/drmap.480868/)
- ImageFrame Geyser issues remain open/discussed in 2026. — [Geyser #6569](https://github.com/GeyserMC/Geyser/issues/6569)

### Inferences
- If the deployment must serve Bedrock via Geyser with many wall maps, prefer small static installations and/or test ImageOnMapReborn/DrMap under the same mural density before committing to ImageFrame GIFs.

### Gaps
- Head-to-head Bedrock playtest on Paper 26.3 for Reborn vs DrMap vs ImageFrame was not performed in this research task.
