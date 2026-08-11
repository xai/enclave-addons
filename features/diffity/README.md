# Diffity

Installs [diffity](https://diffity.com), a GitHub-style diff viewer and code
review UI, together with the agent skills that drive it. The agent can leave
inline comments in the browser-backed review, and the user can reply or ask the
agent to resolve them.

## What it does

- Installs the pinned `diffity` CLI at image build time with
  `enclave-agent-npm-install`, which targets the private agent Node runtime at
  `/opt/enclave/node` and rewrites the bin shebang to it. The feature does not
  depend on `node-dev`.
- Publishes container port 5391 to an automatically assigned host-loopback
  port. Enclave prints the resolved URL at session start and shows it in
  `enclave ps` while the session runs.
- Puts each repository's review data on a host directory so comment threads and
  tours outlive the container, and clears the stale process registry the
  previous one left behind. Mount that directory yourself with `--add-dir`; see
  "Persisting reviews" below, and do not rely on the fallback location.
- Ships six upstream-derived skills: `/diffity-diff`, `/diffity-review`,
  `/diffity-resolve`, `/diffity-tree`, `/diffity-resolve-tree`, and
  `/diffity-tour`. Enclave composes them into every enabled tool that declares
  a managed skills directory: Claude Code, Codex, Mistral Vibe, OpenCode, and
  Pi in the current built-in set. Theia does not expose an agent skill system.

Normal local diff and review operation makes no outbound requests, so the
feature adds nothing to the gateway allowlist. GitHub PR workflows shell out to
`gh`; enable the built-in `github-cli` feature for those.

## Persisting reviews

Create the store once on the host, and mount it in the sessions where you want
diffity:

```bash
mkdir -p ~/.local/state/enclave-diffity
enclave --features "+diffity" --add-dir ~/.local/state/enclave-diffity
```

Enclave mounts an `--add-dir` directory at the path it has on the host, so the
entrypoint finds it under the host user's home rather than under `$HOME`. To
keep the store somewhere else, set `ENCLAVE_DIFFITY_STORE` to that path on the
host and forward it with `--pass-env ENCLAVE_DIFFITY_STORE`. Put the path in
`add_dirs` in the global or project config to stop passing the flag; the
feature still has to be enabled for the session either way.

Diffity keeps everything for one repository in `~/.diffity/<repo-hash>/`, where
`<repo-hash>` is the first 12 hex characters of sha256 over the repository root
path: `reviews.db`, the `-wal` and `-shm` files SQLite creates beside it, and
`current-session`. The entrypoint symlinks that directory into the store, both
for this session's repository and for every repository the store already holds.
`registry.json` stays container-local, deliberately: it lists running instances
by PID and port, and both belong to the container that produced them.

This mirrors a layout diffity owns, and diffity has moved it before. An earlier
version of this feature linked `~/.diffity/reviews.db`, a path 0.9.5 no longer
writes, and every review died with its container while the store sat empty.
After a version bump, compare the directory name the entrypoint prints against
`repoHash` in `diffity list --json`; if they differ, the layout moved again.

The store is per host directory, not per project. Because diffity keys data by
the repository root, one directory serves every project, every tool, and every
session — including two sessions on the same repository, which share one SQLite
database instead of getting one each. Keep the store on a local filesystem:
concurrent WAL access needs working POSIX locks and shared memory, so a store
on NFS or SMB corrupts or fails.

The session start-up prints where reviews for this repository live, or a
warning naming the reason they will not persist — an unmounted
`ENCLAVE_DIFFITY_STORE`, a store the container user cannot write, a workspace
that is not a git checkout, or the fallback below. Read that line; every one of
these outcomes is otherwise invisible until reviews go missing.

Without `--add-dir`, the database falls back to the tool config store, which is
where this feature used to keep it. That location is per project, per tool and
per store key, and with `host_config=passthrough` Enclave's config-source
overlay deletes everything in it that is not on its preserve list, at session
start, silently. This has destroyed a populated review database. Treat the
fallback as "reviews last as long as the container" unless you have checked
that your sessions run with `host_config=none`.

`eclipse-enclave/enclave#37` replaces all of this with a declared
`state: true` store, per project and tool-independent. Once it lands, this
feature should adopt it and the `--add-dir` route can go away.

## Notes

- **Open the URL Enclave printed**, not the one diffity printed. The host port
  is assigned by the daemon and differs from the container's 5391. Run
  `enclave ps` on the host to recover the current URL.
- **Append the route and ref to that URL.** Enclave can only publish the
  origin: the port exists before any diffity server does, so `openUrl` cannot
  carry the ref of a session the agent starts later. The UI reads the ref from
  the query string and falls back to the working tree when it is absent, so the
  bare URL shows "No changes found" on a clean tree even while the server is
  serving a different diff. Take the `ref` field from `diffity list --json` and
  open `<url>/diff?ref=<ref>` — `/diff?ref=main..HEAD` for that comparison,
  `/diff?ref=work` for a working-tree session, `/tree` for a tree session
  (`ref: "__tree__"`). The skills report the right path; this is the rule they
  follow.
- The host port is auto-assigned, so it changes between sessions and the ones
  Docker hands out are reused across them. Pin it with `-p 15391:5391` (or
  `"ports": ["15391:5391"]` in the config) when you want a stable bookmark:
  the feature's declared port dedups on the container port and steps aside for
  an explicit mapping. Only do this if you run one diffity session at a time —
  a fixed host port is what `hostAllocation: auto` exists to avoid, and the
  second concurrent session fails at container start.
- The same mapping takes an explicit host IP, which is the only way to reach
  the UI from another machine: `-p 0.0.0.0:0:5391` binds every interface and
  still lets the daemon pick the host port, `-p 0.0.0.0:15391:5391` fixes both.
  Per invocation only — never put it in the config and never change `openUrl`.
  The UI has no authentication and can read and modify the mounted repository,
  and Docker's published-port rules sit in front of most host firewalls, so
  this hands the repository to anything that can route to the host. Enclave
  still prints the URL as `localhost`; substitute the host's address.
- There is no browser in the container. Browser launches attempted by
  `diffity`, `diffity tree`, and `diffity open` fail silently while the server
  continues to run. `/diffity-diff` and `/diffity-tree` now pass `--no-open`,
  as do the other skills that start a server.
- Only one reachable diffity instance is supported per session. Enclave
  publishes container port 5391 only; if another instance increments to 5392,
  it is unreachable from the host. `/diffity-diff`, `/diffity-tree`, and
  `/diffity-review` inspect the registry first, reuse an exact repo/mode/ref
  match, and use `--new` only when replacing a mismatched session. They report
  a replacement so the user knows the browser and agent CLI changed context.
- The CLI is installed image-wide and remains usable in a tool without managed
  skills, whether or not a store is mounted.
- Do not run `diffity prune` in a persistent session. It removes `~/.diffity`
  wholesale, and the entries that matter there are symlinks: Node does not
  follow those, so the store keeps its data while the session loses its links
  to it. Persistence stays off for the rest of that container session, and the
  next session relinks.
- Persistence keeps the database, not the session. `current-session` records
  the ref and the head commit, so new commits on the branch start a fresh
  session for the new head. Earlier threads stay in the database; they are not
  listed as current.
- Under `--backend qemu`, leave the store unmounted and let `~/.diffity` stay
  ephemeral. The review database runs SQLite in WAL mode, and the escape hatch
  for WAL over a 9p-mounted store (`sandbox.qemuStoreCacheMmap`) is tool-only;
  a mixin cannot request it.
- Never run `npm install -g diffity` or `diffity update` inside a session.
  Both bypass the build-time pin; `diffity update` installs `@latest` using the
  session's Node/npm path and may then suggest replacing the skills. A missing
  binary means the feature needs to be reinstalled and the image rebuilt.
- `install.sh` sets `npm_config_prefix` itself.
  `enclave-agent-npm-install` only reads that variable to find installed bins;
  it does not pass it to npm. Without the explicit prefix, npm falls back to
  `/opt/enclave/node` and fails with EACCES in the non-root user phase.
- After a rebuild, `diffity doctor` rechecks Git, repository detection, Node,
  `better-sqlite3`, and the installed CLI version. Enclave's session-start URL
  or `enclave ps` confirms the published host port.
- Diffity listens on the container wildcard address, while Enclave publishes
  the port on host loopback by default. Do not override that binding to expose
  the UI beyond the host: the service can read and modify the mounted
  repository.
- The exact npm version is pinned, but its dependency lifecycle scripts run at
  image build because `better-sqlite3` is native. This install path has no
  repository lockfile or separately recorded tarball integrity pin.

## Configuration

The feature is opt-in (`defaultEnabled: false`). The repository install script
enables it in the global Enclave config, so every tool session receives the CLI
and every skill-capable tool receives the skills. To enable it only for selected
projects, remove `"+diffity"` from the global `features` array and add it to
`~/.config/enclave/projects/<hash>/config.json` instead.

## Updating the vendored skills

The published CLI version and skill source revision are independent pins in
`install.sh`. The current skills are compatible with 0.9.5, but they are newer
than the commit that produced that npm release. Do not infer synchronization
from `packages/cli/package.json`; upstream leaves that version unchanged between
releases.

From a diffity checkout at the intended `DIFFITY_SKILLS_REVISION`:

```bash
rm -rf features/diffity/skills/diffity-*
cp -R /path/to/diffity/skills/. features/diffity/skills/
rm -rf features/diffity/skills/diffity-learn
cp /path/to/diffity/LICENSE features/diffity/skills/LICENSE.upstream
```

Then reapply the Enclave adaptations carried by this feature:

- Omit `/diffity-learn`; upstream references four `prompts/*.md` files that do
  not exist in the upstream repository or npm package.
- Never self-install or self-update the CLI from a skill.
- Use tool-neutral shell/editing language rather than harness-specific tool
  names.
- Start every server with `--no-open`. In `/diffity-diff`, `/diffity-tree`, and
  `/diffity-review`, inspect `diffity list --json` before changing the active
  session, use `--new` only for an intentional replacement, and say when a
  replacement occurred. Never print the container port; direct the user to
  Enclave's host URL.

Set `DIFFITY_SKILLS_REVISION` to the checkout's full commit SHA. Choose and set
`DIFFITY_VERSION` separately from a published npm release, inspect
`npm view diffity@<version> gitHead`, compare the CLI's `diffity --skills-hash`
with the release source, and verify every command and flag used by the adapted
skills before updating either pin.

## Third-party content

The skills were copied from the diffity repository at commit
`9370438b0b50bb06881d95e3578a2df407d6e6bb` and then adapted as listed above.
The installed `diffity@0.9.5` npm artifact reports git commit
`031244552c7b5db04988adfb8de32713bf4fea96`.

Upstream's licensing declarations are unsettled. Its repository `LICENSE` and
`packages/cli/package.json` declare MIT, while its README and the published
`diffity@0.9.5` npm metadata declare PolyForm Shield 1.0.0.
`skills/LICENSE.upstream` preserves the repository's MIT notice for the copied
skill sources; it does not resolve the contradictory npm artifact terms.
