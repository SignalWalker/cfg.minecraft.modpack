{
  description = "";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    packwiz = {
      url = "github:packwiz/packwiz";
      # inputs.nixpkgs.follows = "nixpkgs";
      flake = false;
    };
  };
  outputs =
    inputs@{
      flake-parts,
      ...
    }:

    flake-parts.lib.mkFlake { inherit inputs; } (
      { moduleWithSystem, lib, ... }:
      let
        serverName = "playground";
      in
      {
        imports = [ ];
        systems = [
          "x86_64-linux"
        ];
        flake = {
          nixosModules.default = moduleWithSystem ((import ./nixosModule.nix) serverName);
        };
        perSystem =
          {
            self',
            pkgs,
            # system,
            ...
          }:
          {
            formatter = pkgs.nixfmt;
            devShells = {
              default = pkgs.mkShell {
                packages = [ self'.packages.packwiz ];
              };
            };
            packages = {
              default = self'.packages.${serverName};
              packwiz = pkgs.buildGoModule {
                name = "packwiz";
                src = inputs.packwiz;
                vendorHash = "sha256-ChUE4hWl+UyPpbzK0GbJTD0AoBCogI7qGstga4+WujI=";
              };
              ${serverName} =
                let
                  inherit (builtins)
                    readFile
                    substring
                    foldl'
                    attrValues
                    ;
                  index = fromTOML (readFile ./pack/index.toml);
                  pack = fromTOML (readFile ./pack/pack.toml);
                  toCurseUrl =
                    toml:
                    let
                      fileNum = toString toml.update.curseforge.file-id;
                      fileNs = substring 0 4 fileNum;
                      fileId = lib.strings.removePrefix "0" (substring 4 3 fileNum);
                    in
                    "https://mediafilez.forgecdn.net/files/${fileNs}/${fileId}/${lib.strings.escapeURL toml.filename}";
                  # fetchCurseforge =
                  #   toml:
                  #   let
                  #     fileId = lib.strings.splitString "0" (toString toml.update.curseforge.file-id);
                  #   in
                  #   {
                  #     name = toml.filename;
                  #     outputHashMode = "flat";
                  #     outputHashAlgo = toml.download.hash-format;
                  #     outputHash = toml.download.hash;
                  #     nativeBuildInputs = [ pkgs.packwiz ];
                  #   };
                  fetchMod =
                    toml:
                    pkgs.fetchurl {
                      url = toml.download.url or (toCurseUrl toml);
                      outputHashAlgo = toml.download.hash-format;
                      outputHash = toml.download.hash;
                      passthru = toml;
                    };
                  mods = foldl' (
                    acc: file:
                    let
                      toml = fromTOML (readFile file);
                    in
                    if toml.side == "client" then
                      acc
                    else
                      acc
                      // {
                        ${toml.name} = fetchMod toml;
                      }
                  ) { } (lib.filesystem.listFilesRecursive ./pack/mods);
                in
                pkgs.stdenvNoCC.mkDerivation {
                  pname = pack.name;
                  version = pack.version;
                  passthru = {
                    inherit mods index pack;
                    packwizRoot = ./pack;
                  };
                  src = ./pack;
                  installPhase =
                    let
                      installMods = lib.concatStringsSep "\n" (
                        map (mod: "ln -sT '${mod}' \"$out/${mod.passthru.filename}\"") (attrValues mods)
                      );
                    in
                    ''
                      runHook preInstall

                      mkdir $out
                      ${installMods}

                      runHook postInstall
                    '';
                };
            };
          };

      }
    );
}
