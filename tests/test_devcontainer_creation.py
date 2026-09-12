"""Dev container creation must succeed on a host that has no Wolfram Engine.

``postCreateCommand`` used to be one 25-step ``&&`` chain, and on a fresh host it
died twice: at the first engine-side ``ln`` (``ln -sf`` tolerates a missing
target but not a missing parent directory, and an empty engine mount has no
``Executables/``), and again in ``install-lsp-wl.sh``, which ran a Wolfram kernel
under ``set -euo pipefail``.  Because the chain is ``&&``, both aborts also
stopped the Claude memory restore and the session reindex that ``CLAUDE.md``
promises happen on every rebuild (GH #559).

These are static assertions on the committed configuration.  They deliberately
do **not** execute the lifecycle scripts: CI has none of the bind mounts, so
running them there would exercise something other than what runs in the
container.  The fresh-home rehearsal lives in the pull request as a transcript.

Every path is derived from the configuration itself rather than written down --
``tests/`` is not in the ``test_repo_hygiene`` allowlist, and a hardcoded
container home would fail that check.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
DEVCONTAINER = REPO_ROOT / ".devcontainer" / "devcontainer.json"

# The line #559 dispatched, to be carried verbatim.  An unregistered PSALTer does
# not fail loudly: it completes and writes a silently wrong spectrum, so this
# must run on every creation -- and must never abort creation itself.
PSALTER_TAIL = (
    "(bash scripts/psalter/ensure_registered.sh || echo 'PSALTer resources "
    "NOT registered -- run: bash scripts/psalter/ensure_registered.sh')"
)

HOST_HOME = "${localEnv:HOME}"


def _load() -> dict[str, Any]:
    """Parse devcontainer.json, tolerating the whole-line // comments JSONC allows."""
    text = DEVCONTAINER.read_text(encoding="utf-8")
    stripped = "\n".join(
        "" if line.lstrip().startswith("//") else line for line in text.splitlines()
    )
    return json.loads(stripped)


def _mounts() -> list[dict[str, str]]:
    parsed = []
    for mount in _load()["mounts"]:
        fields = dict(part.split("=", 1) for part in mount.split(",") if "=" in part)
        parsed.append(fields)
    return parsed


def _steps() -> list[str]:
    return _load()["postCreateCommand"].split(" && ")


def test_devcontainer_json_parses() -> None:
    """A malformed devcontainer.json fails the build with no useful message."""
    config = _load()
    assert config["mounts"], "mounts must not be empty"
    assert config["postCreateCommand"], "postCreateCommand must not be empty"


def test_host_bind_sources_are_created_by_initialize_command() -> None:
    """Every host-rooted bind mount must be created before the container starts.

    Docker gives a missing bind source no useful treatment: it either refuses, or
    creates it empty and root-owned.  ``initializeCommand`` runs on the host, so
    it is the only place this can be fixed -- and it is what lets the
    ``chown`` in ``postCreateCommand`` stay non-recursive.
    """
    config = _load()
    initialize = config.get("initializeCommand")
    assert initialize, "initializeCommand is required: it creates the host bind sources"

    body = initialize[-1] if isinstance(initialize, list) else initialize
    assert "mkdir -p" in body, "initializeCommand must create the bind sources"

    for mount in _mounts():
        source = mount.get("source", "")
        if mount.get("type") != "bind" or HOST_HOME not in source:
            continue
        suffix = source.split(HOST_HOME, 1)[1].lstrip("/")
        assert suffix in body, (
            f"bind source {source!r} has no matching mkdir in initializeCommand; "
            "a fresh host gets an empty root-owned directory instead"
        )


def test_initialize_command_refuses_an_unset_home() -> None:
    """Unset ``${localEnv:*}`` variables are left blank by the spec.

    With HOME blank the bind sources resolve to the filesystem root, so the guard
    must fail loudly rather than let ``docker run`` proceed.
    """
    initialize = _load()["initializeCommand"]
    body = initialize[-1] if isinstance(initialize, list) else initialize
    assert '-z "$HOME"' in body, "initializeCommand must guard against an unset HOME"
    assert "exit 1" in body, "the HOME guard must abort, not warn"


def test_named_volumes_are_chowned() -> None:
    """Docker materialises a named volume root-owned, so the user cannot write it.

    ``~/.Wolfram`` holds the Wolfram resource registry; if registration fails on a
    permission error, PSALTer writes a silently wrong spectrum.
    """
    chown = next((s for s in _steps() if s.startswith("sudo chown")), None)
    assert chown, "postCreateCommand must take ownership of the named volumes"

    for mount in _mounts():
        if mount.get("type") != "volume":
            continue
        target = mount["target"]
        assert target in chown, f"named volume {target!r} is not chowned; it stays root-owned"


def test_chown_does_not_descend_into_bind_mounts() -> None:
    """``chown -R`` walked the 1.6 GB engine tree and rewrote ownership on the host."""
    chown = next((s for s in _steps() if s.startswith("sudo chown")), None)
    assert chown
    assert " -R" not in chown, (
        "chown must stay non-recursive: through a bind mount it rewrites the host's "
        "own file ownership"
    )


def test_no_symlink_wiring_remains_inline() -> None:
    """Link wiring belongs in setup-wolfram-links.sh, where it can be tested.

    A chain inside a JSON string cannot be ``bash -n``'d, traced, or rehearsed
    against a throwaway home -- which is how the fresh-host abort survived.
    """
    for step in _steps():
        assert not re.search(r"(^|\s)ln\s", step), (
            f"inline link wiring found in postCreateCommand: {step!r}; "
            "it belongs in .devcontainer/scripts/setup-wolfram-links.sh"
        )


def test_psalter_registration_runs_last_and_cannot_abort_creation() -> None:
    """The registry is container overlay, so it must be re-created on every start.

    It must also never fail the build: a host without the engine yet still has to
    finish creating, and be told the recovery command.
    """
    steps = _steps()
    assert steps[-1] == PSALTER_TAIL, (
        "the PSALTer registration step must be present verbatim and last; found: "
        f"{steps[-1]!r}"
    )


def test_every_lifecycle_script_exists() -> None:
    """A renamed or retired script turns container creation into a silent skip."""
    config = _load()
    commands = " && ".join(
        str(config.get(key, "")) for key in ("onCreateCommand", "postCreateCommand")
    )
    for match in re.finditer(r"bash\s+((?:\.devcontainer|scripts)/[\w./-]+)", commands):
        script = REPO_ROOT / match.group(1)
        assert script.is_file(), f"lifecycle command references a missing script: {match.group(1)}"
