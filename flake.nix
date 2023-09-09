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
      devShells =
        std.mapAttrs (system: pkgs: {
          default = pkgs.mkShell {
            packages = with pkgs; [packwiz];
          };
        })
        nixpkgsFor;
    };
}
