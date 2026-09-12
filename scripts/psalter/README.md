# `scripts/psalter/` — the PSALTer Tier-1 install gate

Verifies a PSALTer install by reproducing the author's own published result, and
records the evidence so the verdict can be re-checked without re-running anything.

Added by #526. Deliberately outside `tests/wolfram/test_*.wls`, which
`scripts/run_wolfram_tests.sh` picks up by glob and which must stay fast.

## The one command

```bash
bash scripts/psalter/run_tier1_gate.sh
```

Exit 0 means the verdict was `match`. Everything lands in a timestamped directory
under `third_party/psalter_runs/` (gitignored), with `tier1_diff.json` as the
machine-readable verdict and `tier1_summary.txt` as the human one.

To re-verify an existing run without spending the Wolfram lane again:

```bash
bash scripts/psalter/run_tier1_gate.sh --diff-only third_party/psalter_runs/tier1-<stamp>
```

## Why *this* is the install gate

Both sides are the author's: his published input script
(`ParticleSpectrographCTEG.m`) and his published result file
(`ParticleSpectrographCTEG.mx`), both fetched at pinned revisions. **So a mismatch
can only be our install.** A check that mixed his input with our own physics could
not localize a failure, which is why the physics checks are a separate, later tier
and are not run here.

The published script is run **in place and unmodified** — never copied, never
edited. `manifest.json` records its sha256 before and after the run, so
"unmodified" is a checkable fact rather than a claim.

## How the verdict is decided

Per key, cheapest first: exact structural equality, then equality of a
canonicalized form, then a time-limited proof that the difference is zero.

That last step is **three-valued, not yes/no**. `Simplify` is incomplete, so
"proved equal", "proved different" and "could not decide" are three different
facts, and collapsing the last two into a pass would void the gate's whole
justification. An undecided comparison is a blocking flag carrying the expression
that defeated it. Which keys needed the fallback is recorded: if many did, that is
a finding about canonicalization, not a clean pass.

A checksum is a fast path and a fingerprint, never the verdict — two equal
expressions can serialize differently.

`verdict` distinguishes `oracle_unreadable` from `mismatch`. The published result
file is a version-sensitive binary dump written by Wolfram 14.2; if it will not
load, the gate *could not be run*, which is a different fact from the install
being wrong. That case is checked first, in seconds, before anything expensive.

## The checkpoint trace is free

PSALTer announces each internal function as it is entered, whenever it runs
without a notebook front end. So the gate does not instrument anything: it
timestamps the process's own output (`stamp_lines.py`) and extracts the stage
boundaries afterwards (`extract_checkpoints.py`). Nothing is injected and no
symbol is redefined, which is how the run can be both traced and unmodified.

`--checkpoint-at` additionally takes liveness snapshots (elapsed, %CPU, RSS, last
stage reached) at the given offsets, so "still running after N hours" becomes a
reportable fact. Default `3600,28800`.

## `QT_QPA_PLATFORM=offscreen` is mandatory

PSALTer exports a PDF through the Wolfram front end every time a field is
declared, and again for the spectrograph. Neither call is guarded or
time-limited. When no Qt platform plugin can be initialized, the front end aborts
and the export **blocks indefinitely** rather than failing — inside a long run
that is indistinguishable from PSALTer being slow, and it holds the single-license
Wolfram lane open forever. Every script here sets the variable itself.

## Files

> **Before any run on a fresh container:** `wolframscript -file scripts/psalter/register_resources.wl`.
> Without it PSALTer does not fail — it completes and writes a **silently wrong** spectrum
> (empty source constraints, zero pseudo-determinants), which is what #543 turned out to be.
> `bash scripts/verify-wolfram-setup.sh --require-psalter` exits **1** when they are missing or
> resolve to anything but the certified identities (it was exit 2 before the #549 routing was
> reversed for this check; the gate refuses on 1 and proceeds on 2).

| file | what it does |
| --- | --- |
| `run_tier1_gate.sh` | the one command; orchestrates everything below |
| `vector_smoke.wls` | preflight on a small theory, before the expensive run |
| `tier1_diff.wls` | loads both result files and produces `tier1_diff.json` |
| `stamp_lines.py` | timestamps the run's output stream |
| `extract_checkpoints.py` | run log → stage trace |
| `summarize_diff.py` | artifact → human summary; the single place the exit code is derived |
| `probe_521_method.wls` | is `Method` inert? (#521) |
| `probe_522_couplings.wls` | is a bare numeric coefficient rejected? (#522) |
| `probe_523_harvest.wls` | what must the exporter read? (#523) |
| `ensure_registered.sh` | **the one to run**: registers (below) and verifies; exits non-zero on any failure. Called by `install-psalter.sh` and the devcontainer's `postCreateCommand` |
| `register_resources.wl` | registers the two Function Repository resources PSALTer needs and never declares (#543) with **fixed certified identities**, from the engine-bundled `LinearlyIndependent.wl` (sha256-asserted) and the committed `resources/PolynomialDegree-1-0-0-definition.nb`. **Required before the gate, and again after every container rebuild** — the registry lives in the container overlay. Idempotent; takes the lane for ~1 min; never edits PSALTer |
| `repro_543.wl` | the known-answer ladder behind #543 — scalar, Proca, Fierz–Pauli, CTEG — each rung's expected result stated in the file, so a failure is decidable without an oracle |

The probes need only a working install, not a passing gate, and each writes a
transcript prefixed `PROBE5xx` for the measurements record.

## Reference sources are fetched, never committed

PSALTer and the supplemental materials are GPL-3.0-or-later and this repository is
MIT, so the route is committed and the payload is not; the gate invokes
`scripts/research/psalter_stage1/fetch_reference_sources.sh` when needed. The one
deliberate exception is the two small `.wxf` fixtures under
`tests_cosmo/fixtures/psalter/` — see that directory's `PROVENANCE.md`.
