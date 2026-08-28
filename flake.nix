{
  description = "AmneziaVPN client packaged for NixOS from the official Qt Installer Framework .run installer";

  nixConfig = {
    extra-substituters = [ "https://cache.nixos.org" ];
    extra-trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        rec {
          amnezia-vpn = pkgs.callPackage ./pkgs/amnezia-vpn.nix { };
          default = amnezia-vpn;
        }
      );

      overlays.default = final: prev: {
        amnezia-vpn = final.callPackage ./pkgs/amnezia-vpn.nix { };
      };

      nixosModules = rec {
        amnezia-vpn = import ./modules/amnezia-vpn.nix self;
        default = amnezia-vpn;
      };

      formatter = forAllSystems (system: (pkgsFor system).nixfmt-tree);

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              p7zip
              patchelf
              binwalk
              nix-prefetch
            ];
          };
        }
      );
    };
}
