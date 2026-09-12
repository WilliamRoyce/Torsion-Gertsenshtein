"""Render a Tier-1 diff artifact as a human summary, and decide the exit code.

Single place the gate's pass/fail is derived, so a fresh run and a `--diff-only`
re-verification cannot disagree.

Only three per-entry statuses count as passing. `undecided_timeout` deliberately
does not: Simplify is incomplete, so "did not prove equal" and "proved different"
are different facts, and treating the former as a pass would manufacture one.

Usage:
    python3 summarize_diff.py tier1_diff.json [--quiet]
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Iterator

PASSING = ("identical", "equal_normalized", "equal_simplified")


def walk(entry: dict[str, Any], depth: int = 0) -> Iterator[tuple[int, dict[str, Any]]]:
    yield depth, entry
    for child in entry.get("children", []):
        yield from walk(child, depth + 1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    with open(args.artifact, encoding="utf-8") as handle:
        data = json.load(handle)

    verdict = data.get("verdict", "unknown")
    out: list[str] = []
    out.extend(("=" * 70, "PSALTer Tier-1 install gate", "=" * 70))
    env = data.get("environment", {})
    # Refuse a verdict produced by an engine other than the certified one. The gate
    # script records the engine in its manifest; the diff artifact records $Version.
    # A leftover WOLFRAMSCRIPT_KERNELPATH, or a PATH that reaches a different
    # wolframscript, would otherwise certify silently on the wrong engine.
    expected = os.environ.get("EXPECTED_WOLFRAM_VERSION", "14.3.0")
    got = str(env.get("wolfram_version", "")).split(" ")[0]
    if got != expected:
        print(
            f"REFUSED: this diff was produced by Wolfram {got or '<unknown>'}, not the "
            f"certified {expected} (set EXPECTED_WOLFRAM_VERSION to certify anew)"
        )
        return 1
    out.extend(
        (
            f"  theory        : {data.get('theory_name')}",
            f"  wolfram       : {env.get('version_number')} on {env.get('system_id')}",
            f"  generated     : {data.get('generated_utc')}",
            "",
        )
    )

    if data.get("keys_ours") is not None:
        out.extend(
            (
                f"  keys (ours)   : {data['keys_ours']}",
                f"  keys (oracle) : {data['keys_oracle']}",
            )
        )
        if data.get("keys_only_ours") or data.get("keys_only_oracle"):
            out.extend(
                (
                    f"  only ours     : {data['keys_only_ours']}",
                    f"  only oracle   : {data['keys_only_oracle']}",
                )
            )
        if data.get("context_mismatches"):
            out.append(
                f"  note          : keys matched by name across differing contexts: "
                f"{data['context_mismatches']}"
            )
        out.append("")

    entries = data.get("entries", [])
    if entries:
        out.extend(("  per-key comparison", "  " + "-" * 66))
        for entry in entries:
            for depth, node in walk(entry):
                path = ".".join(str(p) for p in node["path"])
                mark = "ok  " if node["status"] in PASSING else "FAIL"
                indent = "  " * depth
                ours = node.get("ours", {})
                extra = f"dims={ours.get('dimensions')} leaves={ours.get('leaf_count')}"
                out.append(f"  {mark} {indent}{path:<28} {node['status']:<20} {extra}")
                if node.get("detail"):
                    out.append(f"       {indent}{node['detail']}")
                for pos in node.get("differing_positions", [])[:5]:
                    out.extend(
                        (
                            f"       {indent}at {pos['position']}:",
                            f"       {indent}  ours   = {pos['ours']}",
                            f"       {indent}  oracle = {pos['oracle']}",
                        )
                    )
        out.append("")

    # A gate that needed the fallback everywhere is a finding about
    # canonicalization, not a clean pass, so surface it rather than burying it.
    fallback = data.get("used_simplify_fallback") or []
    if fallback:
        out.extend(
            (
                f"  NOTE: {len(fallback)} key(s) needed the Simplify fallback: {fallback}",
                "        Heavy fallback use is a canonicalization finding, not a clean pass.",
                "",
            )
        )

    if data.get("status_tally"):
        out.append(f"  tally         : {data['status_tally']}")
    out.extend(
        (
            f"  VERDICT       : {verdict.upper()}",
            f"  reason        : {data.get('verdict_reason', '')}",
            "=" * 70,
        )
    )

    if not args.quiet:
        print("\n".join(out))

    return 0 if verdict == "match" else 1


if __name__ == "__main__":
    sys.exit(main())
