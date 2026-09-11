#!/usr/bin/env bash
# Gertsenshtein Effect — Derive → Inspect → Simulate → Measure
#
# Physics: Graviton-photon conversion in uniform background magnetic field B0.
# The Einstein-Maxwell Lagrangian is linearized around flat spacetime + B0,
# producing coupled wave equations for h_+ (graviton) and a_y (photon).
#
# Gauge choices (standard for linearized Einstein-Maxwell, see e.g. Dandoy et al. 2024):
#   h: TT gauge (transverse-traceless) — standard for linearized gravity
#   a: Lorenz gauge (d_mu a^mu = 0) — decouples EM into wave equations
# Together these reduce the full tensor+vector system to just h_+ and a_y.
#
# After constraint elimination (traceless, transverse → gradient-zero), the
# 3+1D system reduces to 6 fields in 1+1D:
#   h_7 ↔ a_2  (plus polarization — Gertsenshtein channel)
#   h_5 ↔ a_1  (cross polarization — decoupled, stays zero)
#   a_0, a_3   (gauge modes — decoupled free waves, stay zero)
#
# Initial condition: monochromatic plane wave on h_7 (graviton h_+).
# Plane-wave IC matches the analytical derivation and avoids spectral
# broadening of a Gaussian wave packet.
# Wavevector k = 2π·32/100 ≈ 2.011 ensures k >> B₀κ (massless limit)
# and integer wavelengths in the domain (no spectral leakage).
#
# Validation: P(graviton -> photon) = sin^2(kappa * B0 * D / 2)
# with D = c * t_end = 200.
# Derived from eigenmode analysis of coupled h_7/a_2 system.
#
# Running:
#   cd examples/gertsenshtein && bash run.sh

set -euo pipefail
cd "$(dirname "$0")"

OUT=../data/gertsenshtein_output

echo "=== Gertsenshtein Effect: Graviton-Photon Conversion ==="
echo ""

# Step 1: Derive coupled equations from Einstein-Maxwell Lagrangian
echo "--- Step 1: Derive ---"
# The committed spec under ../data/ is the frozen legacy oracle (tests_cosmo/data/oracles,
# #525/#554): re-deriving in place overwrites it with the current generator's output.
# Opt in explicitly.  FORCE_DERIVE=1 ./run.sh
if [[ "${FORCE_DERIVE:-0}" == "1" ]]; then
    tidal derive theory.toml
else
    echo "skipping 'tidal derive theory.toml' -- the committed spec is the oracle; FORCE_DERIVE=1 to re-derive in place"
fi
echo ""

# Step 2: Inspect the derived JSON (expect 6 fields after elimination)
echo "--- Step 2: Inspect ---"
tidal inspect ../data/gertsenshtein.json
echo ""

# Step 3: Simulate — plane wave graviton propagating through B0 region
# k = 2π·32/100 ≈ 2.011 (32 wavelengths in domain, 16 pts/wavelength)
# t_end = 200 → D = 200, giving ~2 full Rabi oscillation cycles at B0=0.3
echo "--- Step 3: Simulate ---"
tidal simulate ../data/gertsenshtein.json \
  --grid-shape 512 \
  --bounds 0:100 \
  --periodic \
  --ic plane-wave \
  --ic-wavevector 2.0106 \
  --ic-amplitude 0.1 \
  --ic-component h_7 \
  --t-end 200.0 \
  --param kappa=1.0 --param B0=0.3 \
  --output "$OUT"

echo ""

# Step 4: Measure energy conservation and conversion
echo "--- Step 4: Measure ---"
tidal measure "$OUT" --what conservation --param kappa=1.0 --param B0=0.3
tidal measure "$OUT" --what conversion --param kappa=1.0 --param B0=0.3
tidal measure "$OUT" --what energy --param kappa=1.0 --param B0=0.3
echo ""

# Step 5: Plots
echo "--- Step 5: Plots ---"



echo ""
echo "=== Done ==="
echo "Plots saved to: $OUT/"
ls "$OUT"/*.png 2>/dev/null | sed 's|.*/|  |'
