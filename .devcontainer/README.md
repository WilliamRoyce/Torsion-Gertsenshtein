# DevContainer Configuration

This directory contains the complete development container setup for the TIDAL project, with integrated Wolfram Engine 14.3 and xAct tensor computation framework.

## Directory Structure

```
.devcontainer/
├── README.md                 # This file
├── devcontainer.json         # Main VS Code dev container configuration
├── test-noble.json          # Test configuration (legacy)
├── docs/                     # Documentation files
│   ├── WOLFRAM_GUIDE.md     # Complete Wolfram Engine setup and usage guide
│   └── XACT_TESTS.md        # xAct test suite documentation
├── scripts/                  # Utility scripts for setup and maintenance
│   ├── setup-wolfram-links.sh         # Wire the mounted engine, license and cache
│   ├── build-xperm.sh                 # Build xPerm from source for current GLIBC
│   ├── fix-xperm.sh                   # Fall back to pure-Mathematica xPerm
│   ├── install-lsp-wl.sh              # Wolfram Language Server + paclets
│   ├── install-extensions-final.sh    # Install VS Code extensions
│   ├── notify-install-extensions.sh   # Extension installation notification
│   ├── reindex-claude-sessions.sh     # Rebuild the Claude session index
│   ├── setup-swap.sh                  # Swap file for large derivations
│   ├── sync-claude-memory.sh          # Back up / restore Claude memory
│   ├── validate-setup.sh              # -> scripts/verify-wolfram-setup.sh
│   ├── check-wolfram.sh               # -> scripts/verify-wolfram-setup.sh
│   └── wolfram-activation-manager.sh  # Manage Wolfram licensing and activation
└── tests/                    # Comprehensive test suite
    ├── test-all-xact.sh              # Master test runner (runs all tests below)
    ├── test-xtensor.wls              # Test xTensor (abstract tensor algebra)
    ├── test-xcoba.wls                # Test xCoba (coordinate-based computations)
    ├── test-xperm.wls                # Test xPerm (permutation algorithms + MathLink)
    ├── test-xpert.wls                # Test xPert (perturbation theory)
    ├── test-integration.wls          # Integration test (Schwarzschild computation)
    ├── test-xact.wls                 # Combined xAct test (legacy)
    └── comprehensive-xact-test.wls   # Comprehensive test suite (legacy)
```

## First-Time Setup

**See [docs/WOLFRAM_GUIDE.md](docs/WOLFRAM_GUIDE.md).** It is the single source for Wolfram
setup: six steps from a bare machine to the certified configuration, ending at

```bash
bash scripts/verify-wolfram-setup.sh --require-psalter   # exit 0
```

Do not follow setup instructions from anywhere else — three paths used to disagree here and
none of them reached PSALTer (GH #559).

A container whose engine is not installed yet still finishes creating: `postCreateCommand`
guards every Wolfram step and prints the install steps.

### Wolfram Engine Management

Check Wolfram Engine health:

```bash
bash scripts/verify-wolfram-setup.sh
```

Manage activation and licensing:

```bash
bash .devcontainer/scripts/wolfram-activation-manager.sh status
bash .devcontainer/scripts/wolfram-activation-manager.sh backup
bash .devcontainer/scripts/wolfram-activation-manager.sh restore
```

Install or update VS Code extensions:

```bash
bash .devcontainer/scripts/install-extensions-final.sh
```

## Key Features

### Wolfram Engine Integration

- **Version**: 14.3.0
- **Licensing**: `mathpass` in the mounted userbase — offline, and **not** a cloud login
- **Persistence**: All licensing and activation data persists across rebuilds
- **MathLink**: Enabled for high-performance computations with xPerm

### xAct Tensor Framework

- **xTensor**: Abstract tensor algebra
- **xCoba**: Coordinate-based computations
- **xPerm**: Advanced permutation algorithms (MathLink enabled)
- **xPert**: Systematic perturbation theory

### VS Code Configuration

- **Extensions**: 16 pre-configured extensions (Python, Ruff, Prettier, GitHub Copilot, etc.)
- **Python Support**: Full debugging, linting, and testing setup
- **Settings**: Format on save, auto-import organization, pytest configuration

## Development Workflow

### First-Time Setup (New Users)
The six steps in [docs/WOLFRAM_GUIDE.md](docs/WOLFRAM_GUIDE.md) — about 30 minutes, mostly
download.

### Every Container Build
1. **Host directories**: `initializeCommand` creates the bind-mount sources on the host
2. **Container Creation**: `onCreateCommand`, then `postCreateCommand`
3. **Mounts**: engine, userbase and caches are already populated — nothing is reinstalled
4. **Wolfram wiring**: `setup-wolfram-links.sh` re-creates the links and `WolframScript.conf`
5. **Claude state**: memory restored, session index rebuilt
6. **PSALTer resources**: re-registered — the registry is a volume, but a fresh one starts empty
7. **Extension Installation**: manual via `install-extensions-final.sh`

The license is **not** restored from a backup: `mathpass` persists because the userbase is a
mount. What `.activation_backup` restores is wolframscript's cloud tokens, which nothing in
TIDAL needs.

## Important Notes

- **Mounts**: 6 mounts ensure everything persists across rebuilds:
  - Engine: `~/.local/wolfram/engine/14.3` (host bind)
  - User base: `~/.local/wolfram/userbase` (host bind)
  - Machine ID: `/etc/machine-id` (host bind, read-only)
  - Cache: `~/.cache/Wolfram` (host bind)
  - Claude data: `~/.claude` (named volume)
  - Wolfram resource registry: `~/.Wolfram` (named volume) — without it PSALTer writes a
    silently wrong spectrum after every rebuild

- **GLIBC Compatibility**: xPerm is compiled from source to match container's GLIBC version (2.36)

- **File Paths**: All scripts and documentation reference files using relative paths (e.g., `.devcontainer/docs/WOLFRAM_GUIDE.md`)

## Documentation

See the comprehensive guides in the `docs/` folder:

- **WOLFRAM_GUIDE.md**: Complete Wolfram Engine setup, licensing, activation, and troubleshooting
- **XACT_TESTS.md**: xAct test suite documentation and usage

## Troubleshooting

If tests fail or Wolfram Engine isn't working:

1. Verify: `bash scripts/verify-wolfram-setup.sh --require-psalter`
2. Re-wire the links: `bash .devcontainer/scripts/setup-wolfram-links.sh`
3. Re-register PSALTer resources: `bash scripts/psalter/ensure_registered.sh`
4. Read [docs/WOLFRAM_GUIDE.md](docs/WOLFRAM_GUIDE.md) — troubleshooting lives there

## Contact & Updates

For issues or updates related to xAct framework, visit:

- xAct homepage: http://xact.es
- xPerm MathLink: Part of xAct 1.3.0+
