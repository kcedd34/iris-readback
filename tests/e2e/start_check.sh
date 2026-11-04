#!/usr/bin/env bash
# The start waits for the Java gateway and says so when it cannot:
#  1. a Java gateway that is down is started and waited for by the step that sets up the unit component;
#  2. when that step cannot succeed the bootstrap stops with a clear message, does not start the production, and exits non-zero;
#  3. verify.sh accuses a production that is not running as soon as it is not;
#  4. after a restart of the container the production comes back by itself (only the bootstrap starts it) and the event log of that start
#     holds no error and no warning (Ens_Util.Log, types 1 to 3).
# Runs against the running stack and leaves it as it found it.
set -uo pipefail
cd "$(dirname "$0")/../.."
cid=$(docker compose ps -q iris)
[ -n "$cid" ] || { echo "START the iris container is not running"; exit 2; }
iris() { docker exec -i "$cid" iris session IRIS -U USER; }
fail() { echo "START FAIL: $1"; restore; exit 1; }
restore() { printf 'kill ^Readback("home")\nhalt\n' | iris >/dev/null 2>&1; docker compose start iris >/dev/null 2>&1; }
trap restore EXIT

# 1. The gateway is stopped; the step brings it back.
out=$(printf 'set sc=##class(%%Net.Remote.Service).StopGateway("%%Java Server") hang 3\nwrite "RB_DOWN=",##class(Readback.Units.Setup).Accepts("127.0.0.1",53272,2),!\nset sc=##class(Readback.Units.Setup).EnsureComponent() write "RB_SC=",$select($system.Status.IsOK(sc):"ok",1:$system.Status.GetErrorText(sc)),!\nwrite "RB_UP=",##class(Readback.Units.Setup).Accepts("127.0.0.1",53272,5),!\nhalt\n' | iris)
echo "$out" | grep -q "RB_DOWN=0" || fail "the gateway was not down before the step: $out"
echo "$out" | grep -q "RB_SC=ok" || fail "the step did not bring the gateway back: $out"
echo "$out" | grep -q "RB_UP=1" || fail "the gateway does not accept a connection after the step: $out"

# 2. The component cannot be set up: the bootstrap stops, loudly, before the production.
printf 'set ^Readback("home")="/tmp/rb-nowhere"\nhalt\n' | iris >/dev/null
out=$(docker exec "$cid" /opt/readback/src/ops/bootstrap.sh 2>&1); code=$?
printf 'kill ^Readback("home")\nhalt\n' | iris >/dev/null
echo "$out" | tail -4
[ "$code" -ne 0 ] || fail "the bootstrap exited 0 although the unit component could not be set up"
echo "$out" | grep -q "READBACK UNITS FAILED" || fail "the failure is not named"
echo "$out" | grep -q "READBACK ABORTED: the unit conversion component" || fail "there is no abort message that says what failed"
echo "$out" | grep -q "READBACK PRODUCTION" && fail "the production was started after the unit component failed"

# 3. verify.sh accuses a production that is not running.
lastlog=$(printf 'set rs=##class(%%SQL.Statement).%%ExecDirect(,"SELECT MAX(ID) m FROM Ens_Util.Log") do rs.%%Next() write "RB_MAX=",+rs.m,!\nhalt\n' | iris | grep '^RB_MAX=' | cut -d= -f2)
docker compose stop iris >/dev/null 2>&1
started=$SECONDS
out=$(src/ops/verify.sh 120 2>&1); code=$?
took=$((SECONDS - started))
echo "$out" | tail -3
[ "$code" -ne 0 ] || fail "verify.sh exited 0 with the container stopped"
echo "$out" | grep -q "the production is not running" || fail "verify.sh did not say that the production is not running"
[ "$took" -lt 60 ] || fail "verify.sh took ${took}s to say it"
docker compose start iris >/dev/null 2>&1
src/ops/verify.sh 240 >/dev/null 2>&1 || fail "the stack did not come back after the check (the production did not start by itself)"

# 4. The start after that restart: production running (verify.sh said so), and a clean event log.
sleep 25
cid=$(docker compose ps -q iris)
bad=$(printf 'set rs=##class(%%SQL.Statement).%%ExecDirect(,"SELECT ID, Type, ConfigName, SUBSTR(Text,1,120) T FROM Ens_Util.Log WHERE ID > '"$lastlog"' AND Type IN (1,2,3) ORDER BY ID") while rs.%%Next() { write "RB_BAD ",rs.ID," t=",rs.Type," ",rs.ConfigName," ",rs.T,! }\nhalt\n' | iris | grep '^RB_BAD')
[ -z "$bad" ] || fail "the event log of the restart holds errors or warnings: $bad"
trap - EXIT
echo "start check passed"
