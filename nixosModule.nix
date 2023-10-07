{self, ...}: pack: {
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  ini = pkgs.formats.ini {};
  minecraft = config.services.minecraft;
  mcServer = lib.types.submoduleWith {
    modules = [
      ({
        config,
        lib,
        pkgs,
        name,
        ...
      }: {
        options = with lib; {
          enable = mkEnableOption "minecraft server";
          user = mkOption {
            type = types.str;
            default = name;
          };
          group = mkOption {
            type = types.str;
            default = "minecraft";
          };
          dir = let
            mkDir = root:
              mkOption {
                type = types.str;
                readOnly = true;
                default = "${root}/${config.user}";
              };
          in {
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
              default = pkgs.temurin-bin;
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
                url = "https://maven.quiltmc.org/repository/release/org/quiltmc/quilt-installer/0.8.2/quilt-installer-0.8.2.jar";
                hash = "sha256-fL1QnCcomJodOAay3Z1AvdgORpl7CuYbrXIz0i2k8Ao=";
              };
            };
            version = mkOption {
              type = types.str;
              default = pack.versions.quilt;
            };
          };
          minecraft = {
            version = mkOption {
              type = types.str;
              default = pack.versions.minecraft;
            };
          };
          mods = mkOption {
            type = types.package;
            default = self.packages.${pkgs.system}.driftingLeague;
          };
          prism = {
            instance = mkOption {
              type = types.package;
              default = config.mods.passthru.prism;
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
        };
      })
    ];
  };
in {
  options = with lib; {
    services.minecraft = {
      servers = mkOption {
        type = types.attrsOf mcServer;
        default = {};
      };
      packwiz = {
        hostName = mkOption {
          type = types.nullOr types.str;
          default = null;
        };
      };
    };
  };
  disabledModules = [];
  imports = [];
  config = lib.mkMerge ((map (serverName: let
      server = config.services.minecraft.servers.${serverName};
    in {
      users.users.${server.user} = {
        isSystemUser = true;
        home = server.dir.state;
        group = server.group;
      };
      users.groups.${server.group} = {};

      systemd.tmpfiles.rules = [
        "L+ ${server.dir.state}/mods - - - - ${server.mods}"
        "f ${server.environmentFile} 0640 ${server.user} ${server.group}"
        "z ${server.environmentFile} 0640 ${server.user} ${server.group}"
      ];

      networking.firewall = lib.mkIf server.openFirewall {
        allowedTCPPorts = [server.port];
        allowedUDPPorts = [server.port];
      };

      systemd.services."minecraft-${serverName}-setup" = {
        after = ["network-online.target"];
        partOf = ["minecraft-${serverName}.service"];
        path = [server.java.package];
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

      systemd.services."minecraft-${serverName}" = {
        after = ["minecraft-${serverName}-setup.service"];
        requires = ["minecraft-${serverName}-setup.service"];
        wantedBy = ["multi-user.target"];
        path = [server.java.package];
        restartTriggers = [server.mods];
        serviceConfig = {
          EnvironmentFile = server.environmentFile;

          Type = "simple";
          ExecStart = "${server.java.package}/bin/java -Xms${server.java.memory.initial} -Xmx${server.java.memory.max} -jar ${server.dir.state}/quilt-server-launch.jar nogui";
          ExecStop = "${server.rcon.package}/bin/mcrcon -H localhost -P ${toString server.rcon.port} -p \"$MINECRAFT_RCON_PASSWORD\" stop";
          SuccessExitStatus = [0 1];
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
      services.nginx.virtualHosts = lib.mkIf (minecraft.packwiz.hostName != null) {
        ${minecraft.packwiz.hostName} = {
          locations."=/${serverName}.zip".alias = server.prism.instance;
          locations."/${serverName}".root = server.mods.passthru.packwizRoot;
        };
      };
    }) (attrNames config.services.minecraft.servers))
    ++ [
    ]);
  meta = {};
}
