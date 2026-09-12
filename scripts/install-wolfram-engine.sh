#!/usr/bin/env bash
# ==============================================================================
# Wolfram Engine Installation Script
# ==============================================================================
# Installs Wolfram Engine for headless Linux use, onto the directory the dev
# container bind-mounts from the host so it survives rebuilds.
#
# No lifecycle hook runs this: it is install step 2 of the six in
# .devcontainer/docs/WOLFRAM_GUIDE.md, run by hand, once per machine.
#
# Usage:
#   ./scripts/install-wolfram-engine.sh [--skip-download]
#
# Options:
#   --skip-download  Skip downloading if installer already exists in third_party/
#
# Environment Variables:
#   WOLFRAM_VERSION  Wolfram Engine version (default: 14.3.0)
#   WOLFRAM_INSTALL_DIR  Install root (default: $HOME/.local/wolfram/engine, the
#                        dev container's bind mount). scripts/verify-wolfram-setup.sh
#                        rejects a kernel installed anywhere else.
#
# ==============================================================================

set -euo pipefail

# Configuration
WOLFRAM_VERSION="${WOLFRAM_VERSION:-14.3.0}"
# The mount, not /usr/local. devcontainer.json bind-mounts
# $HOME/.local/wolfram/engine/<series> from the host, and verify-wolfram-setup.sh
# hard-fails any kernel outside it: an engine under /usr/local is wiped on every
# rebuild, after which wolframscript silently falls back to CLOUD evaluation.
WOLFRAM_INSTALL_DIR="${WOLFRAM_INSTALL_DIR:-${HOME}/.local/wolfram/engine}"
# 14.3.0 -> 14.3: the mount is named by the series, not the point release.
ENGINE_SERIES="${WOLFRAM_VERSION%.*}"
ENGINE_DIR="${WOLFRAM_INSTALL_DIR}/${ENGINE_SERIES}"
ENGINE_KERNEL="${ENGINE_DIR}/Executables/WolframKernel"
# Keep the engine's own scripts inside the engine: /usr/local/bin would create a
# second wolframscript that shadows the mounted one on PATH.
WOLFRAM_SCRIPTS_DIR="${ENGINE_DIR}/Executables"

# Derived paths
INSTALLER_NAME="WolframEngine_${WOLFRAM_VERSION}_LIN.sh"
DOWNLOAD_URL="https://account.wolfram.com/download/public/wolfram-engine/desktop/LINUX"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
THIRD_PARTY_DIR="${PROJECT_ROOT}/third_party"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Installing into $HOME needs no root, and demanding it is what left root-owned
# files inside the mount. Escalate only for a target outside the user's home,
# and refuse /usr/local outright.
check_target() {
    if [[ "$ENGINE_DIR" == /usr/local/* ]]; then
        log_error "Refusing to install into ${ENGINE_DIR}"
        log_error "  /usr/local is not mounted: the engine would be wiped on the next"
        log_error "  container rebuild, and verify-wolfram-setup.sh rejects a kernel"
        log_error "  outside the mount. Leave WOLFRAM_INSTALL_DIR unset to install to:"
        log_error "    ${HOME}/.local/wolfram/engine"
        exit 1
    fi
    if [[ "$ENGINE_DIR" != "${HOME}/"* && $EUID -ne 0 ]]; then
        log_error "Installing outside your home directory needs root."
        log_error "  Re-run with sudo, or leave WOLFRAM_INSTALL_DIR unset."
        exit 1
    fi
}

# Check if Wolfram Engine is already installed
# The kernel file on the mount, never `command -v wolframscript`: the dev
# container image ships a standalone wolframscript at /usr/bin that evaluates in
# the CLOUD, so `command -v` succeeds on a machine with no engine at all. This
# function then reported "already installed" and skipped the install on exactly
# the fresh container that needed it (#559).
check_existing_installation() {
    if [[ -x "$ENGINE_KERNEL" ]]; then
        log_info "Wolfram Engine ${ENGINE_SERIES} already installed: ${ENGINE_DIR}"
        return 0
    fi
    return 1
}

# Install system dependencies
install_dependencies() {
    log_info "Installing system dependencies..."
    local sudo_cmd=""
    if [[ $EUID -ne 0 ]]; then
        if command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
            sudo_cmd="sudo"
        else
            log_warn "Cannot install system packages without root -- skipping."
            log_warn "  The dev container already installs the engine's runtime libraries."
            return 0
        fi
    fi
    $sudo_cmd apt-get update -qq
    $sudo_cmd apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        xz-utils \
        unzip \
        libglib2.0-0 \
        libx11-6 \
        libxext6 \
        libxrender1 \
        libsm6 \
        libfontconfig1 \
        libasound2 \
        libfreetype6 \
        libgl1 \
        libglu1-mesa
    log_info "Dependencies installed successfully"
}

# Download Wolfram Engine installer
download_installer() {
    local installer_path="${THIRD_PARTY_DIR}/${INSTALLER_NAME}"
    
    # Create third_party directory if it doesn't exist
    mkdir -p "$THIRD_PARTY_DIR"
    
    if [[ -f "$installer_path" ]]; then
        log_info "Installer already exists at ${installer_path}"
        return 0
    fi
    
    log_info "Downloading Wolfram Engine ${WOLFRAM_VERSION}..."
    log_warn "Note: You may need to download manually from https://www.wolfram.com/engine/"
    log_warn "The direct download URL requires authentication."
    
    # Try to download (this may fail if authentication is required)
    if curl -L -o "$installer_path" "$DOWNLOAD_URL" 2>/dev/null; then
        # Check if we got a valid shell script (not an HTML error page)
        if head -1 "$installer_path" | grep -q "^#!"; then
            log_info "Download completed successfully"
            chmod +x "$installer_path"
            return 0
        else
            log_warn "Downloaded file does not appear to be the installer"
            rm -f "$installer_path"
        fi
    fi
    
    log_error "Automatic download failed. Please download manually:"
    log_error "  1. Visit https://www.wolfram.com/engine/"
    log_error "  2. Download the Linux installer"
    log_error "  3. Place it at: ${installer_path}"
    return 1
}

# Run the Wolfram Engine installer
run_installer() {
    local installer_path="${THIRD_PARTY_DIR}/${INSTALLER_NAME}"
    
    if [[ ! -f "$installer_path" ]]; then
        log_error "Installer not found at ${installer_path}"
        return 1
    fi
    
    log_info "Running Wolfram Engine installer..."
    
    # Run installer in automatic mode
    # The installer accepts these during automatic installation:
    # - Installation directory
    # - Scripts directory
    # - Whether to create symbolic links
    
    # Create installation directory
    mkdir -p "$ENGINE_DIR"
    
    # Run with auto mode and predefined answers
    # Note: the installer prompts for
    # 1. the installation directory -- must be ${ENGINE_DIR}
    # 2. the scripts directory     -- must stay inside the engine
    # -auto supplies both; the heredoc below is the fallback for older installers.
    echo -e "\n\n" | bash "$installer_path" -- \
        -auto \
        -targetdir="${ENGINE_DIR}" \
        -execdir="${WOLFRAM_SCRIPTS_DIR}" \
        2>/dev/null || {
            # If -auto flag doesn't work, try with heredoc for interactive prompts
            log_info "Trying interactive installation with preset answers..."
            bash "$installer_path" <<EOF


EOF
        }
    
    log_info "Wolfram Engine installation completed"
}

# Verify installation
verify_installation() {
    log_info "Verifying installation..."
    
    # Again the kernel file, not PATH: /usr/bin/wolframscript would make a failed
    # install look successful.
    if [[ ! -x "$ENGINE_KERNEL" ]]; then
        log_error "Kernel not found at ${ENGINE_KERNEL}"
        log_error "  The installer did not write to the expected location."
        log_error "  Re-run and give ${ENGINE_DIR} when it asks for the install directory."
        return 1
    fi
    
    log_info "Wolfram Engine installed successfully!"
    log_info "Location: ${ENGINE_DIR}"
    
    # Check if activated (this will fail if not activated, which is expected)
    log_info ""
    log_info "=========================================="
    log_info "IMPORTANT: License Activation Required"
    log_info "=========================================="
    log_info "Run the following command to activate:"
    log_info "  wolframscript -activate"
    log_info ""
    log_info "You will need a Wolfram ID (free at wolfram.com)"
    log_info "=========================================="
    
    return 0
}

# Main installation function
main() {
    local skip_download=false
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --skip-download)
                skip_download=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [--skip-download]"
                echo ""
                echo "Options:"
                echo "  --skip-download  Skip downloading if installer already exists"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $arg"
                exit 1
                ;;
        esac
    done
    
    log_info "=========================================="
    log_info "Wolfram Engine Installation Script"
    log_info "Version: ${WOLFRAM_VERSION}"
    log_info "=========================================="
    
    # Check if already installed
    if check_existing_installation; then
        log_info "Skipping installation (already installed)"
        exit 0
    fi
    
    check_target
    install_dependencies
    
    if [[ "$skip_download" == false ]]; then
        download_installer || {
            log_warn "Download failed, checking if installer exists..."
        }
    fi
    
    # Check if installer exists before proceeding
    if [[ ! -f "${THIRD_PARTY_DIR}/${INSTALLER_NAME}" ]]; then
        log_error "Installer not found. Please download manually and place in third_party/"
        exit 1
    fi
    
    run_installer
    verify_installation
    
    log_info "Installation complete!"
}

# Run main function
main "$@"
