#!/usr/bin/env bash
# Bump sources.json to the latest (or given) nouride release: ./update.sh [vX.Y.Z]
set -euo pipefail
cd "$(dirname "$0")"

repo=nouverse/nouride-releases
auth=()
[ -n "${GITHUB_TOKEN:-}" ] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
tag=${1:-$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name)}
base="https://github.com/$repo/releases/download/$tag"

sums=$(curl -fsSL "$base/SHA256SUMS"; curl -fsSL "$base/SHA256SUMS-router")

hashes='{}'
for name in nouride-linux-x64 nouride-linux-arm64 nouride-router-linux-x64 nouride-router-linux-arm64; do
  hex=$(awk -v f="$name.tar.gz" '$2 == f { print $1 }' <<<"$sums")
  [ -n "$hex" ] || { echo "no checksum for $name in $tag" >&2; exit 1; }
  sri=$(nix hash convert --hash-algo sha256 --to sri "$hex")
  hashes=$(jq --arg k "$name" --arg v "$sri" '. + {($k): $v}' <<<"$hashes")
done

jq -n --arg v "${tag#v}" --argjson h "$hashes" '{version: $v, hashes: $h}' >sources.json
echo "sources.json -> ${tag#v}"
