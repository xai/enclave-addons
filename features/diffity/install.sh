#!/bin/bash
# Install the diffity CLI into the private agent Node runtime
set -euo pipefail

# The published CLI and vendored skills come from different upstream revisions.
# Keep both pins explicit and reconcile their compatibility when either changes
# (see README.md, "Updating the vendored skills").
DIFFITY_VERSION="0.9.5"
DIFFITY_SKILLS_REVISION="9370438b0b50bb06881d95e3578a2df407d6e6bb"

# enclave-agent-npm-install runs npm from /opt/enclave/node and rewrites the
# bin shebang to that interpreter, so this feature does not depend on node-dev.
#
# npm_config_prefix has to be set here. The helper only reads it to locate the
# installed bins afterwards; it does not pass it to npm, and unlike the tool
# path (enclave-install-tool exports it) nothing sets it for feature installs.
# Without it npm falls back to its own prefix, /opt/enclave/node, which the
# agent user cannot write to in the user phase -- EACCES on mkdir.
#
# Command-scoped on purpose, as in node-dev: `npm config set prefix` persists
# into ~/.npmrc, and nvm then aborts `nvm use` with exit 11 in every later
# build layer and at container start.
npm_config_prefix="$HOME/.local" enclave-agent-npm-install "diffity@${DIFFITY_VERSION}"

if ! command -v diffity >/dev/null 2>&1; then
    echo "diffity not found in PATH after installation" >&2
    exit 1
fi

# better-sqlite3 is a native module: load it here so an ABI mismatch fails the
# build instead of the first agent invocation.
if ! diffity --version >/dev/null 2>&1; then
    echo "diffity installed but not runnable (native module ABI mismatch?)" >&2
    exit 1
fi

echo "diffity ${DIFFITY_VERSION} installed at: $(command -v diffity)"
echo "diffity skills revision: ${DIFFITY_SKILLS_REVISION}"
