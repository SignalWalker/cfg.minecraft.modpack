{
  description = "";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    alejandra = {
      url = "github:kamadorueda/alejandra";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs @ {
    self,
    nixpkgs,
    ...
  }:
    with builtins; let
      std = nixpkgs.lib;
      systems = attrNames inputs.alejandra.packages;
      nixpkgsFor = std.genAttrs systems (system:
        import nixpkgs {
          localSystem = system;
          crossSystem = system;
          overlays = [];
        });
    in {
      formatter = std.mapAttrs (system: pkgs: pkgs.default) inputs.alejandra.packages;
      packages =
        std.mapAttrs (system: pkgs: {
          default = self.packages.${system}.driftingLeague;
          driftingLeague = let
            index = fromTOML (readFile ./pack/index.toml);
            pack = fromTOML (readFile ./pack/pack.toml);
            toCurseUrl = toml: let
              fileNum = toString toml.update.curseforge.file-id;
              fileNs = substring 0 4 fileNum;
              fileId = std.strings.removePrefix "0" (substring 4 3 fileNum);
            in "https://mediafilez.forgecdn.net/files/${fileNs}/${fileId}/${std.strings.escapeURL toml.filename}";
            fetchCurseforge = toml: let
              fileId = std.strings.splitString "0" (toString toml.update.curseforge.file-id);
            in {
              name = toml.filename;
              outputHashMode = "flat";
              outputHashAlgo = toml.download.hash-format;
              outputHash = toml.download.hash;
              nativeBuildInputs = with pkgs; [packwiz];
            };
            fetchMod = toml:
              pkgs.fetchurl {
                url =
                  toml.download.url
                  or (toCurseUrl toml);
                outputHashAlgo = toml.download.hash-format;
                outputHash = toml.download.hash;
                passthru = toml;
              };
            mods = foldl' (acc: file: let
              toml = fromTOML (readFile file);
            in
              if toml.side == "client"
              then acc
              else
                acc
                // {
                  ${toml.name} = fetchMod toml;
                }) {} (std.filesystem.listFilesRecursive ./pack/mods);
          in
            pkgs.stdenvNoCC.mkDerivation {
              pname = pack.name;
              version = pack.version;
              passthru = {
                inherit mods index pack;
                packwizRoot = ./pack;
                prism = pkgs.stdenvNoCC.mkDerivation {
                  name = "${pack.name}.zip";
                  src = ./prism;
                  packwiz_bootstrap = pkgs.fetchurl {
                    url = "https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/v0.0.3/packwiz-installer-bootstrap.jar";
                    hash = "sha256-qPuyTcYEJ46X9GiOgtPZGjGLmO/AjV2/y8vKtkQ9EWw=";
                  };
                  builder = ./build-pack.sh;
                  nativeBuildInputs = with pkgs; [zip];
                };
              };
              src = ./pack;
              installPhase = let
                installMods = std.concatStringsSep "\n" (map (mod: "ln -sT ${mod} $out/${mod.passthru.filename}") (attrValues mods));
              in ''
                runHook preInstall

                mkdir $out
                ${installMods}

                runHook postInstall
              '';
            };
        })
        nixpkgsFor;
      devShells =
        std.mapAttrs (system: pkgs: {
          default = pkgs.mkShell {
            packages = with pkgs; [packwiz];
          };
        })
        nixpkgsFor;
      nixosModules.default = (import ./nixosModule.nix) inputs (self.packages."x86_64-linux".driftingLeague.passthru.pack);
    };
}
