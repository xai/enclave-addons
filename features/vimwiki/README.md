# vimwiki

[vimwiki](https://github.com/vimwiki/vimwiki) for the [neovim](../neovim/)
feature, built for the host-encrypted `~/vimwiki` workflow: the host decrypts
the wiki into a tmpfs session directory and runs neovim against it inside an
enclave container (see the wiki's `bin/wiki-edit` / `bin/wiki-session`).

## Behaviour

- Drops `lua/plugins/vimwiki.lua` into the neovim feature's config and bakes
  the plugin into the image at build time (`Lazy! sync`; the sandbox has no
  github.com access at runtime).
- The plugin only *loads* inside an unlocked wiki session, detected by a
  `.unlock-manifest.json` in the working directory or `$VIMWIKI_ROOT` in the
  environment (pass it with `--pass-env VIMWIKI_ROOT`). Everywhere else it
  stays dormant (lazy.nvim `cond`), so a container with this feature baked
  in still behaves like plain neovim.
- Sets `vim.g.loaded_gnupg = 1`: session files are already plaintext, and
  nothing may try to en/decrypt them in-container.

## Enablement

Per run only — deliberately never in the global `features` array:

```bash
enclave --tool neovim --features +neovim,+vimwiki
```

The repo installer respects that (`x-install-mode: per-run` in the spec): it
copies the extension but does not touch the global config. The `neovim`
feature must be part of the same selection — `install.sh` fails the image
build otherwise (`failOnInstallError: true`).
