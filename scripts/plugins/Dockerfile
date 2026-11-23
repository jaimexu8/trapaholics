# Builder image for plugins that are compiled from source (see scripts/build-plugins.sh).
# JDK 25 is the toolchain (Maven). Base image pinned by exact tag.
FROM maven:3.9.16-eclipse-temurin-25
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
