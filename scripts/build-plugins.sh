#!/usr/bin/env bash
# Builds/downloads the plugin jars that are NOT pulled from Modrinth by compose,
# using only Docker on the host (JDK 25 builder image, see scripts/plugins/).
#
#   PlotSquared 7.6.1        -> plugins-built/creative/   (GPL source build)
#   CoreProtect CE 25.0      -> plugins-built/survival/   (source build, Paper 26.3)
#   EssentialsX(+Spawn) dev  -> plugins-built/{survival,creative}/ (sha256-verified)
#
# Pins live in scripts/plugins/versions.env. Output dirs are gitignored and are
# mounted read-only at /plugins in the survival/creative containers; the itzg
# image copies them into /data/plugins on start.
#
# Usage: scripts/build-plugins.sh            # build everything (re-runnable)
#        scripts/build-plugins.sh --clean    # also wipe source checkouts + caches
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source-path=SCRIPTDIR source=plugins/versions.env
. "$ROOT/scripts/plugins/versions.env"

IMAGE="trapaholics-plugin-builder:1"
WORK="$ROOT/.build"
OUT="$ROOT/plugins-built"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "docker is required"

if [[ "${1:-}" == "--clean" ]]; then
  log "Removing $WORK"
  rm -rf "$WORK"
fi

mkdir -p "$WORK/src" "$WORK/home" "$WORK/cache/m2" "$WORK/cache/gradle" \
         "$OUT/survival" "$OUT/creative"

log "Building builder image $IMAGE"
docker build -q -t "$IMAGE" "$ROOT/scripts/plugins" >/dev/null

# Run a command inside the builder as the invoking user, with /work = .build/.
in_builder() {
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/work/home \
    -e GRADLE_USER_HOME=/work/cache/gradle \
    -e MAVEN_OPTS="-Dmaven.repo.local=/work/cache/m2" \
    -v "$WORK:/work" -w /work \
    "$IMAGE" "$@"
}

# checkout <dir> <repo> <ref> <commit>
# Fetches exactly <commit>, checks it out clean, and verifies it. When <ref> is
# a tag, also verifies the remote tag still points at <commit>.
checkout() {
  local dir="$1" repo="$2" ref="$3" commit="$4"
  log "Checking out $dir @ $ref ($commit)"
  # shellcheck disable=SC2016  # expanded inside the container
  in_builder bash -euo pipefail -c '
    dir="$1"; repo="$2"; ref="$3"; commit="$4"
    if [ ! -d "src/$dir/.git" ]; then
      git init -q "src/$dir"
      git -C "src/$dir" remote add origin "$repo"
    fi
    cd "src/$dir"
    git remote set-url origin "$repo"
    tag_sha="$(git ls-remote origin "refs/tags/$ref^{}" "refs/tags/$ref" | head -n1 | cut -f1)"
    if [ -n "$tag_sha" ] && [ "$tag_sha" != "$commit" ]; then
      echo "Tag $ref points at $tag_sha, expected $commit" >&2; exit 1
    fi
    git fetch -q --depth 1 origin "$commit"
    git -c advice.detachedHead=false checkout -q --force FETCH_HEAD
    git clean -q -fdx
    head="$(git rev-parse HEAD)"
    [ "$head" = "$commit" ] || { echo "HEAD $head != $commit" >&2; exit 1; }
  ' _ "$dir" "$repo" "$ref" "$commit"
}

# fetch_verified <url> <sha256> <dest-in-.build>
fetch_verified() {
  local url="$1" sha="$2" dest="$3"
  log "Downloading $(basename "$dest")"
  # shellcheck disable=SC2016  # expanded inside the container
  in_builder bash -euo pipefail -c '
    curl -fsSL --retry 3 -o "$3.tmp" "$1"
    echo "$2  $3.tmp" | sha256sum -c --quiet -
    mv "$3.tmp" "$3"
  ' _ "$url" "$sha" "$dest"
}

# --- PlotSquared ------------------------------------------------------------
checkout plotsquared "$PLOTSQUARED_REPO" "$PLOTSQUARED_REF" "$PLOTSQUARED_COMMIT"
log "Building PlotSquared $PLOTSQUARED_REF"
in_builder bash -euo pipefail -c '
  cd src/plotsquared
  ./gradlew --no-daemon -q \
    -Porg.gradle.java.installations.paths=/opt/jdk21 \
    -Porg.gradle.java.installations.auto-download=false \
    :plotsquared-bukkit:shadowJar
'
ps_jar="$WORK/src/plotsquared/Bukkit/build/libs/plotsquared-bukkit-${PLOTSQUARED_REF}.jar"
[[ -f "$ps_jar" ]] || die "PlotSquared jar not found at $ps_jar"

# --- CoreProtect ------------------------------------------------------------
checkout coreprotect "$COREPROTECT_REPO" "$COREPROTECT_REF" "$COREPROTECT_COMMIT"
log "Building CoreProtect @ $COREPROTECT_COMMIT"
in_builder bash -euo pipefail -c '
  cd src/coreprotect
  mvn -B -q -DskipTests package
'
cp_jar="$(find "$WORK/src/coreprotect/target" -maxdepth 1 -name 'CoreProtect-*.jar' \
          ! -name '*-shaded.jar' ! -name 'original-*' | head -n1)"
[[ -n "$cp_jar" && -f "$cp_jar" ]] || die "CoreProtect jar not found in target/"

# --- EssentialsX ------------------------------------------------------------
enc_ver="${ESSENTIALSX_VERSION//+/%2B}"
fetch_verified "$ESSENTIALSX_BUILD_URL/EssentialsX-${enc_ver}.jar" \
  "$ESSENTIALSX_SHA256" "EssentialsX.jar"
fetch_verified "$ESSENTIALSX_BUILD_URL/EssentialsXSpawn-${enc_ver}.jar" \
  "$ESSENTIALSXSPAWN_SHA256" "EssentialsXSpawn.jar"

# --- Install into the per-server output dirs -------------------------------
log "Installing jars into $OUT"
rm -f "$OUT"/survival/*.jar "$OUT"/creative/*.jar
cp "$WORK/EssentialsX.jar"      "$OUT/survival/EssentialsX-${ESSENTIALSX_VERSION}.jar"
cp "$WORK/EssentialsXSpawn.jar" "$OUT/survival/EssentialsXSpawn-${ESSENTIALSX_VERSION}.jar"
cp "$cp_jar"                    "$OUT/survival/$(basename "$cp_jar")"
cp "$WORK/EssentialsX.jar"      "$OUT/creative/EssentialsX-${ESSENTIALSX_VERSION}.jar"
cp "$ps_jar"                    "$OUT/creative/$(basename "$ps_jar")"

(
  cd "$OUT"
  {
    echo "# Generated by scripts/build-plugins.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# PlotSquared $PLOTSQUARED_REF @ $PLOTSQUARED_COMMIT"
    echo "# CoreProtect $COREPROTECT_REF @ $COREPROTECT_COMMIT"
    echo "# EssentialsX $ESSENTIALSX_VERSION"
    find survival creative -name '*.jar' -type f -print0 | sort -z | xargs -0 sha256sum
  } > MANIFEST.txt
)
cat "$OUT/MANIFEST.txt"
log "Done."
