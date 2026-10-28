#!/usr/bin/env bash
# Retrieval with the container's network disconnected: the embedding model comes from the image, so two
# identical searches must work and agree. The network is reconnected on exit, even on failure.
set -uo pipefail
cd "$(dirname "$0")/../.."

cid=$(docker compose ps -q iris)
[ -n "$cid" ] || { echo "OFFLINE the iris container is not running"; exit 2; }
networks=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$cid")
reconnect() { for n in $networks; do docker network connect "$n" "$cid" 2>/dev/null || true; done; }
trap reconnect EXIT

for n in $networks; do docker network disconnect "$n" "$cid" || { echo "OFFLINE could not disconnect $n"; exit 2; }; done

# No route out: a real connection attempt must fail, otherwise the check proves nothing.
if docker exec "$cid" bash -c 'timeout 5 bash -c "exec 3<>/dev/tcp/1.1.1.1/443"' 2>/dev/null; then
  echo "OFFLINE the container still has network access"; exit 2
fi

run() {
  docker exec -i "$cid" iris session IRIS -U USER <<'OS' 2>&1 | grep '^RB_SELF'
set ok=##class(Readback.Retrieval.Engine).SelfCheck()
write "RB_SELF ok="_ok,!
halt
OS
}

first=$(run); second=$(run)
echo "$first"
echo "$second"
echo "$first" | grep -q 'RB_SELF available=1' || { echo "OFFLINE retrieval is not available without the network"; exit 1; }
echo "$first" | grep -q 'RB_SELF ok=1' || { echo "OFFLINE the two searches in one run differ or are empty"; exit 1; }
[ "$(echo "$first" | grep 'RB_SELF first=')" = "$(echo "$second" | grep 'RB_SELF first=')" ] || { echo "OFFLINE two runs gave different answers"; exit 1; }
echo "offline check passed"
