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
      };
      java = {
        package = mkOption {
          type = types.package;
          default = pkgs.temurin-bin;
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
    ];

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
      serviceConfig = {
        StateDirectory = league.user;
        WorkingDirectory = league.dir.state;
        Type = "forking";
        ExecStart = "${league.java.package}/bin/java -jar ${league.dir.state}/quilt-server-launch.jar nogui";
        User = league.user;
        Group = league.group;
      };
    };
  };
  meta = {};
}
