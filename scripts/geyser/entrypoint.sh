#!/bin/sh
# Geyser container entrypoint (busybox sh in eclipse-temurin alpine).
#
# ./geyser/config.yml is seeded once from config/geyser/config.yml (`cp -n`,
# DEPLOY.md step 6) and is otherwise owned by the operator. The only value we
# manage here is the playit NXS signaling token, which must never be in git:
# when GEYSER_NXS_TOKEN is set in .env it is written into
# bedrock.signaling.nxs.token on every start. When it is unset, config.yml is
# left exactly as it is (so a token pasted by hand keeps working).
set -eu

CFG=/data/config.yml

if [ -n "${GEYSER_NXS_TOKEN:-}" ]; then
  if [ ! -f "$CFG" ]; then
    echo "geyser-entrypoint: $CFG missing; seed it first (DEPLOY.md step 6)" >&2
    exit 1
  fi
  tmp="$CFG.entrypoint.tmp"
  # Replace the `token:` key inside the `nxs:` block (any indentation). The
  # token is read from ENVIRON (no awk escape processing) and single-quoted
  # for YAML ('' escapes a literal quote).
  if ! awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    BEGIN { tok = ENVIRON["GEYSER_NXS_TOKEN"]; gsub(/\047/, "\047\047", tok); n = -1; done = 0 }
    {
      if (n >= 0 && $0 ~ /^ *[^ #]/ && indent($0) <= n) n = -1
      if (n >= 0 && $0 ~ /^ *token:/) {
        print substr($0, 1, indent($0)) "token: \047" tok "\047"; done++; next
      }
      if ($0 ~ /^ *nxs:[ \t]*$/) n = indent($0)
      print
    }
    END { exit done == 1 ? 0 : 1 }
  ' "$CFG" >"$tmp"; then
    rm -f "$tmp"
    echo "geyser-entrypoint: no single bedrock.signaling.nxs.token key in $CFG" >&2
    exit 1
  fi
  if cmp -s "$tmp" "$CFG"; then
    rm -f "$tmp"
  else
    cat "$tmp" >"$CFG"   # keep the file's owner/mode
    rm -f "$tmp"
    echo "geyser-entrypoint: wrote GEYSER_NXS_TOKEN into bedrock.signaling.nxs.token"
  fi
fi

exec java -jar /opt/Geyser-Standalone.jar --nogui
