#!/usr/bin/env bash
# Checks, before anything else runs, that the AI Hub image of the chosen Early Access build (154 or 109) is present locally
# and that the demo password reaches the product exactly as it was written.
# The build is chosen with READBACK_BASE_IMAGE (environment or .env); without it the product uses build 154.
# The image must never be pulled from or pushed to a public registry.
set -uo pipefail
cd "$(dirname "$0")/../.."
build154="irishealth-community:2026.3.0AI.154.0"
build109="irishealth-community:2027.1.0AI.109.0"

# The demo password. Whatever the person writes is passed on untouched, with two exceptions that would change it on the way:
#  - in the .env file compose reads a dollar sign as the start of a variable (com$dolar arrives as "com"): write $$ for a literal one;
#  - the product trims spaces at both ends and drops control characters, while the interface would send them as written.
# Everything else was measured to arrive intact: quotes, apostrophes, #, !, backslash, ampersand, spaces inside (docs/probes.md).
check_password() {
  local raw="" source=""
  if [ -n "${READBACK_DEMO_PASSWORD+x}" ]; then
    raw="$READBACK_DEMO_PASSWORD"; source="the environment variable READBACK_DEMO_PASSWORD"
  elif [ -f "${READBACK_ENV_FILE:-.env}" ]; then
    local line
    line="$(grep -m1 '^READBACK_DEMO_PASSWORD=' "${READBACK_ENV_FILE:-.env}" || true)"
    if [ -n "$line" ]; then
      raw="${line#READBACK_DEMO_PASSWORD=}"; source="READBACK_DEMO_PASSWORD in ${READBACK_ENV_FILE:-.env}"
      # Compose removes one pair of surrounding quotes; inside single quotes a dollar sign is literal, everywhere else $$ is $.
      local literal=0
      case "$raw" in
        \'*|\"*) ;;
        *)
          if printf '%s' "$raw" | grep -q '[[:space:]]#'; then
            cat >&2 <<MSG
The demo password in $source has a # after a space.
Compose reads that as the start of a comment in .env and drops the rest, so the accounts would be created with a shorter
password than the one you wrote. Remove the space before the #, or put the whole password in single quotes.
MSG
            return 1
          fi ;;
      esac
      case "$raw" in
        \'*\') raw="${raw#\'}"; raw="${raw%\'}"; literal=1 ;;
        \"*\") raw="${raw#\"}"; raw="${raw%\"}" ;;
      esac
      if [ "$literal" = "0" ] && printf '%s' "$raw" | grep -q '\$'; then
        if printf '%s' "${raw//\$\$/}" | grep -q '\$'; then
          cat >&2 <<MSG
The demo password in $source contains a dollar sign.
Compose reads a single dollar sign in .env as a variable ("com\$dolar" arrives as "com"), so the accounts would be created
with a different password than the one you wrote. Write two dollar signs for a literal one ("com\$\$dolar"), or leave the
dollar sign out.
MSG
          return 1
        fi
        raw="${raw//\$\$/\$}"
      fi
    fi
  fi
  [ -z "$raw" ] && return 0
  if [ "$raw" != "$(printf '%s' "$raw" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" ]; then
    echo "The demo password in $source starts or ends with a space. The product trims it, so the page and the accounts would disagree. Remove the space." >&2
    return 1
  fi
  if printf '%s' "$raw" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "The demo password in $source holds a control character (a tab, for example). Use printable characters only." >&2
    return 1
  fi
  return 0
}

check_password || exit 1
if [ "${READBACK_PREFLIGHT_PASSWORD_ONLY:-}" = "1" ]; then
  echo "Demo password accepted."
  exit 0
fi

# The chosen image: the environment, then the .env file compose reads, then build 154.
image="${READBACK_BASE_IMAGE:-}"
if [ -z "$image" ] && [ -f "${READBACK_ENV_FILE:-.env}" ]; then
  image="$(grep -m1 '^READBACK_BASE_IMAGE=' "${READBACK_ENV_FILE:-.env}" | cut -d= -f2- | sed -e "s/^[\"']//" -e "s/[\"']\$//" || true)"
fi
image="${image:-$build154}"

load_steps() {
  cat <<MSG

Download the IRIS for Health Community image with AI Hub from the Early Access portal, then load it and tag it with the
name this project expects. The product runs on two Early Access builds; use the one the portal offers you.

  Build 154 (the default):
    docker load -i irishealth-community-2026.3.0AI.154.0-docker.tar.gz
    docker tag <name-printed-by-docker-load>:<tag> $build154

  Build 109:
    docker load -i irishealth-community-2027.1.0AI.109.0-docker.tar.gz
    docker tag <name-printed-by-docker-load>:<tag> $build109
    echo 'READBACK_BASE_IMAGE=$build109' >> .env     # the default is build 154

'docker images | grep irishealth' shows the name a loaded image received. Then run this script again.
MSG
}

if docker image inspect "$image" >/dev/null 2>&1; then
  case "$image" in
    "$build154") echo "Image $image found (AI Hub Early Access build 154)." ;;
    "$build109") echo "Image $image found (AI Hub Early Access build 109)." ;;
    *) echo "Image $image found. Only build 154 ($build154) and build 109 ($build109) were tested; this one is used as it is." ;;
  esac
  exit 0
fi

echo "Image $image is not loaded locally." >&2
for other in "$build154" "$build109"; do
  if [ "$other" != "$image" ] && docker image inspect "$other" >/dev/null 2>&1; then
    echo "The image $other is loaded, though. To use it, set READBACK_BASE_IMAGE=$other in .env (or in the environment), or load $image as below." >&2
  fi
done
load_steps >&2
exit 1
