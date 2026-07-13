#!/bin/bash
# Install Neovim with lazy.nvim plugin manager and base plugins
set -euo pipefail

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

# Bootstrap lazy.nvim plugin manager
LAZY_DIR="$HOME/.local/share/nvim/lazy/lazy.nvim"
if [ ! -d "$LAZY_DIR" ]; then
    git clone --filter=blob:none --branch=stable \
        https://github.com/folke/lazy.nvim.git "$LAZY_DIR"
fi

# Write neovim configuration
mkdir -p "$HOME/.config/nvim/lua/plugins"

cat > "$HOME/.config/nvim/init.lua" <<'INITLUA'
-- Sensible defaults
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.signcolumn = "yes"
vim.opt.cursorline = true
vim.opt.scrolloff = 8
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.undofile = true
vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

-- lazy.nvim is cloned at image build time by install.sh
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")

-- Load plugins from lua/plugins/
require("lazy").setup("plugins")
INITLUA

cat > "$HOME/.config/nvim/lua/plugins/editor.lua" <<'PLUGINS'
return {
  "tpope/vim-sleuth",
  "tpope/vim-surround",
  "tpope/vim-repeat",
  "tpope/vim-fugitive",
  { "junegunn/fzf", build = "./install --bin" },
  "junegunn/fzf.vim",
}
PLUGINS

# Pre-install plugins at build time; the sandbox cannot reach github.com
# at runtime unless the session network policy allows it.
nvim --headless "+Lazy! sync" "+qa!" 2>&1 || echo "Warning: plugin pre-install incomplete"

echo "Neovim $(nvim --version | head -1) installed with lazy.nvim"
