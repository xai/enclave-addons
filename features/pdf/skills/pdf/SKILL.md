---
name: pdf
description: Read, search, split, render, or OCR a PDF. Use whenever a task involves a .pdf file — extracting its text, finding something in it, pulling out pages or images, looking at how a page is laid out, or handling a scan that has no text layer.
user-invocable: true
---

# Working with PDFs

A PDF is a description of marks on a page, not a document format. Two files
that look identical on screen can be a text layer you can read directly or a
photograph of a page that contains no letters at all. Everything below follows
from that difference, so establish it first.

## Always start with pdf-probe

```
pdf-probe report.pdf
```

```
report.pdf
  pages       12
  size        2.4 MB
  text layer  yes -- all 12 pages
  next        pdftotext -layout in.pdf -
  page size   595.276 x 841.89 pts (A4)
  producer    pdfTeX-1.40.25
```

The `text layer` line decides the route, and the `next` line names the command
for it. Never conclude that a PDF is empty because `pdftotext` printed
nothing — that is what a scan looks like, and it is the single most common way
this goes wrong. `pdf-probe` accepts several files at once.

## Getting the text out

| Situation | Command |
| --- | --- |
| Text layer, prose | `pdftotext -layout in.pdf -` |
| Text layer, a page range | `pdftotext -layout -f 3 -l 7 in.pdf -` |
| Reading order matters more than layout | `pdftotext in.pdf -` (no `-layout`) |
| Columns are interleaving badly | `mutool draw -o /tmp/out.txt in.pdf` (a different engine) |
| You need coordinates for each word | `pdftotext -tsv in.pdf -` |
| You want markdown, not flat text | via `pdftohtml` and `pandoc` — see below |
| No text layer | OCR — see below |

`-layout` preserves the visual arrangement with spaces, which is what makes
tables and multi-column papers readable. Without it, `pdftotext` emits the
order the marks appear in the file, which is better for continuous prose and
worse for anything arranged in columns.

`-tsv` is the one to reach for when position matters — it gives a table of
every block, line, and word with its bounding box, which is enough to
reconstruct a layout the other modes flatten. `-bbox-layout` is the same
information as XHTML. `mutool` is a wholly different rendering engine, so when
poppler interleaves columns it is worth a second opinion; give it an output
filename and it infers the format from the extension.

Send output to stdout with `-` and read it, rather than writing a `.txt` file
into the user's repository.

## Markdown, not flat text

**`pandoc` cannot read PDF.** `pandoc in.pdf -o out.md` fails with an unknown
input format, and no flag changes that — PDF has no structure for pandoc to
read. Go through HTML instead, which is where poppler keeps what it recovered
of the headings and emphasis:

```
pdftohtml -s -i -noframes -stdout in.pdf | pandoc -f html -t gfm --wrap=none
```

`-s` makes one document rather than a file per page, `-i` drops images so no
stray files land beside the input, and `-stdout` keeps the whole thing in the
pipe. `--wrap=none` leaves lines unwrapped, which greps and diffs better.

Use this when the structure is the point — a document that will be edited,
committed, or quoted section by section. For reading a PDF to answer a
question, `pdftotext -layout` is fewer moving parts and loses less.

What survives is headings, emphasis, lists, and paragraph breaks. What does
not is anything the PDF only expressed visually: column layout, and tables,
which arrive as runs of text. Check the output against the rendered page
(`pdftoppm`) before trusting a table that came through this way.

Pandoc also handles the far end — markdown to `docx`, `html`, `odt`, `epub`,
`rst`, and back. **Producing a PDF is the exception:** `pandoc -o out.pdf`
needs a LaTeX engine, which this feature does not install. Select a TeX Live
feature alongside it for that:

```
enclave --features "+pdf,+texlive-debian" --rebuild
pandoc notes.md -o notes.pdf
```

## Scans and OCR

When `pdf-probe` reports no text layer, add one:

```
OMP_THREAD_LIMIT=1 ocrmypdf -l deu+eng scan.pdf scan-ocr.pdf
pdftotext -layout scan-ocr.pdf -
```

`ocrmypdf` keeps the original page images and adds an invisible text layer
beneath them, so the output stays visually identical and becomes searchable.
Installed languages are English and German; `-l deu+eng` covers both at once
and is a safe default when you don't know which applies. `OMP_THREAD_LIMIT=1`
is worth setting because ocrmypdf already runs pages in parallel, and
tesseract's own threading fights it.

Useful flags:

- `--skip-text` — the document is partly digital, partly scanned; OCR only the
  pages that need it. Without this, ocrmypdf refuses to touch a file that
  already has text anywhere.
- `--redo-ocr` — an existing OCR layer is poor and should be replaced.
- `--clean` — descreen and despeckle before recognition, for noisy scans.
- `--deskew` — pages photographed at an angle.
- `--rotate-pages` — pages sideways or upside down.

OCR is slow: budget roughly a second or two per page, more with `--clean`. For
a long document where only one section matters, cut the pages out first with
`qpdf` and OCR those.

Below about 200 dpi (`pdf-probe` reports the resolution for scans) recognition
degrades badly, and no flag fixes a source that lacks the detail.

## Looking at a page

Sometimes reading the page is the answer — a figure, a chart, a form, a table
whose structure no extractor recovers, a layout question. Render it and look:

```
pdftoppm -png -r 150 -f 3 -l 3 -singlefile in.pdf /tmp/page
```

That writes exactly `/tmp/page.png`, which you can then read as an image.
Use `-singlefile` whenever you want one page: without it `pdftoppm` appends a
page number padded to the width of the document's page count, so the same
command yields `page-3.png` for a 9-page file and `page-03.png` for a 90-page
one — guessing wrong there costs a round trip.

For a range, drop `-singlefile` and list the directory afterwards rather than
predicting the names. Use `-r 150` for legibility at a reasonable size; raise
it to `-r 300` only when fine print matters, since the file grows with the
square of the resolution. Always bound the range with `-f`/`-l` — rendering a
400-page document produces 400 images and helps nobody.

For the images embedded in a page, rather than a picture of the page:

```
pdfimages -png -f 3 -l 3 in.pdf /tmp/img
```

## Searching

`pdfgrep` searches PDFs directly, without extracting them first:

```
pdfgrep -n -i "clause 7" contract.pdf          # with page numbers
pdfgrep -r -n "invoice" docs/                  # a whole tree
pdfgrep -c "invoice" *.pdf                     # match counts per file
```

It reads the text layer, so it finds nothing in a scan that has not been
OCR'd. `pdf-probe` on a file that surprises you by matching nothing is the
first thing to check.

## Pages, structure, and repair

`qpdf` is the tool for everything structural. It rewrites the file without
re-rendering it, so nothing is lost to a conversion.

```
qpdf in.pdf --pages . 3-7 -- out.pdf           # extract pages 3 to 7
qpdf in.pdf --pages . 1-9 . 20-z -- out.pdf    # drop pages 10 to 19
qpdf --empty --pages a.pdf b.pdf -- out.pdf    # merge
qpdf --decrypt --password=PW in.pdf out.pdf    # remove a password
qpdf --decrypt in.pdf out.pdf                  # clear owner restrictions
qpdf --check in.pdf                            # diagnose a damaged file
qpdf --qdf --object-streams=disable in.pdf out.pdf   # human-readable internals
qpdf --json in.pdf                             # the object structure, as JSON
```

Page ranges are inclusive, `z` means the last page, and `r3` counts three from
the end. `.` refers to the file already named.

If a PDF is damaged and `qpdf --check` reports errors, either `qpdf in.pdf
repaired.pdf` (which rewrites the structure) or `mutool clean in.pdf
repaired.pdf` often recovers it.

To make a large PDF smaller, downsample its images with ghostscript:

```
gs -sDEVICE=pdfwrite -dPDFSETTINGS=/ebook -dNOPAUSE -dBATCH \
   -sOutputFile=small.pdf in.pdf
```

`/ebook` targets 150 dpi; `/screen` is smaller and coarser, `/printer` larger
and sharper. This re-encodes the images, so it is lossy — keep the original.

## Metadata and fonts

```
pdfinfo in.pdf                                 # pages, size, producer, dates
pdffonts in.pdf                                # embedded fonts; empty means a scan
mutool show in.pdf trailer                     # raw object inspection
```

`pdffonts` listing nothing is a second, independent confirmation that a file
carries no text.

## Rules

- Probe before extracting. The failure mode of skipping it is a confident
  report that a document is empty when it is merely scanned.
- Don't write intermediate files into the user's repository. Use `/tmp`, or
  stdout where the tool allows it.
- Bound page ranges on anything that renders or OCRs. Both are slow and both
  produce output per page.
- Quote the source. When you report what a PDF says, give the page number —
  `pdftotext -f N -l N` and `pdfgrep -n` both make that cheap.
- These tools are read-mostly, but `ocrmypdf`, `qpdf`, and `gs` all write new
  files. Never write over the input; nothing here has an undo.
