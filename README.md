# Enclave Add-ons

Add-ons for [enclave](https://github.com/eclipsesource/yoloarena) that are
not bundled with the main repository:
[user extensions](https://github.com/eclipsesource/yoloarena/blob/main/docs/extensions/README.md#extension-sources)
(features and tools) and
[user commands](https://github.com/eclipsesource/yoloarena/blob/main/docs/ARCHITECTURE.md#key-concepts)
(`enclave <name>` subcommands).

## Installation

Clone this repository and run the install script with the add-ons you want:

```bash
./install.sh neovim rebase
```

The script copies extensions into the enclave user extension root
(`~/.config/enclave/extensions/` on Linux,
`~/Library/Application Support/org.eclipse.enclave/config/extensions/` on
macOS) and enables opt-in features in your global enclave config. Afterwards,
bake them into the image:

```bash
enclave --rebuild
```

User commands are copied into `commands/` in the enclave config root instead
and become available immediately as `enclave <name>` — no rebuild needed.

Run `./install.sh` without arguments to list the available add-ons.

## Available add-ons

| Name | Kind | Description |
| --- | --- | --- |
| [neovim](features/neovim/) | feature | Neovim editor with lazy.nvim and sensible defaults |
| [texlive-debian](features/texlive-debian/) | feature | TeX Live from Debian packages, sized for math/CS papers (beamer, TikZ, biblatex/biber, latexmk, IEEE/ACM classes) |
| [texlive-upstream](features/texlive-upstream/) | feature | Current or pinned TeX Live release from TUG/CTAN via install-tl; wins over texlive-debian on `PATH` |
| [rebase](commands/host/rebase) | host command | `enclave rebase [target]` — agent-assisted rebase onto a target branch (default `main`) |
| [triage](commands/host/triage) | host command | `enclave triage` — collect unaddressed feedback from the branch's GitHub PR and the latest `.reviews/` round(s), verify it, and fix the findings you select |

## Updating

Pull the latest changes, re-run the install script for your add-ons (it
overwrites the installed copy), and rebuild:

```bash
git pull
./install.sh neovim rebase
enclave --rebuild
```

## Removing an add-on

Delete an extension from the user extension root, drop its `+<name>` entry
from the `features` array in your global config
(`~/.config/enclave/config.json` on Linux), and rebuild:

```bash
rm -rf ~/.config/enclave/extensions/features/neovim
enclave --rebuild
```

User commands are removed by deleting the installed file; no config entry or
rebuild is involved:

```bash
rm ~/.config/enclave/commands/host/rebase
```

## Repository layout

The layout mirrors the enclave config root: `features/` and `tools/` map to
`extensions/{features,tools}/`, `commands/` maps to `commands/`:

```
.
├── install.sh          # generic installer: ./install.sh <name>...
├── commands/           # user commands: enclave <name>
│   └── host/
│       ├── rebase
│       └── triage
├── features/           # kind: mixin — tooling available to all agents
│   ├── neovim/
│   ├── texlive-debian/
│   └── texlive-upstream/
└── tools/              # kind: sandbox — runnable agents (none yet)
```

## Adding an add-on

Create `features/<name>/` (or `tools/<name>/`) with a `spec.yaml` following
the [extension format](https://github.com/eclipsesource/yoloarena/blob/main/docs/extensions/README.md),
add a `README.md`, and list the add-on in the table above. For a user
command, add an executable file `commands/host/<name>` (runs on the host)
or `commands/session/<name>` (runs in the container). The install script
discovers add-ons by directory or file name, so no installer change is
needed.
