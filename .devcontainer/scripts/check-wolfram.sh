#!/usr/bin/env bash
# check-wolfram.sh -- redirect to the one verifier (GH #559).
#
# This ran five quick checks and printed "Installation: OK / Kernel: Working /
# Script: Working" unconditionally in its summary, even after two of them had
# failed.  It also used `wolframscript -code "3+3"` as proof the engine worked,
# which the dev container image's standalone /usr/bin/wolframscript answers from
# the CLOUD.  scripts/verify-wolfram-setup.sh tests the mounted kernel instead.
#
# The old script, if you need it:  git show v0.54.1:.devcontainer/scripts/check-wolfram.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "${REPO_ROOT}/scripts/verify-wolfram-setup.sh" "$@"
