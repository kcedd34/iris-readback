#!/usr/bin/env bash
# The preflight accepts the demo passwords that reach the product intact and refuses the ones that would not, with no stack and no cost.
set -uo pipefail
cd "$(dirname "$0")/../.."
fail=0
file="$(mktemp)"
trap 'rm -f "$file"' EXIT
expect() { # expect accept|refuse "what" "content of .env". The variable is unset: it would win over the file (the battery exports one).
  printf '%b' "$3" > "$file"
  if env -u READBACK_DEMO_PASSWORD READBACK_PREFLIGHT_PASSWORD_ONLY=1 READBACK_ENV_FILE="$file" src/ops/preflight.sh >/dev/null 2>&1; then got=accept; else got=refuse; fi
  [ "$got" = "$1" ] || { echo "FAIL: $2: expected $1, got $got"; fail=1; }
}
expect refuse "a single dollar sign in .env"           'READBACK_DEMO_PASSWORD=com$dolar\n'
expect refuse "a dollar sign inside double quotes"     'READBACK_DEMO_PASSWORD="com$dolar"\n'
expect accept "a doubled dollar sign"                  'READBACK_DEMO_PASSWORD=com$$dolar\n'
expect accept "a dollar sign inside single quotes"     "READBACK_DEMO_PASSWORD='com\$dolar'\n"
expect accept "double quote inside"                    'READBACK_DEMO_PASSWORD=com"aspas\n'
expect accept "apostrophe inside"                      "READBACK_DEMO_PASSWORD=com'apostrofo\n"
expect refuse "a hash after a space (a comment in .env)" 'READBACK_DEMO_PASSWORD=com #hash\n'
expect accept "a hash after a space inside single quotes" "READBACK_DEMO_PASSWORD='com #hash'\n"
expect accept "hash inside"                            'READBACK_DEMO_PASSWORD=com#hash\n'
expect accept "exclamation, backslash, ampersand, semicolon" 'READBACK_DEMO_PASSWORD=a!b\\c&d;e\n'
expect accept "a space inside"                         'READBACK_DEMO_PASSWORD=com espaco\n'
expect refuse "a space at the end"                     'READBACK_DEMO_PASSWORD=comespaco \n'
expect refuse "a space at the start"                   'READBACK_DEMO_PASSWORD= comespaco\n'
expect refuse "a control character"                    'READBACK_DEMO_PASSWORD=com\ttab\n'
expect accept "an empty password (one is generated)"   'READBACK_DEMO_PASSWORD=\n'
expect accept "no password line"                       'OPENAI_API_KEY=\n'
# The environment variable is passed on untouched by compose: a dollar sign is fine there.
if env READBACK_DEMO_PASSWORD='com$dolar' READBACK_PREFLIGHT_PASSWORD_ONLY=1 READBACK_ENV_FILE=/nonexistent src/ops/preflight.sh >/dev/null 2>&1; then :; else echo "FAIL: a dollar sign in the environment variable was refused"; fail=1; fi
if env READBACK_DEMO_PASSWORD=' x' READBACK_PREFLIGHT_PASSWORD_ONLY=1 src/ops/preflight.sh >/dev/null 2>&1; then echo "FAIL: a leading space in the environment variable was accepted"; fail=1; fi

# The image check, with a stand-in for docker that knows only the images named in LOADED. No stack, no image needed.
stub="$(mktemp -d)"
trap 'rm -f "$file"; rm -rf "$stub"' EXIT
printf '#!/usr/bin/env bash\n[ "$1 $2" = "image inspect" ] && case " $LOADED " in *" $3 "*) exit 0;; esac\nexit 1\n' > "$stub/docker"
chmod +x "$stub/docker"
b154=irishealth-community:2026.3.0AI.154.0
b109=irishealth-community:2027.1.0AI.109.0
image_case() { # image_case "what" "loaded images" "READBACK_BASE_IMAGE" "env file content" accept|refuse "text the output must hold"
  printf '%b' "$4" > "$file"
  out="$(env -u READBACK_BASE_IMAGE ${3:+READBACK_BASE_IMAGE=$3} LOADED="$2" PATH="$stub:$PATH" READBACK_DEMO_PASSWORD=x READBACK_ENV_FILE="$file" src/ops/preflight.sh 2>&1)" && got=accept || got=refuse
  [ "$got" = "$5" ] || { echo "FAIL: $1: expected $5, got $got"; fail=1; }
  case "$out" in *"$6"*) ;; *) echo "FAIL: $1: the message lacks '$6'"; fail=1 ;; esac
}
image_case "build 154 by default"               "$b154"       ""     ''                                accept "build 154"
image_case "build 109 from the environment"     "$b109"       "$b109" ''                               accept "build 109"
image_case "build 109 from .env"                "$b109"       ""     "READBACK_BASE_IMAGE=$b109\n"     accept "build 109"
image_case "nothing loaded names both builds"   ""            ""     ''                                refuse "irishealth-community-2027.1.0AI.109.0-docker.tar.gz"
image_case "nothing loaded gives the 154 steps" ""            ""     ''                                refuse "docker tag <name-printed-by-docker-load>:<tag> $b154"
image_case "only 109 loaded, 154 chosen"        "$b109"       ""     ''                                refuse "READBACK_BASE_IMAGE=$b109"
image_case "only 154 loaded, 109 chosen"        "$b154"       "$b109" ''                               refuse "READBACK_BASE_IMAGE=$b154"
image_case "another name is used as it is"      "my/own:tag"  "my/own:tag" ''                          accept "Only build 154"
[ "$fail" = "0" ] && echo "password preflight check passed"
exit "$fail"
