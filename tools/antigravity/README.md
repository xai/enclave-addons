# antigravity (tool)

Runs Google's [Antigravity CLI](https://antigravity.google/docs/cli/overview)
(`agy`) as an enclave session tool: `enclave --tool antigravity` starts the
agent on the project directory, inside the usual container, read-write project
mount and DNS allowlist.

```bash
enclave --tool antigravity                    # build the image the first time with --rebuild
enclave --tool antigravity -- --model gemini-3-pro
enclave --tool antigravity continue           # --continue, the most recent conversation
```

`agy` is distributed as a prebuilt binary; upstream publishes a changelog,
examples and an issue tracker at
[google-antigravity/antigravity-cli](https://github.com/google-antigravity/antigravity-cli),
but no source. Everything below about its on-disk and on-the-wire behaviour was
checked against the 1.2.5 Linux build rather than taken from the docs, which
are thin on both.

## Install

```bash
./install.sh tools/antigravity
enclave --tool antigravity --rebuild
```

`install.sh` fetches the release tarball from GitHub and installs the binary as
`~/.local/bin/agy`, rather than running upstream's
`curl https://antigravity.google/cli/install.sh | bash`. That installer resolves
the build through a Cloud Run auto-updater host the image cannot reach, and then
edits shell profiles the image already sets up. Pin a version by setting
`ANTIGRAVITY_VERSION` in both `install.sh` and `check-update.sh`; left at
`latest`, `check-update.sh` reports the newest upstream tag and enclave rebuilds
the image when it changes.

## Authentication

Two ways in, and they are independent:

- **Antigravity account (Google sign-in).** Run `agy` and follow the prompt. The
  CLI detects that it is in a container and uses the paste-a-code flow: it
  prints an authorization URL, you open it in your host browser and paste the
  code back. No callback port has to be published. Credentials land in a file
  under `~/.gemini/antigravity-cli/` (the OS keyring is skipped without a D-Bus
  session bus), which the config store persists across sessions.
- **Gemini API key.** Export `GEMINI_API_KEY` *and* set `"modelProvider":
  "gemini"` in the CLI settings — the key alone is ignored. The gateway injects
  the key as `x-goog-api-key` on requests to `generativelanguage.googleapis.com`,
  so it is never present in the container environment in the clear.

`/logout` clears the stored session.

## Data privacy

The settings template ships the three switches that matter and
`entrypoint.d/setup.sh` re-applies them at every start:

| Setting | Effect |
| --- | --- |
| `enableTelemetry: false` | Opts out of the anonymous usage statistics Google collects by default |
| `showFeedbackSurvey: false` | No post-task survey prompts |
| `allowNonWorkspaceAccess: false` | The agent stays inside the workspace; files elsewhere in the container need explicit approval |

The re-application is not belt and braces, it is required. `agy` persists
settings *sparsely*: on exit it rewrites `settings.json` keeping only the keys
whose value differs from the default it holds for the session, so
`enableTelemetry` disappears from the file after the very first run. Enclave
copies a settings template only when the target does not exist yet, so without
the entrypoint merge the opt-out would apply once and never again. The merge
adds back what is missing and touches nothing else — meaning a value you change
with `/config` inside a session survives exactly as long as `agy` keeps writing
it down.

One consequence worth knowing: because the key is stripped, you cannot read
your telemetry state back off disk, and `agy -p /config` does not report it
either ([issue #1010](https://github.com/google-antigravity/antigravity-cli/issues/1010)).
The setting is the documented opt-out and the CLI does read it at startup; it is
not something this extension can verify for you.

What the network policy adds, which does not depend on a setting being honoured:

- `play.googleapis.com` is denied. That is Clearcut, the endpoint the CLI's
  analytics worker posts to. It sits under `googleapis.com`, which has to
  resolve for the agent backend, so it is listed under `network.deniedDomains`
  in `spec.yaml` rather than left out of the allowlist: deny out-ranks allow
  (dnsmasq resolves by longest match), and the gateway's proxy refuses the host
  as well, so a resolver that answered anyway would not help.
- The auto-updater host is denied too, and `AGY_CLI_DISABLE_AUTO_UPDATE=true`
  stops the CLI from spawning the background update process in the first place.
  Without it every session tries to replace the binary the image was built with.

And what neither reaches: the CLI also records command usage over the same gRPC
connection it uses for the agent itself
(`exa.analytics_pb.AnalyticsService/RecordCommandUsage` on the backend host).
Blocking that means blocking the agent, so `enableTelemetry` is the only lever
there. Prompts, file contents and command output go to Google as part of normal
operation in any case; upstream's terms state that interactions data is
collected to improve the product unless you opt out.

Two identifiers are generated on first run and then persist in the config store
for the life of that store: `~/.gemini/antigravity-cli/installation_id` and a
second installation UUID. `enclave` keeps them per tool and per project, so they
do not follow you across projects, and deleting the store resets them.

## Network

Allowlisted: `antigravity.google` (sign-in landing page, OAuth client metadata,
changelog), the `google.conf` fragment (sign-in, token refresh, the
`cloudcode-pa`/`aicode` agent backend, `generativelanguage` for API-key mode,
and the `aiplatform`/`iamcredentials`/`sts` hosts enterprise Agent Platform and
ADC need), plus GitHub and the usual package registries so the agent can work in
the project. Denied: Clearcut and the updater, as above.

The CLI's browser tools want to download a Playwright browser at runtime
(`~/.cache/ms-playwright-go`), which the allowlist does not cover. Treat the
browser tooling as unavailable in a session.

## Configuration layout

`agy` keeps two trees under `~/.gemini`, both inside the single config store
this extension declares:

| Path | Holds |
| --- | --- |
| `.gemini/antigravity-cli/` | `settings.json`, `keybindings.json`, conversations (SQLite, WAL), caches, logs, credentials |
| `.gemini/config/` | What the CLI shares with the Antigravity IDE: `skills/`, `mcp_config.json`, `workflows/`, `global_workflows/`, per-project permissions |

Managed skills are composed into `~/.gemini/config/skills`, the scope every
Antigravity product reads, so an enclave feature that ships skills (for example
[diffity](../../features/diffity/)) reaches this tool too. Host config
passthrough is limited to settings, keybindings, MCP servers, skills and
workflows; plugins and the hook configuration are left out, since both execute
code the enclave session did not build.

## Files

| File | Purpose |
| --- | --- |
| `spec.yaml` | Extension manifest (sandbox behaviour, denied domains, credentials) |
| `install.sh` | Installs `agy` from the upstream GitHub release |
| `check-update.sh` | Latest release tag, for enclave's update probe |
| `gateway-allowlist.conf` | DNS allowlist |
| `templates/settings.json` | Privacy defaults, copied on first start |
| `entrypoint.d/setup.sh` | Re-applies those defaults on every start |

## Known limits

- **Needs an enclave with the nested-skills-dir store fix.** `skillsDir` is
  `.gemini/config/skills`, two levels below `configDir` and in a different
  subtree than the settings file, which is the one shape enclave does not
  pre-create in the config store
  ([enclave#92](https://github.com/eclipse-enclave/enclave/issues/92)). Until
  that fix ships, the container runtime creates `~/.gemini/config` as root and
  `agy` dies at startup with
  `mkdir /home/agent/.gemini/config/projects: permission denied`. Workaround:
  after the first failed start, replace that directory in the store with one
  you own, then start again.

  ```bash
  store=~/.local/state/enclave/projects/<hash>/antigravity/config-store/default
  podman unshare rm -rf "$store/config"   # docker: sudo rm -rf
  mkdir -p "$store/config"
  ```

  Ephemeral sessions (`--no-persist`) recreate the store, so they hit it again.
- **No session detection.** `spec.yaml` declares no `authFiles` for the account
  session: upstream does not document the credential file's name and it is not
  discoverable in the binary. `enclave auth import/export` therefore has nothing
  to copy for this tool — sign in once inside a session and the config store
  keeps it.
- **Sign-in may not survive a restart.** Upstream
  [issue #479](https://github.com/google-antigravity/antigravity-cli/issues/479)
  reports the container's file-backed token being written but never read back,
  so every fresh process asks you to sign in again. Whether 1.2.5 still does
  this was not verifiable here — it needs an account to reproduce. If you hit
  it, the API-key route above is unaffected.
- **`enclave resume` falls back to `--continue`.** `agy` has no flag for its
  conversation picker; use `/resume` inside the session.
- **Yolo mode is the enclave default.** Sessions start with
  `--dangerously-skip-permissions`, as they do for the other agent tools; pass
  `--no-yolo` for the CLI's own review prompts.
