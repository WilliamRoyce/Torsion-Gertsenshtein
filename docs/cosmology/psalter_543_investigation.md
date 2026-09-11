# PSALTer Tier-1 mismatch (#543): investigation record

**Status (2026-09-11):** cause located and reproduced by execution; the two undocumented
Function Repository dependencies are supplied from genuine code and proven live on master and
subkernels; ladder and gate results per engine are recorded in §6. The handoff `I-543.md` was
amended at the instruction site where its research items were refuted (§8).

This is the record the session was asked for: what is an assertion (executed, with the command
and its output), what is a hypothesis (with the test that decides it), and where each conclusion
is written into the instruction sites. Wolfram 14.3.0 (`14.3.0 for Linux x86 (64-bit) (July 31,
2025)`) unless stated; PSALTer v2.0.2 @ `bb45adb0`; xAct 1.2.1; one kernel at a time.

## 1. TL;DR

- Tier 1 replays the author's published CTEG input and diffs the two association keys against
  his committed `.mx`. `WaveOperator` is bit-exact; `PseudoDeterminant` is all zeros;
  `$LocalSourceConstraints` is `{}` against 21.
- **Cause:** PSALTer calls `ResourceFunction["LinearlyIndependent"]` and
  `ResourceFunction["PolynomialDegree"]` — two Wolfram Function Repository functions declared in
  no README or install instruction. On this machine they never resolved. An unresolved or
  `$Failed` `ResourceFunction` is not a Boolean, so the `If` that appends null vectors takes no
  branch; every null space comes back `{}`; the source-constraint list is empty; the compensator
  in `ManualPseudoInverse` is zero; `Det` of each gauge-singular block is exactly `0`; the
  division at `UnmakeSymbolic.m:75` produces `Power::infy`; every pseudo-determinant is `0`.
  Subkernel messages are silenced by `PSALTer.m:18-20`, so nothing announced it.
- **Not the cause:** the Wolfram version (the handoff's leading hypothesis). PSALTer has no
  built-in `Inverse[]`/`PseudoInverse[]` and one built-in `NullSpace` on numeric input; every
  link of the chain above was reproduced by execution independent of the engine.
- **Resolution route:** the genuine code, registered locally — `LinearlyIndependent` is a thin
  wrapper around `ResourceFunctionHelpers`LinearlyIndependent`, shipped by Wolfram in a paclet
  already installed; `PolynomialDegree` is the author's six-line definition evaluated verbatim
  from the repository's own definition notebook (sha256-pinned). The repository itself served no
  definitions to anyone during the session (global outage, then a server-side truncation even for
  an authenticated client and for in-cloud evaluation). Script: `scripts/psalter/register_resources.wl`.
- **Proof of behavior, not resolution (#556):** the cubic control — `ParticleSpectrum` on a
  cubic Lagrangian throws `ParticleSpectrum::NonQuadraticFields` with the resources registered
  and accepts it without them.

## 2. Assertions versus hypotheses

| claim | status | evidence |
|---|---|---|
| The tree has no built-in `Inverse[]`/`PseudoInverse[]`; one built-in `NullSpace` (`MinimalExampleCaseNullSpace.m:5`) | assertion | `grep -rn` over the installed tree; every other hit is `ConjectureNullSpace`/`ManualPseudoInverse` |
| First `Power::infy` is the division at `UnmakeSymbolic.m:75` | assertion | 2026-09-09 `run.log`: message at +244.32 s between the last `ConsolidateUnmakeSymbolic`/`GrabExpression`/`SimplifyIfSmall` trace lines (+244.29) and the first `ConsolidateFinalElement` (+244.36); the only division in that window |
| Every `SymbolicNullSpace` returned `{}` in both CTEG runs | assertion | `checkpoints.json` call counts: `CommonNullVector` 53–58, `IsNullVectorOfSpace` 434–480, `CleanNullVector`/`EnsureLinearInCouplings` (survivors only) **0** |
| Unresolved/`$Failed` `ResourceFunction` makes `If` take no branch | assertion | `If[{2,1} > 2, "fired", "not fired", "neither"]` → `"neither"`; `If[$Failed > 2, …]` → `"neither"`; `And[True, $Failed[…]]` stays non-Boolean (§4) |
| I-526's `PolynomialDegree` shim was inert at `ValidateLagrangian.m:38` | assertion | `Exponent[a^2 b, {a,b}]` → `{2,1}`; the shim's shape throws nothing on `{a^3 b, a b}` (#556) |
| I-526's `LinearlyIndependent` shim never reached subkernels | assertion (mechanism) | `CommonNullVector.m:10` submits `IsNullVectorOfSpace` via `NewParallelSubmit`; subkernels `ParallelNeeds` PSALTer from their own `$Path`; the shim lived in a master-side copy at `/tmp/i526-diagnostic` |
| The genuine `LinearlyIndependent` returns `ConditionalExpression` on symbolic input | assertion | `ResourceFunctionHelpers`LinearlyIndependent[{{1,2,0},{3,x,0}}]` → `ConditionalExpression[True, -6 + x != 0]` |
| PSALTer never hands it symbolic input | assertion | `SymbolicNullSpace.m:8-23` substitutes integers 1–9 for every variable (`Couplings = Variables[…]`, `Def` included); reproduced with the recipe on a symbolic block: candidates have `Variables = {}`, results `{True, False, False}` |
| README known bug 1 is the same endpoint reached sporadically | **hypothesis** | test: `$DiagnosticMode` on a healthy configuration, compare `MinimalExampleCaseNullSpaces` across draws for residual `Def` dependence (the toy run shows a `Def`-dependent candidate differs per draw and is never "common") |
| The engine version plays no role | assertion | §6: the same ladder passes and the same gate components give `match` with both keys identical on 14.2.1 |
| The repository served no definitions during the session | assertion | anonymous: API `302 → j_spring_oauth_security_check?statusCode=401`; authenticated kernel: `ResourceFunction::lfail`, `DownloadedVersion -> None`; in-cloud evaluation (15.0.1): `$Failed`; controls `BinarySearch`, `Nullity` and older versions identical; the notebook download via the resource system: `libcurl error (18): end of response with 26010 bytes missing`; Wolfram support page (updated Sep 10, 5:30 pm CDT) listing services unavailable |

## 3. Timeline of the cloud, because it shaped the session

2026-09-07 → 09-09: `www.wolframcloud.com` and the resource-system API returned 503 with
Wolfram's own maintenance page ("Scheduled Upgrade", later "Unscheduled Maintenance",
`Retry-After: 3600`), identical with a browser User-Agent, from the host browser and from an
external fetcher on unrelated infrastructure; `resources.wolframcloud.com` 404; `www.wolfram.com`,
`reference.wolfram.com`, `account.wolfram.com` 200 throughout. Container egress is an ordinary
residential IPv4 with no proxy variables; nothing to fix on our side (#551).

2026-09-11: primary services restored per Wolfram's notice. From the container: landing 200,
Function Repository pages 200, definition notebooks downloadable (200, complete). But no
definition was served by the resource system: see the last row of §2. The user's Wolfram-ID login
(`wolframscript -authenticate`, then an in-kernel `CloudConnect`) persists in fresh kernels
(`$CloudConnected = True`) and changed nothing about that.

## 4. Standalone reproductions outside PSALTer

All run with `wolframscript -file`, lane idle. The scratch-userbase mechanism
(`WOLFRAM_USERBASE=<copy with only Licensing/mathpass>`) was used so the certified environment was
never modified; it is honored on master and subkernels.

**4.1 The Boolean-context primitive (#556, executed 2026-09-11).**

```wolfram
TensorsValue = {a, b};
Exponent[a^2 b, TensorsValue]                          (* {2, 1} *)
Exponent[a^2 b, TensorsValue] > 2                       (* {2, 1} > 2, unevaluated *)
If[Exponent[a^2 b, TensorsValue] > 2, "fired"]          (* unevaluated If: the shim's shape *)
If[{2, 1} > 2, "fired", "not fired", "neither branch"]  (* "neither branch" *)
Catch[(If[Exponent[#, TensorsValue] > 2, Throw["NonQuadraticFields"]]) & /@ {a^3 b, a b}; "no throw"]  (* "no throw" *)
```

**4.2 The unresolved resource has the same shape.** With no definition available:
`ResourceFunction["LinearlyIndependent"][{{1,0},{0,1}}]` → `$Failed[{{1,0},{0,1}}]`;
`!$Failed[…]` stays unevaluated; `And@@{!$Failed[…], …}` is not `True`;
`If[And[…] && …, AppendTo[…]]` appends nothing.

**4.3 PSALTer's recipe on a symbolic singular block** (`SymbolicNullSpace.m:8-23` +
`MinimalExampleCaseNullSpace.m:5`, `SeedRandom[543]`):

```wolfram
singularBlock = {{Def^2 a, Def a}, {Def a, a}};
Couplings = DeleteDuplicates@Flatten@(Variables /@ Flatten@singularBlock);    (* {a, Def} *)
(* three draws of integers 1..9, PSALTer's construction *)
ns = (Normalize /@ NullSpace@FullSimplify@(singularBlock /. #)) & /@ rules;
(* {{{-(1/Sqrt[82]), 9/Sqrt[82]}}, {{-(1/Sqrt[10]), 3/Sqrt[10]}}, {{-1/5/Sqrt[2], 7/(5 Sqrt[2])}}} *)
Variables[Join @@ ns]                                                   (* {} : numeric *)
(!LI[Join[#, {First@cand}]]) & /@ ns                                    (* {True, False, False} *)
```

The candidate depends on the `Def` draw, so it is never common — the shape of README bug 1.

**4.4 Genuine functions on PSALTer's call shapes** (installed paclet; the author's notebook):
`LinearlyIndependent`: `{{1,0},{0,1}}` → `True`; `{{1,0},{2,0}}` → `False`; `{{0,1}}` → `True`;
`{{0,0}}` → `False`; `!LI[Join[{{1,0}}, {{0,1}}]]` → `False`; `If[True && LI[…], "appended", …]`
→ `"appended"`. `PolynomialDegree`: `a^2 b` → `3`; `0` → `Undefined`; `a b + a^3` → `3`;
`c1 Def^4 + c2 Def^2` in `Def` → `4`; `If[PD[a^3 b, {a,b}] > 2, "fired", …]` → `"fired"`.

**4.5 By-name precedence, measured.** With the repository answering (even 401 on the
definition), `ResourceFunction["Name"]` returns the repository's definition-less object and
ignores local registrations. With `$ResourceSystemBase` unreachable *in the registering kernel*,
the registered local objects win and the shared name cache
(`~/.Wolfram/Objects/Persistence/ResourceNames`) records them; afterwards fresh kernels with the
normal address — subkernels launched by `LaunchKernels` included — resolve both names locally.
Objects built from a definition notebook (`ResourceFunction[NotebookObject]`) carry the
repository identity and always route back to it; plain `ResourceObject[<|…|>]` objects do not.

## 5. The registration script

`scripts/psalter/register_resources.wl` (its header documents everything):

- **`LinearlyIndependent`** — locates the `ResourceFunctionHelpers` paclet via `PacletFind`
  (1.3.34; `Kernel/LinearlyIndependent.wl` sha256
  `7bc228a2eb817a65b1760fee81954922430f11031287b045912c1379bd58b817`) and loads that file
  **verbatim under a private package name** (`PSALTerResources`RFH``, only the `BeginPackage`
  name changed), so the function and its two private helpers (`undeterminedsystem`,
  `DetNotZero`) land in our context and the registered object stores the full definition
  (definition list of 3). A registration that merely *referenced*
  `ResourceFunctionHelpers`LinearlyIndependent` was engine-dependent: on 14.3.0 that symbol is
  an autoload alias (one `OwnValue`, no `DownValues`) and the reference resolved through the
  paclet at call time; on 14.2.1 the same object evaluated to `$Failed` once PSALTer was loaded
  (the paclet symbol autoloads in a plain 14.2.1 kernel but not after `Needs["xAct`PSALTer`"]`).
  By value, the object behaves on both engines, master and subkernels.
- **`PolynomialDegree`** — downloads the repository's definition notebook if absent and refuses
  on a digest mismatch (sha256 `c233e226d4c77de65ee19ddbc84c20c9724df467bb86c27f1a65f17fba89787c`;
  the first run refused a mistyped constant — the gate working), evaluates its one definition
  cell verbatim in `PSALTerResources`` (definition list of 2).
- Cleans the shared registry of every object named for either function **by reading each
  cached object's own metadata** (name lookups are what is being controlled, so they are not
  used for cleanup), registers both as plain local objects with `$ResourceSystemBase`
  unreachable *in that kernel only*, resolves both by name once, and fails unless the master
  **and** a fresh subkernel return `{True, False, "appended", 3, "fired"}` and the resolved
  UUIDs are the registered ones.

Two slips worth recording, both caught by the script's own checks rather than by reading:
`DownValues`, `Definition` and `Language`ExtendedFullDefinition` hold their argument, so
`DownValues[liSym]` inspected the variable, not the symbol it held — the "0 DownValues" readings
in three earlier probes were this, not a property of the paclet. And a hand tidy-up that deleted
registry objects with `DownloadedVersion -> None` deleted the freshly registered ones too
(local registrations carry that field); the ladder's `env resources=` line caught it, and the
cubic-control run on that empty registry is kept as the **negative control** (cubic accepted,
`$Failed` resources, full cascade).

## 6. Ladder and gate results

| rung | 14.3.0 (certified) | 14.2.1 (cross-check) |
|---|---|---|
| X cubic control (must throw `NonQuadraticFields`) | **PASS** — threw; negative control on an empty registry: accepted | **PASS** |
| G Maxwell ×3 (constraint row, non-zero pseudo-determinant) | **PASS ×3** — `Dimensions[$LocalSourceConstraints] = {3, 1}`, `PseudoDeterminant = {{1, 1}, {1, −Def²Θ₁/2}}` | **PASS ×3**, same values |
| A scalar (non-zero quadratic, pole `±Θ₂/Θ₁`) | **PASS** — `(Def²Θ₁ − Θ₂)/2`, pole `Def² = Θ₂/Θ₁` | **PASS**, same |
| B Proca (both keys = published 0⁺/1⁻ blocks) | **PASS** — `(Def²(Θ₂−Θ₁) − Θ₃)/2`, `(−Def²Θ₁ − Θ₃)/2` (closes #542's "missing mass term") | **PASS**, same |
| C Fierz–Pauli (published sectors) | **PASS** — `{{−3β², 1}, {1, β}, {β − αDef²/2, 1}}` | **PASS**, same |
| D CTEG gate (`summarize_diff.py`) | **MATCH** — tally `{identical: 2}` (run `tier1-20260911T151115Z` on the final registration; an earlier pass at `tier1-20260911T144346Z` used the reference-form registration); no `Power::infy`; render 0 `Indeterminate`, 0 `$Failed`, real unitarity line; 449 s, exit 0 | **MATCH** — `{identical: 2}`, component run (§6.1); no PDF (front end) |
| D CTEG `$LocalSourceConstraints` | dims `{3, 7}`: seven irreducible rows, `2J+1 = {1, 1, 3, 3, 3, 5, 5}`, **21 generators** (the published count); pseudo-determinants identical to the oracle | identical: `{3, 7}`, `{1, 1, 3, 3, 3, 5, 5}`, 21; same expressions |

PSALTer lists every spin sector as an even/odd parity pair and puts the literal `1` in a slot
that carries no field, so the ladder drops literal `1`s before matching (a literal `0` is the
failure signature and is never dropped). The first ladder pass "failed" rungs A and B on exactly
that expectation of mine; the values were right.

**14.2.1 install notes (refuting handoff item 6 "installs without root"):** the Makeself
installer prints "must be run as root or with sudo" and exits without installing as the user;
with passwordless `sudo` it installs to `~/.local/wolfram/engine/14.2` (6.8 GB, then `chown`
back). Passing `-execdir` equal to `<targetdir>/Executables` makes the installer overwrite the
kernel launcher with a symlink to itself; the launchers (`WolframKernel`, `MathKernel`, `math`,
`wolfram`) are version-agnostic shell scripts that resolve their own top directory and were
copied from the 14.3 install. Selected per run with
`WOLFRAMSCRIPT_KERNELPATH=~/.local/wolfram/engine/14.2/Executables/WolframKernel`
(the `WolframScript.conf` pin is overridden by the variable). The shared `mathpass` validated
for 14.2.1 (`$LicenseType` Professional) with no activation; xPerm's MathLink binary built on
14.3 connects ("Connection established"); PSALTer loads; `$MaxLicenseSubprocesses` 8.
**Its front end cannot start headlessly in this container** (`UsingFrontEnd[…]` → `$Failed`,
no message; the FE binary is present), so no PDF is ever exported under 14.2.1 and
`verify-wolfram-setup.sh` check 9 hard-fails there; the gate wrapper's `require_psalter` step
refuses in consequence (and `--skip-preflight` skips only the vector smoke, not that step).
The 14.2.1 cross-check is therefore a **component run**: the published script unmodified under
the 14.2.1 kernel, `tier1_diff.wls`, `summarize_diff.py` (§6.1).

### 6.1 The 14.2.1 cross-check verdict

Component run `third_party/psalter_runs/tier1-142-manual-20260911T155325Z` (gitignored):
the published `ParticleSpectrographCTEG.m` unmodified (sha256 `2232a103…5825` before and
after) under the 14.2.1 kernel, `tier1_diff.wls` against the same oracle
(`07a8cd59…412b4`), `summarize_diff.py`: **`match`**, tally `{identical: 2}` —
`PseudoDeterminant` identical (3×2, 71 leaves), `WaveOperator` identical (303 leaves);
`used_simplify_fallback` `[]`; no `Power::infy`; all twelve stages reached; 409 s; exit 0;
no PDF (front end). Together with the 14.3.0 gate this shows the engine plays no role in
#543: the same registration gives bit-identical results on the author's tested version.

## 7. Registry and environment state after the session

Certified resource-handling leg: see §5 and the evidence README. `~/.Wolfram/Objects` is
container overlay (not bind-mounted): the registration must be re-run after a container rebuild —
routed to the orchestrator for `install-psalter.sh`/devcontainer. Under the pinned userbase
nothing in `Applications/`, `Licensing/` or `INSTALLED_COMMIT` changed; kernel runs rewrote the
usual runtime caches (`FrontEnd/14.3_Caches/…`, `Paclets/Configuration/*.pmd*`). The Wolfram-ID
cloud login persists in fresh kernels; undo with `CloudDisconnect[]` / removing the stored
connection data under `~/.cache/Wolfram/WolframScript/`.

## 8. What the handoff got wrong, and where it is amended

- `I-543.md` research item 2 ("both symptoms sit on the same two built-ins … one behavioral
  change in `NullSpace`"): refuted; amended at the instruction site.
- `I-543.md` research item 5 ("ruled out by test … the two Function Repository resources"):
  the test did not discriminate (#556); amended at the instruction site.
- `stage1_measurements.md` §4.4: rewritten (ruling-out withdrawn with the reason).
- The `EXPIRES-WITH: #543` sites are re-dated or removed in the same PR as the certification.

## 9. Routing

- Re-registration after container rebuild: `install-psalter.sh` / devcontainer (orchestrator).
- `scripts/psalter/README.md` entries for `register_resources.wl` and `repro_543.wl`.
- `run_tier1_gate.sh`: the manifest lacks the engine version and `--theory` is hardcoded to CTEG.
- Tier-1 tolerance if healthy runs differ in output form (PSALTer is unseeded).
- Upstream: `docs/cosmology/psalter_543_upstream_issue.md` (the user files it).
