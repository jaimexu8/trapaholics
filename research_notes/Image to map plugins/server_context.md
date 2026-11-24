Server facts for researchers:
# Server context (read-only observation of /home/jaime/moth/mc)

- Platform: Paper (TYPE: PAPER via itzg/minecraft-server:2026.11.0-java25)
- Minecraft / API version: 26.3
- Paper build: 258 (jar: minecraft/paper-26.3-258.jar)
- Log confirmation: "Loading Paper 26.3-258-main@9ee1fac ... for Minecraft 26.3"; "Implementing API version 26.3.build.258-stable"
- Not Folia; single Paper process
- Geyser Standalone + Floodgate Spigot 2.2.5-b141 present (Bedrock via NetherNet)
- No mods/ directory; plugin-only stack
- Live plugins under minecraft/plugins/: Chunky, CoreProtect, EssentialsX(+Spawn), FAWE, FastAsyncVoxelSniper, GriefPrevention, LuckPerms, Multiverse-*, WorldGuard, floodgate, spark (bundled). NO image/map plugin currently installed in live plugins.
- Legacy data/ (old 26.2 stack, unused per DEPLOY.md) had SushiImage-0.5.jar and SushiImage/ config dir. ARCHITECTURE.md roadmap/history mentions SushiImage with EssentialsX/spark on an earlier phase.
- Java 25 required for Paper 26.x
- Compatibility target for plugins: Paper/Bukkit API 26.3; Geyser players matter; Folia not required.

Sources: docker-compose.yml; minecraft/logs/latest.log; DEPLOY.md; ARCHITECTURE.md; directory listings of minecraft/plugins and data/plugins.
