#!/usr/bin/env bash
# Start script, run after IRIS is up through iris-main -a.
# Loads and compiles the Readback classes into USER only when the source changed, then makes sure the
# production is running. Recompiling on every start would disturb the production that IRIS
# auto-starts, and resets its TCP connections.
# Exits 0 on purpose: a non-zero exit would make iris-main stop IRIS.
set -uo pipefail

src="${READBACK_SRC:-/opt/readback/src}"
hash="$(cd "$src" && find . -type f -not -name '*.pyc' | sort | xargs sha256sum | sha256sum | cut -c1-16)"
log="$(mktemp)"

echo "Readback: source hash ${hash}"
iris session IRIS -U USER <<OS 2>&1 | tee "$log"
if \$get(^Readback("srcHash"))'="${hash}" {
  write "Readback: loading classes from ${src} into USER...",!
  set sc=\$system.OBJ.LoadDir("${src}","ck",.err,1)
  if \$system.Status.IsError(sc) { write "READBACK LOAD "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { set ^Readback("srcHash")="${hash}" }
} else {
  write "Readback: classes already loaded for this source, not recompiling",!
}
set sc=##class(Ens.Director).SetAutoStart("Readback.Production")
if '##class(Ens.Director).IsProductionRunning("Readback.Production") {
  set sc=##class(Ens.Director).StartProduction("Readback.Production")
  if \$system.Status.IsError(sc) { write "READBACK START "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { write "READBACK PRODUCTION "_"STARTED",! }
} else {
  write "READBACK PRODUCTION "_"ALREADY RUNNING",!
}
halt
OS

if grep -q "^READBACK \(LOAD\|START\) FAILED" "$log"; then
  echo "Readback did not start. IRIS keeps running so you can inspect it: docker compose logs iris"
fi
rm -f "$log"
exit 0
