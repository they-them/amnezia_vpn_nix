# NixOS module for the AmneziaVPN client, modelled on nixpkgs'
# nixos/modules/programs/amnezia-vpn.nix but wired to this flake's package.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.amnezia-vpn;
in
{
  # nixpkgs ships its own `programs.amnezia-vpn` (for the source-built package).
  # Both modules declare the same options, so the upstream one is replaced
  # rather than merged. Users who prefer the nixpkgs build can still get it via
  # `programs.amnezia-vpn.package = pkgs.amnezia-vpn;`.
  disabledModules = [ "programs/amnezia-vpn.nix" ];

  options.programs.amnezia-vpn = {
    enable = lib.mkEnableOption "the AmneziaVPN client and its privileged helper service";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.amnezia-vpn;
      defaultText = lib.literalExpression "amnezia-vpn.packages.\${system}.amnezia-vpn";
      description = "The amnezia-vpn package to use.";
    };

    linkWireguardTools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Create `/usr/bin/wg-quick` and `/usr/bin/awg-quick` symlinks.

        The prebuilt client resolves the WireGuard helper through
        `Utils::usrExecutable()`, which only ever looks in `/usr/sbin` and
        `/usr/bin` — a `PATH` entry is not enough. Without these links,
        WireGuard and AmneziaWG connections fail to come up. Set to `false` if
        you would rather keep `/usr/bin` untouched and only use protocols that
        do not need `wg-quick` (OpenVPN, Xray/VLESS, ShadowSocks, Cloak).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    services.dbus.packages = [ cfg.package ];

    # The client rewrites DNS through update-resolv-conf.sh, which talks to
    # systemd-resolved.
    services.resolved.enable = true;

    systemd = {
      packages = [ cfg.package ];
      services."AmneziaVPN" = {
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [
          gawk
          iproute2
          iptables
          procps
          sudo
          wireguard-tools
          amneziawg-tools
        ];
      };

      tmpfiles.rules = lib.optionals cfg.linkWireguardTools [
        "L+ /usr/bin/wg-quick  - - - - ${lib.getExe' pkgs.wireguard-tools "wg-quick"}"
        "L+ /usr/bin/awg-quick - - - - ${lib.getExe' pkgs.amneziawg-tools "awg-quick"}"
      ];
    };
  };
}
