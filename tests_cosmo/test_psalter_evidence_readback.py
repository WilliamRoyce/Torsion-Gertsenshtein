"""Reading a recorded Tier-1 verdict back must never be able to destroy it.

The committed evidence under ``docs/cosmology/evidence/`` is the basis of an open
decision, and it deliberately excludes the ``.mx`` files the verdict was computed
from. That combination is what made the original defect possible: the documented
re-verification command *recomputed* the comparison and rewrote ``tier1_diff.json``
in place, so pointing it at the evidence turned a real ``mismatch`` into an
``ours_unreadable`` failure artifact -- silently, because the overwritten file was
still well-formed JSON.

The gate was not vacuous. It worked correctly and wrote its answer over the
question. So two properties are probed here, the way a gate gets probed failing:

1. the read-back path is **read-only**, and
2. the recompute path **refuses** when its inputs are absent, rather than
   manufacturing a failure artifact in their place.

Neither test needs Wolfram or the network: the refusal is checked before the
engine-idle guard and before any reference fetch.
"""

from __future__ import annotations

import hashlib
import json
import shutil
import subprocess  # noqa: S404  -- args are repo paths and tmp_path, never external input
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
GATE = REPO_ROOT / "scripts" / "psalter" / "run_tier1_gate.sh"
SUMMARIZE = REPO_ROOT / "scripts" / "psalter" / "summarize_diff.py"
EVIDENCE = REPO_ROOT / "docs" / "cosmology" / "evidence" / "tier1-20260907"


def _bash() -> str:
    """Absolute path to bash, so the test does not depend on PATH resolution."""
    found = shutil.which("bash")
    assert found is not None, "bash is required to run the gate script"
    return found


def _digests(directory: Path) -> dict[str, str]:
    return {
        f.name: hashlib.sha256(f.read_bytes()).hexdigest()
        for f in sorted(directory.iterdir())
        if f.is_file()
    }


def test_evidence_directory_holds_a_verdict_but_not_the_mx() -> None:
    """The precondition that made the defect possible, asserted so it stays known."""
    assert (EVIDENCE / "tier1_diff.json").is_file()
    assert not list(EVIDENCE.glob("*.mx")), (
        "an .mx appeared in the committed evidence; the license position for run "
        "outputs sits with #495, and its size is why it was excluded"
    )


def test_recompute_refuses_without_its_inputs_and_writes_nothing(
    tmp_path: Path,
) -> None:
    """--diff-only must refuse, not overwrite the verdict with a failure artifact."""
    work = tmp_path / "evidence"
    work.mkdir()
    (work / "tier1_diff.json").write_text(
        json.dumps(
            {"verdict": "mismatch", "verdict_reason": "recorded", "entries": []}
        ),
        encoding="utf-8",
    )
    before = _digests(work)

    result = subprocess.run(  # noqa: S603
        [_bash(), str(GATE), "--diff-only", str(work)],
        capture_output=True,
        text=True,
        timeout=300,
        cwd=REPO_ROOT,
        check=False,
    )

    assert result.returncode != 0, "refusal must be a failure exit, not a silent no-op"
    assert _digests(work) == before, (
        "--diff-only modified the directory it was asked to check; that is the "
        "original defect, in which a recorded verdict became 'ours_unreadable'"
    )
    combined = result.stdout + result.stderr
    assert "summarize_diff.py" in combined, (
        "the refusal must name the read-only command that does work"
    )


def test_reading_a_recorded_verdict_back_is_read_only(tmp_path: Path) -> None:
    """summarize_diff.py must re-derive the verdict without touching anything."""
    work = tmp_path / "evidence"
    work.mkdir()
    source = EVIDENCE / "tier1_diff.json"
    (work / "tier1_diff.json").write_bytes(source.read_bytes())
    before = _digests(work)

    result = subprocess.run(  # noqa: S603
        [sys.executable, str(SUMMARIZE), str(work / "tier1_diff.json")],
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )

    assert _digests(work) == before, "reading a verdict back must not write"
    recorded = json.loads(source.read_text(encoding="utf-8"))["verdict"]
    assert recorded.upper() in result.stdout
    # Exit code carries the verdict: 0 only for a match.
    assert (result.returncode == 0) == (recorded == "match")


def test_evidence_readme_documents_the_read_only_command() -> None:
    """The documented route must be the one that cannot destroy the evidence."""
    readme = (EVIDENCE / "README.md").read_text(encoding="utf-8")
    assert "summarize_diff.py" in readme
    index = readme.index("## Reproducing")
    assert readme.index("summarize_diff.py") > index
    assert readme.index("summarize_diff.py") < readme.index("--diff-only", index), (
        "the read-only command must be documented before the recompute path, "
        "so a reader reaches for it first"
    )
