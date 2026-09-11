# Draft upstream issue for PSALTer (wevbarker/PSALTer) — not filed by the session

**Title:** Two undocumented Function Repository dependencies silently produce a wrong spectrum
(empty source constraints, zero pseudo-determinants) when unavailable — and a deterministic
trigger for "Known bugs" item 1

## Summary

`ParticleSpectrum` calls `ResourceFunction["LinearlyIndependent"]` (SymbolicNullSpace.m:31 on the
master; IsNullVectorOfSpace.m:6 on subkernels) and `ResourceFunction["PolynomialDegree"]`
(ValidateLagrangian.m:38; UnresolvedPoleRow.m:11,21). Neither is declared in the README or the
install instructions. When either cannot be resolved — no network, a Function Repository outage,
or an environment where `ResourceFunction` returns `$Failed` — the run **completes and writes its
`.mx`**, but:

- every `SymbolicNullSpace` returns `{}` (no gauge symmetry is identified), because an unresolved
  `ResourceFunction[...]` is not a Boolean, so `And[…]` never becomes `True` and the `If` that
  appends to `CommonNullVectors` takes neither branch;
- `ManualPseudoInverse` then uses the all-zero placeholder null space, the compensator is zero,
  `Det[TheInputMatrix + CompensatorMatrix]` is identically zero for gauge-singular blocks, and
  `UnmakeSymbolic.m:75` divides by it (`Power::infy`, then `Indeterminate`), so every entry of
  `PseudoDeterminant` in the theory association is `0`;
- `ValidateLagrangian`'s `NonQuadraticFields` check never fires (a cubic Lagrangian is accepted).

Because `PSALTer.m:18-20` redefines `Message` to `Null` on subkernels, the `ResourceObject::notfname`
/ `ResourceFunction::lfail` messages from the subkernel call site are never seen; on the master only
three `ResourceObject::notfname` for `PolynomialDegree` appear, and the run carries on.

## Reproduction (Wolfram 14.3.0, PSALTer v2.0.2 @ bb45adb0, xAct 1.2.1, Linux)

Any environment where `ResourceFunction["LinearlyIndependent"]` does not resolve (e.g. offline).
Your own published input reproduces it at full scale: `SupplementalMaterials-2506b`
`ParticleSpectrographCTEG.m` @ 37c86a5d, unmodified, gives `WaveOperator` bit-identical to your
committed `ParticleSpectrographCTEG.mx` and `PseudoDeterminant = {{0,0},{0,0},{0,0}}` where the
`.mx` holds e.g. `(-2 (1 + 2 Def^2) MPlanck2)/3`; `$LocalSourceConstraints` is `{}` where the
21-generator formulation should give 21 rows. Minimal: Maxwell (`-1/2 T1 (∂_a A_b)^2 + 1/2 T1 (∂·A)^2`,
~60 s) loses its one source constraint and its pseudo-determinants.

Standalone shape of the failure:

```wolfram
r = $Failed[{{1, 0}, {0, 1}}];   (* what an unresolved ResourceFunction application returns *)
And[True, !r]                    (* stays non-Boolean *)
If[And[True, !r] && r, "appended", "not appended", "neither"]   (* "neither" *)
```

With the genuine functions available again (we registered `ResourceFunctionHelpers`LinearlyIndependent`
from the paclet Wolfram ships, and the `PolynomialDegree` definition from its repository
notebook), the same inputs give Booleans at both call sites, `NonQuadraticFields` throws on a
cubic Lagrangian, and the constraints and pseudo-determinants return.

## Relation to "Known bugs" item 1

The README documents "a sporadic error where some of the gauge symmetries are not identified …
random number generation at runtime … usually fixed by re-running". That is the same endpoint —
`CommonNullVectors` staying `{}` — reached sporadically with the resource present. Two
observations from the same code path:

1. With the resource **absent**, the loss is total and deterministic; re-running cannot fix it.
   A partial supply (e.g. a substitute defined only on the master, not on the subkernels that
   `ParallelNeeds` the package) reproduces it in a form indistinguishable from the sporadic bug.
2. With the resource present, `SymbolicNullSpace` draws integers 1–9 for **every** variable of the
   rescaled block, `Def` included. A candidate null vector that still depends on `Def` after
   `RemoveReferencesToMomentum` therefore differs per draw and is never "common" across the
   minimal examples (`And@@{True, False, False}`), which is a concrete mechanism for a sporadic
   loss that a luckier draw repairs. We have not yet verified this on a real theory; it is a
   hypothesis with a test (`$DiagnosticMode`, compare `MinimalExampleCaseNullSpaces` across draws).

## Suggested changes

- Declare the two dependencies in the README/install instructions, and check them at load
  (`ResourceFunction` resolution on the master **and** on a subkernel), failing loudly.
- Guard the two call sites so a non-Boolean result aborts with a message rather than silently
  emptying the null space (e.g. `TrueQ`/`Check`).
- Consider not silencing `Message` on subkernels, or at least forwarding `ResourceFunction::lfail`.

## Aside: `Method` is inert (v2.0.2)

`Options@ParticleSpectrum` declares `Method -> "Easy"`, but there are zero `OptionValue@Method`
sites in the installed tree (five for `MaxLaurentDepth`); `"Easy"`, `"Hard"` and an invalid value
give byte-identical results, `$Local*` globals and message lists (probe `scripts/psalter/probe_521_method.wls`).

## Environment

Wolfram Engine 14.3.0 (Linux-x86-64), also checked on 14.2.1 (see the project's investigation
record for the per-engine table); PSALTer v2.0.2 @ bb45adb0; xAct 1.2.1; `QT_QPA_PLATFORM=offscreen`.
