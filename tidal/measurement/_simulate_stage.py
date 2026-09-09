"""Simulate stages for executing one parameter point.

Runs one point's simulation, either to disk (:func:`simulate_run`) or wholly
in memory (:func:`run_inference_step`), and prepares a worker process to do so
(:func:`init_worker`).  Reached through :mod:`tidal.measurement._run_stages`,
which re-exports these names; that module's docstring carries the layering
rationale and the history.

These lived in ``tidal.cli._sweep`` until ``tidal sweep`` was retired (#533).

**The residual coupling this file owns.**  Every function here ultimately calls
``tidal.cli._simulate._simulate``, the 3,126-line simulation driver, plus its
``_parse_params`` helper.  That is one of exactly two edges from
:mod:`tidal.measurement` into :mod:`tidal.cli`, and it is deliberate: turning it
around means relocating the driver, which is M4/M5 work under the cosmology
programme (``docs/cosmology/repo_reshape.md`` section 7).  Keeping it alone in
this file means that relocation touches one file.

Every ``tidal.cli`` import below is function-local, so importing this module
does not import :mod:`tidal.cli`.
"""

from __future__ import annotations

import time
from typing import TYPE_CHECKING

import numpy as np

if TYPE_CHECKING:
    from argparse import Namespace
    from pathlib import Path

    from tidal.measurement._io import SimulationData
    from tidal.symbolic.json_loader import EquationSystem

__all__ = ["init_worker", "run_inference_step", "simulate_run"]


def _build_sim_args(
    base_args: Namespace,
    param_overrides: dict[str, float],
    output_dir: Path | None,
    grid_shape_override: int | None = None,
    *,
    replicate_seed: int | None = None,
    ic_perturbation: float | None = None,
) -> Namespace:
    """Build a simulate-compatible Namespace for one run.

    Copies all simulation flags from *base_args* and overrides
    parameters and output path.

    Parameters
    ----------
    output_dir : Path | None
        Directory to write snapshots to.  Pass ``None`` for the in-memory
        inference path (``run_inference_step``) — the returned Namespace
        will have ``output=None`` and no disk-writer will be set up.
    replicate_seed : int, optional
        If set, overrides ``ic_noise_seed`` and ``ic_perturbation_seed``
        for ensemble variation across replicates.
    ic_perturbation : float, optional
        If set, enables IC perturbation with this scale.
    """
    import copy

    sim_args = copy.copy(base_args)

    # Clear simulate-specific resume flags — sweep has its own boolean
    # --resume (resume interrupted sweep), which must not leak into
    # _simulate() where --resume expects a directory path string.
    sim_args.resume = None
    sim_args.snapshot = None
    sim_args.t_additional = None

    # Override parameters: merge base --param list with sweep overrides
    base_params: list[str] = list(getattr(base_args, "param", []) or [])
    for k, v in param_overrides.items():
        # Remove any existing override for this key
        base_params = [p for p in base_params if not p.startswith(f"{k}=")]
        base_params.append(f"{k}={v}")
    sim_args.param = base_params

    if output_dir is None:
        # In-memory path (inference): no disk writer, no plot.  _simulate
        # sees output=None and skips both _setup_disk_writer_native and
        # _generate_output (gated on in_memory_out is not None).
        sim_args.output = None
        sim_args.output_format = None
        sim_args.no_plot = True
    else:
        # Output to subdirectory (force directory format for disk-backed streaming)
        # Note: no_plot must be False because _infer_output_format checks it first
        # and would return "summary" (skipping disk write). Instead, set
        # output_format="directory" which gets checked after no_plot.
        sim_args.output = str(output_dir)
        sim_args.output_format = "directory"
        sim_args.no_plot = False
    sim_args.quiet = True

    # Grid shape override for convergence mode
    if grid_shape_override is not None:
        sim_args.grid_shape = str(grid_shape_override)

    # Ensemble seed injection — each replicate gets independent seeds for
    # IC noise and IC perturbation via SeedSequence.spawn() to avoid
    # correlated randomness when both are active simultaneously.
    if replicate_seed is not None:
        children = np.random.SeedSequence(replicate_seed).spawn(2)
        sim_args.ic_noise_seed = int(children[0].generate_state(1)[0])
        sim_args.ic_perturbation_seed = int(children[1].generate_state(1)[0])

    # IC perturbation scale
    if ic_perturbation is not None:
        sim_args.ic_perturbation = ic_perturbation

    return sim_args


def simulate_run(
    base_args: Namespace,
    spec_path: Path,
    param_overrides: dict[str, float],
    output_dir: Path,
    grid_shape_override: int | None = None,
    *,
    replicate_seed: int | None = None,
    ic_perturbation: float | None = None,
    spec: EquationSystem | None = None,
) -> tuple[int, float, EquationSystem]:
    """Execute a single simulation and return (exit_code, wall_time_s, spec).

    Returning the loaded ``EquationSystem`` allows callers to reuse it
    for measurement without a redundant file read + JSON parse.
    """
    from tidal.cli._simulate import (
        _parse_params,  # pyright: ignore[reportPrivateUsage]
        _simulate,  # pyright: ignore[reportPrivateUsage]
    )

    sim_args = _build_sim_args(
        base_args,
        param_overrides,
        output_dir,
        grid_shape_override,
        replicate_seed=replicate_seed,
        ic_perturbation=ic_perturbation,
    )
    if spec is None:
        from tidal.symbolic import load_equation_system

        spec = load_equation_system(spec_path)
    params = _parse_params(sim_args.param, spec)

    # normalize_kinetic_coefficients band-aid removed: the modal solver
    # now reads `kinetic_coefficient_symbolic` directly into the M
    # diagonal (see tidal/solver/modal.py _build_evolution_matrices).
    t0 = time.monotonic()
    exit_code = _simulate(sim_args, spec, params)
    wall_time = time.monotonic() - t0
    return exit_code, wall_time, spec


def run_inference_step(
    base_args: Namespace,
    spec_path: Path,
    param_overrides: dict[str, float],
    spec: EquationSystem | None = None,
) -> SimulationData:
    """Run one simulation in-memory for the inference likelihood path.

    Same setup as :func:`simulate_run` but wires an
    :class:`InMemoryAccumulator` (via ``_simulate(..., in_memory_out=...)``)
    in place of the :class:`SnapshotWriter`, returning the resulting
    ``SimulationData`` directly without any disk round-trip.  This skips
    the ~600-800 ms/eval penalty documented in issue #269.

    Raises
    ------
    RuntimeError
        If the underlying ``_simulate`` call fails.
    """
    from tidal.cli._simulate import (
        _parse_params,  # pyright: ignore[reportPrivateUsage]
        _simulate,  # pyright: ignore[reportPrivateUsage]
    )

    # output_dir=None: _build_sim_args clears sim_args.output and disables
    # both the disk writer and plot dispatch.  _simulate still sees
    # in_memory_out != None and populates the SimulationData.
    sim_args = _build_sim_args(base_args, param_overrides, output_dir=None)
    if spec is None:
        from tidal.symbolic import load_equation_system

        spec = load_equation_system(spec_path)
    params = _parse_params(sim_args.param, spec)

    sim_data_out: list[SimulationData] = []
    exit_code = _simulate(sim_args, spec, params, in_memory_out=sim_data_out)
    if exit_code != 0 or not sim_data_out:
        msg = f"in-memory simulate failed (exit code {exit_code})"
        raise RuntimeError(msg)
    return sim_data_out[0]


def init_worker() -> None:
    """Initialize a parameter-point worker process.

    Runs once per worker at Pool creation.  Two responsibilities:

    1. Set BLAS/LAPACK thread count to 1 — prevents thread oversubscription
       when running N parallel simulations, each of which would otherwise
       spawn its own BLAS thread pool.
    2. Pre-import the heavy solver / measurement / spec-loader modules.
       Without this, each worker pays a ~10 s cold-import cost on its first
       task (profiled against a 90-point sweep on sapphire: 16 cold tasks
       at 10 s each vs 74 warm tasks at 0.9 s each).  Paying the import
       cost once at worker startup amortizes it into pool creation and
       converts the sweep from ``16 cold + 74 warm / 16 workers ≈ 15 s
       compute wall`` to ``90 warm / 16 workers ≈ 5 s compute wall``.
    """
    import os

    for var in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS"):
        os.environ[var] = "1"

    # Pre-import the full solver/measurement stack so the first task each
    # worker picks up doesn't pay cold-import latency.  Imports intentionally
    # kept inside the function so the initializer is picklable and so
    # module-import side effects only fire in worker processes.
    import tidal.cli._simulate  # noqa: F401  # type: ignore[reportUnusedImport]
    import tidal.measurement._stability  # noqa: F401  # type: ignore[reportUnusedImport]
    import tidal.solver.grid  # noqa: F401  # type: ignore[reportUnusedImport]
    import tidal.solver.modal  # noqa: F401  # type: ignore[reportUnusedImport]
    import tidal.symbolic.json_loader  # noqa: F401  # type: ignore[reportUnusedImport]
