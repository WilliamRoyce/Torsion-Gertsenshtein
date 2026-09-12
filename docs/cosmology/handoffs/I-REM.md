# I-REM — Amend the instruction sites Wave 0 falsified, integrate the docs, fix the tooling

> **STATUS: COMPLETE — 2026-09-09.** Merged from `cosmo/irem-amendments` (PR #550, `32d21a3b`).
> Closed #545, #546, #540; opened #551. Amended the instruction sites Wave 0 falsified,
> integrated the docs, fixed the tooling, and added `oracle.yml` — **proven in both directions**
> (CI 34393316535 failure on a corrupted fixture, 34392693815 success clean). Replaced the
> six-item exporter list with a rule + anchor + guard rather than a longer list. Found PSALTer's
> own README known-bug #1, which turned out to describe #543's symptom.
>
> Kept as the record of *what was asked*. **Not an open assignment.**

| | |
|---|---|
| **Issue** | #545, #546 (fix and they close) · #540 (wording) · #534, #535, #536, #530 (back-references) · umbrella #488 |
| **Wave** | 0-completion |
| **Wolfram lane** | **No.** Do not start a kernel — another session holds it. Nothing here needs one. |
| **Depends on** | nothing. **Merges first** in this wave |
| **Owned paths** | `docs/cosmology/{stage1_engineering_plan,spectrum_design,repo_reshape,solver_design}.md` · `docs/README.md` · `docs/cosmology/handoffs/README.md` (new) · `tidalcosmo/README.md`, `tidalcosmo/cli/README.md` · `scripts/README.md`, `scripts/oracles/README.md` · `scripts/full_test.sh`, `scripts/verify-wolfram-setup.sh` (**header comment only**), `scripts/install-xact-xcoba.sh`, `scripts/install-psalter.sh` + `scripts/psalter/run_tier1_gate.sh` (**file mode only**) · `tests_cosmo/__init__.py`, `tests_cosmo/test_oracles.py` (**docstrings only**) · `.claude/skills/*/SKILL.md` · `Makefile` · `.github/workflows/{oracle.yml,deploy.yml,test.yml}` · `cspell.json`, `.gitignore`, `.gitattributes`, `pyrightconfig.json`, `.pre-commit-config.yaml` · `pyproject.toml` (**marker descriptions only**) · `.devcontainer/docs/WOLFRAM_GUIDE.md` · `CLAUDE.md`, root `README.md` |

## Why this exists

Wave 0 measured a number of things that contradict what the design documents still say, and
the amendments were made *next to* several of those claims rather than *in* them. A delegate
who copies a list gets the wrong list. Separately, three Wave-0 outputs are unreachable from
the docs index, the new package's README says it contains no code, and five developer
commands silently skip the new test suite.

**None of this is new design.** Every correction below is already measured and recorded
somewhere in the repo; your job is to put it where the next reader will actually see it.
Where a row says *(verify at site)*, treat it as a hypothesis and check before editing.

## Commit 1 — `fix(cosmology):` the wrong-result class

These three would cause an implementer to build the wrong thing.

1. **`stage1_engineering_plan.md:460-464` still lists SIX `$Local*` globals.** The amendment
   above it (`:446-458`) is correct and says eight; **the list itself was never edited**, so
   anyone copying it exports six. Rewrite the list in place to the eight from §0.4 —
   `$LocalSourceConstraints`, `$LocalWaveOperator`, `$LocalPropagator`, `$LocalSpectrum`,
   `$LocalMasslessSpectrum`, `$LocalUnresolvedPoles`, `$LocalOverallUnitarity`,
   `$LocalSummaryOfTheory` — keeping the amendment banner. Both of §5's implicit
   justifications were refuted live (#523): `assoc[WaveOperator] === $LocalWaveOperator` is
   **False**, and `$LocalPropagator` **is** populated under `ShowPropagator -> False`.
2. **`spectrum_design.md:450` — the `O_LL` caveat has no #543 note.** It says gauge modes are
   removed first "(PSALTer's Moore–Penrose gauge fixing does this)". On our install
   `$LocalSourceConstraints` is `{}` against the 21 CTEG requires, so that removal is degraded
   and **both** spectrum criteria are blocked, not only the residue cross-check. The
   correction currently lives only in `COSMOLOGY_PROGRAM.md` — a direct violation of
   amend-at-the-instruction-site. Add it here, pinned to PSALTer `bb45adb0` and Wolfram 14.3.
3. **`stage1_engineering_plan.md:586` reader row, and §5's calibration step 3**
   *(verify at site)* — "`Vector` blocks equal the published expressions exactly". #542 shows
   the association omitting `Θ₂`/`Θ₃` on this install, so as written the gate would fail
   against a *correct* install, or be quietly relaxed until it passed. Amend to: gate against
   the **published** expressions and the **committed upstream `.wxf`**; **do not calibrate
   against values measured on this install until #543 is resolved.**

## Commit 2 — `docs(cosmology):` the remaining instruction-site amendments

Each dated 2026-09-09, pinned to the install where install-specific.

4. **`repo_reshape.md:1039-1041`** still says the fixtures "ship with" the §5.2 written
   mapping at M0.5. They cannot: the mapping records how *new-convention* quantities
   correspond to legacy ones, and no new-convention spec exists until M3. Amend to say the
   mapping is **designed and written as part of the symbolic-stage (WS2/M3) work**, before the
   derive port's gate is run — which is what §7's M7 row already assumes ("once M3's §5.2
   mapping is recorded"), and what `tests_cosmo/data/oracles/README.md` already says.
5. **`stage1_engineering_plan.md:584` oracle-T1 row and §3's tier definitions**: Tier 1
   currently **fails** (#543); and even a *pass* would certify the wave operator and the
   pseudo-determinants and **nothing else** — not source constraints, spectrum or unitarity
   conditions. Say so, and note that **Tier 2 must add source-constraint coverage**, since
   there is no oracle for that key.
6. **`stage1_engineering_plan.md:90`** marks `NonQuadraticFields` as thrown. It is **inert
   here**: its guard is `ResourceFunction["PolynomialDegree"]`, which cannot be fetched in
   this container, so it fails silently — **four** silently-absent validations, not two. Same
   correction in `spectrum_design.md` §4.1, which was amended for #522 but not for this.
7. **`spectrum_design.md:839` and `:850`** say "only PSALTer itself is not [installed]" and
   "Only xAct is installed today". PSALTer v2.0.2 `bb45adb0` **is** installed and verified —
   and **uncertified** (#543). Fix both, including the fact that the amendment banner at `:839`
   has itself gone stale.
8. **`spectrum_design.md:871` §14 item 1** says `ParticleSpectrum` wall time is "unmeasured".
   Still true for PGT+EM, but we now have a strong bracketing number: **CTEG (21-generator
   PGT) in 407 s**, with **~72 %** of it in field declaration and decomposition — so adding
   couplings to existing field content is far cheaper than adding fields. Record it.
9. **`stage1_engineering_plan.md` — the `wolfram_driver.py` paragraph** inherits two measured
   requirements (`stage1_measurements.md` §2.5, §10.2, routed to the orchestrator and never
   landed): **never judge a `wolframscript` run by its exit status** (14.3 segfaults on
   shutdown *after* correct results — the CTEG gate run exited **143**), and **set
   `QT_QPA_PLATFORM=offscreen`** beside the engine-idle guard (without a loadable Qt platform
   plugin `UsingFrontEnd@Export` **hangs**, and exposure begins at `DefField`).
10. **`stage1_engineering_plan.md` §1 (environment audit)** — record two environment facts
    found by I-526 and currently written down nowhere that a setup reader would look: the
    **Wolfram Cloud is unreachable from this container** (503/404), so Function Repository
    resources must be supplied locally; and **Inkscape's dependencies are what make the
    headless export work** — `libwayland-egl1` in particular, so `--skip-inkscape` or a
    slimmer image reintroduces the hang. Mirror the second in
    `.devcontainer/docs/WOLFRAM_GUIDE.md`.
11. **`stage1_engineering_plan.md` §0.5** is the only scorecard row still `not tested`
    ("both linearization architectures are documented"). Mark its owner: **I-S1B**.
12. **`stage1_engineering_plan.md:536`** *(verify at site)* — a §6 list item lost its `- `
    bullet in `58605f16`/`c8c57251`. Cosmetic, but it is a Wave-2 instruction site.
13. **Back-references, so trackers are reachable from the design**: `repo_reshape.md` §5.7 →
    **#534** (the port manifest and its walking test); §5.1's `inspect` port row → **#535**
    (`--detail` missing from `query_flags`); `solver_design.md` §12's WKB rung → **#530** (the
    `[survey]`-tagged LJL bounds are the only quantitative accuracy claim for that rung, and
    WKB is now built in the first WS3 handoff rather than gated behind a bake-off).
14. **`repo_reshape.md` §8 — record the decision** that the CI lane stays **one job over both
    suites**, not a separate `tidalcosmo` job (#524's open "if that turns out to be wanted"):
    both suites share one venv, so a second job buys nothing and doubles setup.
15. **`scripts/oracles/README.md:36-38` and `tests_cosmo/test_oracles.py:15-19`** — both
    explain why `--check` is out of CI. One of the two reasons no longer holds: "it would make
    CI fail the day legacy is deleted" is not a coupling to avoid but a **guard with an
    expiry**, exactly like #537 — a legacy-integrity job is *deleted with* the capabilities it
    re-runs. Amend to record that the check now runs in a **path-filtered** workflow (below),
    with its expiry stated.

## Commit 3 — `ci(oracle):` make the standing rule a mechanism

The M0.5 rule *"if `tidal/` or `examples/data/` changes, re-run the oracle in the same
commit"* is enforced by nothing — which is precisely the defect this wave codified as **"a
rule stated in prose is not enforcement"** (#540 was the other instance).

Add `.github/workflows/oracle.yml`:

- `on:` `push` and `pull_request` for `feat/cosmology-program`, with
  `paths: [tidal/**, examples/**, scripts/oracles/**, tests_cosmo/data/oracles/**, uv.lock]`
- one job: `uv sync --all-extras --locked` → `uv run python -m scripts.oracles.freeze_legacy_oracle --check`
- **the expiry in the workflow header**: this job is deleted together with legacy `inspect`
  and `validate` when the derive port lands (M3 → M6/M7); record it in `repo_reshape.md` §7's
  retire column for that row too, per the guards-carry-their-expiry rule.

The path filter answers the cost objection (it will not run on most commits); the expiry
answers the coupling objection. **I-533's deletions under `tidal/` are its first real
trigger** — that is the intended behavior, and `--check` must still report 185 current.

## Commit 4 — `fix(tooling):` stop silently skipping the new suite, and the hygiene batch

16. **`scripts/full_test.sh:26` runs `tests/` only.** So do five skills that run pytest:
    `.claude/skills/{test,validate,commit,validate-physics,sync-docs}/SKILL.md`. This is the
    same defect I-524 fixed in `make test`, three more times. Make each run **both** suites,
    and add the new source→test mapping (`tidalcosmo/X.py` → `tests_cosmo/test_X.py`).
17. **`CLAUDE.md`**: "Eleven design documents" is now **13** — drop the count rather than
    re-fixing a number that has drifted twice; add **one line pointing at the wave board** in
    `docs/COSMOLOGY_PROGRAM.md` (a fresh session currently learns the strategy but not where
    the state lives); add `tests_cosmo/` to Key Commands and to the source→test mapping.
    **Do not** touch the legacy-subcommand list or the `sweep`/`sample` examples — I-533
    reports those and the orchestrator applies them at merge.
18. **`Makefile`**: add an `oracle-check` target, so the documented invocation has a one-word
    form.
19. **#545 — `deploy.yml:29`** runs `sphinx-apidoc … tidal/` only, so `tidalcosmo/` gets no
    API docs. Add a second invocation. **Dry-run it locally into a temp directory first** and
    report the `.rst` files it emits — the criterion is that it produces docs, not that the
    line exists.
20. **#546 — `scripts/install-xact-xcoba.sh:84`** runs a bare `sudo apt-get update -qq` under
    `set -e`, so a transient mirror failure aborts the installer. Warn and continue; the
    `install` step after it stays fatal.
21. **#540** — correct the two marker descriptions in `pyproject.toml:373-374` and the
    `Makefile:61` comment so they stop asserting a default-lane exclusion that nothing
    implements. **Delete the claim; do not build the lane**, and do not install TeX on CI.
22. **Hygiene**, each small and each verified at the site:
    - exec bits: `scripts/install-psalter.sh` and `scripts/psalter/run_tier1_gate.sh` are
      mode `100644` while `install-psalter.sh:42` documents `./scripts/install-psalter.sh`
      (`git update-index --chmod=+x`).
    - `scripts/verify-wolfram-setup.sh:9` says "Checks 7-9 cover PSALTer"; there are four
      (7–10). **Header comment only** — the logic is being changed by another session.
    - `cspell.json`: `docs/cosmology/evidence/**` ignores a hand-written English README —
      narrow it to `**/*.json`, `**/*.txt`, `**/*.log` under that directory. Add the
      programme vocabulary to `words` explicitly (`tidalcosmo`, `PSALTer`, `psalter`, `wxf`,
      `offscreen`, `spectrograph`, `CAMB`, `Cobaya`, …) — today they pass on dictionary luck,
      and the CI action's dictionaries differ from local.
    - `.gitignore`: explicit entries for `third_party/psalter_runs/` and
      `third_party/psalter_reference/` with the reason, as `:5-8` does for `build/`. They are
      currently covered only by the blanket `third_party/`, which also holds a 1.75 GB
      installer and may plausibly be narrowed later.
    - `.gitattributes:59` *(verify)* duplicates `*.py text eol=lf` from `:8`.
    - `pyrightconfig.json` *(verify)*: `tests_cosmo` has no execution environment **by
      design** (`tests_cosmo/__init__.py:16-20`) — one comment saying so, where the next
      person to add one will look.
    - `.pre-commit-config.yaml` *(verify)*: the mypy hook now checks `tidalcosmo/` and
      `tests_cosmo/` alongside pyright strict. Exclude the new trees — §8 makes pyright strict
      the type gate there; two checkers with different verdicts is a future argument.
    - `tests_cosmo/__init__.py:25-26` states "prefer `runpy.run_module` over `subprocess`";
      `test_psalter_evidence_readback.py` violates it with justification (its subject is a
      bash script). One sentence recording the exception.
    - `--locked` on the three `uv sync --all-extras` sites (`test.yml:49`, `deploy.yml:25`,
      `Makefile:42`); `uv lock --check` is clean today, so this fails loudly on drift instead
      of silently resolving past the lock.

## Commit 5 — `docs:` make the wave's outputs reachable

23. **`tidalcosmo/README.md:9-10` says "There is no code here yet … no `__init__.py`".** False
    since `654b627a` — the package ships `__init__.py`, `cli/`, `py.typed`, and is packaged by
    `pyproject.toml:415`. It is the first file a Wave-1 delegate opens. Fix the headline, not
    only the amendment beneath it. Same for **`tidalcosmo/cli/README.md:9-10`** ("still
    genuinely undesigned … treat the contents as a sketch") — three modules and their tests
    shipped, and `error_with_hint` is ported and tested.
24. **`docs/README.md`**: add `stage1_measurements.md`, `docs/cosmology/evidence/`,
    `docs/meetings/` and the **I-series** handoffs — three Wave-0 outputs are currently
    unreachable from the index, one of them the evidence behind a live blocking decision and
    one the record of the meeting that decision is routed to. Fix `:17` ("eight sequential
    handoff sessions (H1–H8)" — there is no `H7.md`; H7's prompt was never committed while its
    output `spectator_route.md` was: say so) and `:34` (which lists `handoffs/H1–H6, H8`
    only).
25. **`docs/cosmology/handoffs/README.md`** (new): the map a cold session needs — one row per
    prompt with issue, wave, lane, status and the outputs it produced, H-series and I-series
    (including I-REM, I-533, I-543). Ten prompts today with no index, growing per wave.
26. **`scripts/README.md`**: the Files table omits `scripts/oracles/freeze_legacy_oracle.py`
    entirely and lists `psalter/run_tier1_gate.sh` without its siblings. Both directories have
    good local READMEs; point at them. **Do not** edit the legacy-subcommand rows — I-533
    reports those.
27. **Root `README.md`** mentions neither `tidalcosmo` nor the cosmology programme — the
    repo's front door still describes only legacy. One short paragraph with a pointer to
    `docs/COSMOLOGY_PROGRAM.md`.

## Success criteria — stated before you write anything, verified from artifacts

1. These greps return **zero**: `no code here yet` · `Eleven design documents` ·
   `only PSALTer itself is not` · `Only xAct is installed today` · `Checks 7-9` ·
   `H1–H6, H8` · `NonQuadraticFields | yes` (the table row) .
2. `grep -c 'LocalSummaryOfTheory' docs/cosmology/stage1_engineering_plan.md` shows the §5
   list carrying **eight** globals.
3. `grep -l tests_cosmo scripts/full_test.sh .claude/skills/*/SKILL.md CLAUDE.md` lists
   **all seven** files.
4. `make oracle-check` runs the documented invocation and exits 0 (185 current). The
   orchestrator may be running the same check concurrently — it is CPU-only, no lane.
5. **`oracle.yml` observed running on your PR**, reported as `CI <run-id>: <conclusion>`,
   fetched with `gh run view --json conclusion` — never inferred from a watch's exit code.
6. `sphinx-apidoc` dry run for `tidalcosmo/` emits `.rst` files; paste the listing.
7. `uv lock --check` clean, and `--locked` present in the three places.
8. Both suites green with BLAS caps; `ruff check`, `ruff format --check .`, `uv run pyright`
   clean; cspell over your changed files (a typo pass — **CI is the gate**, and local cspell
   provably cannot reproduce it: the dictionaries differ, so push and fix forward).
9. Draft PR number reported at your first commit.

## Scope fence

- **Do not touch** `docs/COSMOLOGY_PROGRAM.md`, `docs/cosmology/stage1_measurements.md`,
  `docs/cosmology/evidence/`, `docs/meetings/`, memory files, `CHANGELOG.md`, the version in
  `pyproject.toml`, or the `I-52x.md` prompts — all orchestrator-owned this wave.
- **Do not** delete legacy subcommands or their tests (I-533), and do not start a kernel
  (I-543 holds the lane).
- **Do not "fix" these — they are correct as they stand**: the absent `tests_cosmo` ruff
  per-file-ignore block (deliberate, `stage1_measurements.md:472-478`); `test.yml` relying on
  `testpaths`; the absence of BLAS caps in CI (the runner is uncontended); `error_with_hint`
  having no callers yet; `scripts/` having no `__init__.py`.
- No version bump, no tag, no merge, no issue closing.

## Working rules

**You merge first, and two of your files are also owned by I-543.** Keep your edits to
`scripts/verify-wolfram-setup.sh` strictly to the stale header comment (item 22) and to
`scripts/install-psalter.sh` strictly to the file mode (item 22) — I-543 changes the
expected-engine check and the pin in those same files and rebases on top of you. Anything
wider than that turns into a conflict in the session that is resolving a blocker.

Worktree: `git worktree add /tmp/tidal-remediation -b cosmo/remediation-amendments feat/cosmology-program`.
**Open a draft PR into `feat/cosmology-program` at your first commit** and report its number —
a branch with no PR is never seen by CI, which is how two Wave-0 branches merged having never
faced the gate. Never merge, never touch the shared working directory, never version-bump or
tag. Conventional commits in the five groups above; no attribution trailers.

## If you find the design wrong

Amend at the instruction site, pinned to the date, and report — including if one of the
corrections above is itself wrong. Several of these rows exist *because* an amendment was
written beside a claim instead of into it; do not repeat that shape. If something
architectural does not hold, **stop and report**.

## Report back

Branch · PR · each success criterion with its actual output · amendments made beyond this
list · anything to route · suggested next step.
