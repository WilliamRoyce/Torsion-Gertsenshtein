# Stage-1 measurements — PSALTer install, Tier-1 gate, and the three probes

**Status:** Wave 0, issue #526. Records what was measured on the live install,
not what was expected from reading sources.

**Scope.** This document covers the install, the Tier-1 gate and the #521/#522/#523
probes. The §6 cost measurement on a PGT+EM theory is **Wave 2** and will be
appended here rather than replacing anything.

Companion documents: `stage1_engineering_plan.md` (the design this tests),
`docs/COSMOLOGY_PROGRAM.md` (the wave board).

<!-- cspell:words offscreen infy notfname indet icccm keysyms libxcb -->

## 1. Host and toolchain

| | |
|---|---|
| CPU | 12th Gen Intel Core i7-1260P — 4 physical cores, 8 logical |
| RAM | 12 GB |
| Kernel / distro | 6.6.87.2-microsoft-standard-WSL2 / Debian 12 (bookworm) |
| Wolfram Engine | 14.3.0, `$SystemID` `Linux-x86-64`, `wolframscript` 1.13.0 |
| xAct | 1.2.1 (xTensor, SymManipulator, xPerm, xCore, xTras, xCoba all present) |
| PSALTer | v2.0.2 at `bb45adb0fa21e467dbd88d4dc36ef21b84abbe6d` |
| Inkscape | 1.2.2 — installed by the optional step; **not required** (see §2.4) |
| `QT_QPA_PLATFORM` | `offscreen`, set by every script here (see §2.3) |

PSALTer's dependency list is exactly what xAct already provides, so **the install
is a directory copy**. It does **not** need `xAct`xPlain``, which retires one of
#521's stated worries: an option consumed indirectly through xPlain could not have
escaped a static read, because the package is never loaded. (xPlain is needed only
to run the *SupplementalMaterials-2607 driver scripts* verbatim; nothing in the
Tier-1 path uses it.)

## 2. Install

### 2.1 What was run

```bash
bash scripts/install-psalter.sh
bash scripts/verify-wolfram-setup.sh --require-psalter
```

`INSTALLED_COMMIT` in the installed tree records the resolved revision, the source
URL, the package version parsed from `PSALTer.m`, and when and by what it was
installed. The exporter reads PSALTer's private symbols, so this is a correctness
input rather than bookkeeping.

### 2.2 Verification, and watching it fail

All checks pass, exit 0. Both new failure paths were exercised rather than assumed:

| negative test | result |
|---|---|
| installed tree moved aside, `--require-psalter` | 1 failure, exit 1, remediation names `install-psalter.sh` |
| installed tree moved aside, no flag | warning only, exit 0, three consecutive runs |
| smoke test with an unloadable Qt platform plugin | hangs; `timeout` reports 124, which the check reports as a *hang* and not a failure |

### 2.3 The headless finding — corrected

**PSALTer exports a PDF through the Wolfram front end unconditionally and without
a time limit**, at `DefField` (`Sources/DefField.m:91` → `SummariseField.m:85`) as
well as at `ParticleSpectrum` (`ParticleSpectrum.m:82`). `$NoExport` does not guard
either. So the exposure begins at the *first field declaration*, seconds into a
run — on the published CTEG script, line 7 of 10.

The front end needs a Qt **platform plugin** whose shared libraries are all
present. When none can be initialized, Qt aborts the front-end process and the
export call **blocks indefinitely rather than failing**.

Measured, and then reproduced deliberately:

| configuration | result |
|---|---|
| as originally audited, `DISPLAY=:27` | "no Qt platform plugin could be initialized", `Aborted (core dumped)`, then **blocks** — a 20 s cap hit at 20.001 s, twice |
| `QT_QPA_PLATFORM=offscreen` | succeeds in **3.8 s** |
| forcing `QT_QPA_PLATFORM=xcb` (5 libraries still missing) | reproduces the abort exactly, then blocks to a 25 s cap |

Cause, established rather than inferred: of the nine platform plugins Wolfram
ships, `offscreen` was the only one with all its dependencies satisfied. `xcb` is
missing five libraries (`libxcb-cursor`, `-icccm`, `-image`, `-keysyms`,
`-render-util`) and still is; `wayland-egl` was missing `libwayland-egl1`.

**This corrects the amendment in `stage1_engineering_plan.md` §0.6/§8**, which
attributes the hang to `DISPLAY` being set. `DISPLAY` is why Qt attempts a GUI
platform at all, but it is not the cause: with the libraries present, the same
`DISPLAY=:27` works in ~1.2 s, and so does `DISPLAY` unset or pointed at a
non-existent socket.

**A hang, unlike an error, is the dangerous failure**: it consumes the
single-license Wolfram lane indefinitely and is indistinguishable from "PSALTer is
slow on this theory" — which is exactly the measurement the Wave-2 cost run
exists to make.

### 2.4 An accidental second fix, recorded so it is not mistaken for the first

The optional Inkscape step installs `libwayland-egl1` as a dependency, which makes
the `wayland-egl` plugin loadable and *also* fixes the hang. After running this
installer, the export works with or without the environment variable.

That is luck, not a guarantee: `--skip-inkscape`, a slimmer image or another
distribution puts you back at the hang. `QT_QPA_PLATFORM=offscreen` is the fix to
rely on, and every script here sets it. §0.6's conclusion that Inkscape is
"effectively unused" remains correct about PSALTer's own `$InkscapePath`.

### 2.5 Wolfram Engine crashes on shutdown, intermittently

A trivial one-line command, run three times: twice clean, once printing the
correct answer and then `Segmentation fault (core dumped)`. The crash is after the
work completes, so results are unaffected — but the exit status is not a reliable
signal, and neither is an exact capture of combined stdout+stderr.

Every check here therefore decides success from **what was produced**: the
expected file exists, the expected sentinel line is present. This also surfaced a
pre-existing flake in `verify-wolfram-setup.sh`, filed and fixed as **#541**.

## 3. Wall times

| run | theory | scale | wall time | terminated? |
|---|---|---|---|---|
| install verification | — | load + symbol check | ~40 s | yes |
| `DefField` smoke | one rank-1 field | trivial | ~35 s | yes |
| preflight | massive vector | 1 field, 3 couplings | **26.8 s** | yes |
| **Tier-1 gate** | **CTEG (PGT, 21 generators)** | **2 fields, 5 constants** | **407 s (6 m 47 s)** | **yes** |

**Go/no-go against the design's standard ("minutes are fine, hours are survivable"):
comfortably in the minutes regime.** A 21-generator PGT theory completes in under
seven minutes on four physical cores, so the ~1 h and ~8 h checkpoints never fired.
This is an encouraging input to the Wave-2 PGT+EM cost measurement, though not a
substitute for it — that theory adds a Maxwell sector and more couplings.

Note the run's exit status was **143**, on a run that produced correct artifacts.
That is why every check here judges success from what was produced rather than
from an exit code (§2.5, #541).

## 4. Tier-1 install gate

### 4.1 The one command

```bash
bash scripts/psalter/run_tier1_gate.sh
bash scripts/psalter/run_tier1_gate.sh --diff-only <run-dir>   # re-verify, no Wolfram lane
```

Artifacts in `third_party/psalter_runs/tier1-20260907T103755Z/`:
`tier1_diff.json` (machine-readable verdict), `tier1_summary.txt`, `manifest.json`,
`checkpoints.json`, `run.log`, `run.raw.log`.

`manifest.json` records the published script's sha256 **before and after** the run,
identical (`2232a103…`), so "run unmodified" is a checked fact.

### 4.2 Checkpoint trace

Obtained by timestamping PSALTer's own output — 18,436 stage events across 138
distinct functions, no instrumentation:

| stage | first entered |
|---|---|
| `DefFieldActual` | +9.3 s |
| `SummariseField` | +221.7 s |
| `ValidateLagrangian` | +251.5 s |
| `CombineAssociations` | +260.0 s |
| `ConstructLinearAction` | +294.7 s |
| `ConstructWaveOperator` | +294.7 s |
| `ConstructSourceConstraints` | +299.3 s |
| `ConstructSaturatedPropagator` | +314.7 s |
| `ConstructMassiveAnalysis` | +389.3 s |
| `ConstructMasslessAnalysis` | +389.7 s |
| `ConstructUnitarityConditions` | +401.8 s |
| `ConstructSpectrograph` | +401.9 s |

**Where the time goes:** ~72 % of the run (0 → 294 s) is field declaration and
decomposition — the rank-3 antisymmetric spin connection — and only ~113 s is the
spectrum analysis proper. Worth carrying into the Wave-2 cost estimate: adding
couplings to an existing field content is far cheaper than adding fields.

### 4.3 Verdict — MISMATCH, and it localizes sharply

| key | verdict |
|---|---|
| `WaveOperator` | **identical** — 3 sectors (4×4, 7×7, 3×3), 303 leaves, bit-exact |
| `PseudoDeterminant` | **all zeros** — correct 3×2 shape, every entry `0` |

The oracle's pseudo-determinants are non-trivial polynomials in `Def`, `Mu`,
`MuLambda`, `Nu` and `MPlanck2`; ours are `{{0,0},{0,0},{0,0}}`.

That `WaveOperator` is **bit-exact** is the useful half of this result: field
declaration, decomposition and wave-operator construction are all demonstrably
correct. The failure is downstream, and the trace shows where — a `Power::infy`
(division by zero) at +321.4 s inside `ConstructSaturatedPropagator`, becoming
`0·ComplexInfinity` → `Indeterminate` matrices, which then zero the
pseudo-determinants.

**Filed as #543. The gate was not relaxed and no workaround was applied.**

### 4.4 What was ruled out, by test rather than by argument

- **The two missing Wolfram Function Repository dependencies — refuted.** PSALTer
  calls `ResourceFunction["PolynomialDegree"]` and
  `ResourceFunction["LinearlyIndependent"]` at five sites and neither can be
  fetched here. I supplied both locally, on a throwaway copy of the install, and
  re-ran CTEG: **identical verdict, identical `Power::infy` cascade.** The
  hypothesis was tested and discarded rather than reported as a cause.
- **Subkernel availability.** `LaunchKernels[2]` and `ParallelEvaluate` both work.
- **Headless graphics.** Fixed and verified; the run completes and writes its `.mx`.

**Leading remaining hypothesis: the Wolfram version.** The oracle `.mx` header
decodes to **14.2**; we run **14.3**. Everything symbolic up to the wave operator
agrees exactly and the first divergence is a `1/0` in the inverse path, which fits
a behavioral change between releases. Testing it needs a 14.2 engine — an
environment decision, not one #526 can settle.

### 4.5 A separate defect found on the way

`PolynomialDegree` and `LinearlyIndependent` are downloaded from the Wolfram
Function Repository on first use and are declared in **no** README or install
instruction. When unavailable, PSALTer emits `ResourceObject::notfname` and
**carries on**, so `ValidateLagrangian`'s `NonQuadraticFields` check silently never
runs. `verify-wolfram-setup.sh` now checks both, so this is loud rather than
silent. Directly relevant to #522 (§6), and worth carrying back to the author (D6).

The Wolfram Cloud is unreachable from this container — 503 from
`www.wolframcloud.com` and 404 from the resource API, from both `curl` and Wolfram,
while GitHub returns 200.

### 4.6 The PDF eyeball check

Our `ParticleSpectrographCTEG.pdf` was produced (the headless export works), and is
kept in the run directory. Recorded, explicitly **not** a gate.

## 5. Probe #521 — `ParticleSpectrum` wall time, `Method` inert

**Answer: confirmed inert on the live install.** Reportable as
"`ParticleSpectrum` wall time, PSALTer v2.0.2 @ `bb45adb0`, `Method` inert" —
**never** as an Easy-vs-Hard comparison.

Subject: the smallest theory PSALTer will accept — one rank-0 scalar field, two
couplings — so that any timing difference would have to come from the option
rather than from the physics.

### Evidence

Searching the **installed tree** (not GitHub):

| symbol | `OptionValue@…` call sites |
|---|---|
| `Method` | **0** |
| `MaxLaurentDepth` | 5 |

Declared options are `{TheoryName -> False, MaxLaurentDepth -> 1, Neglect -> {},
MasslessSpectrum -> True, AspectRatio -> Landscape, ShowPropagator -> True,
Method -> "Easy"}`, so `Method` is declared and never read.

Three legs, not two:

| leg | wall time | result hash | `$Local*` hash |
|---|---|---|---|
| `Method -> "Easy"` | 34.37 s | `28e89668…` | identical |
| `Method -> "Hard"` | 30.62 s | `28e89668…` | identical |
| `Method -> "ThisValueMatchesNoBranch"` | 33.02 s | `28e89668…` | identical |

**The third leg is the decisive one and the handoff does not ask for it.** Easy and
Hard agreeing is weak evidence — two real code paths could coincide on a trivial
theory. A value matching *no* branch producing byte-identical output, identical
private globals, and an identical message list is near-conclusive that the option
is never consulted. The ~10 % timing spread is run-to-run noise, not two
algorithms.

### Consequence

The Wave-2 cost measurement is the cost of `ParticleSpectrum`, full stop. Passing
`Method -> "Hard"` remains harmless and correct if a later release wires it up,
which is why the finding is pinned to `bb45adb0`.

### Incidental, and load-bearing for #543

The same error cascade seen on CTEG appears here too — on a single scalar field.
So the fault behind #543 is **not** specific to a large theory or a degenerate
sector, and a ~30 s scalar run reproduces it. Recorded on #543 as a minimal
reproduction.

## 6. Probe #522 — the missing-coupling probe

**Answer: confirmed. PSALTer says nothing at all about a bare numeric
coefficient.** The "reject, never auto-assign" rule is entirely our validator's
job, which makes it load-bearing for correctness rather than a convenience.

### Which messages are actually thrown

Occurrences of each name in the installed tree — one means *defined but never
thrown*, two or more means a throw site exists:

| message | occurrences | thrown? |
|---|---|---|
| `Zero` | 2 | yes |
| `UnknownCoupling` | 2 | yes |
| `UnknownField` | 2 | yes |
| `NonQuadraticFields` | 2 | yes, **but see below** |
| `NonLinearCouplings` | **1** | **never** |
| `ParityOdd` | **1** | **never** |

This reproduces §0.2's table exactly, now on the live install.

**A caveat §0.2 could not have known:** `NonQuadraticFields` has a throw site, but
it is guarded by `ResourceFunction["PolynomialDegree"]`
(`ValidateLagrangian.m:38`), which cannot be fetched here (§4.5). So on this
install that check is *also* dead — a fourth silently-absent validation, and one
that would come back if the resource became available.

### Leg A — the bare numeric coefficient

Measuring silence needed care: this install emits a large ambient message cascade
on any theory whatsoever (#543), so `$MessageList === {}` is unusable. Instead the
same operator was run twice — once with a declared coupling as a **control**, once
with a bare number — and the message sets compared:

| | control (`-1/4 θ₁ ∂A∂A`) | bare (`-1/4 ∂A∂A`) |
|---|---|---|
| distinct messages | 23 | 23 |
| messages only in the bare run | — | **none** |
| wrote its `.mx` | — | yes |

**`messages_only_in_bare = {}`.** PSALTer raises nothing whatever about the
missing coupling and proceeds to a result. Expected outcome recorded as a measured
fact.

### Leg B — a genuinely undeclared symbol

This *does* throw, and the wording our own hint should echo is:

```
ParticleSpectrum::UnknownCoupling:
  The Lagrangian density contains a symbol `1` which was not defined
  using DefConstantSymbol.
```

rendered as: *"The Lagrangian density contains a symbol UndeclaredCoupling which
was not defined using DefConstantSymbol."* PSALTer then aborts via `Throw`.

## 7. Probe #523 — the harvest surface

**Answer: the association carries exactly two keys, there are eight `$Local*`
globals — and the exporter's six-item input surface is WRONG on both of its
implicit justifications.**

### Confirmed

| | measured |
|---|---|
| association keys | **2** — `WaveOperator`, `PseudoDeterminant` |
| `$Local*` globals | **8** |

So §0.4's eight is what exists, exactly as documented.

### Overturned — this is the loud finding

§5's six-item exporter input surface omits `$LocalWaveOperator` and
`$LocalPropagator`. The handoff's reading (which I shared) was that this is not a
contradiction but a justified subset: the wave operator being redundant with the
association key, and the propagator being display-only and suppressed by
`ShowPropagator -> False`, which is what the published CTEG script passes.

**Both justifications fail on the live install**, and identically with the
propagator display on and off:

| test | result |
|---|---|
| `assoc[WaveOperator] === $LocalWaveOperator` | **False** |
| `$LocalPropagator` populated under `ShowPropagator -> False` | **True** (35 leaves) |

`$LocalWaveOperator` (49 leaves) is **not** the same object as the association's
`WaveOperator`, so dropping it discards information rather than avoiding
duplication. And `$LocalPropagator` is populated regardless of the display option,
so "display-only, and switched off anyway" is not true either.

**Consequence for #527/#495:** the Stage-1 exporter must read all **eight**
globals, and `stage1_engineering_plan.md` §5's list needs correcting at the
instruction site. Amended there, pinned to `bb45adb0`.

## 8. Findings checked against §0.1–§0.6

The point of this session was to check the study's static source reading against a
running install. Scorecard:

| § | finding | verdict | evidence |
|---|---|---|---|
| 0.1 | `Method` is a dead option | **confirmed** | 0 `OptionValue@Method` sites; three legs byte-identical, including a nonsense value (§5) |
| 0.2 | PSALTer does not enforce coupling-linearity | **confirmed, and worse** | no extra message vs a declared-coupling control; and `NonQuadraticFields` is *also* dead here because its guard needs an unavailable resource (§6) |
| 0.3 | the TorC input and a result oracle are both published | **confirmed** | both fetched at pinned revisions; the oracle loads on 14.3 despite being written by 14.2 |
| 0.4 | two association keys, eight `$Local*` globals | **confirmed** | measured live: 2 and 8 (§7) |
| 0.5 | both linearization architectures are documented | **not tested** | out of scope for Wave 0 |
| 0.6 | Inkscape unused; headless export is "one live check" | **overturned** | it hangs rather than failing, from `DefField` onward, and the cause is the Qt platform plugin rather than `DISPLAY` (§2.3). Inkscape is unused by PSALTer but fixes the hang by accident (§2.4) |
| §5 | the exporter's six-item input surface | **overturned** | both justifications for omitting two globals fail (§7) |
| §6 | build timestamped stage checkpoints | **unnecessary** | PSALTer already emits them (§4.2) |

Two of the study's positions were overturned and one more shown to be
unnecessary — which is what a first contact with a live install is for.

## 9. Amendments made at instruction sites

Per the flaw protocol, each correction lives where the instruction lives, pinned
to PSALTer `bb45adb0`:

| file | section | what changed |
|---|---|---|
| `stage1_engineering_plan.md` | §0.6 | extended: exposure starts at `DefField`; the cause is the platform plugin, not `DISPLAY` |
| `stage1_engineering_plan.md` | §5 | the six-item exporter input surface is wrong; must be eight |
| `stage1_engineering_plan.md` | §6 | the checkpoint machinery does not need building |
| `stage1_engineering_plan.md` | §8 | risk row corrected to name the real cause |
| `scripts/research/psalter_stage1/README.md`, `fetch_reference_sources.sh` | — | "commit the route, not the payload" qualified with its one deliberate exception |

## 10. Routed to the orchestrator

Things found here that belong to someone else:

1. **#543 — the Tier-1 mismatch is unresolved and blocks certification.** Leading
   hypothesis is the Wolfram version (oracle 14.2, engine 14.3). Testing it needs a
   14.2 engine: an environment decision. A ~30 s scalar run reproduces it, so it is
   cheap to bisect. **The install is not certified by Tier 1.**
2. **`QT_QPA_PLATFORM=offscreen` belongs in `tidalcosmo/derive/wolfram_driver.py`**
   (Wave 1), beside the engine-idle guard — the chokepoint that will actually
   launch kernels. It is in the scripts here deliberately, not container-wide.
3. **PSALTer's two undocumented Wolfram Function Repository dependencies** are worth
   carrying back to the author (D6 relationship): they fail silently and disable
   validation the design relies on.
4. **`tests_cosmo/` has no `per-file-ignores` entry in ruff** while `tests/` does, so
   the new suite is linted strictly. That may be intentional; `pyproject.toml`
   belongs to I-524, so it was not changed.
5. **`#541`** — the pre-existing flaky activation check, fixed here.
6. **`#495`** — the two committed `.wxf` fixtures are flagged for the release-time
   license review.
7. **`scripts/install-xact-xcoba.sh:84`** runs `sudo apt-get update -qq` bare under
   `set -e`, so a transient mirror failure aborts that installer. Not fixed here —
   it is another issue's file. One-line change.
