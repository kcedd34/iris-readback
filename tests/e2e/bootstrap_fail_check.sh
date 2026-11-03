#!/usr/bin/env bash
# A class that does not compile must stop the start: the bootstrap exits non-zero, names the class and the error,
# starts nothing, and does not record the source as loaded. Runs against the running container with a source folder
# that holds only a broken class, so the application's own classes are not recompiled.
set -uo pipefail
cd "$(dirname "$0")/../.."

cid=$(docker compose ps -q iris)
[ -n "$cid" ] || { echo "BOOTSTRAP the iris container is not running"; exit 2; }
iris() { docker exec -i "$cid" iris session IRIS -U USER; }
fail() { echo "BOOTSTRAP FAIL: $1"; cleanup; exit 1; }
cleanup() { docker exec "$cid" rm -rf /tmp/rb-badsrc; printf 'do $system.OBJ.Delete("Zbad.Broken")\nhalt\n' | iris >/dev/null 2>&1; }
trap cleanup EXIT

before=$(printf 'write "H="_$get(^Readback("srcHash")),!\nhalt\n' | iris | grep '^H=')
docker exec "$cid" bash -c 'mkdir -p /tmp/rb-badsrc/Zbad && cat > /tmp/rb-badsrc/Zbad/Broken.cls <<EOF
Class Zbad.Broken
{
ClassMethod A(x, y) As %String
{
	Quit:x = 1 && y "a"
	Quit "b"
}
}
EOF'

out=$(docker exec -e READBACK_SRC=/tmp/rb-badsrc "$cid" /opt/readback/src/ops/bootstrap.sh 2>&1)
code=$?
echo "$out" | tail -8
[ "$code" -ne 0 ] || fail "the bootstrap exited 0 with a class that does not compile"
echo "$out" | grep -q "READBACK COMPILE ERROR: .*Zbad.Broken" || fail "the message does not name the class that failed"
echo "$out" | grep -q "READBACK ABORTED" || fail "there is no abort message"
echo "$out" | grep -q "READBACK PRODUCTION" && fail "the production was started after a compile error"
after=$(printf 'write "H="_$get(^Readback("srcHash")),!\nhalt\n' | iris | grep '^H=')
[ "$before" = "$after" ] || fail "the broken source was recorded as loaded ($before -> $after)"
echo "bootstrap failure check passed"
