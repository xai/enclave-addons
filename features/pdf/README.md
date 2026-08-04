# PDF tools

Everything needed to read, search, cut apart, render, convert, and OCR a PDF
from the container, plus the two things that make an agent use them well: a `/pdf`
skill that says which tool answers which question, and `pdf-probe`, which
reports what a given file actually contains.

## Why a skill and a probe, not just packages

`pdftotext` on a scanned document exits 0 and prints nothing. An agent that
has the binary but not the context reports that the PDF is empty, and the user
is worse off than if the tool had been missing. So the feature installs a
`pdf-probe` that answers the only question that decides the route —

```
$ pdf-probe scan.pdf
scan.pdf
  pages       31
  size        18.7 MB
  text layer  none -- scanned or image-only
  next        ocrmypdf -l deu+eng in.pdf out.pdf, then pdftotext -layout
  page size   595.276 x 841.89 pts (A4)
  producer    Canon iR-ADV C5535
  scan dpi    300 (300 or more is comfortable for OCR)
```

— and a skill that carries the rest of the decision tree.

## What it installs

Three extraction stacks that overlap much less than their names suggest:

| Package | Provides | What only it does |
| --- | --- | --- |
| `poppler-utils` | `pdftotext`, `pdftoppm`, `pdfinfo`, `pdfimages`, `pdffonts`, `pdfseparate`, `pdfunite`, `pdfdetach` | `pdftotext -layout`, the best plain-text fidelity available; `pdftoppm`, which renders a page to PNG so it can simply be looked at |
| `qpdf` | `qpdf` | Structure without re-rendering: decrypt, repair, page ranges, merge, and a `--json` dump of the object tree |
| `mupdf-tools` | `mutool` | A second opinion on column-heavy layouts from a different engine, `mutool clean` for repair, raw object inspection |

Plus `pdfgrep` for searching a tree of PDFs in place, `ghostscript` for
downsampling and repair, `img2pdf` for the reverse direction, and
`fonts-liberation` to substitute for fonts a PDF names but does not embed —
without which `pdftoppm` renders those pages in a default face and the layout
drifts.

`pandoc` sits at the far end of the pipeline. It cannot read PDF and never
will — there is no structure in the format for it to read — but
`pdftohtml -s -i -noframes -stdout | pandoc -f html -t gfm` produces markdown
that keeps the headings, lists, and emphasis `pdftotext` flattens away, which
is the right output when a document is going to be edited or committed rather
than merely read. It also converts onward to `docx`, `odt`, `epub`, and the
rest.

For scans, `ocrmypdf` with `tesseract-ocr` and English and German language
data. `ocrmypdf` adds an invisible text layer beneath the original page
images, so the output looks identical and becomes searchable, and `unpaper`
backs its `--clean` mode for noisy sources.

The packages named in `spec.yaml` come to 204 MB installed on amd64, and
**pandoc is 189 MB of that** — a statically linked Haskell binary is simply
that large. Everything else is small: poppler-utils 0.7 MB, mupdf-tools
0.6 MB, qpdf 0.3 MB, the three tesseract packages 7.6 MB together.

Expect the real cost to be higher, because those figures exclude the
dependency closure, which is where the extraction and OCR bulk actually lives
(libpoppler, libmupdf, libtesseract and leptonica, ghostscript's libraries,
and the Python stack ocrmypdf runs on). Dropping `pandoc` is by far the
biggest single saving available.

Debian's `pandoc` *recommends* `texlive-latex-recommended` and two more TeX
packages, which on an ordinary `apt install` would pull about a gigabyte of
TeX Live in behind it. Enclave installs feature packages with
`--no-install-recommends`
([`build-scripts/install-feature-apt-packages.sh`](https://github.com/eclipse-enclave/enclave/blob/main/runtime-assets/build-scripts/install-feature-apt-packages.sh)),
so that does not happen here.

## Writing a PDF needs a TeX Live feature

The consequence of the above is that `pandoc -o out.pdf` fails: pandoc shells
out to a LaTeX engine for PDF output, and there is none in this feature.
Pairing it with one of the TeX features is deliberate rather than a
workaround — `texlive-debian` produces far better PDFs than any bundled
fallback engine would, and a feature that installs 200 MB of LaTeX to serve
one direction of one tool would be paying for it in every session that only
wanted to read a scan.

```bash
enclave --features "+pdf,+texlive-debian" --rebuild
pandoc notes.md -o notes.pdf
```

If you want PDF output without LaTeX, `weasyprint` is the light alternative
(`pandoc --pdf-engine=weasyprint`, CSS rather than TeX, roughly 40 MB); add it
to `spec.yaml` and rebuild.

## `/pdf` skill

The skill covers the routes in order — probe, then extract or OCR or render —
along with page-range surgery in `qpdf`, searching with `pdfgrep`, and the
rules that keep the work tidy (don't write scratch files into the repository,
bound page ranges on anything slow, cite the page number). It is installed
into every session tool that declares a managed skills directory, and it is
also invocable as `/pdf`.

Its description is written to trigger on any task that touches a `.pdf`, since
the failure it exists to prevent happens on the first command, before an agent
would think to consult anything.

## Deliberate omissions

- **No `pdftk`.** `qpdf` does the same work, and Debian's `pdftk-java` would
  pull in a JRE.
- **No Python PDF stack** (`pdfplumber`, `pymupdf`). Table extraction is the
  one job nothing here does really well, but the libraries that do it are a
  research problem in themselves. `pdftotext -layout` handles ruled tables,
  `pdftotext -tsv` gives per-word coordinates to reconstruct from, and
  rendering the page and looking at it beats a wrong parse.
- **Only English and German** OCR data. Each additional language is about
  15 MB; add `tesseract-ocr-fra` and friends to `spec.yaml` and rebuild.

## Configuration

Add or remove packages in `spec.yaml`, then re-run the repository `install.sh`
and `enclave --rebuild`. `install.sh` verifies at build time that every binary
the feature promises is on `PATH` and that both language packs are present, so
a spec that no longer matches the image fails the build rather than the
session.

## Network

Nothing here needs the network at run time: OCR is entirely local, and the
language data is baked into the image. A PDF fetched from the web is a
separate matter — that is the session's allowlist, not this feature's.

## Enablement

Opt-in (`defaultEnabled: false`), and installing it does not activate it:

```bash
./install.sh pdf                        # copy it onto the machine
enclave --features "+pdf" --rebuild     # and use it where PDFs turn up
```

It is a defensible candidate for the global config if you handle documents
regularly, and an easy one to trim if not: dropping `pandoc` from `spec.yaml`
removes 189 MB on its own.

```bash
./install.sh --enable pdf
enclave --rebuild
```

See the [repository README](../../README.md) for the installer's rules.
