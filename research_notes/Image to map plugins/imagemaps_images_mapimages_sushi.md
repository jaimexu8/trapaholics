# ImageMaps, Images (Spigot), MapImages/MapImage, and SushiImage

Research date: 2026-11-23. Target: Paper Minecraft **26.3** (not Folia), plugin-only, with Geyser/Floodgate. Version note: Mojang/Paper moved from `1.21.x` labeling to year-style `26.x` in 2026; marketplace pages often list both.

## Identity and name collisions (which project is which)

### Takeaway
Four distinct projects match the requested names; "ImageMaps" and "MapImages" both collide with other plugins, so exact marketplace/GitHub identity matters.

### Cited Findings
- **ImageMaps (classic / Spigot + GitHub)** is SydMontague's Bukkit plugin (Spigot resource 81851), jar/command family `/imagemap`, source https://github.com/SydMontague/ImageMaps - [SpigotMC ImageMaps](https://www.spigotmc.org/resources/imagemaps.81851/); [GitHub SydMontague/ImageMaps](https://github.com/SydMontague/ImageMaps)
- **ImageMaps (Modrinth, different plugin)** by RealDoggoHitman/Saltzus is a separate MIT project with only command `/imagemaps:createmap (url)`, Folia+Paper loaders, single release `1.0` dated 2024-11-01 - [Modrinth ImageMaps](https://modrinth.com/mod/imagemaps); [Modrinth API project](https://api.modrinth.com/v2/project/imagemaps); [version API](https://api.modrinth.com/v2/project/imagemaps/version)
- **Images (SpigotMC)** is Andavin's **Custom Images** (resource 53036); download jar is `images-2.x.x.jar`, plugin name Images, commands under `/image` - [SpigotMC Custom Images](https://www.spigotmc.org/resources/custom-images.53036/); [GitHub Andavin/Images](https://github.com/Andavin/Images)
- **MapImages** as an exact Spigot resource name was not found; the closest maintained URL-to-map-item tool is **MapImage** (singular) by TomMustBe12 on Modrinth/GitHub (`/mapimage`) - [Modrinth MapImage](https://modrinth.com/mod/mapimage); [GitHub tommustbe12com/MapImage](https://github.com/tommustbe12com/MapImage). Older unrelated names include MapImg (Spigot 72748, 1.14-era) - [SpigotMC MapImg](https://www.spigotmc.org/resources/mapimg.72748/)
- **SushiImage** is the internal plugin name for Spigot resource **"Map to Image (1.20.6-26.2)"** by `noggin_th` / author string `NogginTime`; permission `sushiimage.admin`; update notes explicitly say "SushiImage frames" - [SpigotMC Map to Image](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/); [updates](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/updates)
- This server's unused `data/plugins/` contains `SushiImage-0.5.jar` and `SushiImage/` (`config.yml`, `sushiimage.db`, `Images/`); live `minecraft/plugins/` does not include it - [local path `/home/jaime/moth/mc/data/plugins/SushiImage-0.5.jar`](file:///home/jaime/moth/mc/data/plugins/SushiImage-0.5.jar); [server_context.md](file:///home/jaime/moth/mc/research_notes/Image%20to%20map%20plugins/server_context.md)
- Extracted `plugin.yml` from the local jar: `name: SushiImage`, `version: '0.5'`, `authors: [ NogginTime ]`, `api-version: '1.20'`, command `image`, permission `sushiimage.admin` default op - [local jar extraction](file:///home/jaime/moth/mc/data/plugins/SushiImage-0.5.jar)

### Inferences
- For this research, treat **SydMontague ImageMaps** and **Modrinth ImageMaps** as separate candidates under the same marketing name.
- Treat user "MapImages" as **MapImage** unless a different jar name appears in server history (none found).

### Gaps
- No Hangar listings were found for these four under the exact names searched (unverified absence beyond searches performed).
- No public GitHub for SushiImage/Map to Image was found under `noggin_th` / NogginTime.

## Supported platforms and latest Minecraft version (late 2026)

### Takeaway
Only **Custom Images 2.5.12** and **SushiImage 0.5.1** publicly advertise tested **26.3** support; SydMontague ImageMaps 1.0.12 claims proper **26.x** compatibility via GitHub; MapImage tops out at listed **26.2**; Modrinth ImageMaps' 26.3 tag is metadata-only on a 2024 jar.

### Cited Findings
- **Custom Images / Images**: Native Major MC Version **26.3**; tested list includes 1.8 through 1.21 plus 26.1/26.2/26.3; update "Update for 26.3 and other minor fixes" dated **Oct 13, 2026** - [SpigotMC Custom Images](https://www.spigotmc.org/resources/custom-images.53036/); [updates](https://www.spigotmc.org/resources/custom-images.53036/updates)
- **SushiImage / Map to Image**: Title still says `(1.20.6-26.2)` but page lists tested **26.3**; update **"26.3 update (0.5.1)"** by noggin_th on **Oct 15, 2026** ("Support Minecraft 26.3"); Native Major still labeled 26.2 on the page header - [resource page](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/); [updates](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/updates)
- **SushiImage 0.5** (local jar / Jul 3, 2026 release): changelog under 0.3/0.5 targeted **1.20.6-26.2**, not 26.3 - [updates](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/updates)
- **MapImage 2.0**: Modrinth `game_versions` include through **26.2** (and 1.20.x/1.21.x) but **not 26.3**; loaders Bukkit/Paper/Spigot; published **2026-03-28** - [Modrinth API versions](https://api.modrinth.com/v2/project/mapimage/version); [project page](https://modrinth.com/mod/mapimage)
- **SydMontague ImageMaps 1.0.12**: GitHub release **2026-11-05**, body "- proper 26.x compatibility"; `pom.xml` depends on `spigot-api` **26.1-R0.1-SNAPSHOT**; Spigot resource page still shows last marketplace update **Aug 13, 2021** / version 1.0.10 / tested through 1.18 - [GitHub release 1.0.12](https://github.com/SydMontague/ImageMaps/releases/tag/1.0.12); [pom.xml](https://raw.githubusercontent.com/SydMontague/ImageMaps/master/pom.xml); [SpigotMC page](https://www.spigotmc.org/resources/imagemaps.81851/); [PR #73](https://github.com/SydMontague/ImageMaps/pull/73)
- **Modrinth ImageMaps 1.0**: only version ever; `date_published` **2024-11-01**; project `updated` also **2024-11-01**; version file originally listed game versions **1.20-1.21.4** on Modrinth version UI, while project-level API now lists up through **26.3** without a new jar - [version API](https://api.modrinth.com/v2/project/imagemaps/version); [project API](https://api.modrinth.com/v2/project/imagemaps); [version page historically 1.20-1.21.4](https://modrinth.com/plugin/imagemaps/version/1.0)

### Inferences
- For Paper **26.3**, safest marketplace-stated fits are Custom Images 2.5.12 and SushiImage **0.5.1** (not the server's leftover 0.5).
- SydMontague 1.0.12 is likely viable on 26.x Paper if built/released jar is used from GitHub, but **26.3-specific** smoke testing is not documented.
- Modrinth ImageMaps claiming 26.3 on the project card should be treated as **unverified marketplace version remapping**, not a 2026 rebuild.

### Gaps
- No independent runtime confirmation on Paper 26.3-258 for any of these plugins in this research pass.
- Folia: Modrinth ImageMaps lists Folia loader; others do not claim Folia (server does not need Folia).

## Last release date and maintenance status

### Takeaway
Custom Images and SydMontague ImageMaps (GitHub) are actively maintained in late 2026; SushiImage is young but updated through Oct 2026; MapImage last code release Mar 2026; Modrinth ImageMaps looks abandoned after a one-shot 2024 release.

### Cited Findings
- **Custom Images**: First release Feb 9, 2018; last Spigot update **Oct 13, 2026** (2.5.12); GitHub `pushed_at` **2026-10-30**, `updated_at` **2026-11-14**; ~494k Spigot downloads; 4.2/5 from 219 ratings - [SpigotMC](https://www.spigotmc.org/resources/custom-images.53036/); [GitHub API](https://api.github.com/repos/Andavin/Images)
- **SushiImage**: First Spigot release **Jun 30, 2026**; latest **0.5.1 Oct 15, 2026**; total downloads ~169 on resource page; 0 ratings - [SpigotMC](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/); [updates](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/updates)
- **MapImage**: First Modrinth publish **2025-06-12**; last version **2.0 on 2026-03-28**; GitHub last push **2026-03-28**, repo description still says `1.20.x-1.21.x` - [Modrinth API](https://api.modrinth.com/v2/project/mapimage); [GitHub API](https://api.github.com/repos/tommustbe12com/MapImage)
- **SydMontague ImageMaps**: Spigot marketplace stale since **2021-08-13** (1.0.10), but GitHub tags **1.0.11** then **1.0.12 (2026-11-05)** with MC 26 fix; author comment: had not followed MC versioning scheme - [Spigot updates](https://www.spigotmc.org/resources/imagemaps.81851/updates); [release 1.0.12](https://github.com/SydMontague/ImageMaps/releases/tag/1.0.12); [PR #73 comment](https://github.com/SydMontague/ImageMaps/pull/73)
- **Modrinth ImageMaps**: single release, project updated **2024-11-01**; no `source_url` / `issues_url` - [project API](https://api.modrinth.com/v2/project/imagemaps)

### Inferences
- Prefer GitHub artifacts for SydMontague ImageMaps over the Spigot 1.0.10 download.
- SushiImage is maintained by the same author as other "Sushi" plugins (DynamicShop) but is new and low-adoption.

### Gaps
- Whether Spigot will be updated to mirror ImageMaps 1.0.12 is unknown.
- SushiImage 0.5.1 jar contents were not downloaded in this pass (0.5 local jar analyzed instead).

## Command syntax for image URL + size (single vs multi-tile)

### Takeaway
True one-command URL-to-map-items is strongest in **MapImage** and **Modrinth ImageMaps**; Classic ImageMaps and Custom Images use file/URL create then place; SushiImage 0.5 loads **local files** with percent scale, not URL WxH in the command strings found.

### Cited Findings
- **MapImage**: `/mapimage <url>` or `/mapimage <url> <HxW>`; HxW is height x width in maps (e.g. `2x4`); maps given top-left to bottom-right; also local files beside `config.yml` in 2.0 - [GitHub README](https://raw.githubusercontent.com/tommustbe12com/MapImage/master/README.md); [Modrinth body](https://modrinth.com/mod/mapimage)
- **Modrinth ImageMaps**: `/imagemaps:createmap (url to image)`; no URL yields random cat picture; **no documented size/WxH argument** - [Modrinth ImageMaps](https://modrinth.com/mod/imagemaps)
- **SydMontague ImageMaps**: URL via `/imagemap download <filename> <sourceURL>` then place with `/imagemap place <filename> [frameInvisible] [frameFixed] [frameGlowing] [size]`; size scales image; default split into 128x128 tiles - [SpigotMC](https://www.spigotmc.org/resources/imagemaps.81851/); [GitHub README](https://github.com/SydMontague/ImageMaps)
- **Custom Images**: `/image create <file|URL> [scale percent]` e.g. `/image create https://somewebsite/image.jpg` or `/image create myImage.png 200`; URL requires `images.command.create.url` since Aug 6, 2025 security fix; scale is percent, not WxH map grid - [SpigotMC](https://www.spigotmc.org/resources/custom-images.53036/); [URL support update](https://www.spigotmc.org/resources/custom-images.53036/update?update=343854); [path/URL security update](https://www.spigotmc.org/resources/custom-images.53036/update?update=605199)
- **SushiImage 0.5**: public page lists `/image load`, `/image remove`, `/image reload`, `/image cancel` - [SpigotMC](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/). Class strings: `Usage: /image load <file> [size_percent]` and `Example: /image load 1.png 200`; after load: `Image selected. Right click a block to place it.` - [local jar ImageLoadCommand.class](file:///home/jaime/moth/mc/data/plugins/SushiImage-0.5.jar). Images live under `plugins/SushiImage/Images/` (local unused tree) - [local dir](file:///home/jaime/moth/mc/data/plugins/SushiImage/)

### Inferences
- If the requirement is literally "paste a URL and get map items," MapImage fits best.
- If the requirement is "show a URL/file image on a wall," Custom Images / SydMontague / SushiImage fit the place-into-world workflow; SushiImage as of 0.5 expects files already in its Images folder (no download command string found).

### Gaps
- Exact SushiImage 0.5.1 command changes (if any) vs 0.5 are undocumented beyond "Support Minecraft 26.3".
- Whether SushiImage accepts a URL argument in any undocumented path was not evidenced in bytecode strings (only file + size_percent).

## Multi-frame support; auto-placement into frames vs giving items

### Takeaway
MapImage **gives map items** (multi-tile matrix); Modrinth ImageMaps appears to give a map; SydMontague and SushiImage **auto-place item frames** on click; Custom Images uses **packet-based virtual frames**, not a handout of vanilla map items as the primary UX.

### Cited Findings
- **MapImage**: "The player receives the filled map in their inventory"; multi-map via HxW - [Modrinth MapImage](https://modrinth.com/mod/mapimage)
- **Modrinth ImageMaps**: marketed as converting images to maps via createmap; no frame auto-placement docs - [Modrinth ImageMaps](https://modrinth.com/mod/imagemaps)
- **SydMontague ImageMaps**: places maps into item frames from upper-left block click; multi-map by splitting to 128x128; optional invisible/fixed/glowing frames - [SpigotMC](https://www.spigotmc.org/resources/imagemaps.81851/)
- **SushiImage**: author: "I use actual Item Frame + Map to display image"; placement lifecycle creates frames then maps; conflict handling vs existing SushiImage frames - [SpigotMC](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/); [0.5 update](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/updates)
- **Custom Images**: rewritten to "packet based entities"; create then paste by clicking / air-click with item in hand; size driven by image resolution and scale percent (128px per block) - [SpigotMC](https://www.spigotmc.org/resources/custom-images.53036/)

### Inferences
- For Bedrock via Geyser, vanilla item-frame+map plugins (SushiImage, SydMontague, MapImage) are more likely to translate than Custom Images' custom packet pipeline (see Geyser section).
- Custom Images is a poor fit if operators need physical map items to carry/trade.

### Gaps
- Modrinth ImageMaps multi-tile behavior is undocumented (likely single map only).

## Persistence across restarts; GIF support

### Takeaway
All four mainstream options claim or implement persistence, with different storage models; **animated GIF** is not a documented feature for any of these four (MapImage accepts GIF as a static-capable format).

### Cited Findings
- **MapImage**: persists URL↔map ID in `config.yml`; re-renders after restart; **requires internet access to the image URL on every start/restart**; formats PNG/JPG/GIF/BMP/WEBP listed; no animation claim - [Modrinth](https://modrinth.com/mod/mapimage); [README](https://raw.githubusercontent.com/tommustbe12com/MapImage/master/README.md). Open issue "Failure to Re-download Map Image after restart" - [GitHub issues](https://github.com/tommustbe12com/MapImage/issues)
- **Custom Images**: SQLite (default) / MySQL / raw file DB; images reload with server - [SpigotMC](https://www.spigotmc.org/resources/custom-images.53036/). "Any image format that Java can support"; list command mainly PNG/JPG; **no animated GIF feature claim** - same page
- **SushiImage**: SQLite file `plugins/SushiImage/sushiimage.db` or MySQL; local unused config matches shipped defaults - [local config.yml](file:///home/jaime/moth/mc/data/plugins/SushiImage/config.yml); [SpigotMC](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/). Render path uses `javax.imageio.ImageIO` / `BufferedImage` / `StaticImageRenderer` class name - [local jar classes](file:///home/jaime/moth/mc/data/plugins/SushiImage-0.5.jar)
- **SydMontague ImageMaps**: maps.yml / images folder persistence described on resource; download stores files locally - [SpigotMC](https://www.spigotmc.org/resources/imagemaps.81851/)
- **Modrinth ImageMaps**: persistence/GIF not documented beyond createmap - [Modrinth](https://modrinth.com/mod/imagemaps)

### Inferences
- MapImage's restart dependence on remote URLs is an operational risk if hosts delete images.
- None of these four compete with ImageFrame-class animated GIF features (out of scope here but relevant as a gap vs alternatives).

### Gaps
- Confirmed animated-GIF behavior: **not documented** for SydMontague, Custom Images, SushiImage, or Modrinth ImageMaps.
- Whether Java ImageIO first-frame GIF decode works for SushiImage/Custom Images is unverified.

## Permissions, limits, Folia, and Geyser support

### Takeaway
Permissions are simple OP-centric on MapImage/SushiImage/Modrinth ImageMaps; Custom Images and SydMontague have finer nodes. Folia only claimed by Modrinth ImageMaps. Geyser: Custom Images has **known Bedrock visibility breakage** after 1.21+ packet changes; others use vanilla maps/frames (theoretically better) but lack explicit Geyser certification.

### Cited Findings
- **MapImage**: `mapimage.use` default OP - [Modrinth](https://modrinth.com/mod/mapimage). Warns excessive images increase RAM - same. No Folia loader - [API](https://api.modrinth.com/v2/project/mapimage)
- **SushiImage**: `sushiimage.admin` default op; limits `max-map-tiles: 1000`, `max-render-distance-blocks: 64`, `visible-item-frame: false` - [plugin.yml / config](file:///home/jaime/moth/mc/data/plugins/SushiImage-0.5.jar); [0.4 update](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/updates). Author notes client lag at 1000++ frames - [SpigotMC](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/)
- **Custom Images**: permissions `images.command.create`, `.delete`, `.delete.near`, `.list`, `.import`, `.transfer`, plus `.create.url` - [SpigotMC](https://www.spigotmc.org/resources/custom-images.53036/); [URL perm update](https://www.spigotmc.org/resources/custom-images.53036/update?update=605199). Folia request issue closed without confirming support - [GitHub #175](https://github.com/Andavin/Images/issues/175). Geyser: Jul 2025 report Bedrock players stopped seeing images; author suspects Netty pipeline listener vs Geyser on 1.21+ - [Spigot discussion p.40](https://www.spigotmc.org/threads/custom-images.302109/page-40)
- **SydMontague ImageMaps**: `imagemaps.*`, `.place`, `.download`, `.delete`, `.info`, `.list`, `.reload`, `.help`, `.toggleFixed`, `.toggleVisible` - [SpigotMC](https://www.spigotmc.org/resources/imagemaps.81851/). No Folia claim found.
- **Modrinth ImageMaps**: lists Folia+Paper; no permission docs on page - [Modrinth](https://modrinth.com/mod/imagemaps); [API](https://api.modrinth.com/v2/project/imagemaps)

### Inferences
- For this Geyser/Floodgate server, Custom Images is a **high risk** choice despite excellent Paper 26.3 maintenance.
- Vanilla map+item-frame approaches (SushiImage, SydMontague, MapImage) are the better Geyser bet, pending live testing.

### Gaps
- No primary-source Geyser test results for SushiImage, MapImage, or SydMontague ImageMaps on 26.3.
- Floodgate-specific interactions: none found.

## License, popularity, and open-issue health

### Takeaway
SydMontague ImageMaps and Custom Images are MIT open source with substantial history; MapImage is All-Rights-Reserved on Modrinth with small GitHub; SushiImage has no public source found; Modrinth ImageMaps is MIT but closed-source-on-Modrinth (no repo link).

### Cited Findings
- **SydMontague ImageMaps**: MIT; ~45 GitHub stars, 34 forks; ~4 open issues (search); Spigot all-time rating 4.4/5 (18) on older page data - [GitHub API license](https://api.github.com/repos/SydMontague/ImageMaps); [CurseForge license](https://www.curseforge.com/minecraft/bukkit-plugins/imagemaps/license); issue search via GitHub API (4 open)
- **Custom Images**: GitHub README states MIT; repo license field null / LICENSE 404; 100 stars, 68 forks, **41 open issues**; Spigot ~494k downloads - [GitHub README](https://github.com/Andavin/Images); [GitHub API](https://api.github.com/repos/Andavin/Images); [SpigotMC](https://www.spigotmc.org/resources/custom-images.53036/)
- **MapImage**: Modrinth license `LicenseRef-All-Rights-Reserved`; source on GitHub (no SPDX license in API); ~9.2k Modrinth downloads; 2 stars; **2 open issues** - [Modrinth API](https://api.modrinth.com/v2/project/mapimage); [GitHub API](https://api.github.com/repos/tommustbe12com/MapImage); [issues](https://github.com/tommustbe12com/MapImage/issues)
- **Modrinth ImageMaps**: MIT; ~13.1k downloads; 19 followers; no issues URL - [project API](https://api.modrinth.com/v2/project/imagemaps)
- **SushiImage**: no license stated on Spigot page; no source link; ~169 downloads; 0 ratings - [SpigotMC](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/)

### Inferences
- Custom Images' large open-issue count reflects popularity + ongoing version churn, not necessarily abandonment.
- SushiImage's closed source + tiny download count means higher unknown-risk for a production 26.3 box despite recent 26.3 update.

### Gaps
- Exact Custom Images SPDX license file missing from repo root.
- SushiImage license/source unavailable.

## Known problems and Paper 26.3 + Geyser fit

### Takeaway
Custom Images: Geyser breakage + packet/handler edge cases. MapImage: restart re-download failures and RAM. SydMontague: Spigot page stale; needed 26.x version-check fix. SushiImage: very new, file-based load, client entity cost. Modrinth ImageMaps: unverified on modern Paper.

### Cited Findings
- **Custom Images**: Geyser/Bedrock visibility reports after Netty listener change - [discussion](https://www.spigotmc.org/threads/custom-images.302109/page-40). Paper creative map pick quirks (blank until restart) noted in Apr 17, 2026 update - [updates](https://www.spigotmc.org/resources/custom-images.53036/updates). Memory complaints exist; author distinguishes oversized paste from true leaks - [Spigot reviews section](https://www.spigotmc.org/resources/custom-images.53036/). Duplicate handler / kick issues historically in tracker - [GitHub issues list](https://github.com/Andavin/Images/issues)
- **MapImage**: open issues on restart re-download failure and "a whole lot of errors"; RAM warning still on Modrinth body despite 1.2 memory fix changelog - [issues](https://github.com/tommustbe12com/MapImage/issues); [Modrinth](https://modrinth.com/mod/mapimage); [version 1.2 changelog via API](https://api.modrinth.com/v2/project/mapimage/version)
- **SydMontague ImageMaps**: frame visibility broken on MC 26 until PR #73 / 1.0.12; Spigot download still 1.0.10 unless using GitHub - [PR #73](https://github.com/SydMontague/ImageMaps/pull/73); [Spigot](https://www.spigotmc.org/resources/imagemaps.81851/)
- **SushiImage**: author warns large frame counts lag **clients**; 0.5 focused on placement conflicts and avoiding touching non-plugin frames; title/native version still 26.2 while 0.5.1 adds 26.3 - [SpigotMC](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/); [updates](https://www.spigotmc.org/resources/map-to-image-1-20-6-26-2.136618/updates)
- **Modrinth ImageMaps**: no source/issues; jar unchanged since 2024-11-01 while tags expanded - [API](https://api.modrinth.com/v2/project/imagemaps)

### Inferences
- **Best feature fit if URL -> inventory map tiles on Paper 26.3**: MapImage 2.0, with caveat that **26.3 is not listed** (26.2 max) and restart/URL dependency exists - smoke-test required.
- **Best maintained Paper 26.3 wall display**: Custom Images 2.5.12 for Java clients; **avoid or heavily test** under Geyser.
- **Best prior-art for this server's leftover data**: SushiImage **0.5.1** (upgrade from local 0.5) for 26.3 claim; workflow is file-in-folder + `/image load` + click place, not pure URL command.
- **SydMontague ImageMaps 1.0.12 from GitHub** is a solid vanilla-frame alternative if you accept download-then-place UX and build trust from recent 26.x fix.
- **Modrinth ImageMaps** is a weak candidate for production 26.3 despite Folia/26.3 tags.

### Gaps
- Side-by-side Geyser Bedrock screenshot verification on Paper 26.3-258 was not performed.
- Whether MapImage 2.0 binary runs unmodified on Paper 26.3 API is unverified.
- Whether SushiImage can ingest URLs by dropping downloaded files only, or has another entry path in 0.5.1, remains partially undocumented.
