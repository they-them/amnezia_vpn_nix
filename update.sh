#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq nix coreutils
# Bump pkgs/amnezia-vpn.nix to the latest stable amnezia-client release.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$root/pkgs/amnezia-vpn.nix"

latest=$(curl -sSf https://api.github.com/repos/amnezia-vpn/amnezia-client/releases \
  | jq -r 'map(select(.prerelease == false)) | .[0].tag_name')

current=$(sed -n 's/^  version = "\(.*\)";$/\1/p' "$pkg")

if [ "$latest" = "$current" ]; then
  echo "amnezia-vpn is already at $current"
  exit 0
fi

url="https://github.com/amnezia-vpn/amnezia-client/releases/download/$latest/AmneziaVPN_${latest}_linux_x64.run"
echo "updating $current -> $latest"
hash=$(nix hash convert --hash-algo sha256 --to sri "$(nix-prefetch-url "$url")")

sed -i "s|^  version = \".*\";$|  version = \"$latest\";|" "$pkg"
sed -i "s|^    hash = \".*\";$|    hash = \"$hash\";|" "$pkg"

echo "done: version=$latest hash=$hash"
