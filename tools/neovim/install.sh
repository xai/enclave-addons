#!/bin/bash
# Install Neovim for the neovim *tool*. Normally a no-op: the neovim
# *feature* installs nvim (plus lazy.nvim and config) into feature-base,
# which the tool stage builds on. The fallback below keeps the tool
# self-contained when the feature is not selected -- a bare editor with
# default config.
set -euo pipefail

if command -v nvim >/dev/null 2>&1; then
    echo "nvim already installed (neovim feature); nothing to do"
    exit 0
fi

# Neovim release to install: "stable" or a pinned tag like "v0.11.2"
NEOVIM_VERSION="stable"

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  NVIM_TARBALL="nvim-linux-x86_64.tar.gz" ;;
    aarch64) NVIM_TARBALL="nvim-linux-arm64.tar.gz" ;;
    *)
        echo "Unsupported architecture: $ARCH" >&2
        exit 1
        ;;
esac

mkdir -p "$HOME/.local"
curl -fsSL "https://github.com/neovim/neovim/releases/download/${NEOVIM_VERSION}/${NVIM_TARBALL}" \
    -o /tmp/nvim.tar.gz
tar -xzf /tmp/nvim.tar.gz -C "$HOME/.local" --strip-components=1
rm -f /tmp/nvim.tar.gz

if ! command -v nvim >/dev/null 2>&1; then
    echo "nvim not found in PATH after installation" >&2
    exit 1
fi

echo "Neovim $(nvim --version | head -1) installed"
