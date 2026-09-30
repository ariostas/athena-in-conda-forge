#!/bin/bash
# A GeoModelXml description turned into a GeoModel SQLite file by gmcat through GMXPlugin, then
# read back and written again by gmcat.
set -euxo pipefail
work=$(mktemp -d)
cp test/HelloWorld.gmx "${work}/"
cp "${PREFIX}/share/GeoModelXml/geomodel.dtd" "${work}/"
cd "${work}"
GMX_FILES=HelloWorld.gmx gmcat "${PREFIX}/lib/libGMXPlugin.so" -o hello.db
gmcat hello.db -o copy.db
for db in hello.db copy.db; do
  sqlite3 "${db}" "select name from LogVols" | tee names.txt
  grep -qx DiamondCylinder names.txt
done
