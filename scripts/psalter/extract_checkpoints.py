"""Turn a stamped PSALTer run log into a machine-readable stage trace.

Reads the output of ``stamp_lines.py`` and reports, for each PSALTer internal
function, when it was first entered and how many times it was entered. That is
the checkpoint trace the Tier-1 gate records -- and it is obtained purely by
watching the process's own output, so the published script stays unmodified.

The lines being matched are emitted by PSALTer itself, one per function entry in
CLI mode. They arrive as ``-e <ESC>[1;34;40m<name><ESC>[0m``: the leading ``-e``
is upstream's, because ``Run`` invokes ``/bin/sh``, whose ``echo`` does not take
``-e`` and prints it literally.

Usage:
    python3 extract_checkpoints.py run.log > checkpoints.json
"""

from __future__ import annotations

import argparse
import json
import operator
import re
import sys

# "<stamp> +<elapsed> [-e ]ESC[1;34;40m<name>ESC[0m"
STAGE_RE = re.compile(
    rb"^(?P<stamp>\S+)\s+\+(?P<elapsed>[\d.]+)\s+(?:-e\s+)?"
    rb"\x1b\[1;34;40m(?P<name>[^\x1b]+)\x1b\[0m\s*$"
)

# PSALTer's own stage boundaries, in the order ParticleSpectrum calls them
# (Sources/ParticleSpectrum.m). Reported separately so the headline trace is the
# seven heavy stages rather than several thousand internal calls.
MAJOR_STAGES = (
    "DefFieldActual",
    "SummariseField",
    "ValidateLagrangian",
    "CombineAssociations",
    "ConstructLinearAction",
    "ConstructWaveOperator",
    "ConstructSourceConstraints",
    "ConstructSaturatedPropagator",
    "ConstructMassiveAnalysis",
    "ConstructMasslessAnalysis",
    "ConstructUnitarityConditions",
    "ConstructSpectrograph",
)


def short_name(qualified: str) -> str:
    """Drop the context, so `xAct`PSALTer`Private`Foo` reads as `Foo`."""
    return qualified.rsplit("`", 1)[-1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", help="stamped log from stamp_lines.py")
    args = parser.parse_args()

    first_seen: dict[str, float] = {}
    counts: dict[str, int] = {}
    total = 0

    with open(args.log, "rb") as handle:
        for raw in handle:
            match = STAGE_RE.match(raw.rstrip(b"\r\n"))
            if match is None:
                continue
            total += 1
            name = short_name(match.group("name").decode("utf-8", "replace").strip())
            elapsed = float(match.group("elapsed"))
            counts[name] = counts.get(name, 0) + 1
            first_seen.setdefault(name, elapsed)

    report = {
        "stage_event_count": total,
        "distinct_functions": len(first_seen),
        # The headline: the documented stage boundaries, in call order, with the
        # offset at which each was first entered.
        "major_stage_first_seen_s": {
            stage: first_seen[stage] for stage in MAJOR_STAGES if stage in first_seen
        },
        "major_stages_not_reached": [s for s in MAJOR_STAGES if s not in first_seen],
        "all_first_seen_s": dict(
            sorted(first_seen.items(), key=operator.itemgetter(1))
        ),
        "call_counts": dict(sorted(counts.items(), key=lambda kv: -kv[1])),
    }
    json.dump(report, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
