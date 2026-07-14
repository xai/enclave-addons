# TeX Live (Debian)

Installs TeX Live from the Debian repositories, sized for scientific writing
in the math/CS domain: beamer, TikZ, biblatex/biber, latexmk, and the
IEEE/ACM publisher classes.

The TeX Live version is whatever the Debian release ships (Debian 13
"trixie": TeX Live 2024). If you need the current release or a pinned year,
use [texlive-upstream](../texlive-upstream/) instead — or alongside.

## What it does

Installs apt packages at image build time (roughly 4 GB in the image):

- `texlive-latex-recommended` — LaTeX core plus beamer, booktabs, caption, ...
- `texlive-latex-extra` — cleveref, enumitem, todonotes, minted, ...
- `texlive-science` — algorithm2e, algorithmicx, siunitx, ...
- `texlive-pictures` — pgf/TikZ, pgfplots
- `texlive-publishers` — IEEEtran, acmart, and other publisher classes
- `texlive-bibtex-extra` + `biber` — biblatex with its backend
- `texlive-luatex`, `texlive-xetex` — lualatex/xelatex engines
- `texlive-fonts-recommended`, `texlive-fonts-extra`, `lmodern`, `cm-super` —
  fonts, including the libertine/inconsolata families acmart requires
  (`texlive-fonts-extra` is the largest chunk; drop it from `spec.yaml` if
  you don't build ACM papers)
- `latexmk`, `ghostscript`, `python3-pygments` (for minted), and
  `poppler-utils` (pdftoppm, so agents can render pages of the built PDF to
  images and inspect their own output)

## Notes

- Debian's TeX Live does not support `tlmgr`; additional packages come from
  apt (add them to `spec.yaml` and rebuild). A missing one-off `.sty` can
  also be vendored into the project directory — TeX searches the current
  directory first.
- Language support beyond English (e.g. `texlive-lang-german`) is not
  included; add the `texlive-lang-*` package you need to `spec.yaml`.
- Coexists with [texlive-upstream](../texlive-upstream/); when both are
  installed the upstream binaries win on `PATH`. See
  [coexistence](../texlive-upstream/README.md#coexistence-with-texlive-debian).

## Configuration

The feature is opt-in (`defaultEnabled: false`). The repository install
script enables it in your global enclave config; see the
[repository README](../../README.md). To enable it only for selected
projects, remove `"+texlive-debian"` from the global `features` array and add
it to `~/.config/enclave/projects/<hash>/config.json` instead.
