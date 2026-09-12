#!/usr/bin/env bash
# ==============================================================================
# Wolfram Engine Activation Script
# ==============================================================================
# Install step 3 of the six in .devcontainer/docs/WOLFRAM_GUIDE.md: a thin
# wrapper around `wolframscript -activate`.
#
# What activation is, and is not. It is a one-time, interactive exchange with
# your own Wolfram ID; the ENGINE (not this script) then writes a license file,
# mathpass, into $UserBaseDirectory/Licensing. In this dev container that is
# $HOME/.local/wolfram/userbase/Licensing/mathpass, which is bind-mounted from
# the host -- so it survives container rebuilds and you activate once, not once
# per rebuild.
#
# It is NOT a cloud login. Nothing in the TIDAL pipeline needs a Wolfram Cloud
# session: WOLFRAMSCRIPT_KERNELPATH is pinned to the mounted kernel, so
# evaluation is local. The cloud tokens under ~/.cache/Wolfram are a separate,
# optional thing, and `.activation_backup` backs up those tokens -- never the
# license.
#
# Usage:
#   ./scripts/activate-wolfram.sh [--interactive | --check]
#
# Options:
#   --interactive  Run interactive activation (default)
#   --check        Check current activation status
#
# ==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if Wolfram Engine is installed
check_installation() {
    # The mounted kernel, never `command -v wolframscript`: the dev container
    # image ships a standalone client at /usr/bin that evaluates in the CLOUD, so
    # `command -v` succeeds with no engine installed -- and activation would then
    # be attempted against nothing (#559).
    local kernel="${HOME}/.local/wolfram/engine/14.3/Executables/WolframKernel"
    if [[ ! -x "$kernel" ]]; then
        log_error "Wolfram Engine is not installed on the mount"
        log_error "  expected kernel: ${kernel}"
        log_error "Run install step 2 first: bash scripts/install-wolfram-engine.sh"
        exit 1
    fi

    if ! command -v wolframscript &> /dev/null; then
        log_error "wolframscript is not on PATH"
        log_error "Run: bash .devcontainer/scripts/setup-wolfram-links.sh"
        exit 1
    fi
}

# Check current activation status
check_activation() {
    log_info "Checking activation status..."
    
    # Try to run a simple computation
    local result
    if result=$(wolframscript -code '1+1' 2>&1); then
        if [[ "$result" == "2" ]]; then
            log_info "✓ Wolfram Engine is activated and working!"
            
            # Get version info
            local version
            version=$(wolframscript -code '$VersionNumber' 2>/dev/null || echo "unknown")
            log_info "  Version: ${version}"
            
            # Get license info
            local license_type
            license_type=$(wolframscript -code '$LicenseType' 2>/dev/null || echo "unknown")
            log_info "  License Type: ${license_type}"
            
            return 0
        fi
    fi
    
    log_warn "✗ Wolfram Engine is not activated"
    log_warn "  Error: ${result}"
    return 1
}

# Interactive activation
activate_interactive() {
    log_info "Starting interactive activation..."
    log_info ""
    log_step "You will be prompted to enter your Wolfram ID credentials."
    log_step "If you don't have a Wolfram ID, create one at: https://account.wolfram.com/"
    log_info ""
    
    wolframscript -activate
    
    # Verify activation
    if check_activation; then
        log_info "Activation successful!"
        return 0
    else
        log_error "Activation may have failed. Please try again."
        return 1
    fi
}

# --env is retired. It demanded WOLFRAM_ID and WOLFRAM_PASSWORD, then admitted it
# could not use them and ran the same interactive `wolframscript -activate` as
# --interactive: a mode that did nothing but ask for a password first (#559).
activate_with_env() {
    log_error "--env was removed: it never used the credentials it asked for."
    log_error "  wolframscript -activate cannot take a Wolfram ID non-interactively."
    log_error ""
    log_error "  Activate interactively, once:   bash scripts/activate-wolfram.sh"
    log_error "  For an unattended machine, activate once and keep the userbase:"
    log_error "    mathpass lives in \$HOME/.local/wolfram/userbase/Licensing/ and is"
    log_error "    bind-mounted from the host, so it survives container rebuilds."
    log_error ""
    log_error "  Recover the old behavior, if you really want it:"
    log_error "    git show v0.54.1:scripts/activate-wolfram.sh"
    exit 2
}

# Show help for activation
show_activation_help() {
    log_info "=========================================="
    log_info "Wolfram Engine Activation Guide"
    log_info "=========================================="
    echo ""
    echo "OPTION 1: Interactive Activation (Recommended)"
    echo "  Run: wolframscript -activate"
    echo "  - Enter your Wolfram ID (email)"
    echo "  - Enter your password"
    echo ""
    echo "OPTION 2: Web-based Activation"
    echo "  1. Run: wolframscript -activate"
    echo "  2. Choose web-based activation option"
    echo "  3. Visit the URL provided"
    echo "  4. Complete activation in browser"
    echo ""
    echo "OPTION 3: License File (Enterprise)"
    echo "  - Copy mathpass to \$HOME/.local/wolfram/userbase/Licensing/"
    echo "    (~/.WolframEngine is a symlink to that directory, so either path works)"
    echo "  - Contact your Wolfram administrator for details"
    echo ""
    echo "WHERE ACTIVATION LANDS:"
    echo "  \$HOME/.local/wolfram/userbase/Licensing/mathpass -- bind-mounted from"
    echo "  the host, so you activate once, not once per container rebuild."
    echo "  This is a license, not a cloud login: nothing in TIDAL needs a Wolfram"
    echo "  Cloud session, and evaluation is local to the mounted kernel."
    echo ""
    echo "CREATING A WOLFRAM ID:"
    echo "  1. Visit: https://account.wolfram.com/login/create"
    echo "  2. Create a free account"
    echo "  3. Wolfram Engine free license includes:"
    echo "     - 2GB memory limit"
    echo "     - Single machine use"
    echo "     - Non-commercial/educational use"
    echo ""
    log_info "=========================================="
}

# Main function
main() {
    local mode="interactive"
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --interactive|-i)
                mode="interactive"
                shift
                ;;
            --env|-e)
                mode="env"
                shift
                ;;
            --check|-c)
                mode="check"
                shift
                ;;
            --help|-h)
                show_activation_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $arg"
                echo "Usage: $0 [--interactive | --env | --check | --help]"
                exit 1
                ;;
        esac
    done
    
    check_installation
    
    case $mode in
        check)
            check_activation
            ;;
        interactive)
            activate_interactive
            ;;
        env)
            activate_with_env
            ;;
    esac
}

# Run main function
main "$@"
