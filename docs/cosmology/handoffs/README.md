# `docs/cosmology/handoffs/` — the prompt index

Every session that did work for the cosmology programme (#488) was dispatched with a prompt
file kept here. **The prompts are kept, not deleted**, because a prompt records *what was
asked*, which is what lets a later reader judge whether the deliverable answered it.

**None of these is an open assignment**, whatever their imperative mood — H2 in particular
opens "if it does not exist yet, ask before proceeding", which was live instruction text for a
task finished five days earlier. Read the status column here first.

**This index is not the state of the programme.** The **wave board** in
[`../../COSMOLOGY_PROGRAM.md`](../../COSMOLOGY_PROGRAM.md) is the single source of truth for
what is merged, dispatched or planned; this file only maps prompts to their outputs.

## Two series

- **H-series — research.** Executed during planning, before implementation began. All
  complete. Their prompts carry a free-text `**Program:** / **Mode:** / **Artifact:**` header
  and a `> **STATUS: COMPLETE**` blockquote, with no wave or lane field (waves did not exist
  yet).
- **I-series — implementation.** Dispatched per issue under the delegation protocol. Each
  carries a uniform header table: issue, wave, **Wolfram lane**, dependencies, owned paths.

**H7 has no prompt file.** It was executed inside the orchestrator's own planning session
rather than dispatched, so only its output was committed. That is why this directory holds
seven `H*.md` files while the programme document speaks of eight handoffs.

## H-series — research (all complete)

| Prompt | Task | Output |
| --- | --- | --- |
| `H1.md` | TorC pipeline audit — settled O1's scope and how the CAMB patch is made (#498) | `../torc_pipeline_audit.md` |
| `H2.md` | Observable-ladder feasibility — established that O2 and O3 are *different numerical problems* (#500–#510) | `../observable_ladder.md`, `../magnetic_field_background.md` |
| `H3.md` | Solver design study — two engines over one shared core; matrix-WKB designed and prototyped (#517–#520) | `../solver_design.md` |
| `H4.md` | New-package design — the strangler-fig migration and the `tidalcosmo/` scaffold (#513–#516) | `../repo_reshape.md` |
| `H5.md` | Literature acquisition — 20/20 fetched and title-verified (#497) | `literature/`, `../../references.md` |
| `H6.md` | Numerical polology design — the two-stage spectrum architecture and its primary algorithm | `../spectrum_design.md` |
| *(H7)* | **No prompt file.** Spectator-route scope, executed during planning | `../spectator_route.md` |
| `H8.md` | Stage-1 engineering **study** — six live-source findings correcting H6 (#521–#523) | `../stage1_engineering_plan.md`, `scripts/research/psalter_stage1/` |

## I-series — implementation

| Prompt | Issue(s) | Wave | Wolfram lane | Status | Output |
| --- | --- | --- | --- | --- | --- |
| `I-524.md` | #524 (M0) | 0 | no | **merged** | `tidalcosmo/` installable, extras, console script, CI lane |
| `I-525.md` | #525 (M0.5) | 0 | no | **merged** | `scripts/oracles/`, 185 frozen fixtures under `tests_cosmo/data/oracles/`; filed #535–#538 |
| `I-526.md` | #526 | 0 | **yes** | **merged, install UNCERTIFIED** | PSALTer v2.0.2 installed; Tier-1 **MISMATCH** → #543. `../stage1_measurements.md`, `../evidence/tier1-20260907/` |
| `I-REM.md` | #545, #546, #540 | 0-completion | no | merges **first** | instruction-site amendments, docs index, `oracle.yml`, tooling |
| `I-533.md` | #533 | 0-completion | no | merges second | retire the M0 drop rows (`sweep`, `sample`, `analyze`, `plot`) |
| `I-543.md` | #543 (+#542, #549) | 0-completion | **yes** | merges last | resolve the Tier-1 gate — pass it, or locate the mechanism |

## The Wolfram lane

**One `wolframscript` machine-wide**, so at most one lane-flagged session may run at a time —
the orchestrator included. Only a prompt whose header says **Wolfram lane: yes** may start a
kernel. Two prompts hold it in the table above; the rest must not.

## Conventions worth knowing before reading one

- A delegate works in its **own git worktree** off `feat/cosmology-program`, branches
  `cosmo/i<issue>-<slug>`, **never merges**, and opens a **draft PR at its first commit** —
  `test.yml` fires on `pull_request`, so a branch with no PR is never seen by CI.
- **Delegates never version-bump, tag, or edit the changelog.** The orchestrator bumps once
  per wave; concurrent bumps guarantee a `pyproject.toml` conflict and a tag collision.
- Each prompt carries a **scope fence** naming the adjacent temptations, and a **flaw
  protocol**: amend a wrong design *at the instruction site* and report it; **stop and report**
  if the design cannot be built as specified.

Full protocol, including the merge checklist and the wave-boundary checklist:
[`../../COSMOLOGY_PROGRAM.md`](../../COSMOLOGY_PROGRAM.md) §"Implementation delegation
protocol".
