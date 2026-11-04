#!/usr/bin/env bash
# Start script, run after IRIS is up through iris-main -a.
# Loads and compiles the Readback classes into USER only when the source changed, then makes sure the
# production is running. Recompiling on every start would disturb the production that IRIS
# auto-starts, and resets its TCP connections.
# Exits 1 when a class does not compile or the unit conversion component cannot be set up: iris-main then stops IRIS and the container ends, so a broken start never looks started.
# Every other problem exits 0: IRIS keeps running so you can inspect it.
set -uo pipefail

src="${READBACK_SRC:-/opt/readback/src}"
hash="$(cd "$src" && find . -type f -not -name '*.pyc' | sort | xargs sha256sum | sha256sum | cut -c1-16)"
datadir="${READBACK_DATA:-/opt/readback/data}"
datahash="$( [ -d "$datadir" ] && cd "$datadir" && find . -type f | sort | xargs -r sha256sum | sha256sum | cut -c1-16 )"
log="$(mktemp)"

echo "Readback: source hash ${hash}"
# Loading comes first and on its own: a class that does not compile must stop the start, not scroll past in the log.
# One line per block: the terminal reads its input line by line, so a block spread over several lines is a <SYNTAX> error and its body would run unconditionally.
iris session IRIS -U USER <<OS 2>&1 | tee "$log"
if \$get(^Readback("srcHash"))'="${hash}" { write "Readback: loading classes from ${src} into USER...",!  set sc=\$system.OBJ.LoadDir("${src}","ck",.err,1)  if \$system.Status.IsError(sc) { write "READBACK COMPILE "_"FAILED: ",\$get(err)," error(s)",!  set i=""  for { set i=\$order(err(i))  quit:i=""  write "READBACK COMPILE "_"ERROR: ",\$get(err(i)),! }  if \$get(err)=0 { write "READBACK COMPILE "_"ERROR: ",\$system.Status.GetErrorText(sc),! } } else { set ^Readback("srcHash")="${hash}" kill ^Readback("dataHash") } } else { write "Readback: classes already loaded for this source, not recompiling",! }
halt
OS

if grep -q "READBACK COMPILE FAILED" "$log"; then
  echo "READBACK ABORTED: the classes in ${src} did not all compile (errors above). Nothing was started." >&2
  echo "Fix the class and rebuild: docker compose up -d --build" >&2
  rm -f "$log"
  exit 1
fi
rm -f "$log"

# The unit conversion component needs the Java gateway to accept connections. The step waits for it, tries again, and stops the start with a clear
# message when it never does: a production that starts without its proxy class cannot start, and an unhealthy container with no reason is worse than a stop.
log="$(mktemp)"
iris session IRIS -U USER <<OS 2>&1 | tee "$log"
set sc=##class(Readback.Units.Setup).EnsureComponent()
if \$system.Status.IsError(sc) { write "READBACK UNITS "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { write "Readback: unit conversion component ready",! }
halt
OS
if grep -q "READBACK UNITS FAILED" "$log"; then
  echo "READBACK ABORTED: the unit conversion component could not be set up (the Java gateway did not accept a connection, or the component is not built). The production was not started." >&2
  echo "Look at the lines above, then rebuild or restart: docker compose up -d --build" >&2
  rm -f "$log"
  exit 1
fi
rm -f "$log"

log="$(mktemp)"
iris session IRIS -U USER <<OS 2>&1 | tee "$log"
set sc=##class(Readback.Config.Loader).LoadIfChanged("${datahash}","${datadir}")
if \$system.Status.IsError(sc) { write "READBACK CONFIG "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { write "Readback: configuration tables up to date",! }
set sc=##class(Readback.Retrieval.Engine).Prepare()
if \$system.Status.IsError(sc) { write "READBACK RETRIEVAL "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { write "Readback: policy index ready",! }
set sc=##class(Readback.API.Status).EnsureWebApp()
if \$system.Status.IsError(sc) { write "READBACK WEBAPP "_"FAILED: ",\$system.Status.GetErrorText(sc),! }
set sc=##class(Readback.MCP.Setup).EnsureWebApp()
if \$system.Status.IsError(sc) { write "READBACK MCP "_"FAILED: ",\$system.Status.GetErrorText(sc),! }
set sc=##class(Readback.Workflow.Setup).EnsureRoles()
if \$system.Status.IsError(sc) { write "READBACK ROLES "_"FAILED: ",\$system.Status.GetErrorText(sc),! }
// The production is not started by IRIS at its own start: it would start before the Java gateway is ready. Only this script starts it, below, after the gateway accepts connections, and it runs at every start of the container.
set sc=##class(Ens.Director).SetAutoStart("")
if '##class(Ens.Director).IsProductionRunning("Readback.Production") { set sc=##class(Ens.Director).StartProduction("Readback.Production")  if \$system.Status.IsError(sc) { write "READBACK START "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { write "READBACK PRODUCTION "_"STARTED",! } } else { write "READBACK PRODUCTION "_"ALREADY RUNNING",! }
// The live agent item needs a key: it is enabled only when one is configured, so replay mode starts without errors. An item is enabled in a running production (it is updated in place), so this comes after the start.
set tLive=(##class(Readback.Config.Mode).Current()="live")
set tCur=##class(Ens.Director).IsItemEnabled("Readback.Agent")
if tLive'=tCur { set sc=##class(Ens.Director).EnableConfigItem("Readback.Agent",tLive)  if \$system.Status.IsError(sc) { write "READBACK AGENT "_"FAILED: ",\$system.Status.GetErrorText(sc),! } }
halt
OS

if grep -q "^READBACK \(START\|CONFIG\|ROLES\|WEBAPP\|MCP\|AGENT\) FAILED" "$log"; then
  echo "Readback did not start. IRIS keeps running so you can inspect it: docker compose logs iris"
fi
rm -f "$log"

# The IPM client and the community package workflow-rest are installed while the image is built (src/ops/prepare-image.sh), so the start needs no network.
# If they are missing the image is not the one this repository builds: say so, and rebuild.
wf="$(iris session IRIS -U USER <<'OS' 2>/dev/null | grep -c '^RB_WF=1'
write "RB_WF=",##class(%Dictionary.ClassDefinition).%ExistsId("isc.wf.REST"),!
halt
OS
)"
if [ "$wf" = "0" ]; then
  echo "READBACK WORKFLOW LAYER MISSING: workflow-rest is not in this image. Rebuild it with network access: docker compose build --no-cache iris" >&2
fi
exit 0
