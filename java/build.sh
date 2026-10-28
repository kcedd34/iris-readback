#!/usr/bin/env bash
# Compiles the unit conversion component against the PEX jar of the image and the vendored UCUM library.
# Output: java/build/readback-units.jar (not committed). Run in the image build and by hand.
set -euo pipefail
cd "$(dirname "$0")"
PEX_JAR="${PEX_JAR:-/usr/irissys/dev/java/lib/1.8/intersystems-pex-1.0.0-shaded.jar}"
rm -rf build/classes && mkdir -p build/classes
javac -cp "lib/ucum-1.0.9.jar:${PEX_JAR}" -d build/classes src/com/readback/units/*.java
jar cf build/readback-units.jar -C build/classes .
echo "built $(pwd)/build/readback-units.jar"
