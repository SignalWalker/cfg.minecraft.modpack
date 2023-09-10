source $stdenv/setup

cp -r $src ./build
chmod -R +w ./build
cp "$packwiz_bootstrap" ./build/.minecraft/packwiz-installer-bootstrap.jar

cd build

zip -r "$out" .
