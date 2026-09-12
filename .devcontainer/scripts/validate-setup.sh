#!/usr/bin/env bash
# validate-setup.sh -- redirect to the one verifier (GH #559).
#
# This ran nine checks of its own and knew nothing of PSALTer or the Wolfram
# resource registry, so "9/9 passed" could be reported on an install that cannot
# produce a correct particle spectrum.  scripts/verify-wolfram-setup.sh is the
# single verifier: it covers seven of the nine and adds four more, including the
# PSALTer install, its pinned commit, and the certified identities of the two
# locally registered resource functions.
#
# TWO CHECKS ARE GONE, deliberately, rather than silently:
#   - wolframclient (the Python client) -- an optional extra that nothing in
#     TIDAL imports; the pipeline shells out to wolframscript.
#   - VS Code extensions -- self-skips outside VS Code, and
#     .devcontainer/scripts/install-extensions-final.sh owns that job.
#
# The old script, if you need it:  git show v0.54.1:.devcontainer/scripts/validate-setup.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec bash "${REPO_ROOT}/scripts/verify-wolfram-setup.sh" "$@"
