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

### 4.4 What was ruled out — and the ruling-out withdrawn (I-543, 2026-09-11)

> **Amendment (I-543, 2026-09-11; PSALTer v2.0.2 @ `bb45adb0`, Wolfram 14.3.0).** The first
> bullet below, as originally written, was wrong: the "test" did not discriminate. Its
> `PolynomialDegree` substitute was `Exponent[expr, vars]`, which returns a *list* for a list of
> variables, so `list > 2` stays unevaluated and `If` takes no branch — exactly what the missing
> resource does (#556, executed: `Exponent[a^2 b, {a,b}]` → `{2,1}`; a cubic passes untouched).
> Its `LinearlyIndependent` substitute lived in a master-side copy of the install, while
> `IsNullVectorOfSpace` runs on subkernels that `ParallelNeeds` the pinned package from their
> own `$Path`. "Identical verdict, identical cascade" was the expected outcome of a control that
> changed nothing at either site. The hypothesis it claimed to discard is the cause.

- ~~**The two missing Wolfram Function Repository dependencies — refuted.**~~ **They are the
  cause.** PSALTer calls `ResourceFunction["LinearlyIndependent"]` at `SymbolicNullSpace.m:31`
  (master) and `IsNullVectorOfSpace.m:6` (subkernels), and `ResourceFunction["PolynomialDegree"]`
  at `ValidateLagrangian.m:38` and `UnresolvedPoleRow.m:11,21`. On this machine they never
  resolved. An unresolved or `$Failed` `ResourceFunction` is not a Boolean, so `And[…]` never
  becomes `True` and the `If` that appends to `CommonNullVectors` takes neither branch. Every
  `SymbolicNullSpace` therefore returns `{}` — both CTEG runs' `checkpoints.json` show
  `CommonNullVector` 53–58 calls and `IsNullVectorOfSpace` 434–480 calls (candidates existed)
  with `CleanNullVector`/`EnsureLinearInCouplings`, which run only on *surviving* null vectors,
  never called. `$LocalSourceConstraints` is then `{}` (§4.4a), and in `ConjectureInverse` the
  same `{}` becomes the all-zero placeholder null space of `ManualPseudoInverse.m:27-31`, a zero
  compensator, and `Det[TheInputMatrix + 0] = 0` for every gauge-singular block; the division
  `AdjugateMatrix/DeterminantSymbolicValue` at `UnmakeSymbolic.m:75` is the first `Power::infy`
  (+244.32 s in the 2026-09-09 log, between the last `ConsolidateUnmakeSymbolic` and the first
  `ConsolidateFinalElement` trace lines), and every pseudo-determinant is `0`. One chain, both
  symptoms. `PSALTer.m:18-20` silences `Message` on subkernels, which is why nothing announced it.
- **Subkernel availability.** `LaunchKernels[2]` and `ParallelEvaluate` both work.
- **Headless graphics.** Fixed and verified; the run completes and writes its `.mx`.

~~**Leading remaining hypothesis: the Wolfram version.**~~ **Withdrawn.** The handoff's
version of it — "a behavioral change in built-in `NullSpace`/`Inverse`/`PseudoInverse`" — was a
substring count of PSALTer's own `ConjectureNullSpace`/`ManualPseudoInverse`: the tree has **no**
built-in `Inverse[]` or `PseudoInverse[]` and one built-in `NullSpace`
(`MinimalExampleCaseNullSpace.m:5`, on integer-substituted matrices). Every link of the chain
above was reproduced by execution independent of the engine. The engine is nevertheless
*measured* rather than assumed: §4.8 records the same ladder and gate on 14.2.1, the author's
tested version.

**What the genuine functions are.** `LinearlyIndependent` (Function Repository v3.0.0) is a
thin wrapper around `ResourceFunctionHelpers`LinearlyIndependent`, shipped by Wolfram in the
`ResourceFunctionHelpers` paclet (1.3.34) already installed in the userbase — the author's real
implementation was on this machine all along. `PolynomialDegree` (v1.0.0, Dennis M Schneider) is
six lines, obtained as the repository's own definition notebook (`PolynomialDegree-1-0-0-definition.nb`,
114,394 B, sha256 `c233e226d4c77de65ee19ddbc84c20c9724df467bb86c27f1a65f17fba89787c`) and
evaluated verbatim, never retyped. On symbolic input the genuine `LinearlyIndependent` returns a
`ConditionalExpression` (non-Boolean), but PSALTer never hands it one: `SymbolicNullSpace.m:8-23`
substitutes integers 1–9 for every variable of the block, `Def` included, before `NullSpace`.

**Resolution and its proof (behavior, not resolution — #556).** `scripts/psalter/register_resources.wl`
registers both as plain local resource objects in the shared registry (`~/.Wolfram/Objects`),
with the repository lookup disabled *inside that kernel only* so the local objects win the name
lookup and the shared name cache records them; nothing on disk disables the repository, and the
gate runs unmodified on the pinned install. Measured after registration: master and fresh
subkernels with the normal repository address return `{True, False, "appended", 3, "fired"}` on
PSALTer's call shapes; the **cubic control** (`scripts/psalter/repro_543.wl X`) makes
`ParticleSpectrum::NonQuadraticFields` throw on a cubic Lagrangian, where the same run on an
empty registry accepted it; **Maxwell** (`repro_543.wl G`, three runs) identifies its one source
constraint every time (`Dimensions[$LocalSourceConstraints] = {3, 1}`) with the 1⁻
pseudo-determinant `−Def²Θ₁/2`; the scalar, Proca and Fierz–Pauli rungs match their published
results (§4.8). Two undocumented, silently degrading dependencies were the install defect; "a
mismatch can only be the install" held as designed.

### 4.4a Does the failure spare the primary algorithm? Checked — no

> **Amendment (I-543, 2026-09-11):** the mechanism behind the `{}` below is now known
> (§4.4): it is the unresolved `LinearlyIndependent` on the subkernels, not a second defect. The
> conclusion of this subsection stands — both criteria were affected — and the readback after
> the resolution is in §4.8.

The natural narrowing is that the broken stage is the one the design already
demotes. `spectrum_design.md` §5 makes the Schur-complement criterion primary
precisely because it "does not involve any inversion of the wave operator nor the
computation of residues of the propagator at massive poles", and instructs that
the residue route be implemented "**never as a second production path**". Our
`1/0` is in `ConstructSaturatedPropagator`, which feeds the residue route. And the
Schur route's main input — the sector coefficient matrices — is exactly the
`WaveOperator` that came back bit-exact.

**But the Schur route has a second input, and it is also broken.** §5's caveat:
`O_LL` must be invertible, so gauge modes are removed first. Those come from
`ConstructSourceConstraints`, which ran at +299 s, *before* the first `Power::infy`
at +321 s — encouraging, and wrong. Measured by replaying the CTEG Lagrangian
without its trailing `Quit[]` and inspecting the private globals:

```
$LocalSourceConstraints   head=List  dims={0}    leaves=1     <- EMPTY
$LocalWaveOperator        head=List  dims={6,3}  leaves=438
$LocalPropagator          head=List  dims={6,3}  leaves=227
$LocalSpectrum            head=List  dims={6}    leaves=713
$LocalMasslessSpectrum    head=List  dims={6}    leaves=46
$LocalUnresolvedPoles     head=List  dims={8}    leaves=24
$LocalSummaryOfTheory     head=List  dims={2}    leaves=664
$LocalOverallUnitarity    head=Text  dims={1}    leaves=2
```

**`$LocalSourceConstraints` is `{}` — zero rows.** CTEG is the 21-generator
formulation (§0.3, §3), and §3 measures the gauge-generator count as exactly the
number of source-constraint rows. Zero is not a plausible answer for it.

There is no oracle for this key — the committed `.mx` carries only `WaveOperator`
and `PseudoDeterminant` — so this is measured against a *published count* rather
than a committed artifact, and it is weaker evidence than the Tier-1 diff. It is
nonetheless the expected value being 21 and the observed value being 0.

**Conclusion: the blast radius is not confined to the residue path.** The Schur
route's gauge-mode removal is degraded too, so #543 must be resolved before either
criterion can be trusted on this install. Recorded so the narrowing is not carried
forward as a partial certification.

**A limit on Tier 1 worth stating plainly:** the oracle contains two keys, so a
Tier-1 *pass* would certify the wave operator and the pseudo-determinants and
nothing else — not the source constraints, the spectrum, or the unitarity
conditions. Those need Tier 2/3, which is why §3 calls Tier 2 the physics gate.

### 4.5 The two dependencies, and the cloud

`PolynomialDegree` and `LinearlyIndependent` are downloaded from the Wolfram Function Repository
on first use and are declared in **no** README or install instruction. When unavailable, PSALTer
emits `ResourceObject::notfname` on the master (three times, for `PolynomialDegree`; the
subkernel-side `LinearlyIndependent` failures are silenced) and **carries on** — see §4.4 for
what that does to the spectrum. `verify-wolfram-setup.sh` check 10 now tests the two functions'
*behavior* on the master **and on a fresh subkernel** and refuses under `--require-psalter` when
they do not behave (the fix is one command, named in its message); the DEGRADED routing adopted
for #549 applied while the functions were merely unavailable, and is reversed now that they are a
certified leg of the configuration.

The cloud, measured rather than inferred (#551): 2026-09-07 → 09-09 a **global Wolfram Cloud
outage** — 503 with Wolfram's own maintenance page (`Retry-After: 3600`), identical from the host
browser and from an external fetcher; nothing container-side. 2026-09-11, primary services
restored, yet **the repository served no function definitions to anyone**: anonymous API
requests `302 → j_spring_oauth_security_check?statusCode=401`; an authenticated local kernel
(`$CloudConnected = True`) `ResourceFunction::lfail`, `DownloadedVersion -> None`; evaluation
inside the Wolfram Cloud (15.0.1) the same `$Failed`; control functions and older versions
identical; the resource system's own notebook download truncated (`libcurl error 18`). That is
why the certified leg is local registration of the genuine code rather than acquisition, and why
the registration must be re-run after a container rebuild (`~/.Wolfram/Objects` is not
bind-mounted) — routed to the orchestrator for `install-psalter.sh`.

### 4.6 The rendered spectrograph

Before the resolution, the render carried **296 `Indeterminate`**, **12 `$Failed`** and PSALTer's
"(Demonstrably impossible)" unitarity verdict (`pdftotext`, evidence README). After it — §4.8 —
the render is checked the same way, as a second observable of the same defect; still explicitly
**not** a gate.

### 4.7 Independent re-run — orchestrator, 2026-09-09

I-526's success criterion 2 required the orchestrator to re-run this gate **from scratch,
before Wave 1 is dispatched**, and the Wolfram-lane rule requires the same before the next
lane occupant starts. It was not done at the wave boundary, and **it could not have been**:
the gate could not be run at all, from 66 seconds after the run recorded above (#549, fixed in
`d6753631` — an unavailable optional resource was routed as a broken install). Attempting
the re-run is what found that.

Run: `third_party/psalter_runs/tier1-20260909T132651Z` (gitignored; the committed evidence
directory was not written to, verified with `git status`).

| | 2026-09-07 (delegate) | 2026-09-09 (orchestrator) |
|---|---|---|
| verdict | `mismatch` | **`mismatch`** |
| tally | `different` 5, `head_mismatch` 5, `identical` 1 | **identical tally** |
| `WaveOperator` | identical, 303 leaves | **identical, 303 leaves** |
| per-entry outcomes | — | **identical** |
| `used_simplify_fallback` | `[]` | `[]` |
| `oracle_sha256` | `07a8cd59…` | **same** |
| `script_unmodified` | true | true |
| engine | 14.3.0 (July 31, 2025) | same |
| wall | 407 s | **302 s** |
| process exit status | **143** | **0** |

`tier1_diff.json` of the re-run: `sha256 63a19679…4ac2d` (it differs from the committed
artifact only in run-scoped fields — timestamps and paths; every verdict-level field above is
equal).

**Two things this establishes.** The MISMATCH is **reproducible** — it is a property of this
configuration, not of one session's procedure or of a transient state, which is what an
independent re-run exists to decide, and it is now a firmer basis for the #543 conversation
than a single run was. And the **shutdown segfault is intermittent**: the same gate, on the
same verdict, exited 143 once and 0 the other time. That is the rule of §2.5 confirmed from
the other side — a `wolframscript` run's exit status carries no information about whether it
produced the right answer, in either direction.


### 4.8 Resolution and certification — I-543, 2026-09-11

With the two genuine functions registered (§4.4), the same gate, the same published script and
the same oracle:

| | 2026-09-07 / 09-09 (uncertified) | **2026-09-11, 14.3.0 (certified)** | 2026-09-11, 14.2.1 (cross-check) |
|---|---|---|---|
| verdict | `mismatch` | **`match`** — tally `{identical: 2}` (run `tier1-20260911T151115Z`, on the final registration) | _see below_ |
| `WaveOperator` | identical, 303 leaves | identical, 303 leaves | _see below_ |
| `PseudoDeterminant` | all `0` | **identical to the oracle**, 3×2, 71 leaves | the readback prints the same six expressions as 14.3.0 and the oracle |
| `$LocalSourceConstraints` | `{}` (0 generators) | dims `{3, 7}`: seven irreducible rows with `2J+1 = {1, 1, 3, 3, 3, 5, 5}`, **21 generators** — the published count, now measured | identical: `{3, 7}`, `{1, 1, 3, 3, 3, 5, 5}`, 21 |
| `Power::infy` in the run | at +321 s / +244 s | **none** | none in the readback run |
| render (`pdftotext`) | 296 `Indeterminate`, 12 `$Failed`, "(Demonstrably impossible)" | **0, 0, a real "Resolved unitarity condition(s)" line** | _see below_ |
| wall | 407 s / 302 s | 449 s | readback 453 s |
| exit status | 143 / 0 | 0 | _see below_ |

Ladder (`scripts/psalter/repro_543.wl`, 14.3.0): **X** cubic control PASS (throws
`NonQuadraticFields`; the same rung on an empty registry accepted the cubic — the negative
control); **G** Maxwell PASS ×3 (`{3, 1}` constraint rows, 1⁻ pseudo-determinant `−Def²Θ₁/2`);
**A** scalar PASS (pole `Def² = Θ₂/Θ₁`); **B** Proca PASS (both keys = the published 0⁺/1⁻
blocks — which also closes the #542 "missing mass term" note); **C** Fierz–Pauli PASS (`−3β²`,
`β`, `β − αDef²/2`, as the author's own spectrograph).

**Certified configuration:** engine 14.3.0 × PSALTer v2.0.2 @ `bb45adb0` × resource handling
as in §4.4 (registered by `register_resources.wl`; checked by `verify-wolfram-setup.sh`
check 10 on master and subkernel; `EXPECTED_WOLFRAM_VERSION=14.3.0`). Evidence:
`docs/cosmology/evidence/tier1-20260911-pass/`. The registry lives in `~/.Wolfram/Objects`
(container overlay, not bind-mounted): after a rebuild, run the registration once before the
gate — routed to the orchestrator for `install-psalter.sh`.

**14.2.1 cross-check (the author's tested version; installer needs `sudo`, contrary to the
handoff's assertion; installed side by side at `~/.local/wolfram/engine/14.2`, selected per
run with `WOLFRAMSCRIPT_KERNELPATH`; shared `mathpass` valid, xPerm's MathLink binary
connects):** the same registration behaves on 14.2.1 under PSALTer on master and subkernels
(`{True, False, "appended", 3}`; `{True, True, 3}`). **Ladder on 14.2.1: every rung PASS** —
X (cubic control throws), G ×3 (`{3, 1}` rows every run), A, B, C with the same values as
14.3.0. **CTEG readback on 14.2.1:** the same seven rows, the same multiplicities and 21
generators, and pseudo-determinant expressions identical to 14.3.0 and to the oracle. The
14.2.1 *gate* run is recorded separately below (its preflight is where the engines differ for
our tooling, not the physics).

**Tier 1 still certifies only the two keys.** The source-constraint count, the spectrum and
the unitarity conditions are Tier 2/3 (§3); the readback above is a measurement, not a
certification.

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
4. ~~`tests_cosmo/` has no `per-file-ignores` entry in ruff~~ — **not a gap; do not
   "fix" it.** Confirmed deliberate: `repo_reshape.md` §8 requires the new tree to
   start without a blanket, and I-524 deleted the entry cloned from `tests/`. New
   tests are meant to be linted strictly. The right response to a `D103` there is a
   docstring, not a per-file ignore. Recorded here because the asymmetry with
   `tests/` looks like an oversight and will keep being reported as one.
5. **`#541`** — the pre-existing flaky activation check, fixed here.
6. **`#495`** — the two committed `.wxf` fixtures are flagged for the release-time
   license review.
7. **`scripts/install-xact-xcoba.sh:84`** runs `sudo apt-get update -qq` bare under
   `set -e`, so a transient mirror failure aborts that installer. Not fixed here —
   it is another issue's file. One-line change.
