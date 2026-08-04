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
- Points `~/.diffity` at the current tool config store, so comment threads and
  tours survive compatible container restarts, and clears the stale process
  registry left by the previous container.
- Ships six upstream-derived skills: `/diffity-diff`, `/diffity-review`,
  `/diffity-resolve`, `/diffity-tree`, `/diffity-resolve-tree`, and
  `/diffity-tour`. Enclave composes them into every enabled tool that declares
  a managed skills directory: Claude Code, Codex, Mistral Vibe, OpenCode, and
  Pi in the current built-in set. Theia does not expose an agent skill system.

Normal local diff and review operation makes no outbound requests, so the
feature adds nothing to the gateway allowlist. GitHub PR workflows shell out to
`gh`; enable the built-in `github-cli` feature for those.

## Notes

- **Open the URL Enclave printed**, not the one diffity printed. The host port
  is assigned by the daemon and differs from the container's 5391. Run
  `enclave ps` on the host to recover the current URL.
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
- The database is scoped by Enclave's config store: per project, per tool, and
  per store key. Reviews therefore do not follow a tool switch, and concurrent
  sessions using suffixed stores do not share reviews. The CLI itself is
  installed image-wide and remains usable even in a tool without managed
  skills.
- Do not run `diffity prune` in a persistent session. It removes the
  `~/.diffity` symlink rather than the backing store, leaving existing data
  intact but disabling persistence for the rest of that container session.
- Under `--backend qemu`, drop the symlink in
  `feature-entrypoint.d/setup.sh` and let `~/.diffity` stay ephemeral. The
  review database runs SQLite in WAL mode, and the escape hatch for WAL over a
  9p-mounted store (`sandbox.qemuStoreCacheMmap`) is tool-only; a mixin cannot
  request it.
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
