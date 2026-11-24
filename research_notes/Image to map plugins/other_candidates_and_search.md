# Other URL-to-map / image-on-map candidates (beyond known set)

Research date: 2026-11-23 (late 2026). Target context: Paper 26.3 + Geyser (plugin-only, not Folia). Excluded from primary evaluation (already known): ImageFrame (LOOHP), ImageOnMap (zDevelopers), DrMap, ImageMaps, Images (SpigotMC), MapImages, SushiImage. Claims marked **unverified** were not confirmed on a live Paper 26.3+Geyser stack.

## What other maintained URL-to-map / image-on-map projects exist now?

### Takeaway
Beyond the excluded set, several Paper/Spigot plugins still claim URL-to-map or image-on-item-frame features in 2025-2026. The strongest Paper 26.3-aligned options found are **Frameify**, **Image-To-Painting**, **ImageOnMapReborn**, and **MapPaint**; Emage, ReColorfulMap, MapImage, and Custom Maps are secondary/partial fits.

### Cited Findings
- Frameify (Modrinth plugin) turns image URLs into WxH item-frame map grids, bakes into vanilla `map_*.dat`, lists MC **26.3 / 26.2 / 26.1.2**, Paper/Purpur only, ARR license, updated about last month relative to page scrape - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Image-To-Painting Hangar pin is **1.4.0 for 1.21-26.3**; CurseForge lists the same project across 26.x - [Hangar Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting); [CurseForge Image To Painting](https://www.curseforge.com/minecraft/bukkit-plugins/image-to-painting)
- ImageOnMapReborn (Optiblur) is an unofficial ImageOnMap successor; SpigotMC **1.2.1** released **2026-11-05**; GitHub states tested on Paper **1.20.1, 1.21.11, and 26.3**; Folia not supported; GPL-3.0 - [GitHub Optiblur/ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn); [SpigotMC ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/history)
- MapPaint Hangar pin is **1.0.0 for 1.20-26.3**, published **2026-11-12**, includes `/paint image [url]` URL import plus in-game painting; MIT - [Hangar MapPaint](https://hangar.papermc.io/BbIJABNPOBATEJb/MapPaint)
- ReColorfulMap Hangar pin is **5.0.1 for 1.20.1-26.2**, Paper/Folia, URL via `/tomap` - [Hangar ReColorfulMap](https://hangar.papermc.io/zhangyuheng/ReColorfulMap)
- Emage SpigotMC **1.5.3** (update **2026-07-05**), Paper 1.21+, tested majors include **26.1**, PacketEvents dependency, GIF/item-frame focus - [SpigotMC Emage](https://www.spigotmc.org/resources/emage.130410/); [GitHub Ed1thy/Emage](https://github.com/Ed1thy/Emage)
- MapImage Modrinth lists **26.2 / 26.1.x / 1.21.x / 1.20.x**, Bukkit/Paper/Spigot, ~9.2K downloads, updated ~8 months before scrape - [Modrinth MapImage](https://modrinth.com/project/P0MLLUxX)
- Custom Maps (Matistan) SpigotMC **1.4.1** last update **2024-05-15**, tested majors include **26.1 / 26.2**, ~1,278 downloads - [SpigotMC Custom Maps](https://www.spigotmc.org/resources/custom-maps.109576/)
- Cartography (Lumine1909) GitHub README: Paper 1.21+, `/getimage -url ... -l -w`, SQLite persistence, GPL-3.0; ~2 stars; Spigot thread from **2023-06** - [GitHub Lumine1909/Cartography](https://github.com/Lumine1909/Cartography); [Spigot Cartography thread](https://www.spigotmc.org/threads/cartography.606894/)
- ImageCanvas Modrinth: Paper **1.21.x**, grids to 15x15, published/updated ~10-11 months before scrape, MIT - [Modrinth ImageCanvas](https://modrinth.com/project/v0YPSYfQ)
- Image Map Plus Modrinth: loaders Paper/Purpur/Spigot, game versions through **1.21.8** (not 26.x on page), `/im create <url>` - [Modrinth Image Map Plus](https://modrinth.com/plugin/image-map-plus)
- URLIMAGETOOMAPART CurseForge: **1.21 / 1.21.1**, last update **2026-02-15**, `/getmap <URL>`, single 128x128, no GIF, ARR, 214 downloads - [CurseForge URLIMAGETOOMAPART](https://www.curseforge.com/minecraft/bukkit-plugins/urlimagetoomapart)
- Fabric secondary: Image2Map Modrinth Fabric/Quilt, MC includes **26.3**, ~402K downloads, multimaps via bundle - [Modrinth Image2Map](https://modrinth.com/mod/image2map)

### Inferences
- For a Paper **26.3** plugin-only server, Frameify, Image-To-Painting, ImageOnMapReborn, and MapPaint are the clearest "currently shipping for 26.3" peers outside the excluded list.
- Emage / MapImage / Custom Maps / ReColorfulMap may work on 26.3 but their public pins stop at 26.1 or 26.2 or older - treat 26.3 as **unverified** until jar-tested.
- Cartography and ImageCanvas look feature-fit but low popularity / stale relative to 26.x; Image Map Plus and URLIMAGETOOMAPART look stuck on 1.21.x lines.

### Gaps
- No live install/test was done on this server's Paper 26.3-258 + Geyser stack.
- Exact download counts / issue counts for Hangar projects beyond page text were not exhaustively scraped.
- Whether ReColorfulMap 5.0.1 or Emage 1.5.3 actually load on API 26.3 is unverified.

## Notable candidate evaluations (platforms, commands, WxH, persistence, GIF, limits, Folia/Geyser, license, problems)

### Takeaway
Among non-excluded plugins, Frameify and ImageOnMapReborn best match "URL + WxH multi-frame + item frames" for Paper 26.3; Image-To-Painting and MapPaint are strong 26.3 alternatives with different workflows; Emage is GIF-forward but packet-custom and Geyser-risky (**unverified**); several others lack explicit WxH or 26.3 pins.

### Cited Findings

#### Frameify (primary candidate)
- Platforms: Paper, Purpur (explicitly **No Spigot**); MC listed **26.3, 26.2, 26.1.2**; also states Java **25+** - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Command: `/frameify create <name> <url> <width> <height> [scale=fit|stretch|crop] [dither=true|false] [deliver=individual|fill|none]`; alias `/fmap`; also `get`, `place`, `calc`, `if` (invisible frames), `manage`, `reload` - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Multi-frame: configurable grid **1x1 up to 64x64** - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Auto-place vs items: `deliver=individual` (tiles), `fill` (auto-place on targeted wall), `none` (bake only); `/frameify place <name>` fills frames - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Persistence: pixel data baked into vanilla map files; maps survive plugin removal; GIF animation needs plugin present (else static) - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- GIF/WebP animated: yes (PNG, JPG, BMP, GIF animated, WebP animated) - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Permissions: `frameify.create|get|place|calc|invisibleframe|manage|delete|admin` (default op) - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Folia: not claimed on Modrinth page (Paper/Purpur only) - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Geyser: no explicit Geyser docs found on project page; baking into vanilla maps may behave closer to vanilla locked maps for Bedrock - **unverified** - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- License: ARR - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Popularity/issues: Modrinth page does not expose a clear download total in the fetched text; GitHub issues not linked on the fetched page - [Modrinth Frameify](https://modrinth.com/plugin/frameify)

#### Image-To-Painting (primary candidate)
- Platforms: Hangar Paper plugin; CurseForge Bukkit plugin; pin **1.4.0 / 1.21-26.3**; 1.4.0 notes say Java **25** and Paper/Purpur **26.3** - [Hangar Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting); [Hangar 1.4.0 notes](https://hangar.papermc.io/Depletion1/Image-To-Painting/versions/1.4.0)
- Commands: `/itp render <URL|file> <fit|fill> [quality]`; give/place/frame/rebuild/quality/rename/delete/list/info/reload - [Hangar Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting)
- Multi-frame: "Multi-Map Support - Automatically splits large images into multiple map tiles"; config "Customizable width and height maxes"; 1.4.0 mentions large mosaics including **8x12 and 16x16** - [Hangar Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting); [Hangar 1.4.0](https://hangar.papermc.io/Depletion1/Image-To-Painting/versions/1.4.0)
- Auto-place: `/itp place wall`, `/itp place air <dir>`, `/itp frame <dir>` - [Hangar Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting)
- Persistence: `renders.yml` / atomic registry across restarts - [Hangar Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting)
- GIF: not advertised on Hangar feature list (URL/file still images emphasized) - **GIF support unverified / likely no** - [Hangar Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting)
- Permissions: `imagetopainting.use|admin|render|give|place|frame|rebuild|quality|rename|list|delete|reload|economy.bypass|update.notify` - [Hangar Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting)
- Economy limits: payment per map configurable - [Hangar Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting)
- Folia/Geyser: not mentioned on Hangar overview - **unverified**
- License: not clearly stated on Hangar overview fetch - **gap**
- Known problems: 1.4.0 notes warn URLs must be **direct** image URLs, not webpage/preview links - [Hangar 1.4.0](https://hangar.papermc.io/Depletion1/Image-To-Painting/versions/1.4.0)

#### ImageOnMapReborn (primary candidate / ImageOnMap successor)
- Platforms: Paper / Purpur / Spigot; MC **1.20.1+**, tested **1.20.1, 1.21.11, 26.3**; Folia **not** supported; GPL-3.0 - [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- Last release: SpigotMC **1.2.1 on 2026-11-05** (total downloads ~147 on history page) - [SpigotMC history](https://www.spigotmc.org/resources/imageonmapreborn.139800/history)
- Command: `/tomap <link|file:name> [resize|resize-stretched|resize-covered] [width height] [dither|nodither]`; e.g. `resize 4 3` or `4x3` for WxH poster; `/maps`, `/givemap`, `/maptool ...` - [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- Multi-frame + auto-place: auto-tiles by pixel size; splatter/poster item places whole grid from **bottom-left** frame; sneak+hit removes whole poster - [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- Persistence: images under plugin data; format compatible with legacy ImageOnMap; auto-import once - [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- GIF: animated GIFs supported; 1.2.1 hardened GIF memory/CPU abuse cases - [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- Limits: new installs `map-player-limit: 200`, `max-image-pixels: 16000000`; hostname whitelist; download timeouts - [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- Permissions: same ImageOnMap nodes (`imageonmap.*`); `imageonmap.localfiles` for `file:` uploads - [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- Geyser: no dedicated Geyser section found in README - **unverified**; inherits same map-packet class of problems as other custom map renderers - **inference**
- Popularity: very new (first release 2026-10-19), low download count vs ImageFrame - [SpigotMC history](https://www.spigotmc.org/resources/imageonmapreborn.139800/history)

#### MapPaint (adjacent URL import + canvas paint)
- Platforms: Paper **1.20-26.3**, one jar; PacketEvents **bundled**; MIT; published **2026-11-12** - [Hangar MapPaint](https://hangar.papermc.io/BbIJABNPOBATEJb/MapPaint)
- URL command: `/paint image [url]` (op-only by default via `mappaint.image`); also panel button; crop/fit/zoom/offset/brightness/contrast/saturation/dither - [Hangar MapPaint](https://hangar.papermc.io/BbIJABNPOBATEJb/MapPaint)
- Multi-frame: canvases **1x1 to 5x5** (config up to **16x16**); not a freeform "URL WxH maps" poster tool like ImageFrame - [Hangar MapPaint](https://hangar.papermc.io/BbIJABNPOBATEJb/MapPaint)
- Persistence: stored in `plugins/mappaint/paintings`; **without the plugin, maps in frames are empty** - [Hangar MapPaint](https://hangar.papermc.io/BbIJABNPOBATEJb/MapPaint)
- GIF: not listed among features - **likely no / unverified**
- Limits: `limits.paintings-per-player` default 200; `import.image-max-bytes` 8 MB; private hosts blocked by default - [Hangar MapPaint](https://hangar.papermc.io/BbIJABNPOBATEJb/MapPaint)
- Folia/Geyser: not mentioned - **unverified**
- Note: primary product is in-game painting; URL import is one feature - [Hangar MapPaint](https://hangar.papermc.io/BbIJABNPOBATEJb/MapPaint)

#### ReColorfulMap
- Platforms: Paper + Folia; Hangar pin **5.0.1 / 1.20.1-26.2** - [Hangar ReColorfulMap](https://hangar.papermc.io/zhangyuheng/ReColorfulMap)
- Command: `/tomap <url> [scaling]` (scale e.g. `0.3`); admin `/reloadColorfulMap`, `/cleanColorfulMap` - [Hangar ReColorfulMap](https://hangar.papermc.io/zhangyuheng/ReColorfulMap)
- Multi-frame: auto-tiles by image pixels (128x128 per map); size driven by image+scale, not explicit WxH args; config `max-frame-x/y` default **32x18** - [Hangar ReColorfulMap](https://hangar.papermc.io/zhangyuheng/ReColorfulMap)
- Auto-place: place first map at **bottom-left** of frame matrix; rest auto-fill; can retrieve maps from matrix - [Hangar ReColorfulMap](https://hangar.papermc.io/zhangyuheng/ReColorfulMap)
- Persistence: PNGs in `plugins/ReColorfulMap/maps`, path in PDC (GitHub README) - [GitHub ColdeZhang/ReColorfulMap](https://github.com/ColdeZhang/ReColorfulMap)
- GIF: not advertised - **unverified**
- Economy/limits: Vault optional; URL whitelist; max frame matrix - [Hangar ReColorfulMap](https://hangar.papermc.io/zhangyuheng/ReColorfulMap)
- 26.3: pin stops at **26.2** - **26.3 unverified**

#### Emage
- Platforms: Paper 1.21+ (SpigotMC tested majors through **26.1**); requires **Java 22** and **PacketEvents**; GPL-3.0 - [SpigotMC Emage](https://www.spigotmc.org/resources/emage.130410/); [GitHub Ed1thy/Emage](https://github.com/Ed1thy/Emage)
- Last update: **1.5.3 on 2026-07-05** - [SpigotMC Emage updates](https://www.spigotmc.org/resources/emage.130410/updates)
- Commands: `/emage apply <url>` (auto-detect grid); `/emage apply-grid <url> <w> <h>`; `/emage remove` - [GitHub Ed1thy/Emage](https://github.com/Ed1thy/Emage)
- Multi-frame: place rectangular item-frame grid first, then apply; older Modrinth 1.1.1 notes mentioned static max **10x10**, GIF max **4x4** (may be outdated vs 1.5.x) - [Modrinth Emage 1.1.1](https://modrinth.com/plugin/emage/version/1.1.1)
- Persistence: flat-file frame storage per 1.5.3 changelog summary - [SpigotMC Emage updates](https://www.spigotmc.org/resources/emage.130410/updates)
- GIF: yes; custom packet pipeline bypasses default map API; claims high FPS / many GIFs - [SpigotMC Emage](https://www.spigotmc.org/resources/emage.130410/)
- Geyser: custom map packets are a known Bedrock pain class; Emage Geyser compatibility **unverified / likely problematic** relative to baked vanilla maps - inference from Geyser map issues elsewhere - [Geyser issue #6569](https://github.com/GeyserMC/Geyser/issues/6569)
- 26.3 / Java 25: page says Java 22 and tested to 26.1 - **26.3 unverified**

#### MapImage (Modrinth P0MLLUxX)
- Platforms: Bukkit/Paper/Spigot; MC through **26.2**; ARR; ~9.2K downloads; updated ~8 months before scrape - [Modrinth MapImage](https://modrinth.com/project/P0MLLUxX)
- Command: `/mapimage <url> [size]`; size `HxW` e.g. `2x3` yields matrix of maps top-left to bottom-right - [Modrinth MapImage](https://modrinth.com/project/P0MLLUxX)
- Persistence: URL↔map ID in `config.yml`; re-renders on restart; needs internet every restart - [Modrinth MapImage](https://modrinth.com/project/P0MLLUxX)
- Formats: PNG, JPG, GIF, BMP, WEBP (animation not claimed) - [Modrinth MapImage](https://modrinth.com/project/P0MLLUxX)
- Permissions: `mapimage.use` (OP default) - [Modrinth MapImage](https://modrinth.com/project/P0MLLUxX)
- Known problems: author warns excessive images can raise RAM usage - [Modrinth MapImage](https://modrinth.com/project/P0MLLUxX)
- Auto-place: not described (items only) - [Modrinth MapImage](https://modrinth.com/project/P0MLLUxX)

#### Custom Maps (Matistan)
- Platforms: SpigotMC; MC 1.16+; tested through **26.2**; source [GitHub Matistan/MinecraftCustomMaps](https://github.com/Matistan/MinecraftCustomMaps); last jar update **2024-05-15** - [SpigotMC Custom Maps](https://www.spigotmc.org/resources/custom-maps.109576/)
- Commands: `/custommap give <url>`, `give automatic`, `give small`, `give scale <n>`; `/custommap fillitemframes ...`; `changeproperties`, `geturl`, `fix` - [SpigotMC Custom Maps](https://www.spigotmc.org/resources/custom-maps.109576/)
- Multi-frame: scale/automatic modes; place bottom-left then display; not classic named WxH create - [SpigotMC Custom Maps](https://www.spigotmc.org/resources/custom-maps.109576/)
- Persistence issue: `/custommap fix` "usually it breaks after server restart" - [SpigotMC Custom Maps](https://www.spigotmc.org/resources/custom-maps.109576/)
- GIF: not claimed
- Maintenance: last update mid-2024 despite tested-version list including 26.x - **stale relative to 2026 releases**

#### Cartography (Lumine1909)
- Platforms: Paper 1.21+ (Spigot compatibility denied in README); GPL-3.0; ~2 GitHub stars - [GitHub Cartography](https://github.com/Lumine1909/Cartography)
- Command: `/getimage -url <url> [-l <h>] [-w <v>] [-keepscale] [-dither] [-nocache] [-pack normal|shulker|compress]` - [GitHub Cartography](https://github.com/Lumine1909/Cartography)
- Multi-frame: yes via `-l` / `-w`; compress pack auto-places on right-click - [GitHub Cartography](https://github.com/Lumine1909/Cartography)
- Persistence: SQLite metadata + cache - [GitHub Cartography](https://github.com/Lumine1909/Cartography)
- GIF: not claimed
- Limits: cool-down, max-size in config (README) - [GitHub Cartography](https://github.com/Lumine1909/Cartography)
- 26.3: README only says 1.21+ - **26.3 unverified**; Modrinth user page does not list Cartography among plugins in search snippet - [Lumine1909 Modrinth](https://modrinth.com/user/Lumine1909/plugins)

#### ImageCanvas
- Platforms: Paper **1.21.x** only on Modrinth; MIT; updated ~10-11 months before scrape - [Modrinth ImageCanvas](https://modrinth.com/project/v0YPSYfQ)
- Command: `/imagemap create <name> <url> <WxH> [-auto] [-HD]`; get/list/delete/upload - [Modrinth ImageCanvas](https://modrinth.com/project/v0YPSYfQ)
- Multi-frame: up to **15x15**; `-auto` fills surrounding frames - [Modrinth ImageCanvas](https://modrinth.com/project/v0YPSYfQ)
- Persistence: saved maps restore after restart - [Modrinth ImageCanvas](https://modrinth.com/project/v0YPSYfQ)
- GIF: not claimed; HD = Floyd-Steinberg dither - [Modrinth ImageCanvas](https://modrinth.com/project/v0YPSYfQ)
- Requirements: Paper **1.21.11** or compatible fork, Java 21+ - [Modrinth ImageCanvas](https://modrinth.com/project/v0YPSYfQ)
- 26.3: not listed - **likely incompatible / unverified**

#### Image Map Plus / Image Map (free)
- Image Map Plus: `/im create <url>`; whitelist/blacklist; tokens/economy/item fees; Discord logger; versions through **1.21.8** on Modrinth - [Modrinth Image Map Plus](https://modrinth.com/plugin/image-map-plus)
- Image Map (free): `/im <url>`; MC **1.19.x-1.20.1**; updated **3 years** ago; points users to Plus - [Modrinth Image Map](https://modrinth.com/mod/image-map)
- Multi-frame WxH: not shown on Plus overview (single-map create emphasized) - [Modrinth Image Map Plus](https://modrinth.com/plugin/image-map-plus)

#### URLIMAGETOOMAPART
- CurseForge Bukkit plugin; `/getmap <Direct_Image_URL>`; JPG/PNG only; no GIF; persists URL/map IDs in `maps.yml`; 1.21/1.21.1; ARR; 214 downloads - [CurseForge URLIMAGETOOMAPART](https://www.curseforge.com/minecraft/bukkit-plugins/urlimagetoomapart)

#### Secondary (Fabric/Quilt - not for this Paper server)
- Image2Map: Fabric/Quilt server-side; MC includes **26.3**; `/image2map create ...`; multimaps in bundle with click-to-place - [Modrinth Image2Map](https://modrinth.com/mod/image2map)
- Not usable on the target Paper plugin-only stack (no mods/) - server context notes

#### Geyser cross-cutting (affects all custom map plugins)
- Open Geyser issue: ImageFrame maps can incapacitate Bedrock players; Geyser maintainer called Bedrock map handling "atrocious" and GIF video maps likely infeasible - [GeyserMC/Geyser#6569](https://github.com/GeyserMC/Geyser/issues/6569)
- Related ImageFrame report: too many ImageFrames in render distance disconnect Bedrock (`End of stream`) - [LOOHP/ImageFrame#123](https://github.com/LOOHP/ImageFrame/issues/123)
- ImageFrame config offers `Hooks.Geyser.DisableSmoothAnimationForBedrockPlayers` - [ImageFrame config.yml](https://github.com/LOOHP/ImageFrame/blob/main/common/src/main/resources/config.yml)
- Implication for candidates: GIF/packet-heavy plugins (Emage, animated Frameify/ImageOnMapReborn) are higher Geyser risk; baked vanilla static maps (Frameify claim) may be safer - **unverified on this stack**

### Inferences
- Best peer set for Paper 26.3 URL+WxH posters outside exclusions: **Frameify**, **ImageOnMapReborn**, **Image-To-Painting**.
- MapPaint is maintained and 26.3-ready but is a paint studio with URL import, not a dedicated poster factory.
- Emage is the most interesting GIF specialist, but PacketEvents + custom packets + Geyser = high risk for this server's Bedrock path.
- Custom Maps' "breaks after restart" note and 2024 last release make it a weak pick despite tested-version labels.

### Gaps
- Folia support for Frameify, Image-To-Painting, MapPaint, Emage, MapImage, Custom Maps not documented on fetched pages.
- Geyser behavior for every non-ImageFrame candidate is untested.
- Exact Emage 1.5.x grid size limits after remaster not confirmed from primary 1.5.3 full changelog text (fetch of Spigot page timed out once).
- Cartography latest release date / jar availability for 26.x not confirmed beyond README.

## Hangar / Modrinth / SpigotMC / CurseForge / GitHub keyword search hits

### Takeaway
Keyword searches for image map / imagemap / map image / image frame / custom map URL surface ImageFrame heavily, plus ReColorfulMap, Image-To-Painting, MapPaint on Hangar; Frameify, MapImage, ImageCanvas, Image Map(+Plus), Image2Map on Modrinth; Emage, Custom Maps, ImageOnMapReborn, Cartography on SpigotMC/GitHub; Image-To-Painting and URLIMAGETOOMAPART on CurseForge.

### Cited Findings
- Modrinth hits include ImageFrame, ImageMaps, Image Map, Image Map Plus, MapImage, Frameify, ImageCanvas, Image2Map (Fabric) - [ImageFrame](https://modrinth.com/project/imageframe); [ImageMaps](https://modrinth.com/mod/imagemaps); [Image Map](https://modrinth.com/mod/image-map); [Image Map Plus](https://modrinth.com/plugin/image-map-plus); [MapImage](https://modrinth.com/project/P0MLLUxX); [Frameify](https://modrinth.com/plugin/frameify); [ImageCanvas](https://modrinth.com/project/v0YPSYfQ); [Image2Map](https://modrinth.com/mod/image2map)
- Hangar hits include ImageFrame (LOOHP), ReColorfulMap, Image-To-Painting, MapPaint - [ImageFrame Hangar](https://hangar.papermc.io/LOOHP/ImageFrame); [ReColorfulMap](https://hangar.papermc.io/zhangyuheng/ReColorfulMap); [Image-To-Painting](https://hangar.papermc.io/Depletion1/Image-To-Painting); [MapPaint](https://hangar.papermc.io/BbIJABNPOBATEJb/MapPaint)
- SpigotMC hits include ImageFrame, Custom Maps, DrMap (excluded), Emage, ImageOnMapReborn - [ImageFrame Spigot](https://www.spigotmc.org/resources/imageframe-load-images-on-maps-item-frames-support-gifs-map-markers-survival-friendly.106031/); [Custom Maps](https://www.spigotmc.org/resources/custom-maps.109576/); [Emage](https://www.spigotmc.org/resources/emage.130410/); [ImageOnMapReborn](https://www.spigotmc.org/resources/imageonmapreborn.139800/history)
- CurseForge hits include ImageOnMap (legacy), Image To Painting, URLIMAGETOOMAPART, Custom map images (older/thin) - [ImageOnMap Curse](https://dev.curseforge.com/projects/imageonmap); [Image To Painting](https://www.curseforge.com/minecraft/bukkit-plugins/image-to-painting); [URLIMAGETOOMAPART](https://www.curseforge.com/minecraft/bukkit-plugins/urlimagetoomapart); [Custom map images](https://www.curseforge.com/minecraft/bukkit-plugins/custom-map-images)
- GitHub hits include LOOHP/ImageFrame (excluded), Lumine1909/Cartography, Optiblur/ImageOnMapReborn, Ed1thy/Emage, ColdeZhang/ReColorfulMap - linked above
- Community: Falcon docs describe general "image maps" mechanics (128x128 tiles) but that is product docs, not a plugin candidate - [Falcon image-maps docs](https://falcon-mc.github.io/docs/image-maps.html)

### Inferences
- Search space is crowded with ImageFrame clones/simplifications; Frameify and ImageOnMapReborn are the notable 2026 newcomers for Paper 26.x.
- Hangar is thinner than Modrinth/Spigot for this niche but hosts two fresh 26.3 projects (Image-To-Painting 1.4.0, MapPaint 1.0.0).

### Gaps
- Direct Hangar/Modrinth UI search result pages were not scraped as ranked SERPs; findings are from web search + project page fetches.
- Polymart / BuiltByBit were not in the assigned source list and were not searched.

## Abandoned or old-version-only projects (1.16-1.20 or stale)

### Takeaway
Several historically popular or search-visible projects are abandoned, stuck on 1.19-1.21.8, or last meaningfully updated years before the 26.x era; treat them as migration sources or non-candidates for Paper 26.3.

### Cited Findings
- Image Map (Modrinth free): MC **1.19.x-1.20.1**, updated **3 years** ago - [Modrinth Image Map](https://modrinth.com/mod/image-map)
- Image Map Plus: supports through **1.21.8**, not 26.x on Modrinth compatibility list; "Updated last year" - [Modrinth Image Map Plus](https://modrinth.com/plugin/image-map-plus)
- ImageOnMap (zDevelopers / CurseForge): "latest version only compatible with Minecraft 1.15+" historically; ImageOnMapReborn states original "has not been updated since 2021" - [CurseForge ImageOnMap](https://dev.curseforge.com/projects/imageonmap); [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- Custom Maps: last update **2024-05-15** despite later "tested" labels; restart breakage noted by author - [SpigotMC Custom Maps](https://www.spigotmc.org/resources/custom-maps.109576/)
- URLIMAGETOOMAPART: only **1.21 / 1.21.1** game versions on CurseForge - [CurseForge URLIMAGETOOMAPART](https://www.curseforge.com/minecraft/bukkit-plugins/urlimagetoomapart)
- ImageCanvas: only **1.21.x**, stale ~10+ months, requires Paper 1.21.11 - [Modrinth ImageCanvas](https://modrinth.com/project/v0YPSYfQ)
- Cartography: originated **2023**; low activity signal (2 stars); 26.x not explicitly claimed - [GitHub Cartography](https://github.com/Lumine1909/Cartography)
- Excluded-but-noted for context: ImageMaps Modrinth page still lists 26.3 compatibility but also "Updated 2 years ago" in search snippet - treat maintenance carefully if reconsidered - [Modrinth ImageMaps](https://modrinth.com/mod/imagemaps)
- ColorfulMap (predecessor of ReColorfulMap): described by ReColorfulMap author as leaving heavy caches / reload pain - [Hangar ReColorfulMap](https://hangar.papermc.io/zhangyuheng/ReColorfulMap)

### Inferences
- For Paper 26.3 shortlist, drop Image Map / Image Map Plus / URLIMAGETOOMAPART / ImageCanvas / Custom Maps / Cartography unless a jar is proven on 26.3.
- ImageOnMap itself is abandoned; ImageOnMapReborn is the maintained drop-in path if preserving old ImageOnMap data matters.

### Gaps
- Exhaustive SpigotMC category crawl for every "Fun" image plugin was not performed.
- SushiImage (legacy on this server's old data/) was excluded by assignment and not re-evaluated here.

## Quick shortlist vs Paper 26.3 + Geyser (plugin-only)

### Takeaway
Prioritize Frameify, ImageOnMapReborn, and Image-To-Painting for URL→WxH map posters on Paper 26.3; treat MapPaint as a maintained hybrid; treat Emage as GIF specialist with Geyser risk; ignore Fabric Image2Map for this stack.

### Cited Findings
- Target server: Paper **26.3-258**, Java 25, Geyser Standalone + Floodgate, no mods/, no Folia - [server_context.md](server_context.md)
- Frameify explicitly lists **26.3** + Java 25+ + Paper/Purpur - [Modrinth Frameify](https://modrinth.com/plugin/frameify)
- Image-To-Painting 1.4.0 and MapPaint 1.0.0 explicitly pin **26.3** - [Hangar Image-To-Painting 1.4.0](https://hangar.papermc.io/Depletion1/Image-To-Painting/versions/1.4.0); [Hangar MapPaint](https://hangar.papermc.io/BbIJABNPOBATEJb/MapPaint)
- ImageOnMapReborn tested on **26.3** - [GitHub ImageOnMapReborn](https://github.com/Optiblur/ImageOnMapReborn)
- Geyser Bedrock map pain is documented for ImageFrame-class maps - [Geyser#6569](https://github.com/GeyserMC/Geyser/issues/6569)

### Inferences
- If Geyser players will see large map walls, prefer static baked vanilla maps and avoid dense animated GIFs until tested.
- Frameify's "survives plugin removal" baking is operationally attractive for this server; MapPaint's opposite (maps empty without plugin) is a persistence downside.

### Gaps
- No side-by-side Geyser render test of Frameify vs ImageOnMapReborn vs Image-To-Painting on this host.
- No confirmation whether Frameify ARR license constraints conflict with operator policy.
