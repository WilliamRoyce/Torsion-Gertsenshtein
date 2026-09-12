# Tier-1 gate evidence — 2026-09-11, PASS (#543)

The measurements behind the **MATCH** verdict that certifies the PSALTer install, recorded in
`docs/cosmology/stage1_measurements.md` §4.4 and §4.8 and reached by the I-543 session. The
failing run it supersedes as *the* install verdict stays at `../tier1-20260907/`; both are the
record, and nothing there was written to.

| file | what it is |
| --- | --- |
| `tier1_diff.json` | the key-by-key diff against the author's committed `.mx` — the verdict: `match`, tally `{identical: 2}` |
| `checkpoints.json` | the 12-stage trace with timings; no `Power::infy` anywhere in the run |
| `tier1_summary.txt` | human-readable summary of the same |
| `manifest.json` | what was run, against which revision; `psalter_capabilities_degraded: false` |
| `diff.log` | the diff step's own output |

**Not committed** (gitignored `third_party/psalter_runs/tier1-20260911T151115Z/`, the run on the final registration; an earlier pass at `tier1-20260911T144346Z/` used a registration that referenced the paclet symbol rather than carrying its definition): `run.log`,
`run.raw.log`, the generated `.mx`, the spectrograph PDFs. Reproducible in ~8 minutes by the full
gate on the configuration below.

## The certified configuration

| leg | value |
| --- | --- |
| engine | Wolfram Engine **14.3.0** for Linux x86 (64-bit), July 31, 2025 (`tier1_diff.json` → `environment`) |
| PSALTer | v2.0.2 @ `bb45adb0fa21e467dbd88d4dc36ef21b84abbe6d` (`INSTALLED_COMMIT`, unchanged) |
| xAct | xAct **1.3.0** bundle (xCore 0.6.10, xPerm 1.2.4, xTensor 1.3.0 of 2025-12-29, xCoba 0.8.6 — measured from the installed `.m` headers 2026-09-11; the earlier "1.2.1" was a label copied from `install-xact-xcoba.sh`'s default and was wrong) |
| oracle | `SupplementalMaterials-2506b` @ `37c86a5d`, `ParticleSpectrographCTEG.mx` sha256 `07a8cd59…412b4`; the published `.m` run unmodified (sha256 `2232a103…5825` before and after) |
| **resource handling** | PSALTer's two undocumented Function Repository dependencies registered locally from genuine code by `scripts/psalter/register_resources.wl`: `LinearlyIndependent` = Wolfram's `ResourceFunctionHelpers` paclet file (1.3.34; `Kernel/LinearlyIndependent.wl` sha256 `7bc228a2…b817`) loaded verbatim under a private package name so the object carries the full definition; `PolynomialDegree` = the author's definition evaluated verbatim from the repository's definition notebook (sha256 `c233e226…787c`). Registered UUIDs at certification: `d40a8dd6-658c-47d2-8719-2f5fc8e1f83d`, `2f89f2e6-7bc8-4491-84bf-d8e13c69addb`. Resolved on the master and on subkernels; checked by `verify-wolfram-setup.sh` check 10 on both. |
| headless | `QT_QPA_PLATFORM=offscreen` |

Why this leg exists, in one line: without those two functions PSALTer completes and writes a
wrong spectrum (empty source constraints, zero pseudo-determinants — the 2026-09-07 verdict);
the Function Repository served no definitions to this machine during the session (#551).

## Reproducing

- **Read the verdict back from these artifacts** — no Wolfram, no lane, nothing written:

  ```bash
  python3 scripts/psalter/summarize_diff.py \
      docs/cosmology/evidence/tier1-20260911-pass/tier1_diff.json
  ```

  Exit 0 here (and only here) means `match`. Since 2026-09-11 it also **refuses** (`REFUSED`,
  exit 1) an artifact whose `environment.wolfram_version` is not `EXPECTED_WOLFRAM_VERSION`
  (14.3.0); `../tier1-20260911-engine-142/summary_refused.txt` is that refusal firing.

- **Recompute the verdict** — `--diff-only` needs the run's own `.mx`, which this directory does
  not carry. **`../tier1-20260911-recert/ours.mx` does**: an independent re-run of this gate the
  same day (`20:19:19Z` vs this one's `15:11:15Z`), from a clean run directory and an *empty*
  registry, whose `tier1_diff.json` differs from the one here in `generated_utc` and nothing
  else. That directory documents the recompute; never point `--diff-only` at a directory under
  `docs/` — it writes its output there, and doing so once destroyed this evidence (#544).

- **Regenerate from scratch** (~8 min on the lane):

  ```bash
  bash scripts/psalter/ensure_registered.sh      # idempotent; exits non-zero on any failure
  bash scripts/psalter/run_tier1_gate.sh         # writes third_party/psalter_runs/tier1-<stamp>/
  ```

  `ensure_registered.sh` registers the two resources under the **fixed UUIDs** recorded above,
  from the engine-bundled (or userbase) `LinearlyIndependent.wl` and the committed definition
  notebook (`scripts/psalter/resources/`, both sha256-asserted), then runs
  `verify-wolfram-setup.sh --require-psalter`, whose check 10 asserts **provenance** — those
  UUIDs resolved on the master *and* on a subkernel — not merely that the two functions behave.
  Behavior alone was what this run's check asserted, and a resource fetched from the repository
  would also have behaved: a rebuild could have produced a green gate on an uncertified leg.
  `install-psalter.sh` calls it as a required step; re-run it after a container rebuild
  (the `wolfram-objects` volume, #559, is what stops a rebuild losing the registry at all).

## Independent of the cloud login, and of the engine minor version

Asserted 2026-09-11 with the cloud reachable, both ways: logged in (the harder case — a
logged-in kernel has a third resolution leg, which cannot preempt a registered name because
by-name lookup is local-first and short-circuits, `ResourceSystemClient` 1.26.1 `Path.m:29-42`,
`FindResource.m:23-34`) and logged out (`WOLFRAMSCRIPT_AUTHENTICATIONPATH` at an empty
directory: `$CloudConnected` False, the same two UUIDs, `verify --require-psalter` exit 0).
Nobody's Wolfram ID is logged out for this — it lives in the user's own home mounts, never in
the repo, and the pipeline never uses it. Do **not** simulate logged-out with `CloudDisconnect[]`:
measured here, it deletes the userbase `Authentication/RecentUser/` record. 14.2.1 gave the same
verdict on the same input (`../tier1-20260911-engine-142/`), so the engine was never the cause.

**The one failure mode nothing prevents:** the resolver silently unregisters a name whose stored
object fails `ResourceObjectQ` (`FindResource.m:76-83`) and falls through to the repository.
The provenance assertion cannot stop that — it makes it impossible to miss (a foreign
resolution reports the repository's UUID, measured as `b9d713ba-…` for `PolynomialDegree`, whose
function then returned `$Failed`). Repair: `bash scripts/psalter/ensure_registered.sh`.

## What the verdict says, and what it does not

Both keys identical to the author's: `WaveOperator` (3 sectors, 303 leaves) and
`PseudoDeterminant` (3×2, 71 leaves — e.g. `(-2 (1 + 2 Def^2) MPlanck2)/3`, where the failing
run had `0`). Tier 1 certifies exactly those two keys. Beyond the gate, the same configuration
gave: source constraints populated for CTEG (`$LocalSourceConstraints` dims `{3, 7}`: seven
irreducible constraint rows with multiplicities `2J+1 = {1, 1, 3, 3, 3, 5, 5}`, **summing to the
21 generators** of the formulation — the number the failing run had as 0; the same on 14.2.1); the render `ParticleSpectrographCTEG.pdf` with **0 `Indeterminate`, 0 `$Failed`** and a
real "Resolved unitarity condition(s)" line (`pdftotext`; the failing render had 296 and 12); and
the known-answer ladder `scripts/psalter/repro_543.wl` passing on every rung (cubic control throws
`NonQuadraticFields`; Maxwell identifies its constraint three runs out of three; scalar, Proca and
Fierz–Pauli match their published results).

Licensing position for run outputs is unchanged from the note on #495.
