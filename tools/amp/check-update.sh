#!/usr/bin/env bash
# Upstream fingerprint for enclave's automatic update probe: the build the Amp
# CLI installer would fetch right now. Pin this to the same value as
# install.sh's AMP_VERSION when you pin the version, or the probe will report a
# change the rebuild cannot deliver.
#
# Amp versions carry a build timestamp and change several times a day, so this
# probe reports a stale image far more often than a tool that cuts releases.
set -euo pipefail

curl -fsS https://static.ampcode.com/cli/cli-version.txt
