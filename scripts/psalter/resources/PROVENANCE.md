# Provenance — `PolynomialDegree-1-0-0-definition.nb`

The Wolfram Function Repository *definition notebook* for `PolynomialDegree` (v1.0.0),
contributed by Dennis M Schneider. `scripts/psalter/register_resources.wl` evaluates the
author's definition **verbatim** from this file and registers it locally under a fixed
identity, because PSALTer calls `ResourceFunction["PolynomialDegree"]` at three sites and
declares it nowhere (GH #543).

| | |
|---|---|
| source | `https://www.wolframcloud.com/download/c64bf854-fcd3-40f3-9aa2-4ec399411d8f?extension=always&filename=PolynomialDegree-1-0-0-definition` |
| retrieved | 2026-09-11, by the I-543 session |
| sha256 | `c233e226d4c77de65ee19ddbc84c20c9724df467bb86c27f1a65f17fba89787c` |
| size | 114,394 bytes |
| pinned by | `register_resources.wl` (refuses on mismatch), `ensure_registered.sh`, `scripts/research/psalter_stage1/fetch_reference_sources.sh` |

## Why it is committed

Certification of the PSALTer install must not depend on a live cloud URL: the Function
Repository returned 503, then 401 for anonymous clients, then truncated responses even for an
authenticated one during the week #543 was open (#551). A fresh clone now carries everything
the certified configuration needs — `LinearlyIndependent` ships inside the Wolfram Engine's
own `ResourceFunctionHelpers` paclet (byte-identical to the userbase copy the certification
used), and this file supplies the other one.

## Licensing position

Function Repository submissions are published for reuse through `ResourceFunction`, and this
notebook is the author's code as the repository distributes it, used unmodified and credited.
This is a **position, not a settled conclusion**: it is flagged on **#495** with the committed
`.wxf` fixtures and the `.mx` evidence for release-time review, and the fallback if it cannot
stand is the pinned download in `fetch_reference_sources.sh`.
