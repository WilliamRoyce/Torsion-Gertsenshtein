# I-ONB — One onboarding path: a fresh user, their own Wolfram ID, the certified configuration

> **STATUS: COMPLETE — 2026-09-12.** Merged from `cosmo/onb-one-path` (PR #564,
> `CI 34712322686: success` on `1158235f`). Closed #559. One six-step path in
> `WOLFRAM_GUIDE.md`; `initializeCommand` + the `wolfram-objects` volume; the postCreate
> chain's Wolfram wiring extracted to `setup-wolfram-links.sh`, which always exits 0 so a
> container completes without an engine and says what to run; `setup_wolfram_engine.sh` and
> `setup_xact.sh` deleted, `validate-setup.sh` and `check-wolfram.sh` redirected;
> `tests/test_devcontainer_creation.py` added. Found a **second** fresh-host abort this prompt
> did not know about (`install-lsp-wl.sh:17`), which had been silently skipping the Claude
> memory restore and the session reindex. Opened #565.
>
> Kept as the record of *what was asked*. **Not an open assignment.**


| | |
|---|---|
| **Issue** | **#559** (this work) · #488 (umbrella) · #543 (the certified configuration this must reproduce) · foundation audit 2026-09-11 |
| **Wave** | 0-completion, hardening (runs alongside the orchestrator's certification-mechanics work) |
| **Wolfram lane** | **NO.** Never start a kernel. The lane guard (`.claude/hooks/wolfram-guard.sh`, #555) now blocks bare `tidal derive` and `bash run.sh` too — it will stop you rather than fail open. The orchestrator runs the kernel rehearsal at merge. |
| **Depends on** | the orchestrator's `scripts/psalter/ensure_registered.sh` (exists) and the corrected verify script (exist on trunk before you branch) |
| **Owned paths** | `.devcontainer/**` (incl. `devcontainer.json`, all docs, the legacy setup scripts) · root `README.md` setup section · `scripts/README.md` · `scripts/install-wolfram-engine.sh` · `scripts/install-xact-xcoba.sh` · `scripts/activate-wolfram.sh` |
| **NOT owned** | `scripts/psalter/**`, `scripts/verify-wolfram-setup.sh`, `scripts/install-psalter.sh` (orchestrator) · anything under `docs/cosmology/` |

## Why this exists — verified facts, not impressions

A new person cloning this repo on a fresh machine with their own Wolfram ID cannot reach the
certified configuration. They cannot reach a working container:

- **`postCreateCommand` aborts on a fresh host.** `devcontainer.json:21-24` bind-mounts
  `${localEnv:HOME}/.local/wolfram/engine/14.3`, `…/userbase` and `~/.cache/Wolfram`. On a new
  host none exist; Docker creates them **empty, root-owned**. Then line 74's chain reaches
  `sudo ln -sf … ~/.local/wolfram/engine/14.3/Executables/wolframscript` — the
  parent does not exist — the `&&` chain dies, `waitFor: postCreateCommand` reports failure,
  and everything after it (license links, memory restore, LSP) never runs. There is no
  `initializeCommand`; nothing creates the host directories; `${localEnv:HOME}` is unguarded
  (empty when VS Code is launched from Windows → sources at filesystem root); the blanket
  `sudo chown -R ~/.local` silently rewrites host ownership.
- **Three onboarding paths disagree and none reaches PSALTer.** (A) `.devcontainer/docs/
  WOLFRAM_GUIDE.md:3-83` (mirrored in `.devcontainer/README.md:35-75`, `QUICKREF.md:12-26`):
  `setup_wolfram_engine.sh` → `setup_xact.sh` → `validate-setup.sh` → "Done!" — installs the
  engine into the mount (right) and xAct **1.3.0** (right — see below), and stops before PSALTer.
  (B) root `README.md:271-284`: `install-wolfram-engine.sh` → `activate-wolfram.sh` →
  `install-xact-xcoba.sh` → `verify-wolfram-setup.sh` (no `--require-psalter`) — installs the
  engine to `/usr/local/Wolfram/…` (**not mounted**, wiped on rebuild, and `WolframScript.conf`
  keeps pointing at the empty mount so `wolframscript` silently falls back to **cloud
  evaluation**) and xAct **1.2.1**. (C) `scripts/README.md`: same as B plus two **false**
  statements — `:19` "installed automatically during container creation" (no hook does) and
  `:278` a `postAttachCommand` that does not exist.
- **The installer is described three ways.** `setup_wolfram_engine.sh:145,159,165`:
  `WolframEngine_14.3.0_LINUX.sh`, "3–4 GB", `~/Downloads`. `install-wolfram-engine.sh:28`,
  `README.md:273`, `scripts/README.md:13`: `WolframEngine_14.3.0_LIN.sh`, `third_party/`.
  Actual: `third_party/WolframEngine_14.3.0_LIN.sh`, 1,750,578,010 bytes.
- **`install-wolfram-engine.sh:6`** claims it is "designed to be run during dev container
  creation" — false; `:24` targets `/usr/local/Wolfram/WolframEngine`.
- **`install-xact-xcoba.sh:158-167`**: the `mcc` search path is `/usr/local/Wolfram/…`
  (absent here; the engine's `mcc` is at `~/.local/wolfram/engine/14.3/Executables/mcc`) and
  the glob sits inside `[[ -f $path ]]`, where bash never expands it — the branch cannot
  succeed.
- **The working xPerm binary is hand-made.** `xperm.linux.64-bit` on the author's host is a
  367-byte wrapper script + `.compiled`, produced by `.devcontainer/scripts/{build,fix}-xperm.sh`,
  which appear in no ordered path.
- **`WOLFRAM_GUIDE.md:285-296`** implies WolframScript needs cloud login ("Wolfram ID tokens for
  WolframScript"). It does not once `WOLFRAMSCRIPT_KERNELPATH` is pinned; nothing in the
  pipeline needs the cloud login. The `.activation_backup` restore in `postCreateCommand`
  restores **cloud tokens**, not the license; `WOLFRAM_GUIDE.md:199-203` says otherwise.
- **The resource registry is container overlay.** `~/.Wolfram/Objects` is not mounted; nothing
  re-registers on rebuild; without registration PSALTer writes a *silently wrong* spectrum.

**CORRECTION you must carry (2026-09-11):** the certified xAct is the **1.3.0 bundle**
(xTensor 1.3.0 of 2025-12-29, xPerm 1.2.4, xCore 0.6.10, xCoba 0.8.6 — measured from the
installed `.m` headers; installed by `setup_xact.sh` on 2026-02-03). The "xAct 1.2.1" that
`install-xact-xcoba.sh:21` defaults to, and that three docs repeated, was a label copied from
that default and never measured. So the `scripts/` stack's xAct default is the *stale* one
and the `.devcontainer` stack's is the certified one — the reverse of what a first reading
suggests. `verify-wolfram-setup.sh` now asserts the four package `$Version` strings.

## The deliverable: six steps, documented once, everything else points at them

1. Download `WolframEngine_14.3.0_LIN.sh` (~1.6 GB; needs a Wolfram account) into `third_party/`.
2. Install the engine into the **mount**: `~/.local/wolfram/engine/14.3`.
3. `wolframscript -activate` with **your own** Wolfram ID — interactive, once; writes
   `mathpass` into the mounted userbase. This is engine *activation*; it is not a cloud login,
   and nothing in the pipeline needs a cloud login.
4. `bash scripts/install-xact-xcoba.sh` — **default corrected to 1.3.0**, writing an
   `INSTALLED_VERSION` marker beside the packages.
5. `bash scripts/install-psalter.sh` — installs PSALTer at `bb45adb0`, **registers the two
   Function Repository resources** (via `ensure_registered.sh`), verifies.
6. `bash scripts/verify-wolfram-setup.sh --require-psalter` → **exit 0**. That is the
   definition of "set up correctly": engine 14.3.0 on the mount, xAct fingerprint, PSALTer at
   the pin, the two resources resolving to their **certified identities** on master and
   subkernel. State the certified tuple in the doc: **Wolfram 14.3.0 × xAct 1.3.0 × PSALTer
   `bb45adb0` × two locally registered resources, independent of cloud login.**

## Work

1. **Fresh-host container creation.** In `devcontainer.json:74`: a guarded `mkdir -p` for
   every engine-side and userbase-side directory before the first `ln -sf` (and make each
   engine-side link conditional on the engine being present, so a container without the
   engine still finishes creating and tells the user to run steps 1–3); an `initializeCommand`
   that creates the three host directories as the invoking user; a guard that fails **loudly**
   if `${localEnv:HOME}` is empty; narrow the `chown -R` to what the container actually needs.
2. **Add the two lines the orchestrator hands you, verbatim.** In `mounts`:
   `"source=wolfram-objects,target=/home/vscode/.Wolfram,type=volume"` (the resource
   registry — the `claude-code-data` volume on line 25 is the proven pattern; a bind to a
   non-existent host dir would be root-owned). At the end of `postCreateCommand`, after
   `reindex-claude-sessions.sh`:
   `&& (bash scripts/psalter/ensure_registered.sh || echo 'PSALTer resources NOT registered -- run: bash scripts/psalter/ensure_registered.sh')`
   — it must not abort container creation on a host that has not installed the engine yet,
   but it must print the exact recovery command.
3. **Collapse the three paths into one.** `WOLFRAM_GUIDE.md` becomes the single source (the
   six steps, the certified tuple, the activation-vs-cloud-login section, what persists where
   and why, `.activation_backup` described truthfully). `.devcontainer/README.md`, `QUICKREF.md`,
   root `README.md:271-284`, `scripts/README.md:107-120` point at it and contradict nothing.
4. **Retire or redirect the `.devcontainer/` install stack**: `setup_wolfram_engine.sh` and
   `setup_xact.sh` either become thin wrappers over the `scripts/` stack or are deleted;
   `validate-setup.sh` and `check-wolfram.sh` point at `verify-wolfram-setup.sh` (they know
   nothing of PSALTer or the registry). Delete, do not leave a corpse: the tag `v0.54.0` keeps
   them.
5. **`install-wolfram-engine.sh`**: inside a container the target is the mount
   (`$HOME/.local/wolfram/engine/14.3`); refuse `/usr/local` there; header corrected.
6. **`install-xact-xcoba.sh`**: default `1.3.0`; the URL pattern that actually works for 1.3.0
   (`install-xact-xcoba.sh:107` uses `https://xact.es/download/xAct_${V}.tgz`, `setup_xact.sh:27`
   uses `https://xact.es/xAct_${V}.tgz` — find out which is real, by `curl -I`, and keep one);
   `mcc` resolved from `dirname "$(command -v wolframscript)"`; the xPerm wrapper folded in or
   documented as an explicit step; write `INSTALLED_VERSION`.
7. **Delete the false statements** (`scripts/README.md:19`, `:278`; the three installer
   name/size/location variants; "Wolfram ID tokens for WolframScript").
8. **`activate-wolfram.sh`**: say what it creates (`mathpass`, where, why it survives) and that
   it is not a cloud login.

## Success criteria — stated before code, verified from artifacts

1. **Cold read**: `WOLFRAM_GUIDE.md` alone yields the six steps and the certified tuple; the
   four other docs point at it and contradict nothing (`grep -rn 'LINUX.sh\|postAttachCommand\|3-4 GB\|/usr/local/Wolfram' .devcontainer/ scripts/README.md README.md` → zero outside dated notes).
2. **Fresh-host rehearsal without a kernel**: extract the `postCreateCommand` chain into a
   script and run it with `HOME=/tmp/fresh-home` (empty) — it **completes** and prints the
   steps-1–3 message. **Probe it failing first** on the unmodified chain, and paste both.
3. `bash -n` on every touched script; `bash scripts/install-xact-xcoba.sh --help` (no kernel)
   shows the corrected default; the `mcc` resolution is demonstrated by a dry path.
4. `.devcontainer/devcontainer.json` is valid JSON with comments stripped (`python3 -c` check).
5. Draft PR at your first commit; `ruff`/`cspell` clean; no kernel started; no version bump;
   nothing outside owned paths; **`verify-wolfram-setup.sh` and `install-psalter.sh` untouched**.

**The orchestrator runs the kernel rehearsal at merge**: steps 4–6 of the path against a
scratch `$UserBaseDirectory` with the existing activated engine, ending at
`--require-psalter` → 0 using the engine-bundled `LinearlyIndependent.wl` and the committed
notebook, with no cloud fetch.

## Working rules

Worktree: `git worktree add /tmp/tidal-onb -b cosmo/onb-one-path feat/cosmology-program`.
Draft PR into `feat/cosmology-program` at your first commit. **Never merge, never bump, never
edit `CHANGELOG.md`, never touch the shared working directory.** Conventional commits, no
attribution trailers. Before running *any* wrapper script, grep it for `wolframscript` and
`tidal derive` — a fence that names a tool cannot see a step that names a script (#555).
**Read the tool's own docs first**: Wolfram's `devcontainer`-relevant behavior (bind sources,
`initializeCommand`) is documented; check it before reasoning from what this repo does.

## If you find the design wrong

Design-document error → amend at the instruction site, dated, and report. Architectural
contradiction (e.g. the mount cannot be made to work for a fresh host) → **stop and report**.

## Report back

Branch · PR · each criterion with its output (both rehearsal transcripts) · every file
retired · anything the orchestrator should route · suggested next step.
