# LuckPerms group definitions for trapaholics (ARCHITECTURE.md §6).
#
# Applied by scripts/luckperms/setup.sh, which sends every non-comment line to a
# backend console over RCON. This file is the source of truth: each run CLEARS
# the three groups and rebuilds them from here, so add permissions here, not
# in-game. (Users and their group memberships are NOT touched.)
#
# Contexts (LuckPerms "server" name per container, see docker-compose.yml):
#   server=velocity | server=survival | server=creative ; world=plots | world=build
# Nodes without a context apply everywhere, including Velocity.

# --- groups ------------------------------------------------------------------
lp creategroup builder
lp creategroup admin
lp group default clear
lp group builder clear
lp group admin clear

lp group default setweight 0
lp group builder setweight 50
lp group admin setweight 100
lp group builder setdisplayname Builder
lp group admin setdisplayname Admin

# =============================================================================
# default — everyone. Minimal.
# =============================================================================
# Network (Velocity): switch servers.
lp group default permission set velocity.command.server true

# Survival: TPA, homes (limit 3 = Essentials `sethome-multiple.default`), spawn,
# basic chat helpers, GriefPrevention claims.
lp group default permission set essentials.tpa true server=survival
lp group default permission set essentials.tpahere true server=survival
lp group default permission set essentials.tpaccept true server=survival
lp group default permission set essentials.tpdeny true server=survival
lp group default permission set essentials.tpacancel true server=survival
lp group default permission set essentials.home true server=survival
lp group default permission set essentials.sethome true server=survival
lp group default permission set essentials.delhome true server=survival
lp group default permission set essentials.sethome.multiple true server=survival
lp group default permission set essentials.sethome.multiple.default true server=survival
lp group default permission set essentials.spawn true server=survival
lp group default permission set essentials.msg true
lp group default permission set essentials.r true
lp group default permission set essentials.list true
lp group default permission set essentials.help true
lp group default permission set essentials.rules true
lp group default permission set essentials.motd true
lp group default permission set griefprevention.createclaims true server=survival
lp group default permission set griefprevention.claims true server=survival
lp group default permission set griefprevention.abandonallclaims true server=survival
lp group default permission set griefprevention.trapped true server=survival
lp group default permission set griefprevention.givepet true server=survival
lp group default permission set griefprevention.unlockdrops true server=survival
lp group default permission set griefprevention.ignore true server=survival

# Creative: one plot via /plot auto (or /plot claim), build in own plot.
# PlotSquared's `plots.permpack.basic` minus plots.download / plots.save / plots.buy /
# plots.merge*, listed explicitly instead of negated (see the note under builder).
lp group default permission set plots.plot.1 true server=creative
lp group default permission set plots.use true server=creative
lp group default permission set plots.info true server=creative
lp group default permission set plots.claim true server=creative
lp group default permission set plots.auto true server=creative
lp group default permission set plots.home true server=creative
lp group default permission set plots.clear true server=creative
lp group default permission set plots.delete true server=creative
lp group default permission set plots.music true server=creative
lp group default permission set plots.list true server=creative
lp group default permission set plots.list.mine true server=creative
lp group default permission set plots.list.shared true server=creative
lp group default permission set plots.list.world true server=creative
lp group default permission set plots.list.all true server=creative
lp group default permission set plots.visit true server=creative
lp group default permission set plots.visit.owned true server=creative
lp group default permission set plots.visit.shared true server=creative
lp group default permission set plots.visit.other true server=creative
lp group default permission set plots.set true server=creative
lp group default permission set plots.set.flag true server=creative
lp group default permission set plots.set.biome true server=creative
lp group default permission set plots.set.home true server=creative
lp group default permission set plots.set.description true server=creative
lp group default permission set plots.description true server=creative
lp group default permission set plots.flag true server=creative
lp group default permission set plots.flag.add true server=creative
lp group default permission set plots.flag.remove true server=creative
lp group default permission set plots.flag.list true server=creative
lp group default permission set plots.flag.info true server=creative
lp group default permission set plots.chat true server=creative
lp group default permission set plots.confirm true server=creative
lp group default permission set plots.toggle true server=creative
lp group default permission set plots.toggle.titles true server=creative
lp group default permission set plots.toggle.chat true server=creative
lp group default permission set plots.toggle.time true server=creative
lp group default permission set plots.alias true server=creative
lp group default permission set plots.alias.set true server=creative
lp group default permission set plots.alias.remove true server=creative
lp group default permission set plots.denied true server=creative
lp group default permission set plots.add true server=creative
lp group default permission set plots.trust true server=creative
lp group default permission set plots.deny true server=creative
lp group default permission set plots.remove true server=creative
lp group default permission set plots.untrust true server=creative
lp group default permission set plots.undeny true server=creative
lp group default permission set plots.kick true server=creative
lp group default permission set plots.done true server=creative
lp group default permission set plots.continue true server=creative
lp group default permission set plots.middle true server=creative
lp group default permission set essentials.tpa true server=creative
lp group default permission set essentials.tpaccept true server=creative
lp group default permission set essentials.tpdeny true server=creative

# Creative: FAWE only inside plots the player owns/was added to (FAWE region
# restrictions + `fawe.plotsquared`), basic WorldEdit commands, plots world only.
# Limits come from FAWE `limits.default` (config/patches/creative/fawe-limits.json).
lp group default permission set fawe.plotsquared true server=creative world=plots
lp group default permission set worldedit.wand true server=creative world=plots
lp group default permission set worldedit.selection.* true server=creative world=plots
lp group default permission set worldedit.region.set true server=creative world=plots
lp group default permission set worldedit.region.replace true server=creative world=plots
lp group default permission set worldedit.region.walls true server=creative world=plots
lp group default permission set worldedit.region.faces true server=creative world=plots
lp group default permission set worldedit.region.overlay true server=creative world=plots
lp group default permission set worldedit.region.stack true server=creative world=plots
lp group default permission set worldedit.region.move true server=creative world=plots
lp group default permission set worldedit.history.undo true server=creative world=plots
lp group default permission set worldedit.history.redo true server=creative world=plots
lp group default permission set worldedit.clipboard.copy true server=creative world=plots
lp group default permission set worldedit.clipboard.cut true server=creative world=plots
lp group default permission set worldedit.clipboard.paste true server=creative world=plots
lp group default permission set worldedit.clipboard.rotate true server=creative world=plots
lp group default permission set worldedit.clipboard.flip true server=creative world=plots
lp group default permission set worldedit.generation.sphere true server=creative world=plots
lp group default permission set worldedit.generation.cylinder true server=creative world=plots
lp group default permission set worldedit.generation.pyramid true server=creative world=plots
lp group default permission set worldedit.analysis.count true server=creative world=plots
lp group default permission set worldedit.analysis.distr true server=creative world=plots

# =============================================================================
# builder — inherits default; extra powers on creative only.
# =============================================================================
lp group builder parent add default

# Higher FAWE limits everywhere on creative (FAWE `limits.builder`).
lp group builder permission set fawe.limit.builder true server=creative
# Build world: build anywhere (also a member of the WorldGuard __global__ region
# there via g:builder, see setup.sh), FAWE with no region mask, and
# FastAsyncVoxelSniper terrain tools.
# WorldEdit commands come from FAWE's own `fawe.permpack.basic` (selections,
# region ops, generation, brushes, tools, clipboard, schematics, history), NOT
# `worldedit.*`, so admin-only nodes (worldedit.reload,
# worldedit.limit.unrestricted, ...) are simply not granted. Never add explicit
# `false` nodes to builder/default: an exact `false` beats a `*` wildcard, so a
# user in both admin and builder would lose those permissions.
lp group builder permission set worldguard.region.bypass.build true server=creative world=build
lp group builder permission set fawe.bypass.regions true server=creative world=build
lp group builder permission set fawe.permpack.basic true server=creative world=build
lp group builder permission set voxelsniper.sniper true server=creative world=build
lp group builder permission set voxelsniper.brush.* true server=creative world=build
# Creative utilities.
lp group builder permission set essentials.speed true server=creative
lp group builder permission set essentials.tp true server=creative

# =============================================================================
# admin — everything, on every server (including Velocity).
# =============================================================================
lp group admin permission set * true

lp sync
