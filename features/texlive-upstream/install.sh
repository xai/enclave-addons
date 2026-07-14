#!/bin/bash
# Install TeX Live from the official upstream installer (install-tl), per
# https://www.tug.org/texlive/quickinstall.html
#
# Unlike the Debian packages (see texlive-debian), this installs a complete
# current or pinned TeX Live release under ~/.local/texlive/<release> and
# symlinks its binaries into ~/.local/bin, which precedes /usr/bin in the
# container PATH.
set -euo pipefail

# TeX Live release to install: "latest" for the current release from CTAN,
# or a year like "2025" for that frozen release from the historic archive
# (available for 2017 and newer). Changing this requires re-running the
# repository install.sh and `enclave --rebuild`.
TEXLIVE_RELEASE="latest"

# Install scheme. scheme-full (default) contains every CTAN package;
# documentation and source files are excluded below, which roughly halves it
# (~4.5 GB in the image). Smaller schemes (scheme-medium, scheme-basic)
# shrink the image but will be missing packages, and installing at runtime
# with tlmgr needs a network allowlist exception (see README).
TEXLIVE_SCHEME="scheme-full"

TLNET="https://mirror.ctan.org/systems/texlive/tlnet"
# Mirror of ftp.tug.org/historic, which is rate-limited
HISTORIC="https://ftp.math.utah.edu/pub/tex/historic/systems/texlive"

case "$TEXLIVE_RELEASE" in
    latest|20[0-9][0-9]) ;;
    *)
        echo "Invalid TEXLIVE_RELEASE '$TEXLIVE_RELEASE' (expected 'latest' or a year like 2026)" >&2
        exit 1
        ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Download and unpack install-tl from the given repository; the installer
# version must match the repository it installs from.
fetch_installer() {
    local repo="$1"
    rm -rf "$WORK/installer"
    mkdir -p "$WORK/installer"
    curl -fsSL --retry 3 "$repo/install-tl-unx.tar.gz" -o "$WORK/install-tl-unx.tar.gz" || return 1
    tar -xzf "$WORK/install-tl-unx.tar.gz" -C "$WORK/installer" --strip-components=1
}

# Echo the release year the unpacked installer belongs to.
installer_release() {
    perl "$WORK/installer/install-tl" --version 2>/dev/null \
        | sed -n 's/^TeX Live.*version \(20[0-9][0-9]\)$/\1/p' | head -n 1
}

fetch_installer "$TLNET"
CURRENT="$(installer_release)"
if [ -z "$CURRENT" ]; then
    echo "Could not determine the current TeX Live release from install-tl --version" >&2
    exit 1
fi

if [ "$TEXLIVE_RELEASE" = "latest" ] || [ "$TEXLIVE_RELEASE" = "$CURRENT" ]; then
    RELEASE="$CURRENT"
    REPO="$TLNET"
else
    RELEASE="$TEXLIVE_RELEASE"
    REPO="$HISTORIC/$RELEASE/tlnet-final"
    if ! fetch_installer "$REPO"; then
        echo "No frozen repository for TeX Live $RELEASE at $REPO" >&2
        echo "(current release is $CURRENT; the historic archive covers 2017 and newer)" >&2
        exit 1
    fi
fi

TEXDIR="$HOME/.local/texlive/$RELEASE"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

# instopt_adjustpath symlinks all binaries into tlpdbopt_sys_bin; docs and
# sources are skipped to keep the image small.
cat > "$WORK/texlive.profile" <<EOF
selected_scheme $TEXLIVE_SCHEME
TEXDIR $TEXDIR
TEXMFLOCAL $HOME/.local/texlive/texmf-local
TEXMFSYSCONFIG $TEXDIR/texmf-config
TEXMFSYSVAR $TEXDIR/texmf-var
TEXMFCONFIG $HOME/.texlive$RELEASE/texmf-config
TEXMFVAR $HOME/.texlive$RELEASE/texmf-var
TEXMFHOME $HOME/texmf
instopt_adjustpath 1
instopt_letter 0
tlpdbopt_sys_bin $BIN_DIR
tlpdbopt_autobackup 0
tlpdbopt_install_docfiles 0
tlpdbopt_install_srcfiles 0
EOF

echo "Installing TeX Live $RELEASE ($TEXLIVE_SCHEME) from $REPO"
export TEXLIVE_INSTALL_NO_WELCOME=1
perl "$WORK/installer/install-tl" --profile "$WORK/texlive.profile" --repository "$REPO"

export PATH="$BIN_DIR:$PATH"
if ! command -v pdflatex >/dev/null 2>&1; then
    echo "pdflatex not found in PATH after installation" >&2
    exit 1
fi
for tool in lualatex xelatex latexmk biber tlmgr; do
    command -v "$tool" >/dev/null 2>&1 \
        || echo "Warning: $tool not found ($TEXLIVE_SCHEME)" >&2
done
for file in beamer.cls tikz.sty biblatex.sty; do
    kpsewhich "$file" >/dev/null 2>&1 \
        || echo "Warning: $file not found ($TEXLIVE_SCHEME)" >&2
done

echo "TeX Live $RELEASE installed to $TEXDIR: $(pdflatex --version | head -n 1)"
