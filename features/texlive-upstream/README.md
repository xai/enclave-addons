# TeX Live (upstream)

Installs an official TeX Live release with the upstream installer
([install-tl](https://www.tug.org/texlive/quickinstall.html)) — either the
current release from CTAN or a pinned year from the frozen historic archive.
Use this when Debian's TeX Live (see [texlive-debian](../texlive-debian/)) is
too old, or when a paper must build against a specific release.

## What it does

- Downloads `install-tl` and installs TeX Live into
  `~/.local/texlive/<release>` at image build time, as the container user
  (no root)
- Installs `scheme-full` without documentation and source files (~4.5 GB in
  the image) — every CTAN package, so beamer, TikZ, biblatex/biber, latexmk,
  IEEEtran, acmart, llncs, ... are all present
- Symlinks all TeX Live binaries into `~/.local/bin` (the installer's
  `instopt_adjustpath`), which precedes `/usr/bin` in the container `PATH`
- Pinned years resolve automatically to the frozen `tlnet-final` repository
  in the historic archive (the regular CTAN mirrors only serve the current
  release)
- Adds supporting apt packages: `perl`, `curl`, `ca-certificates` (for the
  installer), `fontconfig` (system fonts for xelatex/lualatex),
  `ghostscript`, `python3-pygments` (for minted), and `poppler-utils`
  (pdftoppm, so agents can render pages of the built PDF to images and
  inspect their own output)

## Configuration

Features are baked into the image at `docker build` time, so a runtime
environment variable or a project `.env` cannot select the release. The
knobs are variables at the top of `install.sh` (same pattern as
`NEOVIM_VERSION` in the [neovim](../neovim/) feature):

- `TEXLIVE_RELEASE` — `latest` (default) for the current CTAN release, or a
  year like `2025` for that frozen release from the historic archive
  (2017 and newer)
- `TEXLIVE_SCHEME` — `scheme-full` (default). Smaller schemes shrink the
  image at the cost of missing packages; the build then only warns about
  the ones it checks for (beamer, TikZ, biblatex)

After editing, re-run `./install.sh texlive-upstream` from the repository
and rebuild with `enclave --rebuild`.

The feature is opt-in (`defaultEnabled: false`), and installing it does not
activate it: `./install.sh texlive-upstream` only copies it onto your machine.
Select it per session with `enclave --features "+texlive-upstream"`, or make it
permanent by adding `"+texlive-upstream"` to the `features` array in your global
config (`./install.sh --enable texlive-upstream` writes that entry for you) or
in `~/.config/enclave/projects/<hash>/config.json` for one project only. See the
[repository README](../../README.md).

## Coexistence with texlive-debian

Both TeX Live features can be installed side by side; there is no explicit
dependency or conflict mechanism between enclave extensions, and none is
needed here. This feature's binaries live in `~/.local/bin`, which comes
before `/usr/bin` (where the Debian binaries live) in the container `PATH` —
so when both are present, the upstream release wins consistently: `latexmk`,
`pdflatex`, `kpsewhich` etc. all resolve to the same tree. Run
`/usr/bin/pdflatex` explicitly to reach the Debian one.

## Installing packages at runtime (tlmgr)

With `scheme-full` there is nothing to add. If you use a smaller scheme,
`tlmgr install <pkg>` works as the container user (the tree in `$HOME` is
user-owned), but the sandbox blocks CTAN by default. Since
`mirror.ctan.org` redirects to arbitrary mirrors, pin one and allow it for
the session:

```bash
# on the host
enclave --allow-domain ftp.math.utah.edu

# in the container
tlmgr option repository https://ftp.math.utah.edu/pub/tex/historic/systems/texlive/<release>/tlnet-final  # pinned release
tlmgr option repository https://ctan.math.utah.edu/ctan/tex-archive/systems/texlive/tlnet                 # current release
tlmgr install <pkg>
```

Runtime installs land in the container overlay and vanish with the
container; add anything you need permanently to the scheme via a rebuild.
