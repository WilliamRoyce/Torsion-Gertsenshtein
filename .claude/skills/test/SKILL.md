---
name: test
description: Run pytest with smart scope detection based on recently changed files. Use after any code change or when the user says "run tests".
---

# Smart Test Runner

## Changed files
!`(git diff --name-only HEAD 2>/dev/null; git diff --name-only --staged 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null) | sort -u`

## Instructions

Map changed source files to test files using these rules:
- `tidal/solver/X.py` → `tests/test_solver_X.py`
- `tidal/solver/modal.py` → `tests/test_solver_modal.py`
- `tidal/cli/_X.py` → `tests/test_cli.py` and `tests/test_cli_parsing.py`
- `tidal/measurement/_X.py` → `tests/test_measurement.py` and `tests/test_new_measurements.py`
- `tidal/symbolic/` → `tests/test_json_loader.py`
- `tidalcosmo/X.py` → `tests_cosmo/test_X.py` (the new package; see `docs/COSMOLOGY_PROGRAM.md`)
- `tidal/wolfram/` → Wolfram tests only (skip unless user asks for full suite)
- If no mapping found or changes span many modules → run full suite

Run: `uv run pytest <matched_test_files> -x -q $ARGUMENTS`

If nothing matches, or the change spans both packages, run the whole thing **pathless**:
`uv run pytest -x -q`. A path argument overrides `testpaths` in `pyproject.toml`
(`["tests", "tests_cosmo"]`), which silently skips the cosmology suite.

If user provides explicit arguments (e.g., `/test tests/test_solver_modal.py -k eigendecomp`), pass them through directly.

Report: number of tests run, pass/fail count, execution time.
If any test fails, show the failure output and suggest a fix.