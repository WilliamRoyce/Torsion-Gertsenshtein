#!/usr/bin/env bash
# Install Wolfram Language Server (lsp-wl) and required paclets

set -euo pipefail

REPO_DIR="$HOME/.local/share/lsp-wl"
REPO_URL="https://github.com/kenkangxgwe/lsp-wl.git"
KERNEL="$HOME/.local/wolfram/engine/14.3/Executables/WolframKernel"

# The kernel is the engine test, never `command -v wolframscript`: the image
# ships a standalone client at /usr/bin/wolframscript that makes an absent
# engine look present (#559).  Without this guard `set -euo pipefail` turned a
# not-yet-installed engine into a failed postCreateCommand, and because the
# chain is `&&`, the steps after this one -- the Claude memory restore and the
# session reindex -- silently never ran on a fresh host.  The guard is before
# the clone so a fresh host does no network I/O either.
if [[ ! -x "$KERNEL" ]]; then
    echo "install-lsp-wl: Wolfram Engine kernel not found -- skipping."
    echo "  expected: $KERNEL"
    echo "  Run install steps 1-3 (.devcontainer/docs/WOLFRAM_GUIDE.md), then:"
    echo "    bash .devcontainer/scripts/install-lsp-wl.sh"
    exit 0
fi

if [[ -d "$REPO_DIR/.git" ]]; then
    git -C "$REPO_DIR" pull --ff-only
else
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
fi

"$KERNEL" -noprompt -run 'PacletInstall["CodeParser"]; PacletInstall["CodeInspector"]; Exit[]'

echo "Wolfram Language Server repo: $REPO_DIR"
echo "Paclets installed: CodeParser, CodeInspector"
