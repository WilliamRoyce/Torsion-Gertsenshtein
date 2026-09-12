#!/usr/bin/env bash
# ensure_registered.sh -- make PSALTer's two undocumented Function Repository
# dependencies resolve to the CERTIFIED local objects, and prove it.  GH #543.
#
# Idempotent. Run it:
#   - after every container rebuild (the registry under ~/.Wolfram/Objects is
#     container overlay unless the devcontainer mounts it), which is why the
#     devcontainer's postCreateCommand calls this;
#   - from install-psalter.sh, after the package is copied;
#   - any time verify-wolfram-setup.sh check 10 reports the identities missing.
#
# Takes the Wolfram lane for about a minute. Exits non-zero on ANY failure --
# an unregistered install does not fail, it writes a silently wrong spectrum
# (empty source constraints, zero pseudo-determinants), so this must be loud.
#
#   bash scripts/psalter/ensure_registered.sh            # register + verify
#   bash scripts/psalter/ensure_registered.sh --no-verify  # register only
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY=true
[[ "${1:-}" == "--no-verify" ]] && VERIFY=false

NB="${REPO_ROOT}/scripts/psalter/resources/PolynomialDegree-1-0-0-definition.nb"
NB_SHA="c233e226d4c77de65ee19ddbc84c20c9724df467bb86c27f1a65f17fba89787c"
if [[ ! -f "$NB" ]]; then
    echo "ensure_registered: committed notebook missing at ${NB#"$REPO_ROOT"/}" >&2
    echo "  (register_resources.wl will try third_party/psalter_resources/, then a download)" >&2
elif [[ "$(sha256sum "$NB" | cut -d' ' -f1)" != "$NB_SHA" ]]; then
    echo "ensure_registered: committed notebook sha256 mismatch -- refusing to register from it" >&2
    exit 1
fi

if ! command -v wolframscript >/dev/null 2>&1; then
    echo "ensure_registered: wolframscript not on PATH -- install and activate the engine first" >&2
    exit 1
fi

echo "ensure_registered: registering (lane held ~1 min)"
if ! QT_QPA_PLATFORM=offscreen timeout 600 wolframscript -file "${REPO_ROOT}/scripts/psalter/register_resources.wl"; then
    echo "ensure_registered: REGISTRATION FAILED. PSALTer will still load and run, but it will" >&2
    echo "  produce a SILENTLY WRONG spectrum (GH #543). Do not trust any result until this passes." >&2
    exit 1
fi

if $VERIFY; then
    echo "ensure_registered: verifying (--require-psalter)"
    bash "${REPO_ROOT}/scripts/verify-wolfram-setup.sh" --require-psalter
fi
