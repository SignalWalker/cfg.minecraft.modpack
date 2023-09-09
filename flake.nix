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
          drifting-league = let
            index = fromTOML (readFile ./pack/index.toml);
            pack = fromTOML (readFile ./pack/pack.toml);
            toCurseUrl = toml: let
              fileNum = toString toml.update.curseforge.file-id;
              fileNs = substring 0 4 fileNum;
              fileId = std.strings.removePrefix "0" (substring 4 3 fileNum);
            in "https://mediafilez.forgecdn.net/files/${fileNs}/${fileId}/${toml.filename}";
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
            mods = listToAttrs (map (file: let
              toml = fromTOML (readFile file);
            in {
              name = toml.name;
              value = fetchMod toml;
            }) (std.filesystem.listFilesRecursive ./pack/mods));
          in
            pkgs.stdenvNoCC.mkDerivation {
              pname = pack.name;
              version = pack.version;
              passthru = {
                inherit mods;
              };
              mods = attrValues mods;
              src = ./.;
              installPhase = let
                installMods = std.concatStringsSep "\n" (map (mod: "cp ${mod} $out/${mod.passthru.filename}") (attrValues mods));
              in ''
                          runHook preInstall

                          mkdir $out
                ${installMods}

                          runHook postInstall
              '';
            };
          default = self.packages.${system}.drifting-league;
        })
        nixpkgsFor;
      devShells =
        std.mapAttrs (system: pkgs: {
          default = pkgs.mkShell {
            packages = with pkgs; [packwiz];
          };
        })
        nixpkgsFor;
    };
}
