# .devcontainer Quick Reference

## 📁 Directory Map

| Folder      | Purpose         | Key Files                                                                         |
| ----------- | --------------- | --------------------------------------------------------------------------------- |
| `/docs/`    | Documentation   | WOLFRAM_GUIDE.md, XACT_TESTS.md                                                   |
| `/scripts/` | Utility scripts | setup-wolfram-links.sh, build-xperm.sh, install-lsp-wl.sh, etc.                   |
| `/tests/`   | Test suite      | test-all-xact.sh, test-xtensor.wls, test-xcoba.wls, etc.                          |

## 🎯 First-Time Setup

**The six steps are in [docs/WOLFRAM_GUIDE.md](docs/WOLFRAM_GUIDE.md)** — the single source.
Summarized only; follow the guide, not this box:

```bash
# 1. put WolframEngine_14.3.0_LIN.sh (~1.6 GiB) in third_party/
bash scripts/install-wolfram-engine.sh          # 2. onto the mount
wolframscript -activate                         # 3. your own Wolfram ID, once
bash scripts/install-xact-xcoba.sh              # 4. xAct 1.3.0
bash .devcontainer/scripts/build-xperm.sh       #    + the xPerm MathLink binary
bash scripts/install-psalter.sh                 # 5. PSALTer + resource registration
bash scripts/verify-wolfram-setup.sh --require-psalter   # 6. must exit 0
```

---

## 🚀 Common Commands

### Validate Complete Setup

```bash
bash scripts/verify-wolfram-setup.sh                    # 11 checks
bash scripts/verify-wolfram-setup.sh --require-psalter  # the certification gate
```

### Run All Tests

```bash
.devcontainer/tests/test-all-xact.sh
```

### Re-wire Wolfram after installing or activating

```bash
bash .devcontainer/scripts/setup-wolfram-links.sh
```

### Manage Licensing

```bash
bash .devcontainer/scripts/wolfram-activation-manager.sh status
bash .devcontainer/scripts/wolfram-activation-manager.sh backup
bash .devcontainer/scripts/wolfram-activation-manager.sh restore
```

### Install Extensions

```bash
bash .devcontainer/scripts/install-extensions-final.sh
```

### Run Individual Tests

```bash
wolframscript .devcontainer/tests/test-xtensor.wls
wolframscript .devcontainer/tests/test-xcoba.wls
wolframscript .devcontainer/tests/test-xperm.wls
wolframscript .devcontainer/tests/test-xpert.wls
wolframscript .devcontainer/tests/test-integration.wls
```

## 📖 Documentation

- **Setup Guide**: `.devcontainer/docs/WOLFRAM_GUIDE.md`
- **Test Guide**: `.devcontainer/docs/XACT_TESTS.md`
- **Container Config**: `.devcontainer/README.md`

## 🔧 Scripts Reference

### Setup Scripts (First-Time)

Setup lives in `scripts/`, not here — see [docs/WOLFRAM_GUIDE.md](docs/WOLFRAM_GUIDE.md).
`validate-setup.sh` and `check-wolfram.sh` remain as redirects to
`scripts/verify-wolfram-setup.sh`.

### Maintenance Scripts

| Script                          | Purpose                    | Usage                                                                                |
| ------------------------------- | -------------------------- | ------------------------------------------------------------------------------------ |
| `build-xperm.sh`                | Compile xPerm from source  | `bash .devcontainer/scripts/build-xperm.sh`                                          |
| `setup-wolfram-links.sh`        | Wire engine/license/cache  | `bash .devcontainer/scripts/setup-wolfram-links.sh`                                  |
| `fix-xperm.sh`                  | Fix xPerm issues           | `bash .devcontainer/scripts/fix-xperm.sh`                                            |
| `install-extensions-final.sh`   | Install VS Code extensions | `bash .devcontainer/scripts/install-extensions-final.sh`                             |
| `wolfram-activation-manager.sh` | Manage licensing           | `bash .devcontainer/scripts/wolfram-activation-manager.sh [status\|backup\|restore]` |

## ✅ What's Working

- ✅ Wolfram Engine 14.3.0 (activated once; the license persists on a mount)
- ✅ xAct 1.3.0 bundle (xTensor 1.3.0, xPerm 1.2.4, xCore 0.6.10, xCoba 0.8.6)
- ✅ xPerm MathLink (compiled from source against this image's GLIBC 2.36)
- ✅ PSALTer `bb45adb0` with its two resources registered locally
- ✅ Complete test suite (100% passing)
- ⚠️ VS Code extensions — **manual**: `install-extensions-final.sh`

## 📊 Test Status

```
✅ xTensor Core Algebra
✅ xCoba Coordinates
✅ xPerm Permutations (MathLink active)
✅ xPert Perturbations
✅ Full Integration (Schwarzschild computation)

Success Rate: 100% (5/5 tests passing)
```

---

**For detailed information**, see:

- Setup/troubleshooting → `.devcontainer/docs/WOLFRAM_GUIDE.md`
- Testing → `.devcontainer/docs/XACT_TESTS.md`
