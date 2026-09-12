# Tier-1 gate — independent re-run under the hardened mechanics, 2026-09-11 (MATCH)

`VERDICT: MATCH`, both keys `identical`. This directory exists for three reasons the
certifying run's own directory (`../tier1-20260911-pass/`) could not serve:

1. **It is a second run, by a second session, from a clean run directory.** The
   wave-boundary checklist requires exactly that of a lane-held gate — "a delegate's recorded
   verdict is not verification". I-543 ran the gate at `15:11:15Z`; this run is
   `20:19:19Z`, started from an **empty** `~/.Wolfram/Objects` (the rebuild simulation, below).
   The two `tier1_diff.json` files differ in **one field**, `generated_utc`; every comparison,
   dimension, leaf count and reason is identical.
2. **It carries the run's own `ParticleSpectrographCTEG.mx`** as `ours.mx` (1,652 B, sha256 in
   `manifest.json` → `ours_mx_sha256`), so the verdict can be recomputed rather than read back.
   Decision, 2026-09-11: our `.mx` is a *data output* of running the author's script on this
   install — the same position as the committed `.wxf` fixtures, flagged on #495 — whereas the
   author's `.m`/`.mx` remain fetched, never committed (`run_tier1_gate.sh`'s payload rule).
3. **Its manifest records the environment the 15:11 run's could not** — `wolfram_version`
   (added to `run_tier1_gate.sh` in this hardening), the xAct bundle, the registered UUIDs and
   the file hashes they were built from.

## What produced it

```bash
bash scripts/psalter/ensure_registered.sh   # registry was EMPTY; this re-created it
bash scripts/psalter/run_tier1_gate.sh      # 7m47s wall, preflight included
```

`ensure_registered.sh` is idempotent and exits non-zero on any failure. Here it ran against a
registry that had been moved aside — the rebuild path a container recreate takes — and produced
the **same two UUIDs** the certification used (`d40a8dd6-…`, `2f89f2e6-…`), from the
engine-bundled/userbase `LinearlyIndependent.wl` (sha256 `7bc228a2…`, asserted) and the
committed definition notebook (sha256 `c233e226…`, asserted). `verify-wolfram-setup.sh
--require-psalter` then returned 0 with provenance asserted on master *and* subkernel.

## Reading it back, and recomputing it

```bash
# read-only, no Wolfram, nothing written; exit 0 means match
python3 scripts/psalter/summarize_diff.py docs/cosmology/evidence/tier1-20260911-recert/tier1_diff.json

# recompute from ours.mx against the oracle (fetches the pinned reference sources)
cp -r docs/cosmology/evidence/tier1-20260911-recert third_party/psalter_runs/recert-check
mv third_party/psalter_runs/recert-check/ours.mx \
   third_party/psalter_runs/recert-check/ParticleSpectrographCTEG.mx
bash scripts/psalter/run_tier1_gate.sh --diff-only third_party/psalter_runs/recert-check
```

Copy first: `--diff-only` **writes** `tier1_diff.json` into the directory it is given, and it
refuses to write under `docs/` (#544, where a recompute over the evidence destroyed it). The
recomputed artifact will differ from the committed one in `generated_utc` and nothing else.
`summarize_diff.py` additionally **refuses** (`REFUSED`, exit 1) any artifact whose
`environment.wolfram_version` is not `EXPECTED_WOLFRAM_VERSION` (14.3.0) — see
`../tier1-20260911-engine-142/summary_refused.txt` for that refusal firing.

## What the assertions behind this run guarantee — each watched fail

| assertion | probe that reddened it |
| --- | --- |
| both names resolve to the **certified UUIDs**, master and subkernel | `EXPECTED_RESOURCE_UUIDS` set to a wrong pair → two `[FAIL]` lines |
| the registration is **present and ours** | deleted `PolynomialDegree`'s name entry → resolution fell through to the repository's `b9d713ba-…`, whose function returned `$Failed`; `[FAIL]` on behavior *and* provenance |
| the kernel is the **mounted engine** | `EXPECTED_ENGINE_DIR=/nonexistent/engine` → `[FAIL] Kernel is NOT the local engine` (this also closes the cloud-evaluation false pass: `wolframscript` evaluates in the cloud when no local kernel exists) |
| the **xAct bundle** is the certified one | fingerprint set to `xTensor=1.2.0` → `[DEGRADED]` |
| the **verdict's engine** is 14.3.0 | `summarize_diff.py` on the 14.2.1 artifact → `REFUSED`, exit 1 |

Provenance, not behavior, is the point: before this hardening check 10 asserted only that the
two functions *behaved*, which a resource fetched from the repository would also do — so a
rebuild could have produced a green gate on an uncertified leg.

## What this configuration is independent of

- **The Wolfram-ID cloud login.** Asserted both ways with the cloud reachable: logged in (this
  run — the harder case, since a logged-in kernel has a third resolution leg) and logged out (a
  kernel started with `WOLFRAMSCRIPT_AUTHENTICATIONPATH` at an empty directory: `$CloudConnected`
  False, `$WolframID` None, both names resolving to the same UUIDs, `verify --require-psalter`
  exit 0). By-name lookup is **local-first and short-circuits** (`ResourceSystemClient` 1.26.1,
  `Path.m:29-42`, `FindResource.m:23-34`), so a healthy registry cannot be pre-empted by the
  repository. Nobody is logged out for this: the login lives in the user's own home mounts,
    never in the repo, and the pipeline never uses it. Do **not** simulate logged-out with `CloudDisconnect[]`. Measured here, on 2026-09-11: it deleted the userbase `ApplicationData/CloudObject/Authentication/RecentUser/` record and **left the machine logged out of the Wolfram Cloud** — a fresh kernel now reports `$WolframID = None`, and `CloudConnect[]` returns `$Failed` even with the cloud reachable (HTTP 200), so the remaining `~/.cache/Wolfram/WolframScript/connection_*` credential (still byte-identical) does not restore the session on its own. Engine **activation** is untouched (`$LicenseType = Professional`) and nothing in the pipeline needs the login, so this costs capability, not correctness — but restoring it takes one interactive step, `wolframscript -authenticate`. The non-destructive way to test the logged-out case is the environment variable alone: `WOLFRAMSCRIPT_AUTHENTICATIONPATH` at an empty directory.
- **The engine minor version.** 14.2.1 returned the same verdict on the same input
  (`../tier1-20260911-engine-142/`), which is why that engine could be retired.

## The one failure mode nothing can prevent

The resolver **silently unregisters** a name whose stored object fails `ResourceObjectQ`
(`FindResource.m:76-83`) and falls through to the repository. No hook can stop that. What the
provenance assertion guarantees is that it cannot pass unnoticed — the verify goes red naming
the foreign UUID — and the `wolfram-objects` volume (#559, I-ONB) keeps a container rebuild
from taking the registry with it. The repair is `bash scripts/psalter/ensure_registered.sh`.
