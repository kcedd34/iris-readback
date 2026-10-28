#!/usr/bin/env bash
# Start script, run after IRIS is up through iris-main -a.
# Loads and compiles the Readback classes into USER only when the source changed, then makes sure the
# production is running. Recompiling on every start would disturb the production that IRIS
# auto-starts, and resets its TCP connections.
# Exits 0 on purpose: a non-zero exit would make iris-main stop IRIS.
set -uo pipefail

src="${READBACK_SRC:-/opt/readback/src}"
hash="$(cd "$src" && find . -type f -not -name '*.pyc' | sort | xargs sha256sum | sha256sum | cut -c1-16)"
datadir="${READBACK_DATA:-/opt/readback/data}"
datahash="$( [ -d "$datadir" ] && cd "$datadir" && find . -type f | sort | xargs -r sha256sum | sha256sum | cut -c1-16 )"
log="$(mktemp)"

echo "Readback: source hash ${hash}"
iris session IRIS -U USER <<OS 2>&1 | tee "$log"
// One line per block: the terminal reads its input line by line, so a block spread over several lines is a <SYNTAX> error and its body would run unconditionally.
if \$get(^Readback("srcHash"))'="${hash}" { write "Readback: loading classes from ${src} into USER...",!  set sc=\$system.OBJ.LoadDir("${src}","ck",.err,1)  if \$system.Status.IsError(sc) { write "READBACK LOAD "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { set ^Readback("srcHash")="${hash}" kill ^Readback("dataHash") } } else { write "Readback: classes already loaded for this source, not recompiling",! }
set sc=##class(Readback.Config.Loader).LoadIfChanged("${datahash}","${datadir}")
if \$system.Status.IsError(sc) { write "READBACK CONFIG "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { write "Readback: configuration tables up to date",! }
set sc=##class(Readback.Units.Setup).EnsureComponent()
if \$system.Status.IsError(sc) { write "READBACK UNITS "_"FAILED: ",\$system.Status.GetErrorText(sc),! }
set sc=##class(Readback.Retrieval.Engine).Prepare()
if \$system.Status.IsError(sc) { write "READBACK RETRIEVAL "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { write "Readback: policy index ready",! }
set sc=##class(Readback.API.Status).EnsureWebApp()
if \$system.Status.IsError(sc) { write "READBACK WEBAPP "_"FAILED: ",\$system.Status.GetErrorText(sc),! }
set sc=##class(Readback.Workflow.Setup).EnsureRoles()
if \$system.Status.IsError(sc) { write "READBACK ROLES "_"FAILED: ",\$system.Status.GetErrorText(sc),! }
set sc=##class(Ens.Director).SetAutoStart("Readback.Production")
// The live agent item needs a key: it is enabled only when one is configured, so replay mode starts without errors.
set tLive=(##class(Readback.Config.Mode).Current()="live")
set tCur=##class(Ens.Director).IsItemEnabled("Readback.Agent")
if tLive'=tCur { set sc=##class(Ens.Director).EnableConfigItem("Readback.Agent",tLive) }
if '##class(Ens.Director).IsProductionRunning("Readback.Production") { set sc=##class(Ens.Director).StartProduction("Readback.Production")  if \$system.Status.IsError(sc) { write "READBACK START "_"FAILED: ",\$system.Status.GetErrorText(sc),! } else { write "READBACK PRODUCTION "_"STARTED",! } } else { write "READBACK PRODUCTION "_"ALREADY RUNNING",! }
halt
OS

if grep -q "^READBACK \(LOAD\|START\|CONFIG\|ROLES\|WEBAPP\|UNITS\) FAILED" "$log"; then
  echo "Readback did not start. IRIS keeps running so you can inspect it: docker compose logs iris"
fi
rm -f "$log"

# Once per instance: the IPM client (absent from the image) and the community workflow REST module.
# Needs network. Without it the tasks and the read-back rule still work through the engine.
marker="$(iris session IRIS -U USER <<'OS' 2>/dev/null | grep -c '^RB_IPM_DONE'
write "RB_IPM_"_$select($data(^Readback("ipm")):"DONE",1:"TODO"),!
halt
OS
)"
if [ "$marker" = "0" ]; then
  echo "Readback: installing the IPM client and workflow-rest (needs network)..."
  if wget -q -T 30 -O /tmp/zpm-installer.xml https://pm.community.intersystems.com/packages/zpm/latest/installer; then
    ipmlog="$(mktemp)"
    iris session IRIS -U USER <<'OS' 2>&1 | tee "$ipmlog" | grep -E "^READBACK|ERROR" 
set sc=$system.OBJ.Load("/tmp/zpm-installer.xml","c")
zpm "repo -n registry -r -url https://pm.community.intersystems.com/"
zpm "install workflow-rest"
if ##class(%Dictionary.ClassDefinition).%ExistsId("isc.wf.REST") { set ^Readback("ipm")=$horolog  write "READBACK IPM "_"INSTALLED",! } else { write "READBACK IPM "_"NOT INSTALLED: see the output above",! }
halt
OS
    rm -f "$ipmlog"
  else
    echo "Readback: could not download the IPM client; the workflow REST layer is not installed. Tasks still work through the engine."
  fi
fi
exit 0
