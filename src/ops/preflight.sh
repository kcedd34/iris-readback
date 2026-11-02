#!/usr/bin/env bash
# Checks, before anything else runs, that the AI Hub build 154 image is present locally and that the demo password
# reaches the product exactly as it was written.
# The image must never be pulled from or pushed to a public registry.
set -uo pipefail
cd "$(dirname "$0")/../.."
image="${READBACK_BASE_IMAGE:-irishealth-community:2026.3.0AI.154.0}"

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

if docker image inspect "$image" >/dev/null 2>&1; then
  echo "Image $image found."
  exit 0
fi
cat >&2 <<MSG
Image $image is not loaded locally.

Download the IRIS for Health Community image with AI Hub (build 154) from the Early Access
portal as a .tar file, then load it and tag it with the name this project expects:

  docker load -i <downloaded-file>.tar
  docker tag <loaded-image-name>:<tag> $image

'docker images' shows the name the loaded image received. Then run this script again.
MSG
exit 1
