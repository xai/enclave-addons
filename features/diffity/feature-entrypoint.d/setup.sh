# shellcheck shell=bash
# Keep diffity's review database across sessions, and drop the stale registry
#
# Diffity stores comment threads and tours in ~/.diffity, keyed by a hash of
# the repository root. The container home is ephemeral, so point that directory
# at the current per-project, per-tool, per-store-key config store. Reviews do
# not cross tool switches or concurrent sessions that use a suffixed store.
if [ -n "${ENCLAVE_TOOL_CONFIG_DIR:-}" ] && [ ! -e "$HOME/.diffity" ]; then
    if mkdir -p "$ENCLAVE_TOOL_CONFIG_DIR/diffity" 2>/dev/null; then
        ln -s "$ENCLAVE_TOOL_CONFIG_DIR/diffity" "$HOME/.diffity" 2>/dev/null || true
    fi
fi

# The registry tracks running instances by PID. PIDs are per-container and get
# recycled, so an entry left behind by an earlier session can point the skills
# at a port nothing is listening on.
rm -f "$HOME/.diffity/registry.json" "$HOME/.diffity/registry.lock" 2>/dev/null || true
