{
  config,
  pkgs,
  lib,
  ...
}:
with builtins; let
  std = pkgs.lib;
  json = pkgs.formats.json {};
  comp = config.components;
  jgl = comp."LWJGL 3";
  mc = comp."Minecraft";
  quilt = comp."Quilt Loader";
  interm = comp."Intermediary Mappings";
  component = lib.types.submoduleWith {
    modules = [
      ({
        config,
        pkgs,
        lib,
        ...
      }: {
        options = with lib; {
          version = mkOption {
            type = types.str;
          };
          uid = mkOption {
            type = types.str;
          };
        };
      })
    ];
  };
in {
  options = with lib; {
    components = {
      "LWJGL 3" = mkOption {
        type = component;
      };
      "Minecraft" = mkOption {
        type = component;
      };
      "Intermediary Mappings" = mkOption {
        type = component;
      };
      "Quilt Loader" = mkOption {
        type = component;
      };
    };
    outputFile = mkOption {
      type = types.path;
      readOnly = true;
      default = json.generate "mmc-pack.json" config.outputJson;
    };
    outputJson = mkOption {
      type = json.type;
      readOnly = true;
      default = {
        "components" = [
          {
            "cachedName" = "LWJGL 3";
            "cachedVersion" = jgl.version;
            "cachedVolatile" = true;
            "dependencyOnly" = true;
            "uid" = jgl.uid;
            "version" = jgl.version;
          }
          {
            "cachedName" = "Minecraft";
            "cachedRequires" = [
              {
                "suggests" = jgl.version;
                "uid" = jgl.uid;
              }
            ];
            "cachedVersion" = mc.version;
            "important" = true;
            "uid" = mc.uid;
            "version" = mc.version;
          }
          {
            "cachedName" = "Intermediary Mappings";
            "cachedRequires" = [
              {
                "equals" = interm.version;
                "uid" = mc.uid;
              }
            ];
            "cachedVersion" = interm.version;
            "cachedVolatile" = true;
            "dependencyOnly" = true;
            "uid" = interm.uid;
            "version" = interm.version;
          }
          {
            "cachedName" = "Quilt Loader";
            "cachedRequires" = [
              {
                "uid" = interm.uid;
              }
            ];
            "cachedVersion" = quilt.version;
            "uid" = quilt.uid;
            "version" = quilt.version;
          }
        ];
      };
    };
  };
  config = {
    components = {
      "LWJGL 3".uid = "org.lwjgl3";
      "Minecraft".uid = "net.minecraft";
      "Intermediary Mappings" = {
        version = mc.version;
        uid = "net.fabricmc.intermediary";
      };
      "Quilt Loader".uid = "org.quiltmc.quilt-loader";
    };
  };
  meta = {};
}
