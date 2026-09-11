#!/bin/bash
# PreToolUse hook: block parallel wolframscript (single Wolfram Engine license)
# Deny mechanism: exit code 2 = block the action
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check commands that can actually invoke wolframscript.
#
# This filter gates everything below it, including the pgrep check that is the
# actual enforcement -- so anything it does not match is ALLOWED. It therefore
# has to catch every spelling that reaches a kernel, not the two we happened to
# write down (GH #555, found when a delegate ran `bash run.sh` while another
# session held the lane; the complement of #400, which fixed the opposite
# direction).
#
#   wolframscript -f x.wls       matched below
#   uv run tidal derive t.toml   matched below
#   tidal derive theory.toml     MISSED before #555 -- and this bare form is
#                                what all 12 examples/*/run.sh actually use
#   bash run.sh                  MISSED before #555 -- indirect; resolved below
DERIVE_RE='(wolframscript|(^|[[:space:]/])tidal[[:space:]]+derive)'

if ! echo "$COMMAND" | grep -qE "$DERIVE_RE"; then
  # Not a direct invocation. It may still be a wrapper script that runs one, so
  # resolve any shell script named on the command line and look inside it. A
  # fence that names a tool cannot see a step that names a script.
  INDIRECT=""
  for TOKEN in $COMMAND; do
    case "$TOKEN" in
      *.sh|*.bash)
        CANDIDATE="$TOKEN"
        [ -f "$CANDIDATE" ] || CANDIDATE="${CLAUDE_PROJECT_DIR:-.}/$TOKEN"
        if [ -f "$CANDIDATE" ] && grep -qE "$DERIVE_RE" "$CANDIDATE" 2>/dev/null; then
          INDIRECT="$CANDIDATE"
          break
        fi
        ;;
    esac
  done
  [ -n "$INDIRECT" ] || exit 0
fi

# --- False-positive exclusions (GH #400) ---------------------------------
# The match above is on command TEXT, so it also catches commands that merely
# mention wolframscript, or tidal derive invocations that never start it.
# Those consume no license and must not be blocked.

# 1. Read-only inspections that happen to contain the pattern, e.g.
#    `pgrep -f wolframscript` — which is exactly what you want to run WHILE a
#    derivation is in flight.  Match on the first word of the command.
# head -1 first: $COMMAND may be multi-line (heredocs, continuations), and cut
# would otherwise emit one field per line rather than the leading word.
FIRST_WORD=$(printf '%s' "$COMMAND" | head -1 | sed -E 's/^[[:space:]]*//' | cut -d' ' -f1)
FIRST_WORD=$(basename "$FIRST_WORD" 2>/dev/null || printf '%s' "$FIRST_WORD")
case "$FIRST_WORD" in
  # read-only inspection
  pgrep|pkill|ps|grep|rg|egrep|fgrep|ag|awk|sed|cat|head|tail|wc|less|ls|find|\
  diff|cmp|jq|sort|uniq|tee|file|stat)
    exit 0
    ;;
  # tools that never invoke Wolfram but routinely quote its name — writing an
  # issue comment or commit message about wolframscript must not be blocked
  gh|git|echo|printf|cp|mv|mkdir|touch)
    exit 0
    ;;
esac

# 2. `tidal derive --dry-run` only prints the generated script and returns
#    before any wolframscript call; --help likewise.  Neither takes the license.
echo "$COMMAND" | grep -qE '(^|[[:space:]])--(dry-run|help)([[:space:]]|$)' && exit 0

# Block if wolframscript is already running.
#
# Use -x (match the process NAME) rather than -f (match the whole command
# line).  With -f, any shell whose command line merely *mentions*
# wolframscript matches — including the very shell running the command being
# checked — so the guard fired spuriously on commands that were only talking
# about wolframscript.  See GH #400.
if pgrep -x wolframscript > /dev/null 2>&1 || pgrep -x WolframKernel > /dev/null 2>&1; then
  if [ -n "${INDIRECT:-}" ]; then
  echo "BLOCKED: $INDIRECT invokes a Wolfram derivation, and wolframscript is already running (single Wolfram Engine license)." >&2
else
  echo "BLOCKED: wolframscript already running (single Wolfram Engine license). Wait for it to finish or kill it first." >&2
fi
  exit 2
fi
exit 0
