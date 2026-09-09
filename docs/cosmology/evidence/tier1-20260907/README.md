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

- **Read the verdict back from these artifacts** — no Wolfram, no lane, nothing written:

  ```bash
  python3 scripts/psalter/summarize_diff.py \
      docs/cosmology/evidence/tier1-20260907/tier1_diff.json
  ```

  It re-derives the summary and the exit code (0 only for `match`) from the committed
  JSON, so it is the right command for anyone checking the recorded result.

- **Recompute the comparison** from the two `.mx` files: `run_tier1_gate.sh --diff-only
  <run-dir>`. This needs the run's own `ParticleSpectrographCTEG.mx`, which is
  **deliberately not committed here**, so point it at a `third_party/psalter_runs/`
  directory — not at this one. Given a directory without the `.mx` the script now
  refuses and says so; it used to overwrite `tier1_diff.json` with an
  `ours_unreadable` artifact, i.e. destroy the very evidence it was asked to check.

- **Regenerate from scratch** (~7 min, occupies the lane): the same script with no flags.

## What the verdict says

`WaveOperator` bit-exact (3 sectors, 303 leaves); `PseudoDeterminant` all zeros, from a
`1/0` inside `ConstructSaturatedPropagator`. **And the damage is not confined to the
residue path** — `$LocalSourceConstraints` measures `{}` against 21 expected for CTEG's
formulation, so the Schur route's gauge-mode removal is degraded too. Both criteria are
affected; see the correction in `COSMOLOGY_PROGRAM.md`.

## Reproduced independently, 2026-09-09

The orchestrator re-ran the gate from scratch (`third_party/psalter_runs/tier1-20260909T132651Z`,
gitignored) and got the **same verdict, the same tally, the same per-entry outcomes and the
same bit-exact `WaveOperator`** — against the same `oracle_sha256`, with the published script
unmodified. Wall 302 s against this run's 407 s; process exit status 0 against this run's 143,
which confirms the shutdown segfault is intermittent and carries no information about the
result.

So the MISMATCH recorded here is a reproducible property of the configuration, not an artifact
of one session. Details in `docs/cosmology/stage1_measurements.md` §4.7.

Note that this re-run was only possible after #549: the gate had refused to start since 66
seconds after the run recorded here, because an unavailable optional resource was routed as a
broken install. Nothing in this directory was written to by either the failed attempt or the
successful re-run — a read-back path never recomputes (#544).
