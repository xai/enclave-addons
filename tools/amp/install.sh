#!/bin/bash
# Install the Amp CLI from Sourcegraph's release storage.
#
# Not upstream's own installer (curl https://ampcode.com/install.sh | bash):
# that one unpacks into ~/.amp/bin, symlinks the binary onto PATH, appends PATH
# lines to the shell profiles the image already provides, and leaves the
# self-update path in place. It downloads from the same host used here, which
# publishes a SHA-256 next to every build and takes a pinned version.
set -euo pipefail

# Build to install: "latest", or a pinned version like "0.0.1789660852-g000545".
# Pinning here without pinning check-update.sh means the update probe keeps
# reporting the newest upstream build and marking the image stale -- pin both
# or neither.
AMP_VERSION="${AMP_VERSION:-latest}"

BASE="https://static.ampcode.com/cli"

case "$(uname -m)" in
    x86_64)  ASSET_ARCH="x64" ;;
    aarch64) ASSET_ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $(uname -m)" >&2
        exit 1
        ;;
esac

version="$AMP_VERSION"
if [ "$version" = "latest" ]; then
    version="$(curl -fsSL "$BASE/cli-version.txt" | tr -d '[:space:]')"
fi

if [ -z "$version" ]; then
    echo "Could not resolve which Amp CLI build to install" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The gzipped binary is a third of the download. The published checksum covers
# the uncompressed one, so decompress first and verify after.
curl -fsSL "$BASE/${version}/amp-linux-${ASSET_ARCH}.gz" -o "$tmp/amp.gz"
curl -fsSL "$BASE/${version}/linux-${ASSET_ARCH}-amp.sha256" -o "$tmp/amp.sha256"
gunzip -c "$tmp/amp.gz" > "$tmp/amp"

echo "$(cat "$tmp/amp.sha256")  $tmp/amp" | sha256sum -c - > /dev/null

mkdir -p "$HOME/.local/bin"
install -m 0755 "$tmp/amp" "$HOME/.local/bin/amp"

# The image puts ~/.local/bin on PATH; say so explicitly so the check below
# also holds when this script is run outside an image build.
export PATH="$HOME/.local/bin:$PATH"

if ! command -v amp >/dev/null 2>&1; then
    echo "amp not found in PATH after installation" >&2
    exit 1
fi

# Smoke-test the binary against a settings file that turns updates off. Update
# mode defaults to "auto", and the image has no settings file yet, so a bare
# `amp --version` here could replace the build whose checksum was just verified.
printf '{"amp.updates.mode":"disabled"}\n' > "$tmp/settings.json"
echo "Amp CLI $(AMP_SETTINGS_FILE="$tmp/settings.json" amp --version) installed at $(command -v amp)"
