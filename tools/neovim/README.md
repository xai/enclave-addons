# neovim (tool)

Runs Neovim as the sandbox's tool: `enclave --tool neovim` opens the editor
on the project directory, with everything else an enclave session provides
(isolated container, read-write project mount, restricted network). Trailing
arguments go to nvim:

```bash
enclave --tool neovim -- index.md -c VimwikiIndex
```

Notes:

- Editor and configuration come from the [neovim feature](../../features/neovim/);
  select it in the same run — it is what installs nvim into the image. The
  tool's own `install.sh` only provides a bare, unconfigured nvim as a
  fallback when the feature is absent.
- Deny-all network allowlist: plugins are baked at build time, the editor
  needs no egress at runtime.
- No `configDir`, deliberately: nvim's runtime state (shada, undofile, swap)
  can embed edited file contents. For the encrypted-vimwiki workflow that
  state must die with the container, not persist to a host-side store.

Built for the host-encrypted vimwiki workflow (the wiki's wrappers run
`enclave --tool neovim --features +neovim,+vimwiki`; see also the
[vimwiki feature](../../features/vimwiki/)), but generally useful as an
editor-only sandbox.
