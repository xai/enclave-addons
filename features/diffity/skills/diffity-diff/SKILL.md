---
name: diffity-diff
description: Start the diffity browser UI so the user can inspect changes
user-invocable: true
---

# Diffity Diff Skill

You are starting the diffity diff viewer so the user can inspect changes in a host browser.

## Arguments

- `ref` (optional): Git ref to diff (e.g. `main..feature`, `HEAD~3`) or a GitHub PR URL (e.g. `https://github.com/owner/repo/pull/123`). Defaults to working tree changes.

## Instructions

1. Check that `diffity` is available with `command -v diffity`. If it is missing, stop and tell the user to reinstall the Diffity feature and rebuild the Enclave image. Do not install or update diffity inside the session.
2. Get the current repository root with `git rev-parse --show-toplevel`, then run `diffity list --json` and find the entry whose `repoRoot` is that path.
3. Determine the requested registry ref. It is `"work"` when no ref (or `.`) was requested, and otherwise the requested ref string. For a GitHub PR URL, use `gh pr view <pr-url> --json baseRefName --jq .baseRefName`; diffity checks out the PR and stores that base branch as its ref. Only reuse a PR session when `gh pr view --json url --jq .url` also identifies the currently checked-out branch as that requested PR.
4. Choose what to do with the matching repository entry:
   - If its `ref` is the requested ref (and the PR check above matches when applicable), reuse it. Do not run another server command.
   - If it exists but its `ref` or PR differs, start `diffity --no-open --new <ref>` (or `diffity --no-open --new` if no ref) as a long-running background command using the current tool's shell execution facility. Remember whether this replaced a tree session (`ref: "__tree__"`) or a different diff ref.
   - If it does not exist, start `diffity --no-open <ref>` (or `diffity --no-open` if no ref) as a long-running background command using the current tool's shell execution facility. Do not use `--new` when there is nothing to replace.
   Do not use `--quiet`.
5. If a server was started, wait 2 seconds, then run `diffity list --json` and verify that the requested instance is running for the current repository. The reported port is container-local; do not give it to the user.
6. Take the `ref` field of that entry and build the path `/diff?ref=<ref>`, using the registry value verbatim (`/diff?ref=work` for a working-tree session, `/diff?ref=main..HEAD` for that comparison). The user must open this path, not the bare URL: the UI reads the ref from the query string and falls back to the working tree when it is missing, so the bare URL shows "No changes found" on a clean tree no matter which diff the server is serving.
7. Tell the user diffity is running and direct them to Enclave's published URL with that path appended. If a mismatched session was replaced, say so explicitly before the usual message. Keep it short and do not show session IDs, hashes, container ports, or other internals. Examples:

   > Diffity is running. Open the Diffity URL Enclave printed at session start (or run `enclave ps` on the host to see it) and add `/diff?ref=main..HEAD` to it.
   >
   > When you're ready:
   > - Leave comments on the diff in your browser, then run **/diffity-resolve** to fix them
   > - Or run **/diffity-review** to get an AI code review

   Or, after a replacement:

   > Replaced the running tree session with the requested diff session. Open the Diffity URL Enclave printed at session start (or run `enclave ps` on the host to see it) and add `/diff?ref=main..HEAD` to it.
