#!/bin/bash
# Verify that the python-data libraries import, and warm matplotlib's font
# cache.
#
# There is nothing to download here -- the feature is entirely apt packages --
# but "apt installed it" and "python3 can import it" are different claims.
# pygraphviz in particular is a C extension linked against libgvc, and a
# version skew between them surfaces as an ImportError at the top of a script
# rather than as a failed package install. Checking at build time turns that
# into a failed image build, which is the cheaper place to find out.
set -euo pipefail

# Keep this in step with feature-entrypoint.d/setup.sh: the font cache is only
# reused at run time if both agree on where it lives.
MPLCONFIGDIR="$HOME/.cache/matplotlib"
export MPLCONFIGDIR MPLBACKEND=Agg
mkdir -p "$MPLCONFIGDIR"

echo "Verifying imports"
python3 - <<'PY'
import importlib
import sys

# (import name, what it is here for)
modules = [
    ("bs4", "HTML parsing"),
    ("lxml.etree", "the fast HTML/XML parser behind bs4"),
    ("html5lib", "the lenient parser, for markup lxml rejects"),
    ("networkx", "graph analysis"),
    ("pygraphviz", "graphviz layouts through networkx"),
    ("pydot", "reading and writing .dot"),
    ("numpy", "arrays"),
    ("scipy.sparse", "what networkx needs for pagerank and large layouts"),
    ("matplotlib", "plots"),
    ("pybtex.database", "BibTeX, full grammar"),
    ("bibtexparser", "BibTeX, entries as dicts"),
]

missing = []
for name, why in modules:
    try:
        importlib.import_module(name)
    except Exception as exc:                      # ImportError, but also ABI errors
        missing.append(f"  {name} ({why}): {exc}")

if missing:
    print("These modules are installed as packages but do not import:", file=sys.stderr)
    print("\n".join(missing), file=sys.stderr)
    sys.exit(1)
PY

echo "Verifying the scipy-backed networkx calls"
# These are the ones that fail with a bare networkx, and they are the reason
# scipy is in the spec. A failure here means the feature does not do what it
# claims, so it is fatal.
python3 - <<'PY'
import networkx as nx

G = nx.karate_club_graph()
nx.pagerank(G)
nx.adjacency_matrix(G)
nx.community.louvain_communities(G, seed=0)
nx.betweenness_centrality(G)
PY

echo "Verifying that graphviz layouts work end to end"
# The binding, the library, and the layout binaries are three separate things
# that all have to line up, and pygraphviz is a C extension against libgvc, so
# a version skew between them shows up here rather than in the package install.
#
# Not fatal, though: without it networkx still has spring_layout and every
# analysis function, and the graphviz binaries can still lay out a .dot file
# written from Python. Losing one of two layout routes does not justify
# failing an image build that is otherwise fine.
if python3 - <<'PY'
import sys

import networkx as nx

G = nx.karate_club_graph()
pos = nx.nx_agraph.graphviz_layout(G, prog="sfdp")
if len(pos) != G.number_of_nodes():
    print("graphviz_layout returned coordinates for the wrong node count", file=sys.stderr)
    sys.exit(1)
PY
then
    echo "  graphviz layouts available through pygraphviz"
else
    echo "Warning: pygraphviz cannot drive graphviz; nx.nx_agraph.graphviz_layout" >&2
    echo "         is unavailable. spring_layout, the analysis functions, and the" >&2
    echo "         dot/neato/sfdp binaries are unaffected." >&2
fi

for prog in dot neato sfdp fdp twopi circo; do
    command -v "$prog" >/dev/null 2>&1 || {
        echo "graphviz layout engine '$prog' not found in PATH" >&2
        exit 1
    }
done

# Debian carries bibtexparser 1.4.3 under a "2.0.0b5+really1.4.3" version
# string. The two releases have incompatible APIs, so a script written against
# v2 fails on the first call. Assert the shape we documented rather than the
# version string, which lies.
python3 - <<'PY'
import sys

import bibtexparser

if not hasattr(bibtexparser, "loads"):
    print("bibtexparser has no loads(): this is not the 1.x API the skill documents",
          file=sys.stderr)
    sys.exit(1)
if hasattr(bibtexparser, "parse_string"):
    print("Warning: bibtexparser exposes the 2.x API as well; the /python-data "
          "skill documents 1.x and should be revisited", file=sys.stderr)
PY

# First use otherwise spends several seconds scanning fonts, and does it again
# in every session that plots.
echo "Warming the matplotlib font cache"
python3 -c "import matplotlib.font_manager" >/dev/null 2>&1 || \
    echo "Warning: could not warm the font cache; the first plot will be slow" >&2

# --- Verify ------------------------------------------------------------------

echo "python-data installed"
python3 - <<'PY'
import bibtexparser
import bs4
import matplotlib
import networkx
import numpy
import pybtex
import scipy

print(f"  networkx {networkx.__version__}, scipy {scipy.__version__}, "
      f"numpy {numpy.__version__}")
print(f"  matplotlib {matplotlib.__version__} (backend {matplotlib.get_backend()})")
print(f"  beautifulsoup4 {bs4.__version__}")
print(f"  pybtex {pybtex.__version__}, bibtexparser {bibtexparser.__version__}")
PY
echo "  graphviz $(dot -V 2>&1 | sed 's/^dot - //')"
