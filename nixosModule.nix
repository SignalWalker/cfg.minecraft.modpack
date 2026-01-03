{ self, ... }:
serverName:
{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (builtins) attrValues map;
in
{
  options =
    let
      mcServer = lib.submoduleWith {
        modules = [
          (
            {
              config,
              lib,
              pkgs,
              name,
              ...
            }:
            {
              options =
                let
                  inherit (lib) mkEnableOption mkOption types;
                  ini = pkgs.formats.ini { };
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
                      default = pkgs.temurin-bin-17;
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
                  quilt = {
                    installer = mkOption {
                      type = types.package;
                      default = pkgs.fetchurl {
                        url = "https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-installer/0.9.2/quilt-installer-0.9.2.jar";
                        hash = "sha256-w60+I+7oYOUYXFlOfLKA5Pq+fnZqg5RTgdmpnGSFXFs=";
                      };
                    };
                    version = mkOption {
                      type = types.str;
                      default = config.mods.passthru.pack.versions.quilt;
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
                  };
                  prism = {
                    name = mkOption {
                      type = types.str;
                      default = "prism";
                    };
                    mmcPack = mkOption {
                      type = types.submoduleWith { modules = [ (import ./mmcPack.nix pkgs) ]; };
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
                        instance_cfg = ini.generate "instance.cfg" config.instanceCfg;
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
                prism.instanceCfg = {
                  ConfigVersion = "1.2";
                  InstanceType = "OneSix";
                  JoinServerOnLaunch = false;
                  OverrideCommands = true;
                  OverrideConsole = false;
                  OverrideGameTime = false;
                  OverrideJavaArgs = false;
                  OverrideJavaLocation = false;
                  OverrideMemory = false;
                  OverrideMiscellaneous = false;
                  OverrideModLoaderSettings = false;
                  OverrideNativeWorkarounds = false;
                  OverridePerformance = false;
                  OverrideWindow = false;
                  PostExitCommand = "";
                  PreLaunchCommand =
                    lib.mkIf (config.packwiz.hostName != null)
                      "\"$INST_JAVA\" -jar packwiz-installer-bootstrap.jar http://${config.packwiz.hostName}/${config.name}/pack.toml";
                  UseAccountForInstance = false;
                  WrapperCommand = "";
                  iconKey = "fox";
                  name = config.prism.instanceName;
                  notes = "";
                };
              };
            }
          )
        ];
      };
    in
    {
      services.minecraft = {
        servers = lib.mkOption {
          type = lib.types.attrsOf mcServer;
          default = { };
        };
      };
    };
  config =
    let
    in
    lib.mkMerge (
      [
        (
          let
            server = config.services.minecraft.servers.${serverName};
          in
          {
            services.minecraft.servers.${serverName} = {
              mods = self.packages.${pkgs.stdenv.system.hostPlatform.system}.${serverName};
              prism.mmcPack.components = {
                "LWJGL 3".version = "3.3.1";
                "Minecraft".version = server.minecraft.version;
                "Quilt Loader".version = server.quilt.version;
              };
            };
          }
        )
      ]
      ++ (map (
        server:
        lib.mkIf server.enable (
          let
            systemdServiceSetup = "minecraft-server-setup-${server.name}";
            systemdService = "minecraft-server-${server.name}";
          in
          {
            users.users.${server.user} = {
              isSystemUser = true;
              home = server.dir.state;
              group = server.group;
            };
            users.groups.${server.group} = { };

            systemd.tmpfiles.settings = {
              "99-minecraft-${server.name}" = {
                "${server.dir.state}/mods" = {
                  "L+" = {
                    argument = server.mods;
                  };
                };
                ${server.environmentFile} = {
                  "f" = {
                    mode = "0640";
                    inherit (server) user group;
                  };
                  "z" = {
                    mode = "0640";
                    inherit (server) user group;
                  };
                };
              };
            };

            networking.firewall = lib.mkIf server.openFirewall {
              allowedTCPPorts = [ server.port ];
              allowedUDPPorts = [ server.port ];
            };

            systemd.services.${systemdServiceSetup} = {
              after = [ "network-online.target" ];
              partOf = [ "${systemdService}.service" ];
              path = [ server.java.package ];
              serviceConfig = {
                StateDirectory = server.user;
                Type = "oneshot";
                RemainAfterExit = true;
                User = server.user;
                Group = server.group;
              };
              script = ''
                set -e
                java -jar ${server.quilt.installer} install server "${server.minecraft.version}" "${server.quilt.version}" --install-dir="${server.dir.state}" --download-server --create-scripts
              '';
            };

            systemd.services.${systemdService} = {
              after = [ "${systemdServiceSetup}.service" ];
              requires = [ "${systemdServiceSetup}.service" ];
              wantedBy = [ "multi-user.target" ];
              path = [ server.java.package ];
              restartTriggers = [ server.mods ];
              serviceConfig = {
                EnvironmentFile = server.environmentFile;

                Type = "simple";
                ExecStart = "${server.java.package}/bin/java -Xms${server.java.memory.initial} -Xmx${server.java.memory.max} -jar ${server.dir.state}/quilt-server-launch.jar nogui";
                ExecStop = "${server.rcon.package}/bin/mcrcon -H localhost -P ${toString server.rcon.port} -p \"$MINECRAFT_RCON_PASSWORD\" stop";
                SuccessExitStatus = [
                  0
                  1
                ];
                User = server.user;
                Group = server.group;

                StateDirectory = server.user;
                ConfigurationDirectory = server.user;
                WorkingDirectory = server.dir.state;

                ProtectHome = true;
                ProtectSystem = "strict";
                PrivateDevices = true;
                NoNewPrivileges = true;
                PrivateTmp = true;
                ReadWritePaths = server.dir.state;
              };
            };
            services.nginx.virtualHosts = lib.mkIf (server.packwiz.hostName != null) {
              ${server.packwiz.hostName} = {
                locations = {
                  "=/${server.name}/${server.prism.name}.zip".alias = server.prism.instance;
                  "/${server.name}" = {
                    root = server.mods.passthru.packwizRoot;
                  };
                };
              };
            };
          }
        )
      ) (attrValues config.services.minecraft.servers))
    );
  meta = { };
}
