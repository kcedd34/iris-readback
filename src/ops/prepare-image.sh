#!/usr/bin/env bash
# Runs once while the image is built, so the running container needs no network.
#  1. The local embedding model is downloaded into FASTEMBED_CACHE_DIR (soft: retrieval reports itself unavailable without it).
#  2. The IPM client and the community package workflow-rest are installed (hard: the build fails if they do not install).
# The network steps are retried, because a build on a juror's machine should not fail on one dropped connection.
set -uo pipefail

installer_url="https://pm.community.intersystems.com/packages/zpm/latest/installer"
registry_url="https://pm.community.intersystems.com/"
attempts="${READBACK_BUILD_ATTEMPTS:-4}"

retry() {
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then return 1; fi
    echo "prepare-image: attempt $n of $attempts failed, retrying: $*" >&2
    sleep $((n * 5)); n=$((n + 1))
  done
}

session() { iris session IRIS -U USER; }

iris start IRIS quietly || { echo "prepare-image: IRIS did not start" >&2; exit 1; }
status=0

printf 'set emb=##class(%%AI.RAG.Embedding.FastEmbed).Create()\nhalt\n' | session >/dev/null 2>&1 \
  || echo "prepare-image: embedding model warm-up skipped: retrieval will report itself unavailable"

install_workflow() {
  rm -f /tmp/zpm-installer.xml
  wget -q -T 30 -O /tmp/zpm-installer.xml "$installer_url" || return 1
  out="$(session <<OS 2>&1
set sc=\$system.OBJ.Load("/tmp/zpm-installer.xml","c")
zpm "repo -n registry -r -url ${registry_url}"
zpm "install workflow-rest 1.1.1"
write "PREPARE_WF="_##class(%Dictionary.ClassDefinition).%ExistsId("isc.wf.REST"),!
halt
OS
)"
  printf '%s\n' "$out" | tail -n 25
  printf '%s' "$out" | grep -q "PREPARE_WF=1"
}

if ! retry install_workflow; then
  echo "prepare-image: FAILED: the IPM client and workflow-rest did not install after ${attempts} attempts (network to pm.community.intersystems.com is needed once, at build time)." >&2
  status=1
fi

iris stop IRIS quietly
exit "$status"
