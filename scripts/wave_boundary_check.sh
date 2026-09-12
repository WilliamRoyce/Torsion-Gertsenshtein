#!/usr/bin/env bash
# wave_boundary_check.sh -- the mechanical half of the wave-boundary checklist
# (docs/COSMOLOGY_PROGRAM.md, "Wave-boundary checklist"), as one command whose
# output IS the boundary record.
#
# Why a script: three orchestrator omissions in Wave 0 -- the independent Tier-1
# re-run, the per-wave version bump, the EXPIRES-WITH grep before closing an
# issue -- were all items the checklist named in prose and nobody executed.  A rule
# stated in prose is not enforcement (the programme's own rule, applied to its
# orchestrator).  Every line below is either GREEN, RED, or a fact to paste.
#
#   bash scripts/wave_boundary_check.sh            # no Wolfram kernel is started
#   bash scripts/wave_boundary_check.sh --with-wolfram   # also runs verify --require-psalter
#
# Exit 0 only if every RED-capable line is GREEN.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$REPO_ROOT"
WITH_WOLFRAM=false; [[ "${1:-}" == "--with-wolfram" ]] && WITH_WOLFRAM=true
red=0
ok()   { printf '  GREEN  %s\n' "$1"; }
bad()  { printf '  RED    %s\n' "$1"; red=1; }
fact() { printf '  --     %s\n' "$1"; }

echo "== wave boundary check @ $(git rev-parse --short HEAD) ($(date -u +%FT%TZ)) =="

# 1. tree, worktrees, branches
[[ -z "$(git status --porcelain)" ]] && ok "working tree clean" || bad "working tree dirty: $(git status --porcelain | wc -l) path(s)"
n=$(git log --oneline "@{u}..HEAD" 2>/dev/null | wc -l); [[ "$n" -eq 0 ]] && ok "nothing unpushed" || bad "$n unpushed commit(s)"
n=$(git worktree list | wc -l); [[ "$n" -eq 1 ]] && ok "no delegate worktrees" || bad "$((n-1)) extra worktree(s): $(git worktree list | tail -n +2 | awk '{print $1}' | tr '\n' ' ')"
n=$(git ls-remote --heads origin 'cosmo/*' 2>/dev/null | wc -l); [[ "$n" -eq 0 ]] && ok "no remote cosmo/* branches" || bad "$n remote cosmo/* branch(es) not pruned"

# 2. CI conclusion for HEAD, FETCHED -- never inferred from a watch's exit code
sha=$(git rev-parse HEAD)
runs=$(gh run list --branch "$(git branch --show-current)" --limit 10 --json databaseId,workflowName,status,conclusion,headSha \
       -q ".[] | select(.headSha==\"$sha\") | \"\(.databaseId) [\(.workflowName)] \(.status)/\(.conclusion // \"pending\")\"" 2>/dev/null)
if [[ -z "$runs" ]]; then bad "no CI run found for HEAD $(git rev-parse --short HEAD) (push first)"; else
  while read -r line; do
    case "$line" in *"completed/success"*) ok "CI $line" ;; *) bad "CI $line" ;; esac
  done <<< "$runs"; fi

# 3. issues: milestones, and EXPIRES-WITH markers whose issue is closed
no_milestone=$(gh issue list --state open --limit 200 --json number,milestone -q '.[] | select(.number>=487) | select(.milestone==null) | .number' 2>/dev/null | tr '\n' ' ')
[[ -z "$no_milestone" ]] && ok "every open cosmology issue has a milestone" || bad "open issues without a milestone: $no_milestone"
stale=""
for n in $(grep -rhoE 'EXPIRES-WITH: #[0-9]+' docs/ scripts/ 2>/dev/null | grep -oE '[0-9]+' | sort -u); do
  st=$(gh issue view "$n" --json state -q .state 2>/dev/null)
  if [[ "$st" == "CLOSED" ]]; then
    live=$(grep -rn "EXPIRES-WITH: #$n" docs/ scripts/ | grep -v 'EXPIRED\|still true' | wc -l)
    [[ "$live" -gt 0 ]] && stale="$stale #$n($live)"
  fi
done
[[ -z "$stale" ]] && ok "no EXPIRES-WITH marker for a closed issue left un-dated" || bad "closed issues with live EXPIRES-WITH markers:$stale (run the expiry grep)"

# 4. prompts: every I-*.md that the board says merged carries a STATUS header
no_header=""
for f in docs/cosmology/handoffs/I-*.md; do
  b=$(basename "$f" .md)
  if grep -q "| .*$b .*\*\*merged\*\*" docs/COSMOLOGY_PROGRAM.md 2>/dev/null && ! grep -q '^> \*\*STATUS' "$f"; then no_header="$no_header $b"; fi
done
[[ -z "$no_header" ]] && ok "every merged prompt carries a STATUS header" || bad "merged prompts without STATUS header:$no_header"

# 5. memory index: size and integrity
M="${HOME}/.claude/projects/-workspaces-torsion-gertsenshtein/memory"
if [[ -f "$M/MEMORY.md" ]]; then
  lines=$(wc -l < "$M/MEMORY.md"); bytes=$(wc -c < "$M/MEMORY.md")
  { [[ "$lines" -le 140 ]] && [[ "$bytes" -le 17408 ]]; } && ok "MEMORY.md $lines lines / $bytes B" || bad "MEMORY.md over cap: $lines lines / $bytes B (140 / 17408)"
  miss=$(grep -oE '\(([a-zA-Z0-9_.-]+\.md)\)' "$M/MEMORY.md" | tr -d '()' | sort -u | while read -r f; do [[ -f "$M/$f" ]] || echo "$f"; done)
  orphan=$(ls "$M"/*.md | xargs -n1 basename | grep -v '^MEMORY.md$' | while read -r f; do grep -q "($f)" "$M/MEMORY.md" || echo "$f"; done)
  [[ -z "$miss$orphan" ]] && ok "memory index complete (every link resolves, no orphan)" || bad "memory index: missing[$(echo $miss)] orphan[$(echo $orphan)]"
else fact "no memory dir at $M"; fi

# 6. retired CLI names still refuse cleanly
for c in sweep sample analyze plot; do
  uv run tidal "$c" --help >/dev/null 2>&1; rc=$?
  [[ "$rc" -eq 2 ]] && ok "tidal $c exits 2 (retired, names its replacement)" || bad "tidal $c exit=$rc (expected 2)"
done

# 7. the oracle and the version
if uv run python -m scripts.oracles.freeze_legacy_oracle --check >/tmp/wbc_oracle.txt 2>&1; then ok "oracle --check: $(tail -1 /tmp/wbc_oracle.txt)"; else bad "oracle --check failed: $(tail -1 /tmp/wbc_oracle.txt)"; fi
if uv run python -m scripts.oracles.freeze_legacy_oracle --staleness >/tmp/wbc_stale.txt 2>&1; then ok "oracle --staleness: $(tail -1 /tmp/wbc_stale.txt | cut -c1-80)"; else bad "oracle --staleness errored: $(tail -1 /tmp/wbc_stale.txt)"; fi
v=$(grep -m1 '^version' pyproject.toml | grep -oE '[0-9.]+'); t=$(git tag --sort=-creatordate | head -1)
[[ "v$v" == "$t" ]] && ok "version $v is tagged ($t)" || bad "pyproject version $v but newest tag is $t -- bump once per wave"

# 8. the certified Wolfram configuration (optional: starts kernels)
if $WITH_WOLFRAM; then
  if bash scripts/verify-wolfram-setup.sh --require-psalter >/tmp/wbc_verify.txt 2>&1; then ok "verify-wolfram-setup --require-psalter exit 0"; else bad "verify-wolfram-setup --require-psalter exit $? -- see /tmp/wbc_verify.txt"; fi
else fact "verify-wolfram-setup --require-psalter not run (pass --with-wolfram; needs the lane)"; fi

echo "== $([[ $red -eq 0 ]] && echo 'ALL GREEN' || echo 'RED ITEMS ABOVE') =="
exit $red
