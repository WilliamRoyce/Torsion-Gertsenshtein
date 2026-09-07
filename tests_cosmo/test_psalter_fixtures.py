"""The committed PSALTer fixtures are what they claim to be.

These two WXF files are the only upstream bytes committed anywhere in this
repository (everything else is fetched into gitignored ``third_party/``), and
they exist so the Stage-1 reader can be tested without a Wolfram install. Both
properties depend on the bytes being exactly the published ones, so their digests
are checked here rather than trusted.

The integrity check is not ceremonial: the files contain no NUL bytes, so git's
``text=auto`` heuristic classifies them as text. ``.gitattributes`` marks
``*.wxf`` as binary to stop that; this test is what would notice if the rule were
removed or the files were normalized.

See ``tests_cosmo/fixtures/psalter/PROVENANCE.md`` for the source, the pinned
revision, the license position (#495) and the known labeling defect.
"""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

FIXTURE_DIR = Path(__file__).resolve().parent / "fixtures" / "psalter"

# From SupplementalMaterials-2607 at the pinned revision below.
EXPECTED: dict[str, tuple[str, int]] = {
    "ParticleSpectrographVectorTheory.wxf": (
        "8958f32de7530abfc0c261d23084d59652f1fcf2c9fcfa1edb71e5dfd5e0c2ed",
        692,
    ),
    "ParticleSpectrographA23Theory.wxf": (
        "ff48c3f9fa22bb3e57cef99be6a20497d21896e6d5676ef3b5901718ff650bcb",
        2874,
    ),
}

PINNED_REVISION = "b49e9f1d5410ac19884cf9837190be975a58927b"

# WXF streams begin with the format marker "8:" (version 8, no compression).
WXF_MAGIC = b"8:"


def test_fixtures_are_present() -> None:
    """Both published exports are committed, not merely referenced."""
    for name in EXPECTED:
        assert (FIXTURE_DIR / name).is_file(), f"missing fixture: {name}"


def test_fixture_digests_match_provenance() -> None:
    """The bytes are the published ones, so the reader is tested against truth."""
    for name, (digest, size) in EXPECTED.items():
        data = (FIXTURE_DIR / name).read_bytes()
        assert len(data) == size, f"{name}: size {len(data)} != {size}"
        actual = hashlib.sha256(data).hexdigest()
        assert actual == digest, (
            f"{name}: sha256 {actual} != {digest}. The fixture has been altered "
            f"-- most likely line-ending normalization. Check that .gitattributes "
            f"still marks *.wxf as binary."
        )


def test_fixtures_are_wxf() -> None:
    """A truncated or re-encoded fixture would still have the right name."""
    for name in EXPECTED:
        data = (FIXTURE_DIR / name).read_bytes()
        assert data.startswith(WXF_MAGIC), f"{name} is not a WXF stream"


def test_provenance_records_the_pinned_revision_and_digests() -> None:
    """Provenance is only useful if it stays in step with the bytes it describes."""
    text = (FIXTURE_DIR / "PROVENANCE.md").read_text(encoding="utf-8")
    assert PINNED_REVISION in text, "PROVENANCE.md does not name the pinned revision"
    for name, (digest, _size) in EXPECTED.items():
        assert digest in text, f"PROVENANCE.md does not record the digest for {name}"
        assert name in text, f"PROVENANCE.md does not name {name}"


def test_provenance_flags_the_license_review() -> None:
    """The GPL/MIT position is a position, not a settled conclusion (#495)."""
    text = (FIXTURE_DIR / "PROVENANCE.md").read_text(encoding="utf-8")
    assert "#495" in text
    assert re.search(r"GPL-3\.0-or-later", text)


def test_gitattributes_marks_wxf_binary() -> None:
    """Without this rule the fixtures are subject to EOL normalization."""
    attributes = (FIXTURE_DIR.parents[2] / ".gitattributes").read_text(encoding="utf-8")
    assert "*.wxf binary" in attributes
