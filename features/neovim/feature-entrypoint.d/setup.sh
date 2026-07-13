# shellcheck shell=bash
# Set Neovim as the default editor if available
if command -v nvim >/dev/null 2>&1; then
    export EDITOR=nvim
    export VISUAL=nvim
fi
