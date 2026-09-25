{
  description = "Nouride (github:nouverse/nouride-releases) packaged for Nix";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems =
        f:
        lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              # The upstream binary is proprietary; allow just these two.
              config.allowUnfreePredicate =
                p:
                builtins.elem (lib.getName p) [
                  "nouride"
                  "nouride-router"
                ];
            }
          )
        );
    in
    {
      packages = forAllSystems (pkgs: rec {
        nouride = pkgs.callPackage ./package.nix { };
        nouride-router = pkgs.callPackage ./package.nix { edition = "router"; };
        default = nouride;
      });

      overlays.default = final: _prev: {
        nouride = final.callPackage ./package.nix { };
        nouride-router = final.callPackage ./package.nix { edition = "router"; };
      };

      nixosModules.default = import ./module.nix self;
      nixosModules.nouride = self.nixosModules.default;

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
