# Supervisor Meeting — 11 September 2026 (DRAFT, in preparation)

**Period**: 29 August (programme pivot) to 11 September 2026.
**Status of this file**: living draft. Points are added as they arise rather than
reconstructed on the day; anything unresolved by the meeting stays here as an open item.

---

## Headline

The cosmology programme is **design-complete, and the first implementation wave is merged**.
Eight research handoffs (H1–H8) ran between 29 August and 4 September, producing thirteen
design documents; a coherence pass reconciled them, and a scientific review before dispatch
(`docs/cosmology/scientific_review.md`) confirmed the architecture holds at every rung.

**The first wave delivered two of its three goals and caught the third failing.** The new
package is installable with a CI lane that found a real defect on its first execution
(2885 passed / 39 skipped); the legacy oracle is frozen as 185 committed fixtures before any
porting; PSALTer is installed and three source questions are answered from a live install.
**Its install gate does not pass** — see §3b, which is the one thing I would most like your
view on after §1.

**Settled since the last meeting:** the observable ladder's execution order
(`O0 → O1 → O2 → O4a → O3 → O4b/V`), the integration target (our own solver chained to
*unmodified* CAMB), the two-engine solver architecture, and the two-stage spectrum
architecture.

---

## 1. The question I most want your view on — does an FRW background solve the PGT field equations?

**Why it matters.** The whole spectator route rests on expanding the action about a
background and having the order-1 term vanish. That order-1 coefficient *is* the background
field equation, so it vanishes only if the background solves the equations of the theory
being expanded. We take CAMB's background, which solves **Einstein's** equations, while our
action is **PGT**. If a linear term survives, it is a **source** in the perturbation
equations — the spectator modes would be driven rather than freely propagating.

**What we already have.** The thesis settles the flat case:
`docs/tex/background_validity.tex` §"Background Torsion: `T̄ = 0` Is Exact" shows the Cartan
equation gives `0 = 0` for all PGT+EM theories with non-minimal couplings — **on flat
Minkowski with uniform `B₀`**. But the result it rests on (Bahamonde et al.) finds
non-trivial `T̄` precisely for **curved** spacetime, and FRW is curved.

**What we know on FRW.** From `2003.02690` (the group's own): `Q = 0` solves the
pseudoscalar torsion equation identically for *any* couplings — encouraging — but a *fully*
torsion-free FRW background additionally requires `σ₃ = 0` (k-screening) or the
Einstein–Cartan case. Outside those, theories sit in a tracking class whose effective
gravitational constant is rescaled, so CAMB's `G` is not the theory's `G`.

**Our provisional handling**, which I would like checked:

1. **Scope it.** Admissible theories are those admitting the assumed background — stated as
   an explicit validity condition of the route, with the theory judgement left to the user
   rather than silently assumed by the pipeline.
2. **Test it per theory, in-pipeline.** A background-EOM residual computed on the CAMB
   background. Because the residual *is* the tadpole coefficient, its tolerance is
   derivable rather than arbitrary: the induced source must sit far below the signal being
   computed. The expected regime is a **small new term on top of GR**, where residual and
   induced source are correspondingly small.
3. **Scope the extension as research, not resolve it now** — survey which theory classes
   provably admit a torsion-free FRW background and what settling it would require.

**Questions:** Is (1)+(2) the right posture, or does this need settling before O2? Is the
tracking class worth supporting, or is restricting to `T̄ = 0`-admitting theories the
cleaner scope? And is anyone aware of work extending the Minkowski argument to FRW?

**Where it bites first:** O4a (isotropic birefringence) *requires* a homogeneous torsion
mode `S₀(η) ≠ 0`, i.e. `T̄ ≠ 0` by construction — so it is the one rung guaranteed outside
the safe class.

---

## 2. Solver direction — WKB, as you expected

Confirming that the research supports the expectation from the last meeting, and reporting
one honest caveat.

**The design does what you recommended** — find the published methods for analogous
problems and rebuild them. The WKB rung is built on Lorenz–Jahnke–Lubich adiabatic Magnus,
lifted to first-order systems with non-normal `M`, cross-checked against Ioannisian–Smirnov
closed forms, with neutrino oscillation in matter (arXiv:0803.1967) as the template and
Handley's `oscode`/`riccati` as the scalar-case prior art.

**The prototype confirms the property that matters.** On a de Sitter adiabatic band at a
fixed 60 steps, the adiabatic stepper's error is *identical* for `k = 10, 100, 1000`, while
4th-order Magnus at the same step count is useless. That k-independence is the whole point.

**Caveat: no matrix RKWKB solver exists anywhere.** `oscode` and `riccati` solve *scalar*
second-order ODEs only. So this is a **generalization of a published scalar method to
matrix systems**, not a port — higher effort and higher risk than it may sound, and
independently publishable if it works.

**Decision taken:** WKB is implemented alongside Magnus in the first solver handoff rather
than deferred behind it. Both are measured; a bake-off decides composition and handover
thresholds on real numbers, with an adaptive RK baseline as the control. No candidate is
discounted on paper estimates.

One honest caveat on evidence: the error bounds we would quote for the adiabatic method are
still `[survey]`-tagged — taken from the Lorenz–Jahnke–Lubich paper at second hand and not yet
re-derived against the primary source. They are the only quantitative accuracy claim the rung
has, so they get verified at first use rather than cited as settled (#530).

**Question:** does treating the matrix generalization as a publishable result in its own
right match how you would want it framed?

---

## 3. For Wolfgang — the massless spectrum algorithm

Thank you for the steer that the massless analysis was left out of the supplementary
material **for convenience** (TorC not being interested in massless particles) rather than
because it is hard, and that the general algorithm is well understood.

That materially changes how we plan it: our design had recorded it as "implemented
numerically nowhere", which read as *we must invent it*. It is now scoped as
**find-and-implement** — locate the published treatments, curate them, and implement the
complete algorithm — the same pattern we are using for the Schur-complement criterion.

**Question:** which references do you have in mind for the general algorithm? That would
save us a literature search and, more importantly, make sure we implement the version you
would recognize as complete.

Related, and already acted on: the released validator does **not** enforce coupling-linearity —
**measured rather than read**, since the install emits ~23 ambient messages on any theory, so
we diffed a control theory against one with a bare numeric coefficient and found the
difference empty. `NonLinearCouplings` is defined but never thrown. A fourth check,
`NonQuadraticFields`, *has* a throw site but is guarded by `ResourceFunction["PolynomialDegree"]`,
which cannot be fetched in our environment — so it is inert here too. We enforce
coupling-linearity on our side and treat the validator as load-bearing for correctness.

---

## 3b. For Wolfgang — two PSALTer findings from installing v2.0.2 (`bb45adb0`)

**The install reproduces your `CTEG` wave operator bit-exactly but not the pseudo-
determinants.** Running `ParticleSpectrographCTEG.m` unmodified and diffing against the
committed `.mx`: `WaveOperator` matches exactly (3 sectors, 303 leaves), while
`PseudoDeterminant` comes back all zeros. The trace localizes it to a `Power::infy`
(division by zero) at +321 s inside `ConstructSaturatedPropagator`, which becomes
`0·ComplexInfinity` → `Indeterminate` and zeroes the determinants.

Ruled out by test rather than argument: subkernel availability and headless graphics. We
also believed we had ruled out the two missing Function Repository dependencies the same way
— supplied locally, identical failure — but see below: our substitute may not have restored
the behavior it replaced, so that one is back open.
**Our leading hypothesis is the engine version** — your `.mx` header decodes to **14.2** and
we run **14.3**, and everything symbolic agrees up to the point of the inverse.

**Since drafting, we have narrowed it considerably** — and we are not asking you to debug it,
only to say whether the conclusion sounds right:

- **It reproduces.** An independent re-run on 9 September gave the same verdict, the same
  per-entry tally and the same bit-exact `WaveOperator` — so it is a property of the
  configuration, not of one session.
- **It is not a PSALTer version difference.** Your oracle is contemporaneous with v2.0.0/2.0.1
  and we run v2.0.2, but `git diff v2.0.1 v2.0.2` touches **nothing** under
  `ConstructSaturatedPropagator/` or `ConstructSourceConstraints/`.
- **It reproduces on a single scalar field in ~30 s**, not just on CTEG — so it is not about a
  degenerate sector or a large computation, and it is cheap to bisect.
- **Both symptoms sit on the same two built-ins.** `ConjectureInverse.m` calls `NullSpace`
  three times, `Inverse` three times and `PseudoInverse` once; `SymbolicNullSpace.m` calls
  `NullSpace` twice. One behavioral change in `NullSpace` on symbolic input would produce
  *both* the empty source-constraint list and the singular inversion — and 14.3's own release
  notes describe a push to "extend and streamline everything done with matrices".
- Every diff entry is a **structural head mismatch** (`Integer` vs `Times`/`Plus`), i.e. zero
  against a polynomial, not a numerical near-miss.

**Your README may already describe half of this, and we would not have thought to ask
otherwise.** "Known bugs" item 1 is *"a sporadic error where some of the gauge symmetries are
not identified … numerical methods … random number generation at runtime … usually fixed by
re-running"*. Our empty source-constraint list is exactly that symptom — except it is not
sporadic for us; it repeats.

**A candidate deterministic trigger, offered as a question rather than a finding.** PSALTer
calls `ResourceFunction["PolynomialDegree"]` and `ResourceFunction["LinearlyIndependent"]` at
five sites, including inside `SymbolicNullSpace` — the gauge-identification path. Neither can
be fetched from our container: the resource API returns 503 while GitHub returns 200, so it is
network-layer rather than authentication. When they are unavailable PSALTer emits
`ResourceObject::notfname` and **continues**, so `NonQuadraticFields` validation is silently
inert here.

We tried to exclude this by substituting both functions locally and re-running — the verdict
was identical, which we first read as excluding it. On re-reading our own substitute, we think
at least one of them *reproduced* the disabled behavior rather than restoring it (our
`PolynomialDegree` stand-in returns a list where yours returns a scalar, so the comparison it
feeds never evaluates and the guard stays off either way). So the control may not have
discriminated, and **we cannot yet exclude the missing resources.** We are checking that
properly.

**The one question only you can answer:** are those two Function Repository resources meant to
be hard dependencies of PSALTer? If they are, an environment that cannot reach the repository
would lose gauge identification silently, which would look exactly like known bug 1 — and it
would be worth saying so in the README or failing loudly at load. If they are not, we are
looking in the wrong place and would rather know now.

**On the engine version:** 14.2-versus-14.3 remains our other candidate and we can install
14.2.1 alongside to test it. Is 14.2 what you would expect to be required? We will send a
minimal reproduction either way, and if it turns out to be a genuine incompatibility we are
happy to write it up as an issue on the repository.

**Also worth knowing:** `Method` is inert on v2.0.2 — zero `OptionValue@Method` sites against
five for `MaxLaurentDepth`, and `"Easy"`, `"Hard"` and a deliberately invalid value all return
byte-identical results with identical timings. We report `ParticleSpectrum` wall time without a
Method qualifier as a result.

---

## 4. The weakest link in the Gertsenshtein rung — the primordial magnetic field

O3 cannot be posed without an assumed background B-field, since the mixing is *linear* in
it. Two things concern me:

- **The assumption is worth ~10⁴ in the answer.** Published choices run from 47 pG to 5 nG,
  and `P ∝ B₀²`. Any bound we quote must carry its assumed field.
- **The backreaction question is unadjudicated.** Surveying the conversion literature, *not
  one* paper justifies neglecting the field's effect on the expansion history — each takes
  a fixed classical background and imports an observational upper bound. The one paper that
  engages the relevant bound (Caprini–Durrer anisotropic-stress limits) sets it aside on
  the strength of a published criticism. Our own justification is an **energy-density**
  argument (`r_B ≈ 10⁻⁷ B₋₉²`, hence `ΔN_eff ≲ 10⁻⁵`), which does not answer an
  *anisotropic-stress* bound.

**Question:** is the energy-density argument sufficient for our purposes, or should we
adjudicate the anisotropic-stress bound before quoting any O3 result? Currently flagged as
must-resolve-before-publication.

---

## 5. Status, briefly

- **Design documents:** thirteen, under `docs/cosmology/`, with `docs/COSMOLOGY_PROGRAM.md`
  as the operational record (decisions register, ladder, workstreams, wave board).
- **Package:** `tidalcosmo/` is now a real installable package beside legacy `tidal/` — two
  console scripts, `camb`/`cobaya` extras, a CI lane on the integration branch. New code
  never imports legacy, test-enforced. (That guard inverts into a blocker at the final
  rename, which we found by asking what future change makes each guard wrong; it is
  scheduled for deletion rather than adaptation.)
- **First implementation wave — merged, one goal unmet:** packaging ✅; the legacy oracle
  frozen as 185 fixtures before any porting ✅; PSALTer installed and its three live-source
  questions answered ✅; **its Tier-1 install gate reports a mismatch** (§3b), so the install
  is uncertified and we are resolving that before starting the next wave.
- **Approach to delegation:** self-contained handoff prompts to separate sessions, each with
  quantitative success criteria stated before code, merged centrally against a checklist.
  Working well; the two things that bit us were a gate nobody could run and a verification
  step promised in a prompt but never copied onto the checklist that gets executed.

---

## Open items carried in

- The `ν⁰` vs `ν²` frequency scaling is **per-operator**, not a single number. Only `n = 0`
  operators can *explain* the 4.8σ birefringence signal; `ν²` operators can only be
  bounded. Derivation in progress.
- The Chern–Simons couplings need **bare `A_μ`** handling, which the pipeline does not yet
  support — an unsolved problem rather than a configuration step.
- Licensing for code derived from the PSALTer/supplementary sources: a release gate, not an
  implementation one. Attribution to be settled at publication. Concretely, we have now
  committed two small `.wxf` outputs from your supplementary materials (692 B and 2,874 B,
  with provenance and hashes) so our reader can be tested without Wolfram installed. Our
  position is that these are *data outputs of a computation* rather than "the Program" — but
  it is a position, not a settled conclusion, and we would rather hear your view now than at
  publication.
- **A positive result on cost, since it answers our own go/no-go:** CTEG — your 21-generator
  PGT — completes in **407 s** on our install, with ~72 % of that in field declaration and
  decomposition. So adding couplings to an existing field content is far cheaper than adding
  fields, and the "minutes, not hours" regime the design assumed holds.
