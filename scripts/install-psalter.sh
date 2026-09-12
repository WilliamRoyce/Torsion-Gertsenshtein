#!/usr/bin/env bash
# ==============================================================================
# PSALTer Installation Script
# ==============================================================================
# Installs PSALTer (Barker's particle-spectrum package for xAct) into the
# Wolfram Engine user applications directory, at a pinned commit.
#
# The install is a directory copy: PSALTer's only dependencies are xTensor,
# SymManipulator, xPerm, xCore, xTras and xCoba, all of which ship with xAct
# and are installed by ./scripts/install-xact-xcoba.sh.
#
# The pinned commit is a CORRECTNESS input, not bookkeeping: the Stage-1
# exporter reads PSALTer's private symbols, so which revision is installed
# decides whether it reads the right things. The resolved hash is recorded in
# an INSTALLED_COMMIT file inside the installed tree.
#
# HEADLESS NOTE. PSALTer renders PDFs through the Wolfram front end, and does
# so unconditionally -- DefField exports a FieldKinematics<Field>.pdf on every
# field declaration (Sources/DefField.m:91 -> Sources/DefField/SummariseField.m:85),
# and ParticleSpectrum exports the spectrograph (Sources/ParticleSpectrum.m:82).
# Neither call is guarded, and neither is time-limited.
#
# The front end needs a Qt *platform plugin* whose shared libraries are all
# present. When none can be initialized, Qt aborts the front-end process and
# UsingFrontEnd then BLOCKS INDEFINITELY rather than failing -- measured here at
# exactly the imposed 25 s cap, reproducible by forcing an unloadable plugin.
# A hang, unlike an error, consumes the single-license Wolfram lane forever and
# is indistinguishable from "PSALTer is slow".
#
# In this container as originally audited, `offscreen` was the ONLY platform
# plugin with all its dependencies satisfied (xcb was missing five libraries,
# wayland-egl was missing libwayland-egl1). So export QT_QPA_PLATFORM=offscreen
# before running anything that declares a field. This script does that for its
# own verification step.
#
# Note that the optional Inkscape step below ALSO fixes this, by side effect:
# it pulls in libwayland-egl1, which makes the wayland-egl plugin loadable. That
# is luck, not a guarantee -- --skip-inkscape, a slimmer image or another distro
# puts you back at the hang -- so keep setting the variable.
#
# Usage:
#   ./scripts/install-psalter.sh [OPTIONS]
#
# Options:
#   --commit SHA        PSALTer commit to install (default: pinned v2.0.2)
#   --repo URL          Source repository (default: upstream)
#   --dest DIR          xAct applications directory (default: queried from Wolfram)
#   --from-checkout DIR Install from an existing clean checkout instead of fetching
#   --force             Replace an existing install without backing it up
#   --skip-inkscape     Do not attempt the optional Inkscape install
#   --no-verify         Skip the post-install verification
#   --help, -h          Show this help
#
# Exit Codes:
#   0 - Installed and verified
#   1 - Any failure
# ==============================================================================

set -euo pipefail

# Configuration. PSALTER_COMMIT deliberately matches the default in
# scripts/research/psalter_stage1/fetch_reference_sources.sh so that the
# installed revision and the fetched reference sources cannot drift apart.
PSALTER_COMMIT="${PSALTER_COMMIT:-bb45adb0fa21e467dbd88d4dc36ef21b84abbe6d}"  # v2.0.2
PSALTER_REPO_URL="${PSALTER_REPO_URL:-https://github.com/wevbarker/PSALTer}"
PSALTER_VERIFY_TIMEOUT="${PSALTER_VERIFY_TIMEOUT:-1800}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WOLFRAM_USER_DIR=""
DEST_DIR=""
FROM_CHECKOUT=""
FORCE="false"
SKIP_INKSCAPE="false"
NO_VERIFY="false"
WORK_DIR=""
RESOLVED_COMMIT=""
PACKAGE_VERSION=""

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

cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}

# Print the header comment block (between the two "# ===" rules) as help text,
# so editing the header cannot leave --help out of step with it.
show_help() {
    awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' \
        "${BASH_SOURCE[0]}"
}

# Check if Wolfram Engine is available and activated
check_wolfram() {
    # The mounted kernel, not `command -v wolframscript`: the devcontainer image
    # ships its own client at /usr/bin/wolframscript -> /opt/Wolfram/..., so
    # `command -v` succeeds with no engine installed and every later call becomes
    # a cloud evaluation. Same defect class as #559 in ensure_registered.sh and
    # verify-wolfram-setup.sh, found by enumerating the pattern rather than
    # fixing the one site that bit.
    local expected_version="${EXPECTED_WOLFRAM_VERSION:-14.3.0}"
    local engine_dir="${EXPECTED_ENGINE_DIR:-${HOME}/.local/wolfram/engine/${expected_version%.*}}"
    if [[ ! -x "${engine_dir}/Executables/WolframKernel" ]]; then
        log_error "No Wolfram kernel at ${engine_dir}/Executables/WolframKernel"
        log_error "The engine is not installed in its mount. Setup path:"
        log_error "  .devcontainer/docs/WOLFRAM_GUIDE.md"
        exit 1
    fi

    if ! command -v wolframscript &> /dev/null; then
        log_error "wolframscript not on PATH (kernel exists at ${engine_dir})"
        exit 1
    fi

    if ! wolframscript -code "1+1" >/dev/null 2>&1; then
        log_error "Wolfram Engine is not properly activated"
        log_error "Run: ./scripts/activate-wolfram.sh"
        exit 1
    fi

    log_info "Wolfram Engine is available and activated"
}

# Resolve the Wolfram user base directory by asking Wolfram, never by
# hardcoding a path (committed files must carry no environment-specific paths).
get_wolfram_user_dir() {
    WOLFRAM_USER_DIR=$(wolframscript -code '$UserBaseDirectory' 2>/dev/null | tr -d '\n' | tr -d '\r')

    if [[ -z "$WOLFRAM_USER_DIR" ]]; then
        log_error "Could not determine Wolfram user directory"
        exit 1
    fi

    log_info "Wolfram user directory: ${WOLFRAM_USER_DIR}"
}

# PSALTer loads xTensor, SymManipulator, xPerm, xCore, xTras and xCoba. All of
# them come from xAct, so xAct's presence is the whole prerequisite check.
check_prerequisites() {
    if ! command -v git &> /dev/null; then
        log_error "git is required but not installed"
        exit 1
    fi

    local xact_dir="${WOLFRAM_USER_DIR}/Applications/xAct"
    local pkg
    for pkg in xTensor SymManipulator xPerm xCore xTras xCoba; do
        if [[ ! -d "${xact_dir}/${pkg}" ]]; then
            log_error "Required xAct package not found: ${pkg}"
            log_error "Run: ./scripts/install-xact-xcoba.sh"
            exit 1
        fi
    done

    log_info "xAct prerequisites present (xTensor, SymManipulator, xPerm, xCore, xTras, xCoba)"
}

# Fetch PSALTer at the pinned commit into a throwaway directory.
#
# Deliberately NOT reusing scripts/research/psalter_stage1/'s checkout under
# third_party/: that directory only exists if the research fetch script has been
# run, and if it has been edited or left dirty we would install modified sources
# -- silently invalidating the Tier-1 gate this install underpins. --from-checkout
# offers the reuse path explicitly, and requires the checkout to be clean and at
# the pinned revision.
clone_psalter() {
    local repo="${WORK_DIR}/PSALTer"

    if [[ -n "$FROM_CHECKOUT" ]]; then
        log_step "Installing from existing checkout: ${FROM_CHECKOUT}"
        if [[ ! -d "${FROM_CHECKOUT}/.git" ]]; then
            log_error "Not a git checkout: ${FROM_CHECKOUT}"
            exit 1
        fi
        if [[ -n "$(git -C "$FROM_CHECKOUT" status --porcelain)" ]]; then
            log_error "Checkout is dirty; refusing to install modified sources"
            log_error "  ${FROM_CHECKOUT}"
            exit 1
        fi
        RESOLVED_COMMIT="$(git -C "$FROM_CHECKOUT" rev-parse HEAD)"
        if [[ "$RESOLVED_COMMIT" != "$PSALTER_COMMIT" ]]; then
            log_error "Checkout is at ${RESOLVED_COMMIT}, expected ${PSALTER_COMMIT}"
            exit 1
        fi
        cp -a "$FROM_CHECKOUT" "$repo"
        return 0
    fi

    log_step "Fetching PSALTer at ${PSALTER_COMMIT}"
    git init --quiet "$repo"
    git -C "$repo" remote add origin "$PSALTER_REPO_URL"

    # The repository carries large blobs, so prefer fetching the single pinned
    # commit. Not every host allows fetching a bare SHA; fall back to a full clone.
    if git -C "$repo" fetch --quiet --depth 1 origin "$PSALTER_COMMIT" 2>/dev/null; then
        git -C "$repo" checkout --quiet FETCH_HEAD
    else
        log_warn "Shallow fetch of a bare commit failed; falling back to a full clone"
        rm -rf "$repo"
        if ! git clone --quiet "$PSALTER_REPO_URL" "$repo"; then
            log_error "Failed to clone ${PSALTER_REPO_URL}"
            exit 1
        fi
        if ! git -C "$repo" checkout --quiet "$PSALTER_COMMIT"; then
            log_error "Commit not found in ${PSALTER_REPO_URL}: ${PSALTER_COMMIT}"
            exit 1
        fi
    fi

    RESOLVED_COMMIT="$(git -C "$repo" rev-parse HEAD)"
    if [[ ${#PSALTER_COMMIT} -eq 40 && "$RESOLVED_COMMIT" != "$PSALTER_COMMIT" ]]; then
        log_error "Resolved ${RESOLVED_COMMIT} but requested ${PSALTER_COMMIT}"
        exit 1
    fi
    log_info "Fetched at ${RESOLVED_COMMIT}"
}

# Confirm the checkout has the shape we expect before copying anything over an
# existing install.
assert_payload_shape() {
    local src="${WORK_DIR}/PSALTer/xAct/PSALTer"
    local f
    for f in PSALTer.m Sources/ParticleSpectrum.m Sources/DefField.m; do
        if [[ ! -f "${src}/${f}" ]]; then
            log_error "Checkout does not look like PSALTer: missing ${f}"
            exit 1
        fi
    done

    # PSALTer.m carries $Version={"2.0.2",{2026,1,3}}. Recording it alongside the
    # commit makes a silent upstream version change visible.
    PACKAGE_VERSION="$(sed -n 's/.*\$Version[[:space:]]*=[[:space:]]*{"\([^"]*\)".*/\1/p' \
        "${src}/PSALTer.m" | head -1)"
    PACKAGE_VERSION="${PACKAGE_VERSION:-unknown}"
    log_info "PSALTer package version: ${PACKAGE_VERSION}"
}

install_tree() {
    local src="${WORK_DIR}/PSALTer/xAct/PSALTer"
    local dest="${DEST_DIR}/PSALTer"

    mkdir -p "$DEST_DIR"

    if [[ -d "$dest" ]]; then
        if [[ "$FORCE" == "true" ]]; then
            log_warn "Removing existing install at ${dest} (--force)"
            rm -rf "$dest"
        else
            local backup="${dest}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
            log_warn "Existing install found; moving it to $(basename "$backup")"
            mv "$dest" "$backup"
        fi
    fi

    log_step "Installing to ${dest}"
    cp -a "$src" "$dest"
    log_info "Installed"
}

# The exporter reads PSALTer's private symbols, so the installed revision is a
# correctness input. Line 1 is the bare hash, for machine reads (head -1).
write_installed_commit() {
    local marker="${DEST_DIR}/PSALTer/INSTALLED_COMMIT"
    {
        echo "${RESOLVED_COMMIT}"
        echo "source_url=${PSALTER_REPO_URL}"
        echo "package_version=${PACKAGE_VERSION}"
        echo "installed_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "installed_by=scripts/install-psalter.sh"
    } > "$marker"
    log_info "Recorded revision in $(basename "$marker")"
}

# Inkscape is genuinely optional: every Vectorize call site in PSALTer v2.0.2 is
# commented out (Sources/ParticleSpectrum/ConstructSpectrograph.m:49-51,
# Sources/DefField/SummariseField/FieldMosaic.m:10), so $InkscapePath is never
# used. Install it opportunistically and never let a failure stop the install --
# hence every step guarded, and the function always returning 0.
install_inkscape() {
    if [[ "$SKIP_INKSCAPE" == "true" ]]; then
        log_info "Skipping Inkscape (--skip-inkscape)"
        return 0
    fi
    if command -v inkscape &> /dev/null; then
        log_info "Inkscape already present"
        return 0
    fi
    if ! command -v apt-get &> /dev/null; then
        log_warn "No apt-get available; skipping Inkscape (not required)"
        return 0
    fi
    if ! sudo -n true 2>/dev/null; then
        log_warn "No passwordless sudo; skipping Inkscape (not required)"
        return 0
    fi

    log_step "Installing Inkscape (optional)"
    if ! sudo apt-get update -qq; then
        log_warn "apt-get update failed; skipping Inkscape (not required)"
        return 0
    fi
    if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends inkscape; then
        log_warn "Inkscape install failed; continuing (not required)"
        return 0
    fi
    log_info "Inkscape installed"
}

# Verify the install by loading the package and checking that its two entry
# points exist.
#
# Existence is tested with DownValues, not ValueQ: PSALTer defines its functions
# through the StackSetDelayed wrapper (Sources/ReloadPackage/StackSetDelayed.m),
# so the symbols carry definition rules rather than a value, and ValueQ reports
# False for a perfectly good install.
#
# Run from a throwaway directory because PSALTer freezes $WorkingDirectory to the
# process's current directory at load time (PSALTer.m:49-55) and writes there.
# Register the two Function Repository resources PSALTer depends on and never
# declares (#543). Without them an unresolved ResourceFunction is not a Boolean,
# so no gauge symmetry is identified and every pseudo-determinant is zero -- and
# the run still completes and writes its .mx. The registry lives in the container
# overlay, so this must run again after every rebuild, which is why it is here
# rather than in a one-off setup note.
#
# Idempotent, takes the Wolfram lane for about a minute. Never edits PSALTer.
register_resources() {
    local script="${SCRIPT_DIR}/psalter/ensure_registered.sh"
    [[ -f "$script" ]] || { log_error "ensure_registered.sh not found"; return 1; }

    log_step "Registering the Function Repository resources PSALTer needs (#543)"
    # --no-verify: verify_installation runs below and covers check 10 under --require-psalter.
    if bash "$script" --no-verify; then
        log_info "Resources registered with the certified identities"
    else
        log_error "Registration failed. This is NOT optional: an unregistered PSALTer does not"
        log_error "fail, it completes and writes a SILENTLY WRONG spectrum (empty source"
        log_error "constraints, zero pseudo-determinants). Fix it before trusting any result:"
        log_error "  bash scripts/psalter/ensure_registered.sh"
        return 1
    fi
}

verify_installation() {
    log_step "Verifying installation (timeout ${PSALTER_VERIFY_TIMEOUT}s)"

    local test_code='
    Needs["xAct`PSALTer`"];
    Print["PSALTER_VERSION=", xAct`PSALTer`Private`$Version[[1]]];
    Print["PSALTER_INSTALL_DIR=", xAct`PSALTer`Private`$InstallDirectory];
    Print["PSALTER_SYMBOLS_OK=",
      TrueQ[Length[DownValues[xAct`PSALTer`DefField]] > 0 &&
            Length[DownValues[xAct`PSALTer`ParticleSpectrum]] > 0]];
    Print["PSALTER_LOADED"];
    '

    local tmp result rc
    tmp="$(mktemp -d)"
    set +e
    result=$(cd "$tmp" && QT_QPA_PLATFORM=offscreen \
        timeout "$PSALTER_VERIFY_TIMEOUT" wolframscript -code "$test_code" 2>&1)
    rc=$?
    set -e
    rm -rf "$tmp"

    # The first load builds the package's projection-operator tables and is slow.
    if [[ $rc -eq 124 ]]; then
        log_error "Verification timed out after ${PSALTER_VERIFY_TIMEOUT}s"
        log_error "  If it hung rather than being merely slow, the cause is the"
        log_error "  headless PDF export: export QT_QPA_PLATFORM=offscreen"
        log_error "  Raise the budget with PSALTER_VERIFY_TIMEOUT=<seconds>"
        return 1
    fi

    # Judge success from the output, never from the exit status: Wolfram Engine
    # intermittently segfaults during kernel shutdown, after producing correct
    # results, so a non-zero status here does not mean the work failed.
    if echo "$result" | grep -q "PSALTER_LOADED" &&
       echo "$result" | grep -q "PSALTER_SYMBOLS_OK=True"; then
        echo "$result" | grep -E "^PSALTER_(VERSION|INSTALL_DIR)=" | while read -r line; do
            log_info "  ${line}"
        done
        log_info "PSALTer loads and exports DefField and ParticleSpectrum"
        return 0
    fi

    log_error "PSALTer verification failed"
    echo "$result" | tail -20
    return 1
}

show_banner() {
    echo ""
    echo "=============================================="
    echo "  PSALTer Installation"
    echo "=============================================="
    echo ""
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --commit)         PSALTER_COMMIT="$2"; shift 2 ;;
            --repo)           PSALTER_REPO_URL="$2"; shift 2 ;;
            --dest)           DEST_DIR="$2"; shift 2 ;;
            --from-checkout)  FROM_CHECKOUT="$2"; shift 2 ;;
            --force)          FORCE="true"; shift ;;
            --skip-inkscape)  SKIP_INKSCAPE="true"; shift ;;
            --no-verify)      NO_VERIFY="true"; shift ;;
            --help|-h)        show_help; exit 0 ;;
            *)
                log_error "Unknown option: $1"
                log_error "Run with --help for usage"
                exit 1
                ;;
        esac
    done

    show_banner

    check_wolfram
    get_wolfram_user_dir

    if [[ -z "$DEST_DIR" ]]; then
        DEST_DIR="${WOLFRAM_USER_DIR}/Applications/xAct"
    fi

    check_prerequisites

    WORK_DIR="$(mktemp -d)"
    trap cleanup EXIT INT TERM

    clone_psalter
    assert_payload_shape
    install_tree
    write_installed_commit
    install_inkscape || true
    register_resources

    if [[ "$NO_VERIFY" == "true" ]]; then
        log_warn "Skipping verification (--no-verify)"
        log_info "Installation completed"
        exit 0
    fi

    if verify_installation; then
        echo ""
        log_info "PSALTer installed successfully"
        log_info "  Revision: ${RESOLVED_COMMIT}"
        log_info "  Location: ${DEST_DIR}/PSALTer"
        log_warn "  Before running PSALTer, export QT_QPA_PLATFORM=offscreen --"
        log_warn "  DefField and ParticleSpectrum export PDFs unconditionally and"
        log_warn "  will hang without it. See ./scripts/verify-wolfram-setup.sh"
        echo ""
        exit 0
    else
        log_error "Installation completed but verification failed"
        exit 1
    fi
}

main "$@"
