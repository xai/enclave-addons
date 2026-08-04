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
macOS) and enables opt-in features in your global enclave config — except
features whose spec is marked `# x-install-mode: per-run`, which stay out of
the global config and are selected per run with `--features +<name>`.
Afterwards, bake them into the image:

```bash
enclave --rebuild
```

User commands are copied into `commands/` in the enclave config root instead
and become available immediately as `enclave <name>` — no rebuild needed. Host
commands also bring along the shared library they source,
`commands/host/lib/enclave-cmd.sh`.

Run `./install.sh` without arguments to list the available add-ons. A
feature and a tool may share a name (e.g. `neovim`); a bare name installs
every kind it matches, and `features/<name>` / `tools/<name>` picks one.

## Available add-ons

| Name | Kind | Description |
| --- | --- | --- |
| [neovim](features/neovim/) | feature | Neovim editor with lazy.nvim and sensible defaults |
| [vimwiki](features/vimwiki/) | feature | Vimwiki plugin on top of the neovim feature; dormant outside unlocked vimwiki sessions. Per-run feature: select with `--features +neovim,+vimwiki`, never enabled globally |
| [neovim (tool)](tools/neovim/) | tool | `enclave --tool neovim` — Neovim as the session tool, for editor-only sandboxes |
| [texlive-debian](features/texlive-debian/) | feature | TeX Live from Debian packages, sized for math/CS papers (beamer, TikZ, biblatex/biber, latexmk, IEEE/ACM classes) |
| [texlive-upstream](features/texlive-upstream/) | feature | Current or pinned TeX Live release from TUG/CTAN via install-tl; wins over texlive-debian on `PATH` |
| [diffity](features/diffity/) | feature | GitHub-style diff viewer and code review UI, with `/diffity-*` skills for every skill-capable Enclave tool |
| [rebase](commands/host/rebase) | host command | `enclave rebase [target]` — agent-assisted rebase onto a target branch (default `main`) |
| [triage](commands/host/triage) | host command | `enclave triage` — collect unaddressed feedback from the branch's GitHub PR and the latest `.reviews/` round(s), verify it, and fix the findings you select |
| [check-pr](commands/host/check-pr) | host command | `enclave check-pr` — gather all feedback on the branch's GitHub PR, verify it against the code, then ask whether to review the diff, fix the open findings, or stop |

## Host commands

Each host command here is a prompt plus a bit of argument handling, wrapped by
[`commands/host/lib/enclave-cmd.sh`](commands/host/lib/enclave-cmd.sh). The
library gives every command a `-h` that reports its resolved configuration
instead of starting a session, lets it pin a tool and that tool's flags, and
splices those defaults ahead of anything you pass at the call site:

```bash
enclave rebase -h                            # usage and resolved configuration
enclave rebase feature/x                     # positional argument
enclave rebase -- --model sonnet             # appended last, so it wins
enclave rebase --tool codex                  # replaces the tool; drops its flags
ENCLAVE_CMD_TOOL=codex enclave triage        # same, as an env var
ENCLAVE_CMD_ARGS= enclave triage             # keep the tool's own defaults
```

Tool flags rarely transfer between tools, so choosing a tool anywhere always
drops the flags that came with the previous one.

No command here picks a tool or a model: which one suits you is your call, not
the repository's, so all of them run whatever `enclave run` defaults to. Choose
your own by copying
[`enclave-cmd.local.sh.example`](commands/host/lib/enclave-cmd.local.sh.example)
to `enclave-cmd.local.sh` in the installed `commands/host/lib/` and editing it:

```sh
enclave_cmd_tool=claude                    # the default for every command
enclave_cmd_args="--model sonnet"

enclave_cmd_tool_rebase=claude             # and for one command in particular
enclave_cmd_args_rebase="--model opus --effort high"
```

Per command is worth the two lines where the work justifies it — conflict
resolution in `rebase` or a full review in `slopreview` reward a stronger model
than skimming a PR does.

`install.sh` writes `enclave-cmd.sh` but never `enclave-cmd.local.sh`, so
updating this repository leaves those settings alone. Per-command entries
override anything a command declares for itself, which is what makes them
survive a reinstall: retune the local file rather than the installed command.
Set `ENCLAVE_CMD_CONFIG` to keep the file somewhere else.

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

Once the last host command is gone, `commands/host/lib/` can go too — but only
if nothing else sources it, and remember that `enclave-cmd.local.sh` lives
there.

## Repository layout

The layout mirrors the enclave config root: `features/` and `tools/` map to
`extensions/{features,tools}/`, `commands/` maps to `commands/`:

```
.
├── install.sh          # generic installer: ./install.sh <name>...
├── commands/           # user commands: enclave <name>
│   └── host/
│       ├── lib/        # shared helpers, sourced by the commands beside it
│       ├── check-pr
│       ├── rebase
│       └── triage
├── features/           # kind: mixin — tooling available to all agents
│   ├── diffity/
│   ├── neovim/
│   ├── texlive-debian/
│   ├── texlive-upstream/
│   └── vimwiki/
└── tools/              # kind: sandbox — runnable session tools
    └── neovim/
```

## Adding an add-on

Create `features/<name>/` (or `tools/<name>/`) with a `spec.yaml` following
the [extension format](https://github.com/eclipsesource/yoloarena/blob/main/docs/extensions/README.md),
add a `README.md`, and list the add-on in the table above. A feature that
should never live in the global `features` array (because it only makes
sense for particular runs) declares that with a spec comment line
`# x-install-mode: per-run`; the installer then copies it without enabling
it. For a user
command, add an executable file `commands/host/<name>` (runs on the host)
or `commands/session/<name>` (runs in the container). The install script
discovers add-ons by directory or file name, so no installer change is
needed. Files under `commands/host/lib/` are not add-ons — enclave skips
subdirectories when discovering commands, and the installer treats the
directory as a dependency of the commands rather than as an entry of its own.

A feature may ship agent skills as subdirectories of `features/<name>/skills/`.
When that feature is enabled, Enclave composes those directories into every
session tool that declares `sandbox.skillsDir`; tools without a managed skill
interface ignore them. Non-directory entries are not installed as skills, so a
feature can keep an upstream license or provenance notice beside them.

A host command that drives an agent is a prompt around the library:

```sh
#!/bin/sh
set -eu

# shellcheck source=lib/enclave-cmd.sh
. "${0%/*}/lib/enclave-cmd.sh"

enclave_cmd_summary="One or two lines, shown by -h."
enclave_cmd_synopsis="[<target>]"   # only if the command takes a positional

prompt=$(cat <<'EOF'
...
EOF
)

enclave_run "$prompt" "$@"
```

Leave the tool out, as the commands here do: a prompt that only works on one
tool is a prompt to fix, and a model preference belongs in the local config,
where it is the reader's to choose. `enclave_cmd_tool` and `enclave_cmd_args`
exist for a command that truly cannot work otherwise, and are then set together.

Because the library resolves itself from `$0`, an in-tree command runs straight
from a checkout:

```bash
# print the enclave invocation instead of starting a session
ENCLAVE_BIN=echo ./commands/host/rebase -- --model sonnet

# the source directive needs SCRIPTDIR to resolve
find commands -type f -exec shellcheck -x --source-path=SCRIPTDIR {} +
```
