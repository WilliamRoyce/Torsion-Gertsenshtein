"""Measure stage for executing one parameter point.

Dispatches the requested measurements against one run's output, either loaded
from disk (:func:`measure_run`) or already in memory
(:func:`measure_from_sim_data`).  Reached through
:mod:`tidal.measurement._run_stages`, which re-exports these names; that
module's docstring carries the layering rationale and the history.

These lived in ``tidal.cli._sweep`` until ``tidal sweep`` was retired (#533).

**The residual coupling this file owns.**  :func:`measure_from_sim_data`
dispatches through eleven private ``_run_*`` functions in
``tidal.cli._measure``.  That is one of exactly two edges from
:mod:`tidal.measurement` into :mod:`tidal.cli`, and it is deliberate: turning it
around means relocating those dispatchers, which retires with the ``measure``
subcommand at M5 (``docs/cosmology/repo_reshape.md`` section 7).  Keeping it
alone in this file means that relocation touches one file.

The ``tidal.cli`` import below is function-local, so importing this module does
not import :mod:`tidal.cli`.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, cast

import numpy as np

if TYPE_CHECKING:
    from pathlib import Path

    from tidal.measurement._io import SimulationData
    from tidal.symbolic.json_loader import EquationSystem

__all__ = ["measure_from_sim_data", "measure_run"]


def measure_run(
    run_dir: Path,
    spec_path: Path,
    measurements: set[str],
    source: tuple[str, ...] | None,
    target: tuple[str, ...] | None,
    threshold: float,
    spec: EquationSystem | None = None,
) -> dict[str, Any]:
    """Run all requested measurements on an existing simulation output.

    This is the single source of truth for measurement extraction in sweeps.
    Called both after a fresh simulation and when resuming a completed run.

    Returns a dict of scalar metrics.
    """
    from tidal.measurement._io import SimulationData

    if spec is None:
        from tidal.symbolic import load_equation_system

        spec = load_equation_system(spec_path)
    data = SimulationData.load(run_dir, spec)
    return measure_from_sim_data(data, measurements, source, target, threshold)


def measure_from_sim_data(
    data: SimulationData,
    measurements: set[str],
    source: tuple[str, ...] | None,
    target: tuple[str, ...] | None,
    threshold: float,
) -> dict[str, Any]:
    """Dispatch measurement functions against an in-memory SimulationData.

    Same logic as :func:`measure_run` minus the disk load.  Used by the
    Bayesian-inference likelihood path to skip the disk round-trip that
    dominates per-evaluation wall time (see issue #269).
    """
    from tidal.cli._measure import (
        _run_asymptotic,  # pyright: ignore[reportPrivateUsage]
        _run_conservation,  # pyright: ignore[reportPrivateUsage]
        _run_conversion,  # pyright: ignore[reportPrivateUsage]
        _run_dispersion,  # pyright: ignore[reportPrivateUsage]
        _run_effective_mass,  # pyright: ignore[reportPrivateUsage]
        _run_energy,  # pyright: ignore[reportPrivateUsage]
        _run_mixing,  # pyright: ignore[reportPrivateUsage]
        _run_peak_conversion,  # pyright: ignore[reportPrivateUsage]
        _run_resonance,  # pyright: ignore[reportPrivateUsage]
        _run_spectrum,  # pyright: ignore[reportPrivateUsage]
        _run_velocity,  # pyright: ignore[reportPrivateUsage]
    )

    metrics: dict[str, Any] = {}

    if "conservation" in measurements or "summary" in measurements:
        try:
            cons = _run_conservation(data, threshold)
            metrics["max_energy_error"] = cons["max_relative_error"]
            metrics["energy_conserved"] = cons["is_conserved"]
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["max_energy_error"] = None
            metrics["conservation_error"] = str(exc)

    conv_result = None
    if "conversion" in measurements or "summary" in measurements:
        try:
            conv = _run_conversion(data, source, target)
            metrics["P_max"] = conv["peak_probability"]
            metrics["P_max_time"] = conv["peak_time"]
            result_obj = conv["_result_obj"]
            metrics["P_final"] = float(result_obj.probability[-1])
            conv_result = result_obj
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["P_max"] = None
            metrics["conversion_error"] = str(exc)

    if (
        "mixing" in measurements or "summary" in measurements
    ) and conv_result is not None:
        try:
            mix = _run_mixing(conv_result)
            metrics["L_mix"] = mix["mixing_length"]
            metrics["L_mix_uncertainty"] = mix["mixing_length_uncertainty"]
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["L_mix"] = None
            metrics["mixing_error"] = str(exc)

    if "energy" in measurements:
        try:
            eng = _run_energy(data)
            metrics["E_total_final"] = eng["total"][-1]
            metrics["E_total_initial"] = eng["total"][0]
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["energy_error"] = str(exc)

    if "dispersion" in measurements:
        try:
            dyn = list(data.dynamical_fields)
            disp = _run_dispersion(data, dyn)
            result_obj = disp["_result_obj"]
            wn: np.ndarray[Any, np.dtype[np.floating[Any]]] = result_obj.wavenumbers
            freq: np.ndarray[Any, np.dtype[np.floating[Any]]] = (
                result_obj.peak_frequencies
            )
            active = freq > 0.0
            if np.any(active):
                m2_vals: np.ndarray[Any, np.dtype[np.floating[Any]]] = (
                    freq[active] ** 2 - wn[active] ** 2
                )
                metrics["m2_eff"] = float(np.median(m2_vals))
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["dispersion_error"] = str(exc)

    if "effective_mass" in measurements:
        try:
            dyn = list(data.dynamical_fields)
            em = _run_effective_mass(data, dyn)
            metrics["m2_eff"] = em["m2_eff"]
            metrics["m2_eff_std"] = em["m2_eff_std"]
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["effective_mass_error"] = str(exc)

    if "asymptotic" in measurements:
        try:
            asym = _run_asymptotic(data, source, target)
            metrics["P_asymptotic"] = asym["P_final"]
            metrics["P_transmitted"] = asym["P_transmitted"]
            metrics["P_reflected"] = asym["P_reflected"]
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["asymptotic_error"] = str(exc)

    if "peak_conversion" in measurements:
        try:
            if conv_result is not None:
                # Reuse conversion result already computed above
                peak_idx = int(np.argmax(conv_result.probability))
                metrics["P_max"] = float(conv_result.probability[peak_idx])
                metrics["P_max_time"] = float(conv_result.times[peak_idx])
                metrics["P_final"] = float(conv_result.probability[-1])
            else:
                pc = _run_peak_conversion(data, source, target)
                metrics["P_max"] = pc["P_max"]
                metrics["P_max_time"] = pc["P_max_time"]
                metrics["P_final"] = pc["P_final"]
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["peak_conversion_error"] = str(exc)

    if "velocity" in measurements:
        try:
            dyn = list(data.dynamical_fields)
            vel = _run_velocity(data, dyn)
            metrics["v_group_mean"] = vel["v_group_mean"]
            metrics["v_phase_mean"] = vel["v_phase_mean"]
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["velocity_error"] = str(exc)

    if "resonance" in measurements:
        try:
            res = _run_resonance(data, source, target)
            metrics["n_resonant_modes"] = res["n_resonant_modes"]
            metrics["conversion_bandwidth"] = res["conversion_bandwidth"]
            metrics["peak_conversion_k"] = res["peak_conversion_k"]
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["resonance_error"] = str(exc)

    if "spectrum" in measurements:
        try:
            spec_results = _run_spectrum(data)
            # Aggregate scalars from spectrum of each field
            for fname, field_spec in spec_results.items():
                if isinstance(field_spec, dict) and "final" in field_spec:
                    final = cast("dict[str, Any]", field_spec["final"])
                    power_data: list[float] = final["power"]
                    wn_data: list[float] = final["wavenumbers"]
                    power = np.array(power_data)
                    wn_arr = np.array(wn_data)
                    if power.max() > 0:
                        metrics[f"peak_k_{fname}"] = float(wn_arr[np.argmax(power)])
                        metrics[f"peak_power_{fname}"] = float(power.max())
                        threshold_val = 0.01 * power.max()
                        metrics[f"n_active_modes_{fname}"] = int(
                            np.sum(power > threshold_val),
                        )
        except (
            ValueError,
            TypeError,
            KeyError,
            OSError,
            RuntimeError,
            SystemExit,
        ) as exc:
            metrics["spectrum_error"] = str(exc)

    return metrics
