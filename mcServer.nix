pack: pkgs: mmcPackType:
{
  config,
  lib,
  name,
  ...
}:
{
  options =
    let
      inherit (lib) mkEnableOption mkOption types;
    in
    {
      name = mkOption {
        type = types.str;
        default = name;
      };
      enable = mkEnableOption "minecraft server";
      user = mkOption {
        type = types.str;
        default = config.name;
      };
      group = mkOption {
        type = types.str;
        default = config.name;
      };
      dir =
        let
          mkDir =
            root:
            mkOption {
              type = types.str;
              readOnly = true;
              default = "${root}/${config.user}";
            };
        in
        {
          state = mkDir "/var/lib";
          configuration = mkDir "/etc";
        };
      environmentFile = mkOption {
        type = types.str;
        readOnly = true;
        default = "${config.dir.configuration}/env.conf";
      };
      java = {
        package = mkOption {
          type = types.package;
          default = pkgs.temurin-bin-21;
        };
        memory = {
          initial = mkOption {
            type = types.str;
            default = "1024M";
          };
          max = mkOption {
            type = types.str;
            default = "4096M";
          };
        };
      };
      # quilt = {
      #   installer = mkOption {
      #     type = types.package;
      #     default = pkgs.fetchurl {
      #       url = "https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-installer/0.9.2/quilt-installer-0.9.2.jar";
      #       hash = "sha256-w60+I+7oYOUYXFlOfLKA5Pq+fnZqg5RTgdmpnGSFXFs=";
      #     };
      #   };
      #   version = mkOption {
      #     type = types.str;
      #     default = config.mods.passthru.pack.versions.quilt;
      #   };
      # };
      neoforge = {
        installer = mkOption {
          type = types.package;
          default =
            let
              version = config.neoforge.version;
            in
            pkgs.fetchurl {
              url = "https://maven.neoforged.net/releases/net/neoforged/neoforge/${version}/neoforge-${version}-installer.jar";
              hash = "sha256-L2tyiqmWRqaX6wdVzncOlF+VCQxCSOtY9VisDi41eMY=";
            };
        };
        version = mkOption {
          type = types.str;
          default = config.mods.passthru.pack.versions.neoforge;
        };
      };
      minecraft = {
        version = mkOption {
          type = types.str;
          default = config.mods.passthru.pack.versions.minecraft;
        };
      };
      mods = mkOption {
        type = types.package;
        default = pack;
      };
      prism =
        let
          ini = pkgs.formats.ini { };
        in
        {
          name = mkOption {
            type = types.str;
            default = "prism";
          };
          mmcPack = mkOption {
            type = mmcPackType;
          };
          instanceName = mkOption {
            type = types.str;
            default = config.name;
          };
          instanceCfg = mkOption {
            type = ini.type;
          };
          instance = mkOption {
            type = types.package;
            default = pkgs.stdenvNoCC.mkDerivation {
              name = "${config.mods.passthru.pack.name}.zip";
              src = ./prism;
              instance_cfg = ini.generate "instance.cfg" config.prism.instanceCfg;
              packwiz_bootstrap = pkgs.fetchurl {
                url = "https://github.com/packwiz/packwiz-installer-bootstrap/releases/download/v0.0.3/packwiz-installer-bootstrap.jar";
                hash = "sha256-qPuyTcYEJ46X9GiOgtPZGjGLmO/AjV2/y8vKtkQ9EWw=";
              };
              env = {
                MMC_PACK_JSON = config.prism.mmcPack.outputFile;
              };
              builder = ./build-pack.sh;
              nativeBuildInputs = [ pkgs.zip ];
            };
          };
        };
      rcon = {
        package = mkOption {
          type = types.package;
          default = pkgs.mcrcon;
        };
        port = mkOption {
          type = types.port;
          default = 25575;
        };
      };
      port = mkOption {
        type = types.port;
        default = 25565;
      };
      openFirewall = mkEnableOption "minecraft firewall";
      packwiz = {
        hostName = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
      };
    };
  config = {
    prism.mmcPack.components = {
      "LWJGL 3".version = "3.3.3";
      "Minecraft".version = config.minecraft.version;
      "NeoForge".version = config.neoforge.version;
      # "Quilt Loader".version = config.quilt.version;
    };
    prism.instanceCfg = {
      General = {
        ConfigVersion = "1.2";
        InstanceType = "OneSix";
        OverrideCommands = true;
        PostExitCommand = "";
        PreLaunchCommand =
          lib.mkIf (config.packwiz.hostName != null)
            "$INST_JAVA -jar packwiz-installer-bootstrap.jar http://${config.packwiz.hostName}/${config.name}/pack.toml";
        WrapperCommand = "";
        iconKey = "fox";
        name = config.prism.instanceName;
        notes = "";
      };
    };
  };
}
