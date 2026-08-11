---
name: diffity-tree
description: Start the diffity file tree UI for browsing and commenting on files
user-invocable: true
---

# Diffity Tree Skill

You are starting the diffity file tree so the user can browse repository files in a host browser.

## Instructions

1. Check that `diffity` is available with `command -v diffity`. If it is missing, stop and tell the user to reinstall the Diffity feature and rebuild the Enclave image. Do not install or update diffity inside the session.
2. Get the current repository root with `git rev-parse --show-toplevel`, then run `diffity list --json` and find the entry whose `repoRoot` is that path.
3. Choose what to do with the matching repository entry:
   - If its `ref` is `"__tree__"`, reuse it. Do not run another server command.
   - If it exists with any other `ref`, it is a diff session. Start `diffity tree --no-open --new` as a long-running background command using the current tool's shell execution facility, and remember that the diff session was replaced.
   - If it does not exist, start `diffity tree --no-open` as a long-running background command using the current tool's shell execution facility. Do not use `--new` when there is nothing to replace.
   Do not use `--quiet`.
4. If a server was started, wait 2 seconds, then run `diffity list --json` and verify that the current repository now has an entry with `ref: "__tree__"`. The reported port is container-local; do not give it to the user.
5. Verify persistence before handing off: take the entry's `repoHash` and run `readlink "$HOME/.diffity/<repoHash>"`. If it prints nothing, that path is not a link into the host store, so comments in this session are container-local and vanish with it. Lead with that. It means the feature's link no longer matches diffity's layout — a feature bug to report, not something to repair from inside the session.
6. Tell the user diffity tree is running and direct them to Enclave's published URL with `/tree` appended. The tree is a separate route: the bare URL lands on the diff view, which defaults to the working tree and shows "No changes found" when it is clean. If a diff session was replaced, say so explicitly before the usual message. Keep it short and do not show session IDs, hashes, container ports, or other internals. Examples:

   > Diffity tree is running. Open the Diffity URL Enclave printed at session start (or run `enclave ps` on the host to see it) and add `/tree` to it.
   >
   > When you're ready:
   > - Leave comments on any file in your browser, then run **/diffity-resolve-tree** to fix them

   Or, after a replacement:

   > Replaced the running diff session with a tree session. Open the Diffity URL Enclave printed at session start (or run `enclave ps` on the host to see it) and add `/tree` to it.
