# Tier-1 cross-check on Wolfram 14.2.1 — captured 2026-09-11, engine then retired

**One-time historical measurement.** The Tier-1 investigation (#543) concluded that the engine
version plays no role, and the programme and meeting documents said so — but the run directory
the investigation cited had been deleted, so the claim had no artifact. This directory is that
artifact, captured on 2026-09-11 before the 14.2.1 engine was removed.

| | |
|---|---|
| engine | **14.2.1 for Linux x86 (64-bit) (March 25, 2025)** — `engine.txt`, `manifest.json`, `tier1_diff.json:environment` |
| selected by | `WOLFRAMSCRIPT_KERNELPATH=~/.local/wolfram/engine/14.2/Executables/WolframKernel` (overrides the `WolframScript.conf` pin) |
| input | the author's `ParticleSpectrographCTEG.m` @ `SupplementalMaterials-2506b` `37c86a5d`, **unmodified** (sha256 before = after, `manifest.json`) |
| oracle | the author's `ParticleSpectrographCTEG.mx` (`oracle_sha256` in `manifest.json`) |
| resources | the same local registration as the 14.3.0 certification (`d40a8dd6…`, `2f89f2e6…`) |
| verdict | **`MATCH`** — `PseudoDeterminant` identical (3×2, 71 leaves), `WaveOperator` identical (303 leaves); tally `{identical: 2}` |
| ladder rung A | `PASS` on the free scalar (`repro_A.log`, 34.9 s) |
| why a component run | the 14.2.1 front end cannot start headlessly here, so `run_tier1_gate.sh`'s check 9 refuses; this is the published script, `tier1_diff.wls` and `summarize_diff.py` run by hand, as the investigation describes |

**What it establishes.** With the two undeclared Function Repository resources registered,
14.2.1 reproduces the author's oracle exactly as 14.3.0 does. The engine hypothesis is refuted by
execution on both engines, not by reading.

**A second thing it establishes — the engine assertion works.** `summary_refused.txt` is
`summarize_diff.py` run on this diff *without* `EXPECTED_WOLFRAM_VERSION=14.2.1`:

```
REFUSED: this diff was produced by Wolfram 14.2.1, not the certified 14.3.0 (set EXPECTED_WOLFRAM_VERSION to certify anew)
```

That refusal is new (2026-09-11) and this was its first live firing: a run on a non-certified
engine — via a leftover `WOLFRAMSCRIPT_KERNELPATH`, or a `PATH` that reaches
`/opt/Wolfram`'s `wolframscript` — can no longer certify silently.

## Reproducing it

The 14.2.1 engine is **retired** (6.8 GB on the container overlay, referenced by nothing). To
repeat: `third_party/WolframEngine_14.2.1_LIN.sh` (1.6 GB, on the host bind mount) installs with
`sudo` into `~/.local/wolfram/engine/14.2` (see `docs/cosmology/psalter_543_investigation.md`
§6 for the launcher quirk); the shared `mathpass` validates without re-activation; then run the
three components above with `WOLFRAMSCRIPT_KERNELPATH` pointed at it and
`EXPECTED_WOLFRAM_VERSION=14.2.1` on the summarize step.
