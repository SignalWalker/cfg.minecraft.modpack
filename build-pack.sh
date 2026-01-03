source $stdenv/setup

set -xe

cp -r $src ./build
chmod -R +w ./build

mkdir ./build/.minecraft
cp "$instance_cfg" ./build/instance.cfg
cp "$packwiz_bootstrap" ./build/.minecraft/packwiz-installer-bootstrap.jar
cp "$MMC_PACK_JSON" ./build/mmc-pack.json

cd build

zip -r "$out" .
