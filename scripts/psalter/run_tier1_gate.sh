#!/usr/bin/env bash
# cspell:words etime pcpu
# ==============================================================================
# PSALTer Tier-1 install gate
# ==============================================================================
# Runs the author's own published PSALTer script and compares the result against
# the author's own published result file, key by key.
#
# Why this gates the install: BOTH sides are the author's, so a mismatch can only
# be our install. A tier that mixes his input with our physics could not localize
# a failure, which is why the physics checks are a separate, later tier.
#
# One command, re-runnable, and re-verifiable without re-running:
#   bash scripts/psalter/run_tier1_gate.sh                 # full run + compare
#   bash scripts/psalter/run_tier1_gate.sh --diff-only DIR # re-compare only
#
# Everything lands in a timestamped directory under third_party/psalter_runs/
# (gitignored), with tier1_diff.json as the machine-readable verdict.
#
# Usage:
#   bash scripts/psalter/run_tier1_gate.sh [OPTIONS]
#
# Options:
#   --diff-only DIR    Re-run only the comparison, over an existing run directory
#   --skip-preflight   Skip the small-theory preflight
#   --timeout SEC      Ceiling for the PSALTer run (default: 28800, i.e. 8 h)
#   --checkpoint-at L  Comma-separated offsets in seconds (default: 3600,28800)
#   --theory NAME      Theory name (default: CTEG)
#   --help, -h         Show this help
#
# Exit Codes:
#   0 - verdict "match"
#   1 - any other verdict; see "verdict" in tier1_diff.json for which
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT_DIR="${REPO_ROOT}/scripts/psalter"
REF_DIR="${REPO_ROOT}/third_party/psalter_reference"
RUNS_DIR="${REPO_ROOT}/third_party/psalter_runs"

THEORY="CTEG"
TIER1_TIMEOUT="${TIER1_TIMEOUT:-28800}"
CHECKPOINT_AT="3600,28800"
DIFF_ONLY=""
SKIP_PREFLIGHT="false"
RUN_DIR=""
WATCHER_PID=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

show_help() {
    awk 'NR==1 && /^#!/ {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' \
        "${BASH_SOURCE[0]}"
}

cleanup() {
    if [[ -n "$WATCHER_PID" ]] && kill -0 "$WATCHER_PID" 2>/dev/null; then
        kill "$WATCHER_PID" 2>/dev/null || true
    fi
}

# The project's single Wolfram license is machine-wide. The repo's Claude hook
# greps the command text for "wolframscript", which `bash scripts/...` does not
# match, so this script has to guard itself.
require_engine_idle() {
    if pgrep -x wolframscript >/dev/null 2>&1 || pgrep -x WolframKernel >/dev/null 2>&1; then
        log_error "A Wolfram process is already running; only one at a time is permitted"
        pgrep -a -x wolframscript || true
        pgrep -a -x WolframKernel || true
        exit 1
    fi
}

require_psalter() {
    log_step "Verifying the PSALTer install"
    if ! bash "${REPO_ROOT}/scripts/verify-wolfram-setup.sh" --require-psalter >/dev/null 2>&1; then
        log_error "PSALTer verification failed"
        log_error "  Run: bash scripts/verify-wolfram-setup.sh --require-psalter"
        exit 1
    fi
    log_info "PSALTer install verified"
}

# The reference sources are fetched, never committed: PSALTer and the
# supplemental materials are GPL-3.0-or-later and this repository is MIT, so we
# commit the route and not the payload.
ensure_reference_sources() {
    if [[ ! -f "${REF_DIR}/sm2506b/ParticleSpectrographCTEG.m" ||
          ! -f "${REF_DIR}/sm2506b/ParticleSpectrographCTEG.mx" ]]; then
        log_step "Fetching pinned reference sources"
        bash "${REPO_ROOT}/scripts/research/psalter_stage1/fetch_reference_sources.sh" >/dev/null
    fi
    for f in ParticleSpectrographCTEG.m ParticleSpectrographCTEG.mx; do
        if [[ ! -f "${REF_DIR}/sm2506b/${f}" ]]; then
            log_error "Missing reference file after fetch: ${f}"
            exit 1
        fi
    done
    log_info "Reference sources present"
}

# Cheapest disqualifier, run before anything expensive: the published result file
# is a version-sensitive binary dump (written by Wolfram 14.2). If it will not
# load there is nothing to compare against, and Tier 1 cannot be run at all --
# which is a different fact from the install being wrong.
check_oracle_loadable() {
    log_step "Checking the oracle loads"
    local tmp result
    tmp=$(mktemp -d)
    result=$(cd "$tmp" && timeout 300 wolframscript -code "
        Quiet@Check[Get[\"${REF_DIR}/sm2506b/ParticleSpectrographCTEG.mx\"], \$Failed];
        Print[\"ORACLE_SYMBOLS=\", Length[Names[\"*\`${THEORY}\"]]];" 2>&1 || true)
    rm -rf "$tmp"
    if ! echo "$result" | grep -qE "^ORACLE_SYMBOLS=[1-9]"; then
        log_error "The oracle did not load -- Tier 1 cannot be run as specified"
        log_error "  This is NOT a mismatch. Report it; do not relax the comparison."
        echo "$result" | tail -5
        exit 1
    fi
    log_info "Oracle loads"
}

preflight() {
    if [[ "$SKIP_PREFLIGHT" == "true" ]]; then
        log_warn "Skipping preflight (--skip-preflight)"
        return 0
    fi
    log_step "Preflight on a small theory"
    require_engine_idle
    local tmp rc log
    tmp=$(mktemp -d)
    log="${tmp}/preflight.log"
    set +e
    ( cd "$tmp" && QT_QPA_PLATFORM=offscreen \
        timeout 1800 wolframscript -file "${SCRIPT_DIR}/vector_smoke.wls" ) > "$log" 2>&1
    rc=$?
    set -e

    # Grep the file rather than a shell variable: the output is ~150 KB of mixed
    # text and raw ANSI escapes, and keeping it on disk also preserves it as
    # evidence when the preflight is what fails.
    if [[ $rc -eq 124 ]]; then
        log_error "Preflight timed out -- do not start the full run"
        cp "$log" "${RUNS_DIR}/preflight-failed.log" 2>/dev/null || true
        rm -rf "$tmp"; exit 1
    fi
    if ! grep -qaF "PREFLIGHT PASSED" "$log"; then
        log_error "Preflight failed -- do not start the full run"
        grep -av "PREFLIGHT" "$log" | tail -15
        mkdir -p "$RUNS_DIR"; cp "$log" "${RUNS_DIR}/preflight-failed.log" 2>/dev/null || true
        rm -rf "$tmp"; exit 1
    fi
    # PSALTer announces each internal function on entry when it has no front end.
    # The whole checkpoint trace rests on those lines existing, so verify it here
    # rather than discovering an empty trace after a long run.
    local trace_lines
    trace_lines=$(grep -caF "$(printf '\033[1;34;40m')" "$log" || true)
    if [[ "${trace_lines:-0}" -lt 1 ]]; then
        log_error "Preflight produced no stage-trace lines; the checkpoint trace would be empty"
        rm -rf "$tmp"; exit 1
    fi
    rm -rf "$tmp"
    log_info "Preflight passed; ${trace_lines} stage-trace lines observed"
}

make_run_dir() {
    RUN_DIR="${RUNS_DIR}/tier1-$(date -u +%Y%m%dT%H%M%SZ)"
    mkdir -p "$RUN_DIR"
    log_info "Run directory: ${RUN_DIR}"
}

# Take a liveness snapshot at each requested offset. This is what turns "still
# running after N hours" into a reportable fact rather than a guess.
start_watcher() {
    local offsets="${1}"
    (
        prev=0
        IFS=',' read -ra marks <<< "$offsets"
        for mark in "${marks[@]}"; do
            sleep $(( mark - prev )) || exit 0
            prev="$mark"
            {
                echo "=== checkpoint at ~${mark}s ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
                pgrep -a -x WolframKernel || echo "  (no kernel running)"
                ps -o pid,etime,pcpu,rss,comm -C WolframKernel 2>/dev/null || true
                echo "  --- last stage lines ---"
                grep -aF "$(printf '\033[1;34;40m')" "${RUN_DIR}/run.log" 2>/dev/null | tail -3 || true
            } >> "${RUN_DIR}/checkpoints.log"
        done
    ) &
    WATCHER_PID=$!
}

run_spectrum() {
    local src="${REF_DIR}/sm2506b/ParticleSpectrographCTEG.m"
    local before after rc started finished

    before=$(sha256sum "$src" | awk '{print $1}')
    started=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    log_step "Running the published script unmodified (ceiling ${TIER1_TIMEOUT}s)"
    log_info "  This is Barker's file, run in place; it is never copied or edited."

    start_watcher "$CHECKPOINT_AT"

    set +e
    ( cd "$RUN_DIR" && QT_QPA_PLATFORM=offscreen \
        timeout --signal=INT --kill-after=60 "$TIER1_TIMEOUT" \
        wolframscript -file "$src" 2>&1 ) \
      | tee "${RUN_DIR}/run.raw.log" \
      | python3 -u "${SCRIPT_DIR}/stamp_lines.py" --max-line-bytes 4000 \
      > "${RUN_DIR}/run.log"
    rc=${PIPESTATUS[0]}
    set -e

    cleanup
    finished=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    after=$(sha256sum "$src" | awk '{print $1}')

    python3 "${SCRIPT_DIR}/extract_checkpoints.py" "${RUN_DIR}/run.log" \
        > "${RUN_DIR}/checkpoints.json"

    cat > "${RUN_DIR}/manifest.json" <<EOF
{
  "theory_name": "${THEORY}",
  "started_utc": "${started}",
  "finished_utc": "${finished}",
  "timeout_s": ${TIER1_TIMEOUT},
  "exit_status": ${rc},
  "timed_out": $([[ $rc -eq 124 ]] && echo true || echo false),
  "qt_qpa_platform": "offscreen",
  "script_sha256_before": "${before}",
  "script_sha256_after": "${after}",
  "script_unmodified": $([[ "$before" == "$after" ]] && echo true || echo false),
  "oracle_sha256": "$(sha256sum "${REF_DIR}/sm2506b/ParticleSpectrographCTEG.mx" | awk '{print $1}')"
}
EOF

    if [[ $rc -eq 124 ]]; then
        log_error "The run hit the ${TIER1_TIMEOUT}s ceiling and did not terminate"
        log_error "  The checkpoint trace is a real result: ${RUN_DIR}/checkpoints.json"
        return 1
    fi

    # Success is decided from the artifact, never from the exit status: Wolfram
    # Engine intermittently segfaults during kernel shutdown after producing
    # correct results (#541).
    if [[ ! -f "${RUN_DIR}/ParticleSpectrograph${THEORY}.mx" ]]; then
        log_error "The run produced no ParticleSpectrograph${THEORY}.mx"
        grep -avF "$(printf '\033[1;34;40m')" "${RUN_DIR}/run.log" | tail -15
        return 1
    fi
    log_info "Run produced ParticleSpectrograph${THEORY}.mx"
    return 0
}

run_diff() {
    # Refuse rather than clobber. --diff-only re-runs the comparison and REWRITES
    # tier1_diff.json in the target directory, so pointing it at a directory that
    # has the verdict but not the .mx it was derived from would replace a real
    # result with an "ours_unreadable" failure artifact -- destroying the evidence
    # it was invoked to check. That is exactly the shape of the committed evidence
    # under docs/cosmology/evidence/, where the .mx is deliberately excluded.
    local ours="${RUN_DIR}/ParticleSpectrograph${THEORY}.mx"
    if [[ ! -f "$ours" ]]; then
        log_error "No ParticleSpectrograph${THEORY}.mx in ${RUN_DIR}"
        log_error "  --diff-only recomputes the verdict, so it needs the run's own .mx."
        if [[ -f "${RUN_DIR}/tier1_diff.json" ]]; then
            log_info "  That directory already holds a verdict. To read it back without"
            log_info "  Wolfram and without overwriting anything:"
            log_info "    python3 scripts/psalter/summarize_diff.py ${RUN_DIR}/tier1_diff.json"
        fi
        log_info "  To recompute from scratch (~7 min, occupies the lane): run with no flags."
        exit 1
    fi

    require_engine_idle
    log_step "Comparing against the oracle"
    set +e
    timeout 3600 wolframscript -file "${SCRIPT_DIR}/tier1_diff.wls" \
        "${RUN_DIR}/ParticleSpectrograph${THEORY}.mx" \
        "${REF_DIR}/sm2506b/ParticleSpectrograph${THEORY}.mx" \
        "${THEORY}" \
        "${RUN_DIR}/tier1_diff.json" > "${RUN_DIR}/diff.log" 2>&1
    set -e
    if [[ ! -f "${RUN_DIR}/tier1_diff.json" ]]; then
        log_error "The comparison produced no artifact"
        tail -20 "${RUN_DIR}/diff.log"
        exit 1
    fi
}

summarize() {
    set +e
    python3 "${SCRIPT_DIR}/summarize_diff.py" "${RUN_DIR}/tier1_diff.json" \
        | tee "${RUN_DIR}/tier1_summary.txt"
    local rc=${PIPESTATUS[0]}
    set -e
    return "$rc"
}

main() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --diff-only)      DIFF_ONLY="$2"; shift 2 ;;
            --skip-preflight) SKIP_PREFLIGHT="true"; shift ;;
            --timeout)        TIER1_TIMEOUT="$2"; shift 2 ;;
            --checkpoint-at)  CHECKPOINT_AT="$2"; shift 2 ;;
            --theory)         THEORY="$2"; shift 2 ;;
            --help|-h)        show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; exit 1 ;;
        esac
    done

    trap cleanup EXIT INT TERM

    if [[ -n "$DIFF_ONLY" ]]; then
        RUN_DIR="$(cd "$DIFF_ONLY" && pwd)"
        log_info "Re-comparing an existing run: ${RUN_DIR}"
        require_engine_idle
        ensure_reference_sources
        run_diff
        summarize
        exit $?
    fi

    require_engine_idle
    require_psalter
    ensure_reference_sources
    check_oracle_loadable
    preflight
    make_run_dir

    if ! run_spectrum; then
        log_error "The run did not produce a comparable result; see ${RUN_DIR}"
        exit 1
    fi

    run_diff
    summarize
    exit $?
}

main "$@"
