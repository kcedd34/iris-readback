#!/usr/bin/env bash
# Compiles the unit converter and its check with the JDK of the image and runs it against the real UCUM jar.
# Runs inside the compose service; exits non-zero on any failure.
set -euo pipefail
cd "$(dirname "$0")/../.."
docker compose exec -T iris bash -c '
set -e
rm -rf /tmp/unitcheck && mkdir -p /tmp/unitcheck
cd /opt/readback
javac -cp java/lib/ucum-1.0.9.jar -d /tmp/unitcheck java/src/com/readback/units/UnitConverter.java tests/java/UnitConverterCheck.java
java -cp /tmp/unitcheck:java/lib/ucum-1.0.9.jar UnitConverterCheck java/src/com/readback/units/UnitConverter.java
'
