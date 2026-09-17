# amp (tool)

Runs Sourcegraph's [Amp](https://ampcode.com/docs/cli) CLI as an enclave
session tool: `enclave --tool amp` starts the agent on the project directory,
inside the usual container, read-write project mount and DNS allowlist.

```bash
enclave --tool amp                      # build the image the first time with --rebuild
enclave --tool amp -- -m high           # agent mode: low, medium, high, ultra
enclave --tool amp continue             # `amp last`, the most recent thread in this checkout
enclave --tool amp resume               # `amp threads continue`, the thread picker
```

Amp is proprietary — a prebuilt binary under
"© Sourcegraph Inc. All rights reserved", with no public source repository and
no issue tracker; the changelog is a web page at
[ampcode.com/chronicle](https://ampcode.com/chronicle). The documentation is
good, but everything below about on-disk paths, flags and the wire format was
checked against the Linux build `0.0.1789660852-g000545` rather than taken from
it.

## Install

```bash
./install.sh tools/amp
enclave --tool amp --rebuild
```

`install.sh` fetches the binary from `static.ampcode.com`, verifies it against
the SHA-256 published beside it, and installs it as `~/.local/bin/amp`, rather
than running upstream's `curl https://ampcode.com/install.sh | bash`. That
installer unpacks into `~/.amp/bin`, symlinks the binary onto `PATH`, appends
`PATH` lines to shell profiles the image already provides, and leaves the
self-update path in place.

Pin a build by setting `AMP_VERSION` in both `install.sh` and
`check-update.sh`. Left at `latest`, `check-update.sh` reports
`cli-version.txt` and enclave rebuilds when it changes — which is often: Amp
versions carry a build timestamp and move several times a day, so expect this
tool to report a stale image more eagerly than the others.

## Authentication

Two ways in:

- **`amp login`.** The CLI uses a device-code flow: it prints a
  `https://auth.ampcode.com/device?user_code=…` URL and a code, you confirm
  both in your host browser. No callback port has to be published, so unlike
  the OAuth tools this one needs no `oauthPorts` mapping. The token lands in
  `~/.local/share/amp/secrets.json`, which is the config store, so it survives
  the session. `amp logout` removes it.
- **`AMP_API_KEY`.** An access token from
  [Settings → Security](https://ampcode.com/settings/security), prefixed
  `sgamp_`. It authenticates on its own with no local login state. The session
  token `amp login` stores is *not* usable here: it expires within the hour and
  cannot be refreshed from an environment variable.

Amp authenticates with `Authorization: Bearer <token>`, which `spec.yaml`
declares, so enclave can hold the key on the host and have the gateway attach
it to requests for `ampcode.com` instead of putting it in the container
environment.

## What leaves the container

The sandbox contains the agent's *execution* — the loop, the tool calls, the
edits and the shell commands all run in the container, as `amp --executor
local` is the default. It does not contain the conversation. Amp is an
account-based service: prompts, file contents and command output go to Amp's
backend as a matter of normal operation, threads are stored server-side, and
their default visibility is workspace-wide, with admin access for workspace
management. There is no local-only mode to switch on. Set a per-repository
default with `amp threads visibility`, or start a session with
`-- --visibility private`.

Three things that would reach past the container are pinned off instead:

| Pinned | Why |
| --- | --- |
| `AMP_REMOTE_CONTROL_TERMINAL=0` (`spec.yaml`) | Grants ampcode.com terminal access to a thread opened on another client. A session's shell is the thing the sandbox exists to contain, and the CLI does not document which way this defaults |
| `amp.remoteThreadCreation.enabled: false` (template) | Lets ampcode.com open new threads in a TUI running here. Already the upstream default; pinned so it stays one |
| `static.ampcode.com` denied (`spec.yaml`) | `amp update` would replace the binary the image was built with |

Two more move work outside the sandbox on request, and are left available
because they are explicit: `amp -ox` (and `--executor orb`) runs the thread on
Amp's servers instead of in the container, and `amp --no-tui --runner-id <id>`
turns the session into an executor for threads created elsewhere.

The template also turns off the `Amp-Thread:` and `Co-authored-by:` commit
trailers, so an agent's thread URL does not end up in the repository's history.
Delete those two keys from `templates/settings.json` to get them back.

## Network

Allowlisted: `ampcode.com` (the API, the web app, and `auth.ampcode.com` for
device login) and `ampworkers.com` (the WebSocket workers carrying live thread
updates), plus GitHub and the usual package registries so the agent can work in
the project. Denied: `static.ampcode.com`, which `ampcode.com` would otherwise
cover, since dnsmasq matches subdomains and deny out-ranks allow.

No model provider hosts are allowlisted. Amp proxies inference through its own
backend, so the whole egress surface of a session is those two domains — the
smallest of any agent tool here.

## Configuration layout

Amp spreads its state over three XDG directories, and only one of them can be
the enclave config store:

| Path | Holds upstream | Here |
| --- | --- | --- |
| `~/.local/share/amp/` | `secrets.json` (login token), `device-id.json`, local thread state | the config store — `configDir` |
| `~/.config/amp/` | `settings.json`, `skills/` | both redirected into the store |
| `~/.cache/amp/` | `logs/cli.log` | left alone, not persisted |

The store is the directory holding the credential, so a login survives a
restart. The settings file follows it: `entrypoint.d/setup.sh` exports
`AMP_SETTINGS_FILE`, amp's own documented override, pointing at
`~/.local/share/amp/settings.json`.

Managed skills are composed into `~/.local/share/amp/skills`, since enclave
requires `skillsDir` below `configDir`, and the same script links
`~/.config/amp/skills` — the path amp actually searches — at it. Amp follows
that symlink (checked), and `amp.skills.path` stays free for directories you
want to add yourself. A feature that ships skills, for example
[diffity](../../features/diffity/), therefore reaches this tool too.

Amp also reads `~/.claude/skills`, `~/.config/agents/skills`, `~/.agents/skills`
and the project's `.agents/skills` and `.claude/skills`;
`amp.skills.disableClaudeCodeSkills` and `amp.skills.disableGlobalAgentsSkills`
turn those off.

## Files

| File | Purpose |
| --- | --- |
| `spec.yaml` | Extension manifest (sandbox behaviour, denied domains, credentials) |
| `install.sh` | Installs `amp` from `static.ampcode.com`, checksum-verified |
| `check-update.sh` | Current upstream build, for enclave's update probe |
| `gateway-allowlist.conf` | DNS allowlist |
| `templates/settings.json` | Defaults, copied on first start |
| `entrypoint.d/setup.sh` | Points `AMP_SETTINGS_FILE` and the global skills directory into the store, re-asserts the update and permission settings |

## Known limits

- **Yolo mode is a setting, not a flag.** This build has no
  `--dangerously-allow-all`; the equivalent is `amp.dangerouslyAllowAll` in the
  settings file. `entrypoint.d/setup.sh` therefore writes it on every start to
  match enclave's own mode — `true` by default, `false` under `--no-yolo` — and
  the value overrides whatever the persisted file carries. Without that, a file
  left behind by a yolo session would keep a `--no-yolo` session permissive.
  For finer control than on/off, set `amp.permissions` rules and run
  `--no-yolo`.
- **The settings file has to stay plain JSON.** Amp accepts JSONC, `jq` does
  not, and `entrypoint.d/setup.sh` rewrites the file with `jq` on every start.
  A settings file with comments makes the script warn and leave the file alone,
  which also leaves the two pinned settings unapplied.
- **No host config passthrough.** Passthrough resolves below `hostConfigDir`,
  which is the store, `~/.local/share/amp`. The host files worth passing
  through — `settings.json` and `skills/` — live in `~/.config/amp`, outside
  it, so `spec.yaml` declares no `passthroughPaths`.
- **BYOK is not modelled.** Amp supports bringing your own provider keys and
  subscriptions (`amp config model-providers`). Whether the CLI then calls
  provider APIs directly, which the allowlist does not cover, or keeps routing
  through Amp's backend, was not verified here — it needs an account with a key
  attached. If BYOK requests fail in a session, that is the first thing to
  check.
- **Gateway injection is verified for HTTP only.** The `Authorization: Bearer`
  header was confirmed against `POST ampcode.com/api/internal`. Whether the
  WebSocket connection to `production.ampworkers.com` authenticates the same
  way is untested, so a session run with the key suppressed from the container
  may lose live thread updates while ordinary requests keep working.
- **`qemuStoreCacheMmap` is set defensively.** The binary bundles SQLite and
  keeps local thread state in the store; which database files it opens, and
  whether they use WAL, needs an account to observe. The flag is required for
  WAL databases under the QEMU backend and harmless otherwise.
