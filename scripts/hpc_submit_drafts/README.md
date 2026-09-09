# Frozen campaign geometry and configuration

What remains here is **data, not drivers**. The submit scripts that once filled
this tree drove `tidal sweep` and `tidal sample`, and were deleted when those
subcommands were retired (#533); recover any of them with
`git show v0.53.0:scripts/hpc_submit_drafts/<path>`.

These two files stayed because nothing about them depends on a retired CLI:

- `v3e_localised/_geometry.env` — the frozen Phase E localised geometry
  (`BPEAK`, `SIGB`). Read by `scripts/v3e_boccaletti_preflight.py` and its test,
  `tests/test_v3e_boccaletti_preflight.py`, both of which still run. The values
  are a settled choice — see `docs/PHASE_E_TRACKER.md` before changing them.
- `v3_atlas/_atlas_config.env` — the Phase E atlas configuration recorded by
  `docs/PHASE_E_ATLAS_TRACKER.md`.

They were briefly deleted along with the drivers around them and restored in the
same PR: a directory-level purpose test swept up files whose purpose was not
driving anything. Check for readers before removing either.
