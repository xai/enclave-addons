#!/bin/bash
# Install the vimwiki plugin into the neovim feature's configuration
set -euo pipefail

# This feature layers on the neovim feature (priority 85; ours is 90, so it
# installs afterwards). Enclave has no dependency mechanism between features,
# so check for the pieces we build on explicitly.
if ! command -v nvim >/dev/null 2>&1 || [ ! -f "$HOME/.config/nvim/init.lua" ]; then
    echo "vimwiki: the 'neovim' feature must be selected alongside this one" >&2
    echo "vimwiki: (e.g. --features +neovim,+vimwiki)" >&2
    exit 1
fi

mkdir -p "$HOME/.config/nvim/lua/plugins"

# lazy.nvim auto-imports every module under lua/plugins/, so a drop-in file
# is all it takes to extend the neovim feature's plugin set.
cat > "$HOME/.config/nvim/lua/plugins/vimwiki.lua" <<'VIMWIKI'
-- vimwiki.lua — plugin spec for the host-encrypted ~/vimwiki workflow.
-- The host decrypts the wiki into a tmpfs session dir and runs this image
-- against it; see the wiki's bin/{vimwiki-unlock,vimwiki-seal,wiki-edit,
-- wiki-session}.
--
-- The spec is declared unconditionally and the build-time `Lazy! sync`
-- runs with VIMWIKI_BUILD=1 so the plugin gets installed into the image
-- (the sandbox cannot reach github.com at runtime). lazy.nvim skips
-- cond=false plugins on install too (cond only protects them from being
-- cleaned), so cond must evaluate true during that sync; at runtime it
-- gates loading on a real session, keeping every non-wiki nvim run in
-- this image vimwiki-free.

local function vimwiki_root()
  -- Prefer cwd if it's the unlocked session — VIMWIKI_ROOT may be an
  -- alias that doesn't match the buffer's real path, which breaks
  -- vimwiki's path-prefix match (wiki_nr == -1 → no ft set).
  local cwd = vim.fn.getcwd()
  if vim.fn.filereadable(cwd .. "/.unlock-manifest.json") == 1 then
    return cwd
  end
  local env = vim.env.VIMWIKI_ROOT
  if env and env ~= "" then return env end
  return nil
end

-- Session files are already plaintext; nothing may try to en/decrypt them
-- in-container. vim-gnupg is not installed here, but keep the guard.
vim.g.loaded_gnupg = 1

return {
  {
    "vimwiki/vimwiki",
    lazy = false,
    -- VIMWIKI_BUILD marks the image-build sync (see header comment); init
    -- below still requires a real session root, so the build never
    -- configures anything.
    cond = function()
      return vimwiki_root() ~= nil or vim.env.VIMWIKI_BUILD == "1"
    end,
    init = function()
      local root = vimwiki_root()
      if not root then return end
      vim.g.vimwiki_global_ext = 0 -- don't claim every .md file
      vim.g.vimwiki_list = {
        { path = vim.fn.expand(root) .. "/", syntax = "markdown", ext = ".md" },
      }

      local grp = vim.api.nvim_create_augroup("vimwiki_local", { clear = true })

      vim.api.nvim_create_autocmd({ "BufRead", "BufWinEnter", "BufNewFile" }, {
        group = grp,
        pattern = "*.md",
        command = "setlocal syntax=markdown",
      })

      vim.api.nvim_create_autocmd("FileType", {
        group = grp,
        pattern = "vimwiki",
        callback = function()
          pcall(vim.keymap.del, "i", "<Tab>", { buffer = 0 })
          vim.opt_local.modeline = true
        end,
      })
    end,
  },
}
VIMWIKI

# Pre-install the plugin at build time; the sandbox cannot reach github.com
# at runtime unless the session network policy allows it. VIMWIKI_BUILD=1
# makes the spec's cond true for this sync only -- lazy.nvim does not
# install cond=false plugins.
VIMWIKI_BUILD=1 nvim --headless "+Lazy! sync" "+qa!" 2>&1

# `Lazy! sync` does not reliably fail the nvim exit code, so verify that the
# plugin actually landed -- without it this feature is pointless (and the
# spec sets failOnInstallError so this aborts the build).
if [ ! -d "$HOME/.local/share/nvim/lazy/vimwiki" ]; then
    echo "vimwiki: plugin missing after Lazy sync" >&2
    exit 1
fi

echo "vimwiki plugin installed"
