#!/usr/bin/env bash
# Spherical Klein-Gordon (radial plane wave) — Reduced 1+1D pipeline
#
# Physics: Klein-Gordon in spherical coordinates, plane-wave reduction
# along x(=r) (radial propagation, d/d(theta) = d/d(phi) = 0).
# The reduced EOM: d2t(phi) = d2r(phi) + (2/r)*dr(phi) - m2*phi.
# Volume element: r^2 (from factored sqrt|det(g_spatial)|).
#
# Energy conservation: E = integral[ (v^2 + (dr phi)^2 + m2*phi^2) r^2 dr ]
# is exactly conserved (verified analytically: boundary terms vanish).
#
# This tests curved-coordinate reduction with:
#   - Position-dependent coefficient (2/r from Christoffel)
#   - Non-trivial volume element (r^2)
#   - All angular operators eliminated
#
# Running this script:
#   cd examples/spherical_kg_1d && bash run.sh

set -euo pipefail
cd "$(dirname "$0")"

OUT=../data/spherical_kg_1d_output

# Derive equations from Lagrangian (requires wolframscript)
# tidal derive theory.toml

# Inspect the equation system (should show 1+1D with volume_element)
tidal inspect ../data/spherical_kg_1d.json

# Run 1D simulation (Gaussian shell at r=4, Neumann BCs)
# Bounds start at 0.5 to avoid r=0 singularity in 2/r coefficient.
# Use N=256 for adequate resolution — Neumann BCs with curved coordinates
# introduce O(dx^2) energy measurement error at boundaries.
tidal simulate ../data/spherical_kg_1d.json \
  --grid-shape 256 \
  --bounds 0.5:10 \
  --bc neumann \
  --ic gaussian \
  --ic-width 0.5 \
  --ic-center 4.0 \
  --t-end 5.0 \
  --output "$OUT"

# --- Analysis plots ---

# Spacetime heatmap: phi_0 radial evolution

# Profile evolution at multiple times (shows 1/r spreading)

# Peak amplitude vs time (should decay as ~1/r due to spherical spreading)

# Hamiltonian energy decomposition (volume-weighted with r^2)

# Energy conservation check (should be excellent with volume weighting)

# Compare initial vs final profile

echo ""
echo "Analysis complete. Plots saved to: $OUT/"
ls -la "$OUT"/*.png 2>/dev/null || echo "  (no plots generated)"
