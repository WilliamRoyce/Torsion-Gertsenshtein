#!/usr/bin/env bash
# ==============================================================================
# xAct & xCoba Installation Script
# ==============================================================================
# This script installs xAct and xCoba packages for symbolic tensor algebra in
# the Wolfram Engine user applications directory.
#
# It includes GLIBC compatibility fixes by recompiling the xPerm binary.
#
# Usage:
#   ./scripts/install-xact-xcoba.sh [--version VERSION]
#
# Options:
#   --version VERSION  xAct version to install (default: 1.3.0, the certified bundle)
#
# ==============================================================================

set -euo pipefail

# Configuration
# The certified xAct is the CODE, not the tarball label: scripts/verify-wolfram-setup.sh
# asserts the four package $Version strings of the 1.3.0 bundle (xCore 0.6.10,
# xPerm 1.2.4, xTensor 1.3.0, xCoba 0.8.6). The "1.2.1" this defaulted to was
# never a measurement -- it was this line, copied into three documents (#559).
XACT_VERSION="${XACT_VERSION:-1.3.0}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WOLFRAM_USER_DIR=""

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

# Check if Wolfram Engine is available
check_wolfram() {
    # The mounted kernel first, and on its own line. `command -v wolframscript` is
    # not an engine test: the dev container image ships a standalone client at
    # /usr/bin that evaluates in the CLOUD, so it succeeds with no engine at all,
    # and the "1+1" probe below would then pass against the cloud (#559).
    local kernel="${HOME}/.local/wolfram/engine/14.3/Executables/WolframKernel"
    if [[ ! -x "$kernel" ]]; then
        log_error "Wolfram Engine is not installed on the mount"
        log_error "  expected kernel: ${kernel}"
        log_error "Run install steps 1-3 from .devcontainer/docs/WOLFRAM_GUIDE.md:"
        log_error "  bash scripts/install-wolfram-engine.sh"
        log_error "  wolframscript -activate"
        exit 1
    fi

    if ! command -v wolframscript &> /dev/null; then
        log_error "wolframscript is not on PATH"
        log_error "Run: bash .devcontainer/scripts/setup-wolfram-links.sh"
        exit 1
    fi
    
    # Test basic functionality
    if ! wolframscript -code "1+1" >/dev/null 2>&1; then
        log_error "Wolfram Engine is not properly activated"
        log_error "Run: ./scripts/activate-wolfram.sh"
        exit 1
    fi
    
    log_info "Wolfram Engine is available and activated"
}

# Get Wolfram user base directory
get_wolfram_user_dir() {
    WOLFRAM_USER_DIR=$(wolframscript -code '$UserBaseDirectory' 2>/dev/null | tr -d '\n' | tr -d '\r')
    
    if [[ -z "$WOLFRAM_USER_DIR" ]]; then
        log_error "Could not determine Wolfram user directory"
        exit 1
    fi
    
    log_info "Wolfram user directory: ${WOLFRAM_USER_DIR}"
}

# Install development dependencies for recompiling xPerm binary
install_build_deps() {
    log_step "Installing build dependencies for xPerm binary compilation..."
    
    if command -v apt-get &> /dev/null; then
        # A transient mirror failure must not abort the installer under `set -e` (#546): the
        # cached package lists are usually good enough, and the `install` below is the step
        # that actually has to succeed -- it stays fatal, and fails with a real message if the
        # stale lists turn out to be insufficient.
        sudo apt-get update -qq || log_warn "apt-get update failed; continuing with cached package lists"
        sudo apt-get install -y --no-install-recommends uuid-dev gcc build-essential
    else
        log_warn "Package manager not recognized. Ensure gcc, build-essential, and uuid-dev are installed"
    fi
    
    log_info "Build dependencies installed"
}

# Download and extract xAct
download_xact() {
    local apps_dir="${WOLFRAM_USER_DIR}/Applications"
    mkdir -p "$apps_dir"
    
    cd "$apps_dir"
    
    log_step "Downloading xAct version ${XACT_VERSION}..."
    
    local archive="xAct_${XACT_VERSION}.tgz"
    local url="https://xact.es/download/${archive}"
    
    if [[ -d "xAct" ]]; then
        log_warn "Existing xAct installation found. Removing..."
        rm -rf xAct *.tgz* 2>/dev/null || true
    fi
    
    if ! wget -q --show-progress "$url"; then
        log_error "Failed to download xAct from ${url}"
        exit 1
    fi
    
    log_info "Extracting xAct..."
    if ! tar -xzf "$archive" 2>/dev/null; then
        log_error "Failed to extract ${archive}"
        exit 1
    fi
    
    log_info "xAct downloaded and extracted successfully"
}

# Recompile xPerm binary for GLIBC compatibility
recompile_xperm() {
    local mathlink_dir="${WOLFRAM_USER_DIR}/Applications/xAct/xPerm/mathlink"
    
    if [[ ! -d "$mathlink_dir" ]]; then
        log_error "xPerm mathlink directory not found: ${mathlink_dir}"
        exit 1
    fi
    
    cd "$mathlink_dir"
    
    log_step "Checking GLIBC compatibility of existing xPerm binary..."
    
    # Check if existing binary works
    if ldd xperm.linux.64-bit 2>/dev/null | grep -q "not found"; then
        log_warn "Existing binary has dependency issues. Recompiling..."
    else
        # Test if binary actually works (might still have GLIBC version issues)
        if timeout 5 ./xperm.linux.64-bit >/dev/null 2>&1; then
            log_info "Existing xPerm binary is compatible"
            return 0
        else
            log_warn "Binary compatibility test failed. Recompiling..."
        fi
    fi
    
    log_step "Finding MathLink compiler..."
    
    # Resolve mcc from the engine wolframscript actually belongs to. The block
    # this replaces could never match: the globs sat inside double quotes in the
    # `for` list so they were never expanded, `[[ -f $path ]]` does no pathname
    # expansion either, and even expanded it searched /usr/local/Wolfram, where
    # nothing is installed. It had never run -- it only ever exited 1 (#559).
    #
    # Do NOT canonicalize with `readlink -f`: Executables/wolframscript is a
    # symlink into SystemFiles/Kernel/Binaries/Linux-x86-64/, which holds no mcc.
    # The dirname of the link itself is the Executables directory, which does.
    local mcc_path=""
    local exec_dir
    exec_dir="$(dirname "$(command -v wolframscript)")"
    for candidate in \
        "${exec_dir}/mcc" \
        "${HOME}/.local/wolfram/engine/14.3/Executables/mcc" \
        "${HOME}/.local/wolfram/engine/14.3/SystemFiles/Links/MathLink/DeveloperKit/Linux-x86-64/CompilerAdditions/mcc"
    do
        if [[ -x "$candidate" ]]; then
            mcc_path="$candidate"
            break
        fi
    done
    
    if [[ -z "$mcc_path" ]]; then
        log_error "MathLink compiler (mcc) not found beside ${exec_dir}"
        log_error "  Build xPerm with the route that produced the certified binary:"
        log_error "    bash .devcontainer/scripts/build-xperm.sh"
        exit 1
    fi
    
    log_info "Using MathLink compiler: ${mcc_path}"
    
    log_step "Recompiling xPerm binary..."
    
    # Backup original
    if [[ -f "xperm.linux.64-bit" ]]; then
        cp xperm.linux.64-bit xperm.linux.64-bit.original
    fi
    
    # Compile new binary
    if "$mcc_path" xperm.tm -luuid -O3 -o xperm.linux.64-bit.new 2>&1; then
        mv xperm.linux.64-bit.new xperm.linux.64-bit
        chmod +x xperm.linux.64-bit
        log_info "xPerm binary recompiled successfully"
    else
        log_error "Failed to recompile xPerm binary"
        exit 1
    fi
}

# Record what was installed. Nothing else does: verify-wolfram-setup.sh has to
# fingerprint xAct by grepping each package's $Version out of its .m file,
# because the tarball leaves no marker behind.
write_installed_version() {
    local xact_dir="${WOLFRAM_USER_DIR}/Applications/xAct"
    {
        echo "${XACT_VERSION}"
        echo "source_url=https://xact.es/download/xAct_${XACT_VERSION}.tgz"
        echo "installed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "installed_by=scripts/install-xact-xcoba.sh"
    } > "${xact_dir}/INSTALLED_VERSION"
    log_info "Recorded: ${xact_dir}/INSTALLED_VERSION"
}

# Test xAct/xCoba installation
test_installation() {
    log_step "Testing xAct/xCoba installation..."
    
    local test_code='
    Quiet[Needs["xAct`xCoba`"]];
    Print["xCoba version: ", $xAct`xCobaVersionNumber];
    DefManifold[TestM, 4, IndexRange[a, z]];
    Print["✓ xAct/xCoba installation test successful"];
    '
    
    if wolframscript -code "$test_code" 2>/dev/null | grep -q "installation test successful"; then
        log_info "✅ xAct/xCoba installation verified"
        return 0
    else
        log_error "❌ xAct/xCoba installation test failed"
        return 1
    fi
}

# Show usage information
show_help() {
    log_info "=========================================="
    log_info "xAct & xCoba Installation"
    log_info "=========================================="
    echo ""
    echo "This script installs xAct and xCoba packages for symbolic"
    echo "tensor algebra computations in Wolfram Engine."
    echo ""
    echo "Features:"
    echo "  • Downloads official xAct package"
    echo "  • Recompiles xPerm binary for GLIBC compatibility"  
    echo "  • Installs to user Applications directory"
    echo "  • Verifies installation with test"
    echo ""
    echo "Usage:"
    echo "  $0 [--version VERSION] [--help]"
    echo ""
    echo "Options:"
    echo "  --version VERSION  xAct version (default: ${XACT_VERSION})"
    echo "  --help, -h         Show this help"
    echo ""
    echo "Requirements:"
    echo "  • Wolfram Engine installed and activated"
    echo "  • gcc, build-essential, uuid-dev packages"
    echo ""
    log_info "=========================================="
}

# Main installation function
main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --version)
                XACT_VERSION="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    log_info "=========================================="
    log_info "xAct & xCoba Installation Script"
    log_info "Version: ${XACT_VERSION}"
    log_info "=========================================="
    
    check_wolfram
    get_wolfram_user_dir
    install_build_deps
    download_xact
    write_installed_version
    recompile_xperm
    
    if test_installation; then
        log_info ""
        log_info "🎉 Installation completed successfully!"
        log_info ""
        log_info "Usage examples:"
        log_info '  wolframscript -code "Needs[\"xAct\`xCoba\`\"]; DefManifold[M,4]"'
        log_info "  Check examples at: ${WOLFRAM_USER_DIR}/Applications/xAct/Documentation/"
        log_info ""
    else
        log_error "Installation completed but verification failed"
        exit 1
    fi
}

# Run main function
main "$@"