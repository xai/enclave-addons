# Python data libraries

Importable Python libraries for the throwaway analysis script an agent writes
mid-session: HTML parsing, BibTeX parsing, graph analysis and layout, and
plots. Plus a `/python-data` skill that says which call replaces which
hand-rolled loop, and which pinned version will bite.

## Why this is not covered by `python-dev`

Enclave's stock [`python-dev`](https://github.com/eclipse-enclave/enclave/tree/main/extensions/features/python-dev)
feature installs black, ruff, mypy, pytest, ipython, poetry, and pipenv with
`uv tool install`. That puts each one in its own isolated virtualenv, which is
right for a linter and useless for a library: **nothing python-dev installs is
importable.** And the base image's system Python is externally managed
(PEP 668), so `pip install networkx` fails outright.

The result is an agent that can lint a script it cannot write. Asked to build
a co-authorship network it hand-rolls a Fruchterman-Reingold layout, parses
`.bib` with a regex, and strips HTML with `sed 's/<[^>]*>//g'` — not out of
laziness but because there is no import path. This feature is that import
path: every package is an apt `python3-*`, landing in the system
site-packages where `python3 script.py` finds it with no ceremony.

The two features are complementary and the names are deliberate: `python-dev`
is tooling *about* Python code, `python-data` is libraries *for* it.

## What it installs

| Area | Packages | Replaces |
| --- | --- | --- |
| HTML | `python3-bs4`, `python3-lxml`, `python3-html5lib` | regex and `sed` over markup |
| Graphs | `python3-networkx`, `graphviz`, `python3-pygraphviz`, `python3-pydot` | hand-written layouts, counting shared neighbours instead of measuring centrality |
| Numerics | `python3-numpy`, `python3-scipy` | — |
| Plots | `python3-matplotlib` | hand-written SVG |
| BibTeX | `python3-pybtex`, `python3-bibtexparser` | regex over `.bib` |

The named packages come to about 260 MB installed on amd64: networkx 77 MB,
scipy 74 MB, matplotlib 51 MB, numpy 28 MB, graphviz 3 MB, and everything else
under 10 MB together. The dependency closure adds more on top — graphviz's
libraries and the BLAS that numpy and scipy link against are the notable
ones — so treat 260 MB as a floor rather than a total.

Dropping `python3-scipy` and `python3-matplotlib` from `spec.yaml` removes
125 MB of that, with the consequences below.

### scipy is listed on purpose

networkx only *recommends* numpy and scipy, and enclave installs feature
packages with `--no-install-recommends`, so a bare `python3-networkx` arrives
without either. Measured against networkx 3.2.1 with numpy but no scipy:

| Call | Without scipy |
| --- | --- |
| `nx.pagerank` | `ModuleNotFoundError` |
| `nx.adjacency_matrix` | `ModuleNotFoundError` |
| `nx.eigenvector_centrality_numpy` | `ModuleNotFoundError` |
| `nx.spring_layout`, 600 nodes | `ModuleNotFoundError` |
| `nx.spring_layout`, 34 nodes | works |
| `betweenness_centrality`, `louvain_communities`, `shortest_path` | work |

The failing row is most of the reason to install networkx in the first place,
and it fails partway through an analysis rather than at import, so leaving
scipy out trades 74 MB for a class of mid-session surprise.

## Pinned versions worth knowing

Debian decides these, and two of them break plausible code:

| Package | Version | Consequence |
| --- | --- | --- |
| `python3-bibtexparser` | **1.4.3**, behind a `2.0.0b5+really1.4.3` version string | The 2.x API (`parse_file`, `parse_string`) does not exist. Code written against it fails on the first call. Debian reverted the beta; the string is a packaging artefact, not the API |
| `python3-numpy` | 2.2.4 | `np.float_`, `np.NaN`, `np.alltrue`, `np.in1d`, `np.trapz` are gone |
| `python3-networkx` | 3.2.1 | `nx.community.louvain_communities` is present; `nx.info()` is not |
| `python3-matplotlib` | 3.10.1 | Agg backend, pinned by this feature |
| `python3-pybtex` | 0.24.0 | Needs `pkg_resources`; Debian's dependency supplies it |

The `/python-data` skill carries all of these, which is the point of shipping
a skill rather than only packages — an agent that writes `bibtexparser.parse_file`
has lost the session's next five minutes to a traceback.

## Headless matplotlib

`feature-entrypoint.d/setup.sh` exports `MPLBACKEND=Agg`, since there is no
display and the alternative is matplotlib probing for a GUI toolkit at import.
It also points `MPLCONFIGDIR` at `~/.cache/matplotlib`, where `install.sh`
warmed the font cache at build time — otherwise the first `savefig` of every
session spends several seconds rebuilding it and says so on stderr. Both are
set only when the caller has not set them.

## Failure behaviour

The spec sets `failOnInstallError: true`, and `install.sh` does the checking
that apt cannot: that every module actually imports, that the scipy-backed
networkx calls really run, that all six graphviz engines are on `PATH`, and
that `bibtexparser` presents the 1.x API this feature documents. Any of those
failing means the feature does not do what it claims, so any of them fails the
build.

`pygraphviz` is the exception, and warns instead. It is a C extension linked
against `libgvc`, so a version skew between them surfaces as an `ImportError`
at the top of a user's script rather than as a failed package install — worth
detecting at build time, but not worth failing a build over. Without it
`nx.nx_agraph.graphviz_layout` is gone while `spring_layout`, every analysis
function, and the `dot`/`neato`/`sfdp` binaries all still work. This mirrors
how the [java](../java/) feature treats jdtls.

## Network

Nothing here needs the network at run time. These libraries parse; they do not
fetch. Scraping a site still needs that host on the session allowlist
(`enclave run --allow-domain ...`), which no feature can grant.

## Enablement

Opt-in (`defaultEnabled: false`), and installing it does not activate it:

```bash
./install.sh python-data
enclave --features "+python-data" --rebuild
```

It composes with the document features — [pdf](../pdf/) to get text out of
papers, [texlive-debian](../texlive-debian/) to typeset the result:

```bash
enclave --features "+python-data,+pdf,+texlive-debian" --rebuild
```

See the [repository README](../../README.md) for the installer's rules.
