# Neovim

Installs the latest stable [Neovim](https://neovim.io/) with the
[lazy.nvim](https://github.com/folke/lazy.nvim) plugin manager and sensible
defaults, and sets it as the container's default editor (`$EDITOR`/`$VISUAL`).

## What it does

- Downloads the stable Neovim release tarball into `~/.local` at image build
  time (x86_64 and aarch64)
- Bootstraps lazy.nvim and pre-installs a small set of base plugins
  (vim-sleuth, vim-surround, vim-repeat, vim-fugitive, fzf, fzf.vim) — plugins
  must be installed at build time because the sandbox network policy blocks
  github.com at runtime by default
- Writes an `init.lua` with sensible defaults (space leader, relative
  numbers, 4-space indent, system clipboard, persistent undo, ...)
- Exports `EDITOR=nvim` and `VISUAL=nvim` at container startup

## Configuration

To pin a specific Neovim release, edit `NEOVIM_VERSION` in `install.sh`
(default: `stable`). To change plugins or settings, edit the heredocs in
`install.sh` and rebuild.

The feature is opt-in (`defaultEnabled: false`), and installing it does not
activate it: `./install.sh neovim` only copies it onto your machine. Select it
for the sessions that want it with `enclave --features "+neovim"`, or add
`"+neovim"` to the `features` array in your global config for every session
(`./install.sh --enable neovim` writes that entry for you). See the
[repository README](../../README.md).
