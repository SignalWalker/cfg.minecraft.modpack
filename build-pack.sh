source $stdenv/setup

set -e

cp -r $src ./build
chmod -R +w ./build
cp "$packwiz_bootstrap" ./build/.minecraft/packwiz-installer-bootstrap.jar
cp "$MMC_PACK_JSON" ./build/mmc-pack.json

cd build

zip -r "$out" .
