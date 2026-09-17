#!/bin/bash
# Install the Antigravity CLI (agy) from the upstream GitHub release.
#
# Not upstream's own installer (curl https://antigravity.google/cli/install.sh
# | bash): that one resolves the build through a Cloud Run auto-updater host
# this image deliberately cannot reach, then edits shell profiles and aliases
# that the image already provides. The GitHub release carries the same
# archives, is pinnable, and sits on a host the allowlist covers anyway.
set -euo pipefail

# Release to install: "latest", or a pinned tag like "1.2.5". Pinning here
# without pinning check-update.sh means the update probe keeps reporting the
# newest upstream tag and marking the image stale -- pin both or neither.
ANTIGRAVITY_VERSION="${ANTIGRAVITY_VERSION:-latest}"

REPO="google-antigravity/antigravity-cli"

case "$(uname -m)" in
    x86_64)  ASSET_ARCH="x64" ;;
    aarch64) ASSET_ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

version="$ANTIGRAVITY_VERSION"
if [ "$version" = "latest" ]; then
    version="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | jq -r '.tag_name')"
fi

if [ -z "$version" ] || [ "$version" = "null" ]; then
    echo "Could not resolve which Antigravity CLI release to install" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL \
    "https://github.com/${REPO}/releases/download/${version}/agy_cli_linux_${ASSET_ARCH}.tar.gz" \
    -o "$tmp/agy.tar.gz"

# The archive holds a single binary named "antigravity"; upstream installs it
# as "agy", which is the name the docs, the status line and the entrypoint use.
tar -xzf "$tmp/agy.tar.gz" -C "$tmp" antigravity
mkdir -p "$HOME/.local/bin"
install -m 0755 "$tmp/antigravity" "$HOME/.local/bin/agy"

# The image puts ~/.local/bin on PATH; say so explicitly so the check below
# also holds when this script is run outside an image build.
export PATH="$HOME/.local/bin:$PATH"

if ! command -v agy >/dev/null 2>&1; then
    echo "agy not found in PATH after installation" >&2
    exit 1
fi

echo "Antigravity CLI $(agy --version) installed at $(command -v agy)"
