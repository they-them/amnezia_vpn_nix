#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq nix coreutils
# Bump pkgs/amnezia-vpn.nix to the latest stable amnezia-client release.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pkg="$root/pkgs/amnezia-vpn.nix"

auth=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
  auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

latest=$(curl -sSf "${auth[@]}" https://api.github.com/repos/amnezia-vpn/amnezia-client/releases \
  | jq -r 'map(select(.prerelease == false and .draft == false)) | .[0].tag_name')

if [ -z "$latest" ] || [ "$latest" = "null" ]; then
  echo "error: could not determine the latest release" >&2
  exit 1
fi

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
sed -i "s|\*\*AmneziaVPN $current\*\*|**AmneziaVPN $latest**|" "$root/README.md"

echo "done: version=$latest hash=$hash"
