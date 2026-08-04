---
name: python-data
description: Parse HTML, parse BibTeX, analyse or lay out a graph, or draw a plot from Python. Use before writing any script that reads .bib files, scrapes HTML, builds a network of nodes and edges, computes centrality or communities, or produces a chart — these libraries are installed, so none of it should be hand-rolled.
user-invocable: true
---

# Python data libraries

These are installed as system packages and import from plain `python3`. There
is no venv to activate and no `pip install` to run — Debian's Python is
externally managed, so `pip install` fails and would not help if it worked.

The point of this skill is that the work is already done. Do not hand-write a
force-directed layout, a centrality measure, a BibTeX grammar, or an HTML
tag-stripping regex. Each of those is a library call here, and the hand-rolled
version is right until the first input that does not look like the one it was
written against.

Versions are pinned by Debian and some of them matter. The traps are called
out below; they are the difference between a script that runs and one that
fails on its first line.

## BibTeX

**Debian ships bibtexparser 1.4.3 behind a version string that reads
`2.0.0b5+really1.4.3`.** The 2.x API does not exist: `bibtexparser.parse_file`
and `parse_string` are absent, and a script written against v2 fails
immediately. Use the 1.x API.

Never parse `.bib` with a regex. Nested braces and an `@` inside a field are
both legal and both defeat the obvious pattern; the two libraries here handle
them, as verified against exactly that input.

### bibtexparser — entries as dicts, and unicode names

```python
import bibtexparser
from bibtexparser.bparser import BibTexParser
from bibtexparser.customization import author, convert_to_unicode

parser = BibTexParser(common_strings=True)
parser.customization = lambda record: author(convert_to_unicode(record))

with open("references.bib") as fh:
    db = bibtexparser.load(fh, parser)

for entry in db.entries:            # list of plain dicts
    print(entry["ID"], entry.get("year"), entry["title"])
    for name in entry["author"]:    # 'author' customization splits the string
        print("   ", name)          # 'Müller, Anna' -- already unicode
```

`bibtexparser.loads(text, parser)` for a string. Without `customization`,
`entry["author"]` stays one raw `"A and B and C"` string and keeps its LaTeX
escapes. `convert_to_unicode` is what turns `M{\"u}ller` into `Müller`, which
is what makes author names comparable — the same person spelled two ways is
two nodes in a co-authorship graph, and that is a wrong answer, not an
untidy one.

Write it back with `bibtexparser.dumps(db)`.

### pybtex — the stricter grammar

```python
from pybtex.database import parse_file

bib = parse_file("references.bib")

for key, entry in bib.entries.items():          # dict keyed by citation key
    title = entry.fields["title"]               # fields are case-insensitive
    for person in entry.persons["author"]:
        last = " ".join(person.last_names)      # structured, not a string
        first = " ".join(person.first_names)
```

pybtex gives structured `Person` objects rather than strings, which is better
when you need surnames specifically. It does **not** decode LaTeX escapes —
`person.last_names` yields `M{\"u}ller` verbatim. Decode with the latexcodec
that comes with it:

```python
import codecs, latexcodec           # noqa: F401 -- the import registers the codec
codecs.decode(r'M{\"u}ller', "ulatex")     # -> 'M{ü}ller'
```

**Which to use:** bibtexparser when you want dicts and unicode-normalised
names with the least ceremony, which covers most analysis. pybtex when the
file is untrusted or unusual, or when you need surname and given name apart.

## Graphs

networkx 3.2.1, with scipy, numpy, and the graphviz engines.

```python
import networkx as nx

G = nx.Graph()
G.add_edge("Smith", "Müller", weight=3)

nx.betweenness_centrality(G)                    # who connects the clusters
nx.community.louvain_communities(G, seed=0)     # the clusters themselves
nx.shortest_path(G, "Smith", "Müller")
nx.pagerank(G)
nx.degree_centrality(G), nx.eigenvector_centrality_numpy(G)
```

`betweenness_centrality` is the direct answer to "who actually connects these
clusters" — it counts how many shortest paths run through each node, which is
what a bridge between communities looks like. Counting shared co-authors is a
proxy for it, and a poor one.

Pass `seed=` to anything stochastic (`louvain_communities`, `spring_layout`)
so a rerun reproduces the last answer.

### Layout

Do not write a Fruchterman-Reingold loop. There are two implementations here:

```python
pos = nx.spring_layout(G, seed=0)                       # networkx's own F-R
pos = nx.nx_agraph.graphviz_layout(G, prog="sfdp")      # graphviz, via pygraphviz
```

For anything past a few hundred nodes, graphviz is both faster and better;
`sfdp` is the large-graph force layout, `neato` the small-graph one, `dot` for
anything hierarchical, `circo` and `twopi` for radial arrangements. Prefer
`nx_agraph` (pygraphviz) over `nx_pydot` — `pydot` is here for reading and
writing `.dot` files, and its networkx bridge is on the way out.

Or skip Python for the drawing and hand graphviz a `.dot` file directly:

```
sfdp -Goverlap=prism -Tsvg network.dot -o network.svg
```

### scipy is not optional

networkx only *recommends* scipy, but `nx.pagerank`,
`nx.adjacency_matrix`, `nx.eigenvector_centrality_numpy`, and `spring_layout`
above roughly 500 nodes all raise `ModuleNotFoundError` without it. This
feature installs it for that reason. Pure-Python `betweenness_centrality`,
`louvain_communities`, and `shortest_path` work either way.

## HTML

```python
from bs4 import BeautifulSoup

soup = BeautifulSoup(html, "lxml")              # name the parser explicitly
for row in soup.select("table.results tr"):     # CSS selectors
    cells = [td.get_text(strip=True) for td in row.find_all("td")]
```

Name the parser: without one, bs4 picks whatever it finds and warns, so the
same script behaves differently in different images. `lxml` is fast and
strict; switch to `"html5lib"` for markup it chokes on, which is slower but
parses the way a browser would.

`get_text(strip=True)` replaces `sed 's/<[^>]*>//g'`, and unlike it, handles
entities, scripts, comments, and attributes containing `>`.

## Plots

matplotlib 3.10 with the **Agg backend pinned by this feature** — there is no
display in the container. Never call `plt.show()`; it does nothing useful
here. Save to a file and read it back if you need to look at it.

```python
import matplotlib
import matplotlib.pyplot as plt

fig, ax = plt.subplots(figsize=(8, 5))
ax.plot(xs, ys)
ax.set_xlabel("year")
fig.savefig("/tmp/plot.png", dpi=150, bbox_inches="tight")
plt.close(fig)
```

Write to `/tmp`, not into the user's repository, unless the file is the
deliverable. `fig.savefig("out.svg")` for vector output. Close figures in a
loop or memory grows.

**numpy here is 2.x.** `np.float_`, `np.NaN`, `np.alltrue`, `np.in1d`, and
`np.trapz` were all removed — use `np.float64`, `np.nan`, `np.all`,
`np.isin`, `np.trapezoid`. This is the most likely reason a plausible-looking
numpy snippet fails.

## Rules

- Reach for the library before writing the algorithm. If you find yourself
  implementing physics, a grammar, or a tag stripper, stop and look here.
- Name the bs4 parser, seed the stochastic graph functions, and pin figure
  sizes — a rerun that gives a different answer is not reproducible work.
- Scratch output goes to `/tmp`.
- These libraries parse; they do not fetch. Network access is the session's
  allowlist, and a host that is not on it fails no matter what is installed.
