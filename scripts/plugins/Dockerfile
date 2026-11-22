# Builder image for plugins that are compiled from source (see scripts/build-plugins.sh).
#
# JDK 25 is the main toolchain (Maven + Gradle run on it). PlotSquared's Gradle
# build pins a Java 21 toolchain, so a JDK 21 is copied in as well and handed to
# Gradle through org.gradle.java.installations.paths (no toolchain auto-download).
# Base images are pinned by exact tag.
FROM eclipse-temurin:21.0.13_9-jdk AS jdk21

FROM maven:3.9.16-eclipse-temurin-25
COPY --from=jdk21 /opt/java/openjdk /opt/jdk21
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
