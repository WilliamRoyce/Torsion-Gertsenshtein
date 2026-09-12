#!/usr/bin/env bash
# setup-wolfram-links.sh -- wire the mounted Wolfram Engine, userbase and cache
# into every location the engine, wolframscript and the license manager consult.
#
# Extracted from devcontainer.json's postCreateCommand (GH #559).  It is a file,
# not a segment of a JSON string, for three reasons:
#
#   - the chain aborted at its first engine-side `ln` on any host that had not
#     installed the engine yet, and because `&&` stops there, everything after
#     it -- the license links, the Claude memory restore, the session reindex --
#     silently never ran;
#   - every path here derives from $HOME, so the bytes that run in the container
#     can be rehearsed against an empty throwaway home, with no Wolfram kernel
#     and no sudo;
#   - a chain inside a JSON string cannot be `bash -n`'d, traced, or diffed.
#
# EXIT-CODE CONTRACT: this script ALWAYS exits 0.  Container creation must not
# fail because the engine is not installed yet; it must finish and say what to
# run.  Hence no `set -e`: every step is guarded individually, failures are
# counted, and the summary names the recovery command.  (`set -e` plus a
# trailing `exit 0` is self-contradictory -- the script would die before its own
# summary.)  It starts no kernel and touches no network.
#
# Idempotent, which it must be: postCreateCommand runs it on every rebuild, and
# you are meant to re-run it by hand after installing or activating the engine:
#
#   bash .devcontainer/scripts/setup-wolfram-links.sh
#
# Rehearse it on an empty home without touching the real install:
#
#   FRESH=$(mktemp -d)
#   mkdir -p "$FRESH/.local/wolfram/engine/14.3" \
#            "$FRESH/.local/wolfram/userbase" "$FRESH/.cache/Wolfram"
#   env -i HOME="$FRESH" PATH=/usr/local/bin:/usr/bin:/bin \
#       bash .devcontainer/scripts/setup-wolfram-links.sh
set -uo pipefail

ENGINE_VERSION="${WOLFRAM_ENGINE_VERSION:-14.3}"
ENGINE_DIR="${HOME}/.local/wolfram/engine/${ENGINE_VERSION}"
# Derived from HOME only.  Deliberately NOT read from $WOLFRAM_USERBASE:
# devcontainer.json's remoteEnv sets that to the literal container path, so
# honouring it would make a rehearsal under a throwaway HOME write into the
# real userbase.  remoteEnv's value already equals the path computed here.
USERBASE_DIR="${HOME}/.local/wolfram/userbase"
CACHE_DIR="${HOME}/.cache/Wolfram"
CONF_DIR="${HOME}/.config/Wolfram/WolframScript"
CONF_FILE="${CONF_DIR}/WolframScript.conf"
MATHPASS="${USERBASE_DIR}/Licensing/mathpass"
KERNEL="${ENGINE_DIR}/Executables/WolframKernel"
# The engine's own wolframscript, addressed twice: as the relative link text
# (resolved from Executables/) and as the absolute file whose presence is half
# of the engine test.
WS_LINK_TEXT="../SystemFiles/Kernel/Binaries/Linux-x86-64/wolframscript"
WS_SOURCE="${ENGINE_DIR}/SystemFiles/Kernel/Binaries/Linux-x86-64/wolframscript"
# Container-wide license location.  Not a per-user path, so it stays literal.
SYSTEM_LICENSE_DIR="/usr/share/WolframEngine/Licensing"

FAILURES=0
note() { printf 'setup-wolfram-links: %s\n' "$*"; }
warn() { printf 'setup-wolfram-links: %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

# Escalate only when we are not root AND sudo needs no password, so nothing can
# ever block container creation on a password prompt.
as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then sudo "$@"
  else return 1
  fi
}

ensure_dir() {
  [ -d "$1" ] && return 0
  mkdir -p "$1" 2>/dev/null && return 0
  as_root mkdir -p "$1" 2>/dev/null && return 0
  warn "cannot create directory: $1"
  return 1
}

# -n (--no-dereference) is load-bearing.  `ln -sf TARGET LINK` where LINK is
# ALREADY a symlink to a directory does not replace LINK: it creates
# LINK/basename(TARGET) *inside* the target.  That bug is latent in the chain
# this script replaces -- ~/.WolframEngine lives on the container overlay
# (it is in no mount), so every rebuild starts clean and the link is never
# recreated over itself.  Moving the logic into a script you re-run by hand is
# exactly what makes it reachable, which is why the flag is here.
relink() {
  ln -sfn "$1" "$2" 2>/dev/null && return 0
  as_root ln -sfn "$1" "$2" 2>/dev/null && return 0
  warn "cannot link $2 -> $1"
  return 1
}

# The container writes the userbase (paclets, xAct, mathpass) and the
# wolframscript cache.  A bind source created by Docker rather than by
# initializeCommand is root-owned.  Take ownership of ONLY these two -- never
# the engine tree (1.6 GB, read-only in use) and never all of ~/.local, which
# the blanket `sudo chown -R` this replaces rewrote on the HOST through the bind.
ensure_writable() {
  [ -d "$1" ] || return 0
  [ -w "$1" ] && return 0
  note "not writable: $1 -- taking ownership (bind mount: this also changes host ownership)"
  as_root chown -R "$(id -u):$(id -g)" "$1" 2>/dev/null || warn "cannot take ownership of $1"
}

note "home: ${HOME}"

# --- userbase / cache side: unconditional; the container owns these ----------
ensure_dir "${USERBASE_DIR}/Licensing"
ensure_dir "${CACHE_DIR}"
ensure_writable "${USERBASE_DIR}"
ensure_writable "${CACHE_DIR}"

# $UserBaseDirectory comes from WOLFRAM_USERBASE, but the engine and several
# third-party packages still read ~/.WolframEngine.  Keep them one tree.
relink "${USERBASE_DIR}" "${HOME}/.WolframEngine"

# --- wolframscript configuration --------------------------------------------
# Pinning WOLFRAMSCRIPT_KERNELPATH is what stops wolframscript from answering
# with a CLOUD evaluation: the image ships a standalone client at
# /usr/bin/wolframscript, and "1+1" succeeds there too.
if ensure_dir "${CONF_DIR}"; then
  {
    printf 'WOLFRAMSCRIPT_KERNELPATH=%s\n' "${KERNEL}"
    printf 'WOLFRAMSCRIPT_CLOUDBASE=%s\n' 'https://www.wolframcloud.com'
    printf 'WOLFRAMSCRIPT_AUTHENTICATIONPATH=%s\n' "${CACHE_DIR}/WolframScript/"
  } > "${CONF_FILE}" || warn "cannot write ${CONF_FILE}"
fi

# --- wolframscript cloud tokens ---------------------------------------------
# NOT the license.  The license is mathpass, below; this restores cloud
# authentication tokens only, and nothing in the TIDAL pipeline needs them.
if [ -d "${USERBASE_DIR}/.activation_backup" ]; then
  if cp -r "${USERBASE_DIR}/.activation_backup/." "${CACHE_DIR}/" 2>/dev/null; then
    note "wolframscript cloud tokens restored from the userbase backup"
  else
    warn "cannot restore cloud tokens from ${USERBASE_DIR}/.activation_backup"
  fi
fi

# --- license links: only once the license exists ----------------------------
# `wolframscript -activate` (install step 3) writes mathpass into the mounted
# userbase.  Linking to it before it exists would leave dangling links behind,
# so these are guarded -- and re-running this script after step 3 creates them.
# Guarding is also what keeps the fresh-home rehearsal free of sudo.
if [ -f "${MATHPASS}" ]; then
  if ensure_dir "${HOME}/.Mathematica/Licensing"; then
    relink "${MATHPASS}" "${HOME}/.Mathematica/Licensing/mathpass"
  fi
  if ensure_dir "${SYSTEM_LICENSE_DIR}"; then
    relink "${MATHPASS}" "${SYSTEM_LICENSE_DIR}/mathpass"
  fi
fi

# --- engine side: only when the engine is really on the mount ---------------
# The test is the engine's OWN files.  `command -v wolframscript` would be
# wrong: the image's /usr/bin/wolframscript makes an absent engine look present
# (#559), and a kernel that is not the mounted one evaluates in the cloud.
if [ -f "${WS_SOURCE}" ] && [ -x "${KERNEL}" ]; then
  ensure_dir "${ENGINE_DIR}/Executables"
  relink "${WS_LINK_TEXT}" "${ENGINE_DIR}/Executables/wolframscript"
  ensure_dir "${ENGINE_DIR}/Configuration/Licensing"
  relink "${MATHPASS}" "${ENGINE_DIR}/Configuration/Licensing/mathpass"
  note "engine wired: ${ENGINE_DIR}"
  if [ -f "${MATHPASS}" ]; then
    note "license present: ${MATHPASS}"
  else
    note ""
    note "Engine present but NOT activated. Run install step 3, once:"
    note "    wolframscript -activate        # your own Wolfram ID; not a cloud login"
    note "then re-run:  bash .devcontainer/scripts/setup-wolfram-links.sh"
    note ""
  fi
else
  # Deliberately do NOT create Executables/ or a wolframscript symlink here.
  # remoteEnv puts that directory on PATH, so a dangling link would serve a
  # broken wolframscript -- worse than no wolframscript at all.
  note ""
  note "Wolfram Engine ${ENGINE_VERSION} is NOT installed on the mount."
  note "    expected kernel: ${KERNEL}"
  note ""
  note "The container is complete; the Wolfram lane is not. Run install steps 1-3"
  note "from .devcontainer/docs/WOLFRAM_GUIDE.md:"
  note "    1. download WolframEngine_${ENGINE_VERSION}.0_LIN.sh (~1.6 GB) into third_party/"
  note "    2. bash scripts/install-wolfram-engine.sh    # installs onto the mount"
  note "    3. wolframscript -activate                   # your own Wolfram ID, once"
  note "then re-run:  bash .devcontainer/scripts/setup-wolfram-links.sh"
  note ""
fi

if [ "${FAILURES}" -ne 0 ]; then
  note "${FAILURES} step(s) failed above (details on stderr)."
  note "Fix the cause and re-run: bash .devcontainer/scripts/setup-wolfram-links.sh"
fi
exit 0
