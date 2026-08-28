# Evaluate the NixOS module against a throwaway system configuration.
{ flakePath }:
let
  flake = builtins.getFlake flakePath;
  nixpkgs = flake.inputs.nixpkgs;
in
nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  modules = [
    flake.nixosModules.default
    (
      { ... }:
      {
        boot.loader.grub.devices = [ "/dev/null" ];
        fileSystems."/" = {
          device = "/dev/null";
          fsType = "ext4";
        };
        system.stateVersion = "25.11";
        programs.amnezia-vpn.enable = true;
      }
    )
  ];
}
