# PSALTer spectrograph fixtures — provenance

Two small published PSALTer result files, committed so the Stage-1 reader can be
tested **without Wolfram installed**. That property is the whole reason they are
here: everything else in the PSALTer chain needs a Wolfram Engine and a
single-licence lane, and a reader that can only be tested behind that lane would
effectively be untested.

Added by #526 (Wave 0). Consumed by the Stage-1 reader, #527.

## What these files are

Spectrograph exports in Wolfram's **WXF** binary serialization format — that is,
*data outputs of a computation*, not program source.

They were produced by the PSALTer/`ParticleSpectroscopy` pipeline of
arXiv:2606.30785's supplementary material. Note that **PSALTer itself writes no
WXF** (#523): `ParticleSpectrum` populates two association keys and `DumpSave`s a
`.mx`; the spectrograph PDF goes out separately. So these `.wxf` files come from
an **uncommitted curation step** in the polology work, which is also why key
names vary between exports — they were assembled by hand rather than by a single
writer. A reader must therefore be defensive: normalize keys, tolerate
plural/singular variants, and treat a bare unevaluated symbol as *absent*.

## Exact source

| | |
|---|---|
| Repository | `https://github.com/wevbarker/SupplementalMaterials-2607` |
| Pinned revision | `b49e9f1d5410ac19884cf9837190be975a58927b` |
| Upstream paths | `WolframLanguage/ParticleSpectrographVectorTheory.wxf`, `WolframLanguage/ParticleSpectrographA23Theory.wxf` |
| Retrieved | 2026-09-07 |

Re-fetch with the committed route, which pins the same revision:

```bash
bash scripts/research/psalter_stage1/fetch_reference_sources.sh
# -> third_party/psalter_reference/sm2607/   (gitignored)
```

## Integrity

```
8958f32de7530abfc0c261d23084d59652f1fcf2c9fcfa1edb71e5dfd5e0c2ed  ParticleSpectrographVectorTheory.wxf
ff48c3f9fa22bb3e57cef99be6a20497d21896e6d5676ef3b5901718ff650bcb  ParticleSpectrographA23Theory.wxf
```

Sizes: 692 B and 2,874 B. Verify with `sha256sum -c`, or run
`tests_cosmo/test_psalter_fixtures.py`, which checks both digests and sizes.

`.gitattributes` marks `*.wxf` as `binary`. This is not decorative. The files
contain lone CR bytes (5 and 41 respectively) and **no NUL bytes at all**, so
git's `text=auto` heuristic classified them as *text*; they survive normalization
only because they happen to contain no CRLF pairs. That is a property of which
byte values occur, not a guarantee, and the digests above are the gate.

## Licensing position

The upstream repository is **GPL-3.0-or-later**; TIDAL is **MIT**. The position
taken here is that these two files are **data outputs of a computation, not "the
Program"**, and that committing them is therefore not distribution of GPL source.
Reading and adapting the upstream work is explicitly authorized (decision **D6** —
the author's permission is on the record, and borrowed code carries provenance in
its docstrings).

This is stated as a **position, not a settled conclusion.** It is flagged on
**#495** for the release-time licence review regardless of the reasoning above.

These two files are the only upstream bytes committed anywhere in this
repository. Everything else — PSALTer itself, the supplemental sources, the
Tier-1 oracle — is fetched into gitignored `third_party/`, per the rule recorded
in `scripts/research/psalter_stage1/README.md`: commit the route, not the
payload. These are the deliberate exception, for the testability reason above.

## Known defect in this data — read before building a test on it

The released **positional** spin labelling (`SPIN_LABELS = {"0+","1-","2+"}`) is
demonstrably wrong on `A23Theory`, whose `J`-blocks mix parities. Upstream's own
`JuliaExport.m` comments assert the positional convention that its own fixture
contradicts.

So a reader test must assert **block dimensions**, never the positional labels:
`A23Theory` has three `J`-blocks of dimensions 2, 4 and 2, satisfying
`2·1 + 4·3 + 2·5 = 24`. Per-state `J^P` labels have to be exported explicitly
(decision recorded in `docs/COSMOLOGY_PROGRAM.md`), not inferred from position.

**Second caution, found on the live install (#542).** For the Vector theory, the
association keys `WaveOperator` and `PseudoDeterminant` come back *without* the
mass term, while the rendered spectrograph shows the published
`(Def²(Θ₂−Θ₁) − Θ₃)/2` and `(−Def²Θ₁ − Θ₃)/2`. `stage1_engineering_plan.md` §7
specifies a reader gate demanding the published values exactly. Establish which
artifact actually carries them **before** writing that gate; as specified it
would fail against a correct install.
