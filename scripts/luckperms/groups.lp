# LuckPerms group definitions for trapaholics (ARCHITECTURE.md §6).
#
# Applied by scripts/luckperms/setup.sh over RCON. This file is the source of
# truth: each run (re)sets every node below in place, then setup.sh unsets any
# node the groups have in MariaDB that is NOT listed here. No `clear` (groups
# would be empty on a live server until re-added). Only `creategroup`,
# `setweight`, `setdisplayname`, `parent add` and `permission set` (contexts
# world=/server=) are allowed; setup.sh diffs against exactly these.
# (Users and their group memberships are NOT touched.)
#
# Contexts: world=survival | world=survival_nether | world=survival_the_end |
#           world=creative. Nodes without a world context apply everywhere.
# NO explicit false nodes (they beat admin's *), with ONE exception: admin's
# mv.bypass.gamemode.* nodes below (setup.sh allows exactly those).
#
# Multiverse 5 teleport (finer perms on by default for new installs):
#   multiverse.teleport.self.w.<world>
# Access: multiverse.access.<world>
# Gamemode: Multiverse-Core enforce-gamemode forces EVERYONE, admins included,
# into each world's gamemode. Admin `*` would include mv.bypass.gamemode.<world>
# (Multiverse-Core 5.8.2 node name), so admin gets explicit false nodes for it
# (an exact false node beats `*` in LuckPerms).
# Inventory bypass stays OFF (Multiverse-Inventories enable-bypass-permissions:
# false) so admin `*` does NOT skip the survival/creative inventory swap.

# --- groups ------------------------------------------------------------------
lp creategroup builder
lp creategroup admin

lp group default setweight 0
lp group builder setweight 50
lp group admin setweight 100
lp group builder setdisplayname Builder
lp group admin setdisplayname Admin

# =============================================================================
# default — everyone. Minimal. NO FAWE / VoxelSniper / WorldEdit anywhere.
# =============================================================================
# Chat / utilities (everywhere).
lp group default permission set essentials.msg true
lp group default permission set essentials.r true
lp group default permission set essentials.list true
lp group default permission set essentials.help true
lp group default permission set essentials.rules true
lp group default permission set essentials.motd true

# TPA + homes + spawn (shared natively across worlds on one server).
lp group default permission set essentials.tpa true
lp group default permission set essentials.tpahere true
lp group default permission set essentials.tpaccept true
lp group default permission set essentials.tpdeny true
lp group default permission set essentials.tpacancel true
lp group default permission set essentials.home true
lp group default permission set essentials.sethome true
lp group default permission set essentials.delhome true
lp group default permission set essentials.sethome.multiple true
lp group default permission set essentials.sethome.multiple.default true
lp group default permission set essentials.spawn true

# /survival and /creative (bukkit aliases → mv tp ll:<world>, Multiverse-Inventories
# last-location destination). Multiverse 5 finer teleport: self + type + world name:
# type `ll` for the aliases, type `w` for plain `/mv tp <world>`.
lp group default permission set multiverse.access.survival true
lp group default permission set multiverse.access.survival_nether true
lp group default permission set multiverse.access.survival_the_end true
lp group default permission set multiverse.access.creative true
lp group default permission set multiverse.teleport.self.w.survival true
lp group default permission set multiverse.teleport.self.w.survival_nether true
lp group default permission set multiverse.teleport.self.w.survival_the_end true
lp group default permission set multiverse.teleport.self.w.creative true
lp group default permission set multiverse.teleport.self.ll.survival true
lp group default permission set multiverse.teleport.self.ll.creative true
lp group default permission set multiverse.core.list.worlds true

# GriefPrevention claims — survival worlds only (plugin Mode.creative=Disabled).
lp group default permission set griefprevention.createclaims true world=survival
lp group default permission set griefprevention.claims true world=survival
lp group default permission set griefprevention.abandonallclaims true world=survival
lp group default permission set griefprevention.trapped true world=survival
lp group default permission set griefprevention.givepet true world=survival
lp group default permission set griefprevention.unlockdrops true world=survival
lp group default permission set griefprevention.ignore true world=survival
lp group default permission set griefprevention.createclaims true world=survival_nether
lp group default permission set griefprevention.claims true world=survival_nether
lp group default permission set griefprevention.abandonallclaims true world=survival_nether
lp group default permission set griefprevention.createclaims true world=survival_the_end
lp group default permission set griefprevention.claims true world=survival_the_end
lp group default permission set griefprevention.abandonallclaims true world=survival_the_end

# Creative: build by hand only (gamemode forced by Multiverse). No FAWE nodes.

# =============================================================================
# builder — inherits default; FAWE + FastAsyncVoxelSniper in world=creative ONLY.
# No essentials.tp: that allows /tp to any player without asking (use /tpa).
# =============================================================================
lp group builder parent add default

# FAWE builder limits (config/patches/minecraft/fawe-limits.json → limits.builder).
lp group builder permission set fawe.limit.builder true world=creative
# FAWE's fawe.permpack.basic (selections, region ops, generation, brushes, tools,
# clipboard, schematics, history) — NOT worldedit.*, so admin-only nodes are
# simply not granted. Never add explicit false nodes.
lp group builder permission set fawe.permpack.basic true world=creative
lp group builder permission set fawe.bypass.regions true world=creative
lp group builder permission set voxelsniper.sniper true world=creative
lp group builder permission set voxelsniper.brush.* true world=creative
lp group builder permission set voxelsniper.% true world=creative
lp group builder permission set essentials.speed true world=creative

# =============================================================================
# admin — everything, everywhere (except keeping their gamemode across worlds).
# =============================================================================
lp group admin permission set * true
# Admins are forced into each world's gamemode like everyone else (see header).
# These are the ONLY explicit false nodes allowed (checked by setup.sh).
lp group admin permission set mv.bypass.gamemode.survival false
lp group admin permission set mv.bypass.gamemode.survival_nether false
lp group admin permission set mv.bypass.gamemode.survival_the_end false
lp group admin permission set mv.bypass.gamemode.creative false
lp group admin permission set mv.bypass.gamemode.* false

lp sync
