# Tier-1 gate evidence — 2026-09-07 (#543)

The measurements behind the **MISMATCH** verdict recorded in
`docs/cosmology/stage1_measurements.md` §4 and decided on in
`docs/COSMOLOGY_PROGRAM.md` §"Decision on #543".

Committed because this verdict is the basis of a live decision — it is going to the
11 September supervisor conversation, and it blocks certification of the PSALTer install.
It was produced in a delegate worktree under a **gitignored** path, so removing that
worktree would have destroyed the evidence behind a conclusion the programme is carrying.
26 KB is a cheap price for that not being true.

| file | what it is |
| --- | --- |
| `tier1_diff.json` | the key-by-key diff against the author's committed `.mx` — the verdict itself |
| `checkpoints.json` | the 12-stage trace with timings; locates the first `Power::infy` at +321 s |
| `tier1_summary.txt` | human-readable summary of the same |
| `manifest.json` | what was run, against which revision |
| `diff.log` | the diff step's own output |

**Not committed**, and kept only in the gitignored `third_party/psalter_runs/` copy:
`run.log` and `run.raw.log` (2.7 MB combined), the generated `.mx`, and the spectrograph
PDFs. Reproducible in ~7 minutes by the full gate, and the `.mx`/PDFs are run *outputs*
whose license position is covered by the note on #495.

## Reproducing

- **Re-verify from these artifacts**, without spending the single-license Wolfram lane:
  `scripts/psalter/run_tier1_gate.sh --diff-only`
- **Regenerate from scratch** (~7 min, occupies the lane): the same script with no flag.

## What the verdict says

`WaveOperator` bit-exact (3 sectors, 303 leaves); `PseudoDeterminant` all zeros, from a
`1/0` inside `ConstructSaturatedPropagator`. **And the damage is not confined to the
residue path** — `$LocalSourceConstraints` measures `{}` against 21 expected for CTEG's
formulation, so the Schur route's gauge-mode removal is degraded too. Both criteria are
affected; see the correction in `COSMOLOGY_PROGRAM.md`.
