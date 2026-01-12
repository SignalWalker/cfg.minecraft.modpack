serverName:
{ self', ... }:
{
  config,
  pkgs,
  lib,
  ...
}:
{
  options =
    let
      mmcPackType = lib.types.submoduleWith { modules = [ (import ./mmcPack.nix pkgs) ]; };
      mcServer = lib.types.submoduleWith {
        modules = [
          (import ./mcServer.nix self'.packages.${serverName} pkgs mmcPackType)
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
      merge = f: lib.mkMerge (lib.mapAttrsToList f config.services.minecraft.servers);
    in
    {

      users = merge (
        name: server: {
          users.${server.user} = {
            isSystemUser = true;
            home = server.dir.state;
            group = server.group;
          };
          groups.${server.group} = { };
        }
      );

      systemd = merge (
        name: server: {
          tmpfiles.settings = {
            "98-minecraft-${server.name}" = {
              "${server.dir.configuration}/config" = {
                "d" = {
                  user = server.user;
                  group = server.group;
                  mode = "0750";
                };
              };
              "${server.dir.logs}/logs" = {
                "d" = {
                  user = server.user;
                  group = server.group;
                  mode = "0750";
                };
              };
              "${server.dir.logs}/crash-reports" = {
                "d" = {
                  user = server.user;
                  group = server.group;
                  mode = "0750";
                };
              };
            };
            "99-minecraft-${server.name}" = {
              # "${server.dir.state}/mods" = {
              #   "L+" = {
              #     argument = toString server.mods;
              #   };
              # };
              "${server.dir.state}/config" = {
                "L" = {
                  argument = "${server.dir.configuration}/config";
                };
              };
              "${server.dir.state}/logs" = {
                "L+" = {
                  argument = "${server.dir.logs}/logs";
                };
              };
              "${server.dir.state}/crash-reports" = {
                "L+" = {
                  argument = "${server.dir.logs}/crash-reports";
                };
              };
              "${server.dir.state}/.cache" = {
                "L+" = {
                  argument = server.dir.cache;
                };
              };
              "${server.dir.state}/user_jvm_args.txt" = {
                "L+" = {
                  argument = toString (
                    pkgs.writeText "user_jvm_args.txt" ''
                      -Xms${server.java.memory.initial}
                      -Xmx${server.java.memory.max}
                    ''
                  );
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
          services =
            let
              systemdServiceSetup = "minecraft-server-setup-${server.name}";
              systemdService = "minecraft-server-${server.name}";
            in
            {
              ${systemdServiceSetup} = {
                requires = [ "network-online.target" ];
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
                # java -jar ${server.quilt.installer} install server "${server.minecraft.version}" "${server.quilt.version}" --install-dir="${server.dir.state}" --download-server --create-scripts
                script = ''
                  set -xe
                  echo "eula=true" > "${server.dir.state}/eula.txt"
                  java -jar ${server.neoforge.installer} --install-server "${server.dir.state}"
                '';
              };
              ${systemdService} = {
                after = [ "${systemdServiceSetup}.service" ];
                requires = [ "${systemdServiceSetup}.service" ];
                wantedBy = [ "multi-user.target" ];
                path = [ server.java.package ];
                restartTriggers = [ server.mods ];
                serviceConfig = {
                  EnvironmentFile = server.environmentFile;

                  Type = "simple";
                  ExecStartPre = pkgs.writeShellScript "${systemdService}-pre" ''
                    set -xe

                    state_dir="${server.dir.state}"
                    cache_dir="${server.dir.cache}"
                    logs_dir="${server.dir.logs}"
                    config_dir="${server.dir.configuration}"

                    mods_dir="$state_dir/mods"

                    index_dir="$cache_dir/sinytra/index"
                    connector_dir="$cache_dir/sinytra/connector"

                    # set up mods directory
                    if [[ -e "$mods_dir" ]]; then
                      rm -r "$mods_dir"
                    fi
                    cp -r "${toString server.mods}" "$mods_dir"
                    chmod ug+w "$mods_dir"
                    mkdir -p "$index_dir" "$connector_dir"
                    ln -sfT "$index_dir" "$mods_dir/.index"
                    ln -sfT "$connector_dir" "$mods_dir/.connector"
                  '';
                  ExecStart = "${pkgs.busybox}/bin/sh ${server.dir.state}/run.sh nogui";
                  # ExecStart = "java -Xms${server.java.memory.initial} -Xmx${server.java.memory.max} -jar ${server.dir.state}/quilt-server-launch.jar nogui";
                  ExecStop = "${server.rcon.package}/bin/mcrcon -H localhost -P ${toString server.rcon.port} -p \"$MINECRAFT_RCON_PASSWORD\" stop";
                  SuccessExitStatus = [
                    0
                    1
                  ];
                  User = server.user;
                  Group = server.group;

                  StateDirectory = server.user;
                  CacheDirectory = server.user;
                  LogsDirectory = server.user;
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
            };
        }
      );

      networking = merge (
        name: server: {
          firewall = lib.mkIf server.openFirewall {
            allowedTCPPorts = [ server.port ];
            allowedUDPPorts = [ server.port ];
          };
        }
      );

      services.nginx = merge (
        name: server: {
          virtualHosts = lib.mkIf (server.packwiz.hostName != null) {
            ${server.packwiz.hostName} = {
              locations = {
                "=/${server.name}/${server.prism.name}.zip".alias = server.prism.instance;
                "/${server.name}/" = {
                  alias = "${server.mods.passthru.packwizRoot}/";
                  extraConfig = ''
                    autoindex on;
                  '';
                };
              };
            };
          };
        }
      );

    }

  ;
  meta = { };
}
