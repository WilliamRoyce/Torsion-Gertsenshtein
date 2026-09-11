#!/usr/bin/env bash
# CLI equivalents for the Polar Klein-Gordon 2+1D example
# See also: polar_kg.wls (manual derivation), polar_kg_simulation.py (Python simulation)
#
# NOTE: The derive step uses polar coordinates (r, theta) with a coordinate-dependent
# metric. Both TOML and manual .wls derivation are supported.
# The simulation works via CLI with --bc and --ic formula flags.
#
# To run manually:  cd examples/polar_kg

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
tidal inspect ../data/polar_kg.json

# Run simulation (Gaussian ring at r=3, Neumann in r, periodic in theta)
# Coordinates: x=r, y=theta
tidal simulate ../data/polar_kg.json \
  --param polm2=0.5 \
  --grid-shape 128 \
  --bounds 0.5:10,0:6.283185 \
  --bc neumann,periodic \
  --ic formula \
  --ic-formula "np.exp(-(x - 3.0)**2 / 0.5)" \
  --t-end 8.0 \
  --dt 0.005 \
  --scheme scipy
