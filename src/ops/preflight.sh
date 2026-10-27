#!/usr/bin/env bash
# Checks that the AI Hub build 154 image is present locally before anything else runs.
# The image must never be pulled from or pushed to a public registry.
set -uo pipefail
image="${READBACK_BASE_IMAGE:-irishealth-community:2026.3.0AI.154.0}"
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
