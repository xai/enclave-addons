#!/bin/bash
# Install pdf-probe, the one piece of the pdf feature that is not an apt
# package.
#
# Everything else the feature provides comes from Debian, so there is nothing
# to download here. What apt cannot supply is the judgement call an agent has
# to make before it runs anything: a PDF with a text layer and a scan of the
# same document look identical to `ls`, and only one of them answers to
# pdftotext.
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"

cat > "$BIN_DIR/pdf-probe" <<'PROBE'
#!/bin/sh
# pdf-probe -- say what a PDF actually contains, so the next command is an
# informed choice rather than a guess. Installed by the enclave pdf feature.
#
# The question that matters is rarely how many pages a file has; it is whether
# there is a text layer at all. pdftotext on a scan exits 0 and prints nothing,
# which reads like an empty document unless something says otherwise.
set -u

# Non-whitespace characters on a page, at or above which it counts as a text
# page. A scanned page carries none; a page bearing only a stamped folio
# carries two or three.
TEXT_MIN=20

usage() {
    cat <<'EOF'
Usage: pdf-probe <file.pdf>...

Reports pages, size, text-layer coverage, encryption, and page geometry for
each PDF, and names the extraction command that suits it.
EOF
}

case "${1-}" in
    -h|--help) usage; exit 0 ;;
    '') usage >&2; exit 2 ;;
esac

# $info is set by probe() and read here; this script is short enough that a
# shared variable beats threading it through every call.
field() {
    printf '%s\n' "$info" | sed -n "s/^$1: *//p" | head -n 1
}

row() {
    printf '  %-11s %s\n' "$1" "$2"
}

probe() {
    file=$1
    printf '%s\n' "$file"

    if [ ! -f "$file" ]; then
        row error "no such file"
        return 1
    fi

    if ! info=$(pdfinfo "$file" 2>&1); then
        case $info in
            *ncrypted*|*assword*)
                row encrypted "yes, and opening it needs the password"
                row next 'qpdf --decrypt --password=PW in.pdf out.pdf'
                ;;
            *)
                row error "$(printf '%s' "$info" | head -n 1)"
                ;;
        esac
        return 1
    fi

    pages=$(field Pages)
    [ -n "$pages" ] || pages=0
    row pages "$pages"

    bytes=$(field 'File size' | awk '{print $1}')
    case $bytes in
        *[!0-9]*|'') ;;
        *) row size "$(awk -v b="$bytes" 'BEGIN {
               if (b >= 1048576) printf "%.1f MB", b / 1048576
               else printf "%.0f kB", b / 1024
           }')" ;;
    esac

    # One pdftotext run for the whole document: it separates pages with a form
    # feed, so awk can count populated pages without a process per page.
    text=$(pdftotext -q "$file" - 2>/dev/null | awk -v min="$TEXT_MIN" '
        BEGIN { RS = "\f"; n = 0 }
        { s = $0; gsub(/[[:space:]]/, "", s); if (length(s) >= min) n++ }
        END { print n + 0 }')
    case $text in
        *[!0-9]*|'') text=0 ;;
    esac

    # An owner password restricts printing or copying without preventing the
    # file from opening. This has to be read before the text layer is judged:
    # pdftotext refuses to extract from a file whose copy permission is denied,
    # so a perfectly good text layer comes back as zero pages and looks exactly
    # like a scan. Recommending OCR there would be wrong twice over -- it
    # discards real text, and ocrmypdf balks at the same restriction.
    enc=$(field Encrypted)
    case $enc in
        ''|no) restricted=0 ;;
        *) restricted=1 ;;
    esac

    if [ "$text" -eq 0 ] && [ "$restricted" -eq 1 ]; then
        row "text layer" "unknown -- extraction is blocked by the restrictions"
        row next "qpdf --decrypt in.pdf out.pdf, then pdf-probe out.pdf"
    elif [ "$text" -eq 0 ]; then
        row "text layer" "none -- scanned or image-only"
        row next "ocrmypdf -l deu+eng in.pdf out.pdf, then pdftotext -layout"
    elif [ "$text" -lt "$pages" ]; then
        row "text layer" "partial -- $text of $pages pages"
        row next "ocrmypdf --skip-text -l deu+eng in.pdf out.pdf"
    else
        row "text layer" "yes -- all $pages pages"
        row next "pdftotext -layout in.pdf -"
    fi

    [ "$restricted" -eq 1 ] && row encrypted "$enc"

    psize=$(field 'Page size')
    [ -n "$psize" ] && row "page size" "$psize"

    producer=$(field Producer)
    [ -n "$producer" ] && row producer "$producer"

    # Resolution decides how well OCR does, so report it where OCR is the next
    # step. The column layout of `pdfimages -list` is not a stable interface;
    # a change to it makes this print nothing rather than something wrong.
    if [ "$text" -eq 0 ] && [ "$restricted" -eq 0 ]; then
        dpi=$(pdfimages -list -f 1 -l 1 "$file" 2>/dev/null \
            | awk 'NR > 2 && $13 + 0 > best { best = $13 + 0 } END { if (best) print best }')
        case ${dpi:-} in
            ''|*[!0-9]*) ;;
            *) row "scan dpi" "$dpi (300 or more is comfortable for OCR)" ;;
        esac
    fi

    return 0
}

status=0
first=1
for file in "$@"; do
    [ "$first" -eq 1 ] || printf '\n'
    first=0
    probe "$file" || status=1
done

exit "$status"
PROBE

chmod +x "$BIN_DIR/pdf-probe"

# --- Verify ------------------------------------------------------------------

# The apt packages are the feature; a missing binary here means the spec and
# the image disagree, which is worth failing the build over.
for tool in pdftotext pdfinfo pdftoppm pdfimages pdffonts pdftohtml qpdf mutool \
            pdfgrep ocrmypdf tesseract gs pandoc; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "$tool not found in PATH after installation" >&2
        exit 1
    }
done

for lang in eng deu; do
    tesseract --list-langs 2>/dev/null | grep -qx "$lang" || {
        echo "tesseract has no '$lang' language data" >&2
        exit 1
    }
done

echo "pdf feature installed"
echo "  $(pdftotext -v 2>&1 | head -n 1)"
echo "  $(qpdf --version 2>&1 | head -n 1)"
echo "  $(mutool -v 2>&1 | head -n 1)"
echo "  $(pandoc --version 2>&1 | head -n 1)"
echo "  ocrmypdf $(ocrmypdf --version 2>/dev/null), tesseract langs: $(tesseract --list-langs 2>/dev/null | tail -n +2 | tr '\n' ' ')"
echo "  pdf-probe -> $BIN_DIR/pdf-probe"
