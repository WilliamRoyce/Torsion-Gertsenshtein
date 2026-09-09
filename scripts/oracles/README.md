# `scripts/oracles/` — the one place allowed to touch legacy

**Do not import anything from this directory.** Not from `tidalcosmo/`, not from
`tests_cosmo/`, not from `tests/`. It is run by hand and it writes files; that is its
whole interface.

## Why this exception exists

`tidalcosmo` is built beside legacy `tidal` and never imports it — enforced by
[`tests_cosmo/test_package_boundary.py`](../../tests_cosmo/test_package_boundary.py).
That leaves a question: how is a port ever checked against the old physics?

Not by calling legacy from a test. A test that imports or shells out to legacy is
precisely how the oracle stops being data and becomes undeletable infrastructure — at
which point "delete legacy per capability" (`docs/cosmology/repo_reshape.md` §7) quietly
stops being possible. So legacy is run **once**, here, and its outputs are committed as
data under [`tests_cosmo/data/oracles/`](../../tests_cosmo/data/oracles/). New-package
tests assert against those files.

The boundary test names this directory in a comment for exactly that reason. It is the
sanctioned exception, and it exists so nothing else has to be.

## Running it

```bash
uv run python -m scripts.oracles.freeze_legacy_oracle                  # write the fixtures
uv run python -m scripts.oracles.freeze_legacy_oracle --check          # compare; write nothing
uv run python -m scripts.oracles.freeze_legacy_oracle --list           # corpus only; no legacy run
uv run python -m scripts.oracles.freeze_legacy_oracle --only <id>      # one spec, to stdout
uv run python -m scripts.oracles.freeze_legacy_oracle --verify-determinism
```

A full run is ~5–8 minutes: 46 theories × 4 legacy invocations, serial. `--list` answers
"what is in the corpus" in a second without running anything.

**`--check` runs in CI, path-filtered** — `.github/workflows/oracle.yml`. It is also run by
hand, and by the orchestrator at merge.

> **⚠ Amendment (I-REM, 2026-09-09) — this read "deliberately not wired into CI", on two
> reasons. One is answered; the other was wrong in kind.**
>
> - *"It would add six minutes to every run."* Answered by the **path filter**: the workflow
>   fires only on `tidal/**`, `examples/**`, `scripts/oracles/**`,
>   `tests_cosmo/data/oracles/**`, `uv.lock` and its own file — i.e. on exactly the commits
>   the standing rule below is about, and on no others.
> - *"It would make CI fail the day legacy is deleted — the exact coupling this milestone
>   exists to prevent."* This is **not a coupling to avoid; it is a guard with an expiry**,
>   the same shape as #537. A legacy-integrity job is *deleted with* the capabilities it
>   re-runs, not maintained past them. **The expiry is recorded in the workflow header and in
>   `repo_reshape.md` §7's M3 retire row**: `oracle.yml` goes when legacy `inspect` and
>   `validate` go, at M6/M7. The coupling the milestone actually exists to prevent is a
>   *test* that imports or shells out to legacy — which is why the fixtures are frozen data
>   and `tests_cosmo/test_oracles.py` asserts against files, never a live run.
>
> The standing rule below was enforced by nothing until now. A rule stated in prose is not
> enforcement.

## The standing rule

> **If `tidal/` or `examples/data/` changes, re-run this script in the same commit.**

An action rather than a prohibition. "Never edit legacy" is unenforceable and would forbid
fixing an open bug; this is checkable in review, and `--check` is its detector. Without it
the frozen reports can end up describing specs that no longer produce them — an oracle
silently inconsistent with itself, which is the worst failure mode a gate can have.

## Retirement

This directory retires with the legacy tree. Once M3's semantic mapping
(`repo_reshape.md` §5.2) is written and recorded, the fixtures have done their job and go
with `tidal/`; nothing here is maintained beyond that point.

GH #525 · milestone M0.5 · umbrella #488.
