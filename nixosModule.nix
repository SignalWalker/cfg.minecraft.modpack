{self, ...}: pack: {
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  league = config.services.minecraft.driftingLeague;
  ini = pkgs.formats.ini {};
in {
  options = with lib; {
    services.minecraft.driftingLeague = {
      enable = mkEnableOption "drifting league server";
      user = mkOption {
        type = types.str;
        default = "driftingleague";
      };
      group = mkOption {
        type = types.str;
        default = "driftingleague";
      };
      dir = let
        mkDir = root:
          mkOption {
            type = types.str;
            readOnly = true;
            default = "${root}/${league.user}";
          };
      in {
        state = mkDir "/var/lib";
        configuration = mkDir "/etc";
      };
      environmentFile = mkOption {
        type = types.str;
        readOnly = true;
        default = "${league.dir.configuration}/env.conf";
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
        name = mkOption {
          type = types.str;
          default = "prism";
        };
        instance = mkOption {
          type = types.package;
          default = league.mods.passthru.prism;
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
  };
  disabledModules = [];
  imports = [];
  config = lib.mkIf league.enable {
    users.users.${league.user} = {
      isSystemUser = true;
      home = league.dir.state;
      group = league.group;
    };
    users.groups.${league.group} = {};

    systemd.tmpfiles.rules = [
      "L+ ${league.dir.state}/mods - - - - ${league.mods}"
      "f ${league.environmentFile} 0640 ${league.user} ${league.group}"
      "z ${league.environmentFile} 0640 ${league.user} ${league.group}"
    ];

    networking.firewall = lib.mkIf league.openFirewall {
      allowedTCPPorts = [league.port];
      allowedUDPPorts = [league.port];
    };

    systemd.services."drifting-league-setup" = {
      after = ["network-online.target"];
      partOf = ["drifting-league.service"];
      path = [league.java.package];
      serviceConfig = {
        StateDirectory = league.user;
        Type = "oneshot";
        RemainAfterExit = true;
        User = league.user;
        Group = league.group;
      };
      script = ''
        set -e
        java -jar ${league.quilt.installer} install server "${league.minecraft.version}" "${league.quilt.version}" --install-dir="${league.dir.state}" --download-server --create-scripts
      '';
    };

    systemd.services."drifting-league" = {
      after = ["drifting-league-setup.service"];
      requires = ["drifting-league-setup.service"];
      wantedBy = ["multi-user.target"];
      path = [league.java.package];
      restartTriggers = [league.mods];
      serviceConfig = {
        EnvironmentFile = league.environmentFile;

        Type = "simple";
        ExecStart = "${league.java.package}/bin/java -Xms${league.java.memory.initial} -Xmx${league.java.memory.max} -jar ${league.dir.state}/quilt-server-launch.jar nogui";
        ExecStop = "${league.rcon.package}/bin/mcrcon -H localhost -P ${toString league.rcon.port} -p \"$MINECRAFT_RCON_PASSWORD\" stop";
        SuccessExitStatus = [0 1];
        User = league.user;
        Group = league.group;

        StateDirectory = league.user;
        ConfigurationDirectory = league.user;
        WorkingDirectory = league.dir.state;

        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateDevices = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ReadWritePaths = league.dir.state;
      };
    };
    services.nginx.virtualHosts = lib.mkIf (league.packwiz.hostName != null) {
      ${league.packwiz.hostName} = {
        root = league.mods.passthru.packwizRoot;
        locations."=/${league.prism.name}.zip".alias = league.prism.instance;
      };
    };
  };
  meta = {};
}
