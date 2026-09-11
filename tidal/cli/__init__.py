"""Command-line interface for the Lagrangian-to-PDE pipeline.

Entry point: ``tidal`` command with subcommands:

- ``tidal derive``   — Derive equations from Lagrangian via Wolfram/xAct
- ``tidal inspect``  — Display equation system information from JSON
- ``tidal simulate`` — Run PDE simulation from JSON specification
- ``tidal measure``  — Extract physics measurements from simulation output
- ``tidal list``     — List available JSON specifications
- ``tidal validate`` — Validate a JSON equation specification
- ``tidal doctor``   — Check environment health
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from tidal.solver._defaults import DEFAULT_ATOL, DEFAULT_RTOL

__all__ = ["main"]


def _build_parser() -> argparse.ArgumentParser:  # noqa: PLR0915
    """Build the top-level argument parser with subcommands."""
    # Use rich-argparse for colored help if available, fallback to default
    try:
        from rich_argparse import RichHelpFormatter  # type: ignore[import-untyped]

        formatter: type[argparse.HelpFormatter] = RichHelpFormatter  # type: ignore[reportUnknownVariableType]
    except ImportError:
        formatter = argparse.HelpFormatter

    parser = argparse.ArgumentParser(
        prog="tidal",
        description="Lagrangian-to-PDE pipeline: derive, inspect, simulate, measure, list, validate, doctor.",
        formatter_class=formatter,  # type: ignore[reportArgumentType]
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {_get_version()}",
    )
    parser.add_argument(
        "--no-banner",
        action="store_true",
        default=False,
        help="Suppress the startup banner",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        default=False,
        help="Show detailed diagnostic output (solver selection, CFL, Jacobian tier)",
    )
    parser.add_argument(
        "--cite",
        action="store_true",
        default=False,
        help="Print citation information for TIDAL and its dependencies",
    )
    parser.add_argument(
        "--time",
        action="store_true",
        default=False,
        help="Show wall-clock elapsed time after command completes",
    )
    sub = parser.add_subparsers(dest="command", help="Available commands")

    # --- derive ---
    derive_parser = sub.add_parser(
        "derive",
        aliases=["der"],
        help="Derive equations from Lagrangian via Wolfram/xAct",
        description=(
            "Generate equations of motion from a Lagrangian. "
            "Accepts a TOML config file (.toml) or a Wolfram script (.wls)."
        ),
        epilog=(
            "Examples:\n"
            "  tidal derive theory.toml                     # run derivation\n"
            "  tidal derive theory.toml --dry-run            # preview .wls without running\n"
            "  tidal derive theory.toml --save-script eq.wls # save generated script\n"
            "  tidal derive script.wls                       # run existing .wls directly"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    derive_parser.add_argument(
        "config",
        help="Path to .toml config or .wls script (auto-detected by extension)",
    )
    derive_parser.add_argument(
        "--save-script",
        metavar="PATH",
        default=None,
        help="Save generated .wls script to this path (TOML mode only)",
    )
    derive_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print generated .wls without running wolframscript",
    )
    derive_parser.add_argument(
        "--force-derive",
        action="store_true",
        help="Force re-derivation even if the generated script is unchanged",
    )
    derive_parser.add_argument(
        "--output",
        metavar="PATH",
        default=None,
        help="Override output JSON path from config",
    )
    derive_parser.add_argument(
        "--timeout",
        type=int,
        default=600,
        metavar="SECONDS",
        help=(
            "Maximum time (seconds) for wolframscript execution. "
            "Default: 600 (10 min). If exceeded, investigate which pipeline "
            "stage is the bottleneck and optimize. Use 0 for no timeout."
        ),
    )

    # --- inspect ---
    inspect_parser = sub.add_parser(
        "inspect",
        aliases=["insp"],
        help="Display equation system information from JSON",
        description="Load a JSON specification and display its contents.",
        epilog=(
            "Examples:\n"
            "  tidal inspect examples/data/klein_gordon_1d.json\n"
            "  tidal inspect spec.json --params    # show default parameter values"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    inspect_parser.add_argument(
        "json_path",
        help="Path to the JSON equation specification",
    )
    inspect_parser.add_argument(
        "--params",
        action="store_true",
        help="Show default parameter values from metadata",
    )
    inspect_parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output machine-readable JSON instead of human-readable text",
    )
    inspect_parser.add_argument(
        "--latex",
        action="store_true",
        help="Output equations as LaTeX math",
    )
    inspect_parser.add_argument(
        "--latex-format",
        choices=["align", "gather", "kinetic-matrix", "document", "raw"],
        default="align",
        dest="latex_format",
        help=(
            "LaTeX output format (default: align). "
            "'gather' wraps each equation in its own \\begin{aligned} block "
            "inside an outer \\begin{gather*} for per-equation centering "
            "(used by the Appendix-E driver). "
            "'kinetic-matrix' emits the linearized kinetic matrix "
            "\\mathcal{K}(\\partial_t, \\partial_z) as a bmatrix "
            "(used by the Appendix-E driver second pass). "
            "'document' wraps in standalone .tex"
        ),
    )
    inspect_parser.add_argument(
        "--symbols",
        type=Path,
        default=None,
        help=(
            "Path to a TOML symbol-override file (e.g. manuscript/latex_symbols.toml) "
            "binding project-specific tensor heads and parameter names to the "
            "macros and conventions of the surrounding manuscript. See "
            "tidal.symbolic.latex.load_symbol_overrides for the file shape."
        ),
    )
    # --- semantic query flags (#401) ---
    inspect_query = inspect_parser.add_argument_group(
        "semantic queries",
        "Read part of a spec through vetted accessors instead of by eye. "
        "Every sign verdict reports the tactic that decided it, and says "
        "'unknown' rather than guessing when it cannot prove an answer.",
    )
    inspect_query.add_argument(
        "--equation",
        metavar="FIELDS",
        default=None,
        help=(
            "Show a component's equation with effective coefficients (all "
            "matching terms summed, kinetic coefficient divided out). Accepts "
            "a comma-separated list, or 'all' for every component"
        ),
    )
    inspect_query.add_argument(
        "--coefficient",
        metavar="SELECTOR",
        default=None,
        help=(
            "Show one coefficient and every place it is recorded, e.g. "
            "'h_5:laplacian_x(h_5)'. Separates parts of the coefficient from "
            "redundant re-encodings and from the related-but-distinct "
            "Hamiltonian term"
        ),
    )
    inspect_query.add_argument(
        "--families",
        action="store_true",
        help=(
            "Group components into tensor families from tensor_head/tensor_indices "
            "metadata, flagging families whose grouping had to be guessed"
        ),
    )
    inspect_query.add_argument(
        "--diff",
        metavar="OTHER_JSON",
        default=None,
        help=(
            "Compare against another spec, separating real physics changes from "
            "equations merely rescaled. Exits 1 when real changes are found"
        ),
    )
    inspect_query.add_argument(
        "--param",
        action="append",
        metavar="KEY=VALUE",
        default=None,
        help=(
            "Parameter value for numeric corroboration (repeatable). Reported "
            "separately; never used to justify a structural verdict"
        ),
    )
    inspect_query.add_argument(
        "--assume-positive",
        dest="assume_positive",
        metavar="NAMES",
        default=None,
        help="Comma-separated parameters to assume strictly positive",
    )
    inspect_query.add_argument(
        "--assume-nonzero",
        dest="assume_nonzero",
        metavar="NAMES",
        default=None,
        help=(
            "Comma-separated parameters to assume non-vanishing without claiming "
            "a sign (e.g. kappa, whose vanishing would remove the Einstein-Hilbert "
            "term). Sharpens kappa^2 from '0+' to '+'"
        ),
    )
    inspect_query.add_argument(
        "--detail",
        choices=["summary", "full"],
        default="full",
        help=(
            "How much to print for the equation listing. 'summary' gives one "
            "line per operator-field key with only the proven sign, which is "
            "far cheaper for scanning a large spec; 'full' (default) gives the "
            "equations with their coefficients"
        ),
    )
    inspect_query.add_argument(
        "--fields",
        metavar="NAMES",
        default=None,
        help="Comma-separated output fields to keep, to bound --json output size",
    )

    # --- simulate ---
    sim_parser = sub.add_parser(
        "simulate",
        aliases=["sim"],
        help="Run PDE simulation from JSON specification",
        description="Build and run a PDE simulation from a JSON equation specification.",
        epilog=(
            "Examples:\n"
            "  tidal simulate spec.json --param m2=1.0 --t-end 10\n"
            "  tidal simulate spec.json --ic gaussian --ic-width 2.0 --output result.png\n"
            "  tidal simulate spec.json --mode constraint --bc neumann\n"
            "  tidal simulate spec.json --ic formula --ic-formula 'exp(-(x-5)**2)'"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sim_parser.add_argument(
        "json_path",
        nargs="?",
        default=None,
        help="Path to the JSON equation specification",
    )
    # Parameters
    sim_parser.add_argument(
        "--param",
        action="append",
        default=[],
        metavar="KEY=VAL",
        help="Set symbolic parameter (repeatable, e.g. --param m2=1.0)",
    )
    # Grid
    sim_parser.add_argument(
        "--grid-shape",
        default=None,
        metavar="N[,N,N]",
        help="Grid points per axis (e.g. 32 or 32,32,32). Default: auto from dimension",
    )
    sim_parser.add_argument(
        "--bounds",
        default=None,
        metavar="LO:HI[,...]",
        help="Domain bounds per axis (e.g. 0:20 or 0:20,0:10). Default: 0:10",
    )
    sim_parser.add_argument(
        "--periodic",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Use periodic boundary conditions (default: True)",
    )
    sim_parser.add_argument(
        "--bc",
        default=None,
        metavar="BC[,BC,BC]",
        help="Per-axis boundary conditions: periodic, neumann (comma-separated). Overrides --periodic.",
    )
    # Initial conditions
    sim_parser.add_argument(
        "--ic",
        choices=["gaussian", "plane-wave", "zero", "formula", "file", "noise"],
        default="gaussian",
        help="Initial condition type (default: gaussian)",
    )
    sim_parser.add_argument(
        "--ic-formula",
        default=None,
        metavar="EXPR",
        help="Math expression for --ic=formula. Variables: coordinate names (e.g. x,y,z), np (numpy), pi.",
    )
    sim_parser.add_argument(
        "--ic-center",
        default=None,
        metavar="X[,X,X]",
        help="Gaussian center position (default: domain midpoint)",
    )
    sim_parser.add_argument(
        "--ic-width",
        type=float,
        default=None,
        metavar="W",
        help="Gaussian width (default: domain_size/10)",
    )
    sim_parser.add_argument(
        "--ic-amplitude",
        type=float,
        default=1.0,
        metavar="A",
        help="IC peak amplitude (default: 1.0)",
    )
    sim_parser.add_argument(
        "--ic-component",
        default=None,
        metavar="NAME",
        help="Field component for IC (default: first field)",
    )
    sim_parser.add_argument(
        "--ic-wavevector",
        default=None,
        metavar="K[,K,K]",
        help="Wavevector for plane-wave or gaussian IC (e.g. 3 or 0.1,0.0,0.0). "
        "With gaussian: creates a traveling wave packet (positive k = right-mover). "
        "On periodic axes, k is automatically snapped to the nearest discrete "
        "Fourier mode to eliminate spectral leakage; use --ic-no-snap to disable.",
    )
    sim_parser.add_argument(
        "--ic-no-snap",
        action="store_true",
        help="Disable automatic snapping of --ic-wavevector to the nearest "
        "discrete Fourier mode on periodic grids. Legacy behavior: the IC "
        "is cos(k·x) evaluated verbatim at grid points, which leaks amplitude "
        "onto every discrete k-mode when k is off-grid. Only needed for "
        "reproducing pre-snap simulations or for theories where off-grid "
        "wavevectors are physically meaningful.",
    )
    sim_parser.add_argument(
        "--ic-formula-velocity",
        default=None,
        metavar="EXPR",
        help="Velocity (time derivative) expression for --ic=formula. "
        "Same namespace as --ic-formula (x, y, z, sin, cos, exp, ...).",
    )
    sim_parser.add_argument(
        "--ic-field",
        action="append",
        default=[],
        metavar="FIELD:EXPR",
        help="Per-field IC formula override (repeatable). "
        "Format: FIELD:EXPR or FIELD:velocity:EXPR. "
        "Applied after --ic. Example: --ic-field 'chi_0:0.1*sin(x)'",
    )
    sim_parser.add_argument(
        "--ic-file",
        default=None,
        metavar="PATH",
        help="Path to .npy file or simulation output directory for --ic=file.",
    )
    sim_parser.add_argument(
        "--no-closure-restriction",
        action="store_true",
        help="Disable the observable-sector closure restriction (GH #468). For "
        "localized theories with an implicit-dynamical sector whose full pencil "
        "cannot be evolved at double precision, tidal evolves the exactly closed "
        "sector excited by the IC and omits the rest (written as "
        "restricted_spec.json). With this flag the full system is attempted "
        "and refuses honestly.",
    )
    sim_parser.add_argument(
        "--ic-noise-seed",
        type=int,
        default=None,
        metavar="N",
        help="Random seed for --ic=noise (reproducible noise).",
    )
    # Mode
    sim_parser.add_argument(
        "--mode",
        choices=["evolve", "constraint"],
        default="evolve",
        help="'evolve' = time evolution (default), 'constraint' = single constraint solve",
    )
    # Solver
    sim_parser.add_argument(
        "--t-end",
        type=float,
        default=10.0,
        help="Simulation duration (default: 10.0)",
    )
    sim_parser.add_argument(
        "--dt",
        type=float,
        default=None,
        help="Time step (default: auto from CFL)",
    )
    sim_parser.add_argument(
        "--scheme",
        choices=["ida", "leapfrog", "cvode", "scipy", "modal", "modal-jax", "auto"],
        default="auto",
        help=(
            "Solver scheme (default: auto). "
            "'auto' selects the best adaptive solver: cvode for wave systems, "
            "ida for DAE/dissipative systems. "
            "'cvode' uses SUNDIALS/CVODE — adaptive BDF/Adams for wave systems. "
            "'ida' uses SUNDIALS/IDA — handles all equation types including constraints. "
            "'scipy' uses scipy.integrate.solve_ivp — DOP853/RK45/Radau/BDF. "
            "'leapfrog' uses symplectic Störmer-Verlet (fixed dt, zero energy drift)."
        ),
    )
    sim_parser.add_argument(
        "--rtol",
        type=float,
        default=DEFAULT_RTOL,
        help=f"Relative tolerance for adaptive solvers (default: {DEFAULT_RTOL})",
    )
    sim_parser.add_argument(
        "--atol",
        type=float,
        default=DEFAULT_ATOL,
        help=f"Absolute tolerance for adaptive solvers (default: {DEFAULT_ATOL})",
    )
    sim_parser.add_argument(
        "--method",
        type=str,
        default=None,
        help=(
            "Integration method (default: auto). "
            "cvode: 'BDF' (default) or 'Adams'. "
            "scipy: 'DOP853' (default), 'RK45', 'Radau', 'BDF', 'RK23', 'LSODA'."
        ),
    )
    sim_parser.add_argument(
        "--max-step",
        type=float,
        default=None,
        help=(
            "Maximum step size for adaptive solvers. "
            "Default: unbounded for cvode/ida, CFL dt for scipy."
        ),
    )
    sim_parser.add_argument(
        "--snapshots",
        type=float,
        default=None,
        metavar="DT",
        help=(
            "Snapshot interval (default: t_end/20, giving 21 snapshots). "
            "Use --snapshots=t_end for 2-snapshot inference runs."
        ),
    )
    sim_parser.add_argument(
        "--fd-order",
        type=int,
        choices=[2, 4, 6],
        default=4,
        help=(
            "Finite-difference accuracy order for spatial operators (default: 4). "
            "Higher orders use wider stencils: 2->3pt, 4->5pt, 6->7pt. "
            "Order 4 is recommended: O(dx^4) convergence at ~2x per-point cost "
            "vs order 2 — typically enables halving N for the same accuracy. "
            "Ref: Fornberg (1988), Mathematics of Computation 51(184)."
        ),
    )
    sim_parser.add_argument(
        "--leapfrog-order",
        type=int,
        choices=[2, 4],
        default=None,
        help=(
            "Leapfrog integrator order. Default: auto-detect (4 for time-independent "
            "non-dissipative systems, 2 otherwise). "
            "2 = Störmer-Verlet (1 force eval/step). "
            "4 = Yoshida triple-composition (3 force evals/step, O(dt⁴) accuracy). "
            "Yoshida allows ~2x larger dt for the same accuracy. "
            "Only applies when --scheme leapfrog is used. "
            "Ref: Yoshida (1990), Physics Letters A 150(5-7), pp. 262-268."
        ),
    )
    sim_parser.add_argument(
        "--spectral",
        action=argparse.BooleanOptionalAction,
        default=None,
        help=(
            "Use FFT-based spectral operators instead of finite-difference stencils. "
            "Default: auto-detect (enabled when all BCs are periodic and solver is "
            "not IDA). Use --no-spectral to force finite-difference stencils. "
            "Achieves exponential convergence for smooth problems -- typically "
            "N=64-128 instead of N=512-1024. "
            "Incompatible with --scheme ida (use leapfrog, cvode, or scipy). "
            "Ref: Burns et al. (2020), Phys. Rev. Research 2:023068."
        ),
    )
    sim_parser.add_argument(
        "--perturbative-order",
        type=int,
        default=None,
        metavar="N",
        help=(
            "Iterative perturbative expansion order for theories with a "
            "[perturbation] section (v6 plan). N=0 runs the base theory "
            "only; N=1 adds the closed-form Duhamel correction using Pass 0 "
            "eigendata. Default: 1 when the JSON metadata includes a "
            "'perturbation' block (emitted by ExportJSON.wl when "
            "[perturbation] is configured in theory.toml), 0 otherwise. "
            "Requires the modal solver (--scheme modal or auto). "
            "See docs/PERTURBATIVE_REDUCTION_IMPLEMENTATION.md."
        ),
    )
    # Output
    sim_parser.add_argument(
        "--output",
        default=None,
        metavar="DIR",
        help="Directory to write snapshots to (default: print a summary only)",
    )
    sim_parser.add_argument(
        "--format",
        choices=["summary", "directory"],
        default=None,
        dest="output_format",
        help="Output format (default: directory when --output is set, else summary)",
    )
    sim_parser.add_argument(
        "--dry-run",
        action="store_true",
        default=False,
        help="Preview simulation setup without running (grid, solver, IC, memory estimate)",
    )
    sim_parser.add_argument(
        "--list-schemes",
        action="store_true",
        default=False,
        help="List available solver schemes and exit",
    )
    sim_parser.add_argument(
        "--force",
        action="store_true",
        default=False,
        help="Overwrite existing --output directory without prompting",
    )
    sim_parser.add_argument(
        "--quiet",
        "-q",
        action="store_true",
        help="Suppress progress messages (results and errors still shown)",
    )
    # Note: --require-stable removed. The modal solver's eigenvalue pre-check
    # in _evolve_per_mode provides accurate instability detection using the
    # full evolution matrix. The old mass-only check produced false positives
    # for theories with non-unit kinetic coefficients (e.g., PGT torsion).
    sim_parser.add_argument(
        "--allow-inconsistent-ic",
        action="store_true",
        default=False,
        help=(
            "Allow inconsistent initial conditions for constraint equations. "
            "When set, constraint violations produce warnings instead of errors. "
            "Default: error if constraint ICs cannot be made consistent."
        ),
    )
    # Resume from checkpoint
    sim_parser.add_argument(
        "--resume",
        default=None,
        metavar="DIR",
        help=(
            "Resume simulation from a snapshot directory. "
            "Inherits grid, parameters, and BC from saved metadata. "
            "Loads final snapshot by default (use --snapshot N to pick)."
        ),
    )
    sim_parser.add_argument(
        "--snapshot",
        type=int,
        default=None,
        metavar="N",
        help="Snapshot index to resume from (default: last). Requires --resume.",
    )
    sim_parser.add_argument(
        "--t-additional",
        type=float,
        default=None,
        metavar="T",
        help=(
            "Additional simulation time beyond the checkpoint "
            "(alternative to --t-end when using --resume)."
        ),
    )

    # --- list ---
    list_parser = sub.add_parser(
        "list",
        aliases=["ls"],
        help="List available JSON specifications",
        description="Scan a directory for JSON equation specifications and display summaries.",
        epilog=(
            "Examples:\n"
            "  tidal list                          # scan default examples/data/\n"
            "  tidal list --dir /path/to/specs      # scan custom directory"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    list_parser.add_argument(
        "--dir",
        default=None,
        metavar="PATH",
        help="Directory to scan (default: examples/data/)",
    )

    # --- validate ---
    validate_parser = sub.add_parser(
        "validate",
        aliases=["val"],
        help="Validate a JSON equation specification",
        description="Check a JSON specification for errors (unknown operators, bad references, etc.).",
        epilog=(
            "Examples:\n"
            "  tidal validate examples/data/klein_gordon_1d.json\n"
            "  tidal validate spec.json --stability\n"
            "  tidal validate spec.json --stability --param m2=1.0"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    validate_parser.add_argument(
        "json_path",
        help="Path to the JSON equation specification to validate",
    )
    validate_parser.add_argument(
        "--stability",
        action="store_true",
        default=False,
        help=(
            "Run stability checks: tachyon detection (negative mass-matrix "
            "eigenvalues). Uses a 1-point grid; exact for constant-coefficient "
            "systems. Ghost detection is not included -- Hamiltonian kinetic "
            "coefficients alone cannot distinguish ghosts from gauge structure."
        ),
    )
    validate_parser.add_argument(
        "--param",
        action="append",
        default=[],
        metavar="KEY=VAL",
        help="Set symbolic parameter for stability check (repeatable, e.g. --param m2=1.0)",
    )

    # --- measure ---
    measure_parser = sub.add_parser(
        "measure",
        aliases=["meas"],
        help="Extract physics measurements from simulation output",
        description=(
            "Load simulation output from 'tidal simulate --output' and run "
            "measurement analyses (energy, conversion, mixing length, etc.)."
        ),
        epilog=(
            "Examples:\n"
            "  tidal measure result_dir/ --spec spec.json\n"
            "  tidal measure result_dir/ --json\n"
            "  tidal measure result_dir/ --what conversion --source phi_0 --target chi_0\n"
            "  tidal measure result_dir/ --what energy,conservation\n"
            "  tidal measure result_dir/ --output measurement.png"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    measure_parser.add_argument(
        "data_path",
        nargs="?",
        default=None,
        help="Path to the simulation output directory",
    )
    measure_parser.add_argument(
        "--list-types",
        action="store_true",
        default=False,
        help="List available measurement types and exit",
    )
    measure_parser.add_argument(
        "--spec",
        default=None,
        metavar="PATH",
        help="Path to JSON equation spec (auto-discovered from metadata.json if omitted)",
    )
    measure_parser.add_argument(
        "--what",
        default=None,
        metavar="TYPE[,TYPE,...]",
        help=(
            "Measurements to run (comma-separated). "
            "Options: summary, energy, conversion, mixing, spectrum, dispersion, "
            "conservation, effective_mass, asymptotic, peak_conversion, velocity, "
            "resonance. Default: summary"
        ),
    )
    measure_parser.add_argument(
        "--source",
        default=None,
        metavar="FIELD[,FIELD,...]",
        help="Source field(s) for conversion measurement (comma-separated)",
    )
    measure_parser.add_argument(
        "--target",
        default=None,
        metavar="FIELD[,FIELD,...]",
        help="Target field(s) for conversion measurement (comma-separated)",
    )
    measure_parser.add_argument(
        "--param",
        action="append",
        default=[],
        metavar="KEY=VAL",
        help="Override parameter value (repeatable, e.g. --param m2=1.0)",
    )
    measure_parser.add_argument(
        "--energy-threshold",
        type=float,
        default=1e-3,
        metavar="T",
        help="Energy conservation threshold (default: 1e-3)",
    )
    measure_parser.add_argument(
        "--output",
        default=None,
        metavar="PATH",
        help="Save measurement plot (.png or .pdf)",
    )
    measure_parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Output measurements as JSON instead of text",
    )
    measure_parser.add_argument(
        "--quiet",
        "-q",
        action="store_true",
        help="Suppress progress messages",
    )

    # --- doctor ---
    sub.add_parser(
        "doctor",
        aliases=["doc"],
        help="Check environment health (Python, dependencies, Wolfram, xAct)",
        epilog="""Examples:
  tidal doctor              # Full environment check
""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    # Shell completion (optional dependency: shtab)
    try:
        import shtab  # type: ignore[import-untyped]

        shtab.add_argument_to(parser)
    except ImportError:
        pass

    return parser


# ---------------------------------------------------------------------------
# Dispatch and entry point
# ---------------------------------------------------------------------------


def _get_version() -> str:
    """Return the package version string from installed metadata."""
    from importlib.metadata import PackageNotFoundError, version

    try:
        return version("tidal")
    except PackageNotFoundError:
        return "unknown"


_COMMAND_ALIASES: dict[str, str] = {
    "der": "derive",
    "insp": "inspect",
    "sim": "simulate",
    "ls": "list",
    "val": "validate",
    "meas": "measure",
    "doc": "doctor",
}


def _dispatch(args: argparse.Namespace) -> int:  # noqa: PLR0911
    """Lazily import and run the appropriate command handler.

    Parameters
    ----------
    args : argparse.Namespace
        Parsed CLI arguments with ``command`` attribute.

    Returns
    -------
    int
        Exit code from the command handler.

    Raises
    ------
    ValueError
        If ``args.command`` is not a recognized subcommand.
    """
    cmd = _COMMAND_ALIASES.get(args.command, args.command)
    if cmd == "derive":
        from tidal.cli._derive import derive_command

        return derive_command(args)
    if cmd == "inspect":
        from tidal.cli._inspect import inspect_command

        return inspect_command(args)
    if cmd == "simulate":
        from tidal.cli._simulate import simulate_command

        return simulate_command(args)
    if cmd == "list":
        from tidal.cli._list import list_command

        return list_command(args)
    if cmd == "validate":
        from tidal.cli._validate import validate_command

        return validate_command(args)
    if cmd == "measure":
        from tidal.cli._measure import measure_command

        return measure_command(args)
    if cmd == "doctor":
        from tidal.cli._doctor import doctor_command

        return doctor_command(args)
    msg = f"Unknown command: {cmd}"
    raise ValueError(msg)


# Subcommands retired with the M0 drop rows (#533).  argparse would already
# refuse these as an invalid choice, but that message says nothing about where
# the capability went -- and every deleted driver script in this repository's
# history invokes one of them.  This is the tombstone those scripts hit.
_RETIRED_COMMANDS: dict[str, str] = {
    "sweep": "sweep",
    "sw": "sweep",
    "sample": "sample",
    "samp": "sample",
    "analyze": "analyze",
    "plot": "plot",
}

_RETIRED_REPLACEMENT: dict[str, str] = {
    "sweep": "Cobaya's samplers drive parameter campaigns in the new pipeline.",
    "sample": "Cobaya ships PolyChord; inference runs through it (decision D9).",
    "analyze": "GetDist and anesthetic read the chains directly.",
    "plot": "GetDist for posteriors, anesthetic for nested-sampling output.",
}

# The module each subcommand actually lived in.  `plot` is not `_plot.py`:
# that was `tidal simulate`'s rendering helper, retired alongside but never the
# subcommand's implementation.  Getting this wrong is the exact confusion #533
# was scoped on, so it is spelled out rather than derived from the name.
_RETIRED_MODULE: dict[str, str] = {
    "sweep": "_sweep.py",
    "sample": "_sample.py",
    "analyze": "_analyze.py",
    "plot": "_plot_command.py",
}


def _refuse_retired_command(argv: list[str] | None) -> int | None:
    """Refuse a retired subcommand, or return None if *argv* names none.

    Returns the exit code to use, so the caller needs one branch rather than
    a lookup followed by a dispatch.
    """
    tokens = sys.argv[1:] if argv is None else argv
    name = next(
        (_RETIRED_COMMANDS.get(tok) for tok in tokens if not tok.startswith("-")),
        None,
    )
    if name is None:
        return None
    print(
        f"error: `tidal {name}` was retired after v0.53.0.\n"
        f"  {_RETIRED_REPLACEMENT[name]}\n"
        f"  The thesis-era implementation remains at tag v0.53.0:\n"
        f"    git show v0.53.0:tidal/cli/{_RETIRED_MODULE[name]}\n"
        f"  Rationale: docs/cosmology/repo_reshape.md section 5.",
        file=sys.stderr,
    )
    return 2


def _maybe_print_banner(args: argparse.Namespace) -> None:
    """Print the startup banner for long-running commands and bare ``tidal``.

    Quick commands (list, validate, inspect, measure) skip it, as does --cite,
    which is info-only.
    """
    if (
        args.no_banner
        or os.environ.get("TIDAL_NO_BANNER")
        or args.cite
        or _COMMAND_ALIASES.get(args.command, args.command)
        not in {None, "simulate", "derive"}
    ):
        return

    from tidal.banner import print_banner

    print_banner(
        theme=os.environ.get("TIDAL_BANNER_THEME", "ocean"),
        layout=os.environ.get("TIDAL_BANNER_LAYOUT", "auto"),
        version=_get_version(),
    )


def main(argv: list[str] | None = None) -> int:
    """CLI entry point.

    Parameters
    ----------
    argv : list[str] | None
        Command-line arguments. If None, uses sys.argv.

    Returns
    -------
    int
        Exit code (0 for success, non-zero for errors).
    """
    retired = _refuse_retired_command(argv)
    if retired is not None:
        return retired

    parser = _build_parser()
    args = parser.parse_args(argv)

    _maybe_print_banner(args)

    if args.cite:
        from tidal.cli._cite import print_citation

        print_citation()
        return 0

    if args.command is None:
        parser.print_help()
        return 0

    from tidal.cli._console import configure as _configure_console
    from tidal.cli._console import error as _console_error

    _configure_console(
        verbose=getattr(args, "verbose", False),
        quiet=getattr(args, "quiet", False),
    )

    import time

    t0 = time.perf_counter()
    try:
        rc = _dispatch(args)
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        rc = 130
    except FileNotFoundError as exc:
        from tidal.cli._console import error_with_hint

        error_with_hint(
            str(exc),
            [
                "Run 'tidal list' to see available specifications.",
                "Run 'tidal derive <theory.toml>' to generate from a Lagrangian.",
            ],
        )
        rc = 1
    except (ValueError, TypeError) as exc:
        _console_error(str(exc))
        rc = 1
    except RuntimeError:
        import traceback

        traceback.print_exc()
        rc = 1

    if args.time:
        elapsed = time.perf_counter() - t0
        if elapsed >= 60:  # noqa: PLR2004
            mins = int(elapsed // 60)
            secs = elapsed % 60
            print(
                f"[TIME] {args.command} completed in {mins}m {secs:.1f}s",
                file=sys.stderr,
            )
        else:
            print(f"[TIME] {args.command} completed in {elapsed:.2f}s", file=sys.stderr)

    return rc
