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
      mmcPackType = lib.types.submoduleWith { modules = [ (import ./mmcPack.nix pkgs) ]; };
      mcServer = lib.types.submoduleWith {
        modules = [
          (import ./mcServer.nix mmcPackType)
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
  config = lib.mkMerge (
    [
      ({
        services.minecraft.servers.${serverName} = {
          mods = self.packages.${pkgs.stdenv.system.hostPlatform.system}.${serverName};
        };
      })
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
