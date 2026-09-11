#!/usr/bin/env bash
# Massive 3-Form 3+1D — Full derive → inspect → simulate pipeline
#
# Physics: Antisymmetric rank-3 tensor: 64 components reduce to 4 independent
# (C_0..C_3) via epsilon symmetry. Each component satisfies a massive
# Klein-Gordon equation: ∂²C_i/∂t² = ∇²C_i - m²C_i.
#
#
# Running this script:
#   cd examples/massive_3form && bash run.sh
#
# Or run each step manually:
#   tidal derive theory.toml
#   tidal inspect ../data/massive_3form.json
#   tidal simulate ../data/massive_3form.json --param m2=1.0 \
#     --grid-shape 16 --bounds 0:10 --periodic --ic gaussian \
#     --ic-component C_0 --ic-width 1.5 --t-end 5.0

set -euo pipefail
cd "$(dirname "$0")"

# Derive equations from Lagrangian (requires wolframscript)
# The committed spec under ../data/ is the frozen legacy oracle (tests_cosmo/data/oracles,
# #525/#554): re-deriving in place overwrites it with the current generator's output.
# Opt in explicitly.  FORCE_DERIVE=1 ./run.sh
if [[ "${FORCE_DERIVE:-0}" == "1" ]]; then
    tidal derive theory.toml
else
    echo "skipping 'tidal derive theory.toml' -- the committed spec is the oracle; FORCE_DERIVE=1 to re-derive in place"
fi

# Inspect the equation system
tidal inspect ../data/massive_3form.json

# Run simulation (Gaussian pulse in C_0, other components start at zero)
tidal simulate ../data/massive_3form.json \
  --rtol 1e-4 \
  --atol 1e-6 \
  --param m2=1.0 \
  --grid-shape 16 \
  --bounds 0:10 \
  --periodic \
  --ic gaussian \
  --ic-component C_0 \
  --ic-width 1.5 \
  --t-end 5.0
