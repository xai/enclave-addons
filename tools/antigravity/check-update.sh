#!/usr/bin/env bash
# Upstream fingerprint for enclave's automatic update probe: the newest
# Antigravity CLI release tag. Pin this to the same value as install.sh's
# ANTIGRAVITY_VERSION when you pin the version, or the probe will report a
# change the rebuild cannot deliver.
set -euo pipefail

curl -fsS https://api.github.com/repos/google-antigravity/antigravity-cli/releases/latest | jq -r '.tag_name'
