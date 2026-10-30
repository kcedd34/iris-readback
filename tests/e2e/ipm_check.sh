#!/usr/bin/env bash
# Proves the package manifest on a clean instance: a throwaway container of the base image (no product code in it), the IPM
# client installed as a test step, `zpm "load"` of this repository from local files, the product's own checks afterwards.
# Nothing is pushed to a registry; the community registry is only read, for the workflow-rest dependency.
# Needs the base image loaded (src/ops/preflight.sh) and network for the IPM client download.
set -uo pipefail
cd "$(dirname "$0")/../.."
image="${READBACK_BASE_IMAGE:-irishealth-community:2026.3.0AI.154.0}"
name="rb-ipm-check-$$"
work="$(mktemp -d)"
cleanup() { docker rm -f "$name" >/dev/null 2>&1; rm -rf "$work"; }
trap cleanup EXIT
fail() { echo "IPM FAIL: $*"; exit 1; }
sess() { docker exec -i "$name" iris session IRIS -U USER 2>&1; }

docker image inspect "$image" >/dev/null 2>&1 || fail "the base image $image is not loaded (run src/ops/preflight.sh)"
docker run -d --name "$name" "$image" >/dev/null || fail "the clean container did not start"
for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null)" = healthy ] && break
  sleep 3
done
echo 'write "UP",! halt' | sess | grep -q UP || fail "the clean instance did not come up"

# The clean instance holds nothing of the product.
echo 'write "CLS=",##class(%Dictionary.ClassDefinition).%ExistsId("Readback.Install"),! halt' | sess | grep -q "CLS=0" || fail "the instance is not clean"

# Test step: the IPM client is not in the image (platform limitation), so it is installed here and never becomes a dependency of the product.
docker exec "$name" sh -c 'wget -q -T 60 -O /tmp/zpm-installer.xml https://pm.community.intersystems.com/packages/zpm/latest/installer' || fail "the IPM client could not be downloaded"
printf 'set sc=$system.OBJ.Load("/tmp/zpm-installer.xml","c")\nwrite "ZPM_LOAD=",sc,!\nhalt\n' | sess | grep -q "ZPM_LOAD=1" || fail "the IPM client did not install"

# The package files, as a publisher would send them: no build output, no caches, no node modules.
tar --exclude='__pycache__' --exclude='*.pyc' --exclude='node_modules' --exclude='java/build' -cf "$work/pkg.tar" module.xml LICENSE src data java
docker exec "$name" mkdir -p /tmp/pkg && docker cp "$work/pkg.tar" "$name:/tmp/pkg.tar" && docker exec "$name" tar -xf /tmp/pkg.tar -C /tmp/pkg || fail "the package files could not be copied"

log="$work/load.log"
printf 'zpm "repo -n registry -r -url https://pm.community.intersystems.com/"\nzpm "load /tmp/pkg"\nhalt\n' | sess > "$log"
grep -q "\[USER|iris-readback\].Activate SUCCESS" "$log" || { tail -20 "$log"; fail "zpm load of iris-readback did not succeed"; }
grep -q "Readback install:.*FAILED" "$log" && { grep "Readback install:" "$log"; fail "an install step failed"; }
grep -q "production started: ok" "$log" || fail "the production was not started by the install step"

# The product's own checks on the installed package.
echo 'write "RB_STATE=",##class(Ens.Director).IsProductionRunning("Readback.Production"),! halt' | sess | grep -q "RB_STATE=1" || fail "the production is not running"
password="$(sed -n 's/.*generated demo password (shown once): \([A-Za-z0-9]*\).*/\1/p' "$log" | head -1)"
[ -n "$password" ] || fail "the install did not report the demo password"
body="$(docker exec "$name" wget -q -O - --user=observer --password="$password" --auth-no-challenge http://localhost:52773/readback/api/flow)" || fail "the flow path did not answer"
printf '%s' "$body" | grep -q '"mode":"replay"' || fail "the flow path did not report replay mode: $body"
status="$(docker exec "$name" wget -q -O - --user=observer --password="$password" --auth-no-challenge http://localhost:52773/readback/api/status)" || fail "the status path did not answer"
printf '%s' "$status" | grep -q '"productionRunning":true' || fail "the status does not say the production runs"

# The install step is safe to run again.
echo 'set sc=##class(Readback.Install).Run() write "RERUN=",$select($system.Status.IsOK(sc):"ok",1:"FAILED"),! halt' | sess | grep -q "RERUN=ok" || fail "the install step is not repeatable"

echo "ipm check passed"
