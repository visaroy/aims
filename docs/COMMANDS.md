# AIMS commands

All commands operate on one data repo, resolved in this order: `$AIMS_HOME`, the path recorded by
`aims install` in `~/.config/aims/home` (`$XDG_CONFIG_HOME/aims/home`), an `AIMS_HOME` export parsed —
not executed — from a shell profile (`~/.zshenv`, `~/.zprofile`, `~/.zshrc`, `~/.bash_profile`,
`~/.bashrc`, `~/.profile`), then `~/.aims`. `aims home` prints it. Session ids are
`<UTC-timestamp>-<project>-<topic>-<agent>`.

## Explicit invocation policy

AIMS consent is scoped to the current task, not to each command. A clear current-task marker naming
AIMS at the beginning, middle, or end — for example, “This is an AIMS session”, “Use AIMS”, or “Save
the AIMS session” — opts that task into the standard AIMS lifecycle. Once opted in, the agent may use
the normal lifecycle commands needed for that session without separate consent for every operation.
“Save and close the AIMS session” is an explicit request to finish and publish it; session opt-in alone
does not imply closure.

Mere discussion or documentation of AIMS, ordinary coding, or a new conversation is not consent.
Without a current-task marker, use native agent mechanisms and do not invoke AIMS. Engine installation,
update, or repair is a separate explicit permission; if the engine is absent, ask rather than infer
permission from session opt-in. The CLI has no daemon and creates no session implicitly.

AIMS commands are caller-triggered and never run automatically. Externally configured schedulers, such
as a systemd timer, LaunchAgent, or CI job, are separate opt-in integrations. AIMS does not configure
or start such a scheduler automatically, and any scheduled invocation must itself be explicitly
authorized by the user.

## Installation commands

### `aims install [--fresh]`
The zero-configuration installer; `install.sh` runs it after restoring the engine checkout. It never
prompts and is idempotent: a second run changes nothing and reports `unchanged`.

1. **Preflight** — every check runs before the first change, and a blocker exits `1` with
   `Preflight found blockers — nothing was changed:` plus one line per blocker and its fix. Blockers:
   a missing `git`/`bash`/`python3`; an unwritable `~/.local/bin`, `~/.config/aims`, or
   `~/.local/state/aims`; a regular file at `~/.local/bin/aims`; more than one data repo candidate
   (below); a data repo path that exists but is not a Git repository; a `pre-push` hook in the data
   repo that is not the AIMS guard; an agent file with unresolved Git conflict markers, a malformed
   AIMS block, or no write permission; for `--fresh`, unsaved work in the old data repo.
2. **Command** — links `~/.local/bin/aims` to this engine's `bin/aims`.
3. **Data repo** — `$AIMS_HOME`, when set, is used as given. Otherwise the recorded path wins. With
   neither, the installer collects the candidates from shell profile exports and an existing `~/.aims`:
   one candidate is reused (created if it does not exist yet), none means `~/.aims` is created, and two
   different candidates are a blocker — rerun with `AIMS_HOME=<path>` to choose, and the choice is
   recorded. The installer never changes data repo content; it only creates a missing repo with the
   standard scaffold (`sessions/work/`, `.worktrees/`, `SESSIONS.md`, gitignored `credentials/`).
4. **Recorded path** — writes the data repo path to `~/.config/aims/home`, so every agent and shell
   finds it without editing shell profiles. AIMS never writes shell profiles.
5. **Guard** — installs or refreshes the data repo `pre-push` hook (`aims install-hooks`).
6. **Agent rules** — runs `aims wire-agents`.
7. **Report** — the data repo used (`created` or `reused, from env|config|found`), agent files
   changed, Git-tracked files that need a commit through a branch and pull request, possible
   duplicate AIMS text, the backup directory, the undo command, a remote hint when the data repo has
   no `origin`, and the full `aims doctor` output. The exit status is `1` if `aims doctor` reports an
   error.

`--fresh` replaces the data repo: the old one is moved to `<path>.aims-replaced-<UTC timestamp>` and a
new one is created. Nothing is deleted. It refuses while the old repo or any of its worktrees has
uncommitted changes, while a branch has commits that are not on `origin`, and — when there is no
`origin` — unless the repo is still the untouched scaffold. Worktrees inside the moved repo keep their
files; run `git worktree repair` inside the moved repo if you need them as worktrees again.

### `aims uninstall`
Reverses what `aims install` owns and keeps everything else. It removes only the marked AIMS block from
each known agent file (`~/AGENTS.md`, `~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md`,
`~/.gemini/GEMINI.md`, symlinks followed), so your own edits stay; a file that AIMS created and that is
empty afterwards is deleted, so an untouched file returns byte for byte. It also removes the AIMS
`pre-push` guard (only a hook carrying the AIMS guard header) from every data repo candidate, the
`~/.local/bin/aims` link, and `~/.config/aims/home`. Modified files are backed up first, as with an
install. The data repo, the engine checkout, and any `AIMS_HOME` exports in shell profiles are kept;
the output prints how to remove the engine. Running it twice is safe. A malformed block is reported and
left for manual repair (exit status `1`).

### `aims home [--explain]`
Prints the resolved data repo path. `--explain` also lists every candidate with its source (`env`,
`config`, `profile` with the file name, `default`) and whether it is a Git repository, and warns when
there is more than one non-environment candidate.

### `aims init [dir]` *(deprecated in 3.1, kept for the 3.x contract)*
Creates a data repo scaffold with its guard at `[dir]` (default: the resolved data repo), or reports
`AIMS data repo already exists at <dir>`. It prints a deprecation notice on stderr and does nothing
else: it does not record the path, link the command, or wire agents. Use `aims install`.

## Session commands

### `aims start <project> <topic> [agent] --scope host:x,repo:y,... [--continues-from <session-id>] [--parent-session <session-id>]`
Creates branch `ai/` followed by the session id, plus a worktree, verifies the branch is absent,
pushes the start commit with a zero-OID lease, and seeds the local `refs/aims/published/<id>`
sentinel. A valid detected scope overlap is advisory: `aims start` prints the `CONFLICT` diagnostics
and a `WARN`, then continues. Malformed requested scopes, unverifiable conflict checks, origin errors,
Git errors, and lease failures remain blocking. Before admission, it also acquires a **machine-local scope lock** (`$AIMS_HOME/.locks/`,
keyed by a hash of the normalized `--scope`) so two same-machine `aims start` invocations racing on
an overlapping scope — regardless of which process, orchestrator, or agent launched either one —
cannot both slip past the conflict check at the same instant; this lock requires no cooperation from
the caller and is released as soon as admission completes or fails. It also stamps an `observed`
block into `metadata.json` — hostname, the outermost resolvable ancestor process's PID and start
time, and an initial heartbeat — using facts the `aims start` binary itself reads from the operating
system, never values a caller supplies; these are used only for later stale-conflict diagnosis
(`aims conflicts`), never to bypass a real conflict. `--continues-from` records an optional validated
predecessor session ID. `--parent-session` is lineage only; it never exempts a child from the
standard overlapping-scope conflict check.

### `aims heartbeat <session-id>`  *(inside a worktree)*
Bumps `metadata.json`'s `observed.last_heartbeat` to now and pushes that single-field change,
without doing a full `aims save` commit-diff. Intended for a long-running task that would otherwise
show a stale heartbeat, or for an external, opt-in scheduler. It remains caller-triggered and does
not run automatically. `aims save` already bumps this as a
side effect on every save that has something to commit, so most sessions never need to call this
directly.

### `aims delegate-exec <parent-session-id> -- <command> [args...]`  *(inside the parent's worktree)*
The opt-in, ceiling-raising delegation primitive: an orchestrator that wants full correctness for a
delegated subprocess calls this **instead of** invoking the subagent CLI directly. It resolves the
parent session's local worktree, durably records the delegation (id, command, dispatch time) in the
parent's own `metadata.json` and commits/pushes it **before** the child process starts — so even a
child killed immediately after spawn leaves a git-visible "dispatched, not completed" record — then
runs the child with `cwd` set to the parent's worktree and `AIMS_SESSION_ID`/`AIMS_DELEGATE_ID`
exported via its own `exec`, so a delegated child that itself tries `aims start`/`save`/`handoff`/
`publish`/etc. is refused by the existing lifecycle guard. It also holds the local scope lock across
the child's execution, belt-and-suspenders. On exit it records `completed`/`failed` plus the exit
code and commits again. This raises the correctness ceiling for orchestrators that adopt it; it is
not required for the baseline guarantee, which the local scope lock plus the existing git-ref
admission lease provide unconditionally to every caller, cooperating or not.

### `aims save`  *(run inside a worktree)*
Scans tracked and untracked non-ignored files for secret patterns before mutation, then runs
`git add -A` (whole worktree) + commit + **push when the branch is ahead of origin**. Never leaves
work stranded. A normal save only fast-forwards the session branch using the exact remote OID observed
by its fetch; initial creation asserts remote absence and uses a zero-OID lease. After `aims rebase`,
it uses the private exact-OID rewrite marker and `--force-with-lease`; any other divergence is refused.

### `aims rebase <session-id|ai/session-id>`  *(run from `AIMS_HOME`)*
Requires the session worktree to exist, be clean, be on the requested branch, and have `HEAD` exactly
equal to a freshly fetched `origin/<branch>`. It records that exact OID in the private
`refs/aims/rewrite/<session-id>` ref, fetches `origin/main`, and rebases the session worktree onto it.
It also refreshes the local publication sentinel whenever the remote session branch is observed.
The marker survives active conflicts and fetch failures and is cleared only after a successful checkpoint,
a no-op/aborted rewrite, or a compare-and-swap cleanup of a non-resumable startup failure. Resolve a
conflict with `git rebase --continue`, then run `aims save`; use
`git rebase --abort` followed by `aims save` to abandon a rewrite safely.

When a remote rejects the rewritten-session force push, use the supported no-force recovery from the
session worktree: `git update-ref refs/aims/recovery/<session-id> HEAD`, `git fetch origin main`,
`git reset --hard refs/aims/rewrite/<session-id>`, `git merge --no-commit --no-ff origin/main`,
restore the tree with `git checkout refs/aims/recovery/<session-id> -- .`, `git add -A`, and
`git commit --no-edit`; then run `aims save` and delete the recovery ref only after it succeeds.
Preserving the rebased `HEAD` before reset keeps unique actual-conflict resolutions; the completed
merge keeps the original remote tip as an ancestor, so save can use an ordinary fast-forward push.

### `aims handoff [note]`  *(inside a worktree)*
Guarantees `origin` has the complete session, sets `status=handoff`, and does not merge to main. A
successful handoff refreshes the local publication sentinel and updates with the exact remote OID
observed before its checkpoint push. It first requires that observed tip to be an ancestor of local
`HEAD`; pre-existing divergence is refused before metadata changes. Tracked and untracked non-ignored
files are scanned for secret patterns before metadata, worklog, index, commit, or remote mutation.

### `aims handoff check <session-id>`  *(from `AIMS_HOME`)*
Performs a non-mutating readiness check for one local session. It blocks only unsafe transport conditions (missing/mismatched worktree or metadata, absent `origin`, or a potential secret); incomplete context such as no explicit next action is advisory and prints a warning. It never stages, commits, pushes, or changes metadata.

### `aims handoff <session-id>`  *(from `AIMS_HOME/.worktrees`)*
Selects one local session by ID, then performs the same validated handoff from its worktree. It refuses a missing/mismatched worktree or metadata; it does not publish, merge, delete, reset, or rewrite remote history.

### `aims handoff-all [--yes]`  *(from `AIMS_HOME`)*
Finds valid local AIMS worktrees and hands each off. Without `--yes`, requires an interactive `HANDOFF` confirmation. It runs the secret scanner before each session, leaves every worktree in place, and reports blocked sessions without publishing them or rewriting remote history.

**Step 1: run the handoff on Mac**

From the local worktree directory, select exactly one session:

```bash
cd ~/.AI/.worktrees
aims handoff 20260727T141115Z-meta-aims-bulk-handoff-recovery-and-checkpointing-hermes
```

AIMS validates the matching branch and metadata, scans for secrets, commits and pushes the complete session, then sets `status=handoff`. It pauses the session; it does not merge it into `main` or delete its worktree.

**Step 2: adopt it on the other machine**

```bash
cd ~/.AI
aims adopt 20260727T141115Z-meta-aims-bulk-handoff-recovery-and-checkpointing-hermes
```

Only after the work is verified and actually complete should `aims publish <session-id>` be used.

### `aims checkpoint <session-id>|--all`  *(from `AIMS_HOME`)*
Commits and pushes one selected local session, or every valid local session with `--all`, without changing its `active`/`handoff` status. It scans for secrets before staging. This is the primitive intended for an externally configured, opt-in systemd user timer or macOS LaunchAgent; scheduling remains separate and caller-configured, so AIMS does not install or start a background service automatically.

### `aims brief <session-id>`  *(from `AIMS_HOME`)*
Creates an optional English `sessions/work/<session-id>/handoff.md` from the built-in template. It never overwrites an existing brief and does not replace the chronological `worklog.md`.

### `aims adopt <session-id> [--remote]`
Fetches an active remote session, prints an **adoption report** (environment, Git-native handoff delta,
advisory scope-overlap diagnostics, host probe, and recommendation), creates a worktree from the existing
branch, logs the takeover, and seeds the local publication sentinel. A valid overlap in the advisory
diagnostics does not block a handed-off adoption. Local adoption still requires `status=handoff`;
non-handoff status, malformed target scope metadata, origin errors, Git errors, and lease failures remain
blocking. `--remote` = report only. A published session is not an error: adopt reports that its branch was
intentionally removed and points to `aims continue`.

### `aims status <session-id>`
Resolves a session against the shared source of truth. It reports `ACTIVE` for an existing `origin/ai/<session-id>` branch, `PUBLISHED` when complete artifacts exist in `origin/main`, and `NOT FOUND` only when neither source contains the ID.

### `aims continue <published-session-id> <new-topic> [agent] --scope <csv>`
Creates a new worktree from current `origin/main`, preserves the original project, and records `continues_from` in its metadata. It deliberately does not recreate a closed branch on an obsolete base.

### `aims conflicts --scope <csv> [--session <session-id>]`
Read-only diagnostic for writable scopes. Exact `repo:`, `file:`, `host:`, `service:`, and `dashboard:`
scopes conflict when equal; `path:` scopes conflict only when equal or one is a parent of the other.
A `SAFE` result has no overlapping active remote scope. A pre-existing branch with invalid or missing
scope metadata (for example a legacy session created before `--scope` was mandatory) prints one `WARN`
line naming it and is excluded from that scope's result — it never turns the whole check into a hard failure
for every other, valid session. When a `CONFLICT` is found, it also checks — using OS/git facts it re-derives
itself right now, never values trusted from the conflicting branch's own claims about itself beyond what
that branch's own `aims start` stamped at its creation — whether the conflict looks like a same-machine,
dead-ancestor, zero-commit-scaffold orphan, and if so prints a diagnosis suggesting `aims abandon <id>
--empty-only`. This is diagnosis only: it never auto-resolves a conflict, and never suggests reclaiming a
branch that has any commit beyond its initial scaffold.

### `aims abandon <session-id> --empty-only`
Deletes only a pristine, unstarted scaffold session: one commit beyond where it branched from `main`, no changed files outside its session directory, empty work artifacts, and no dirty, locally-ahead, or remotely-advanced worktree. It atomically deletes its session branch and owned scope leases with exact remote leases. Use it for a session blocked before work begins, including a diagnosed orphan from `aims conflicts`; never use it to discard real work.

### `aims abandon <session-id> --empty-only --confirm-orphan <same-session-id>`
The exact four-argument override is for a verified orphan whose canonical local worktree is gone. The repeated session id must be byte-exact; `ai/<session-id>`, reordered options, missing confirmation, and surplus arguments are rejected before fetch or mutation. AIMS warns that it cannot detect uncommitted work in another clone, so the repeated id is explicit operator authority, not proof that no other writer exists. The override additionally requires same-session metadata with `branch: ai/<session-id>`, `status: active`, a canonical worktree path, a nonempty scope whose list is exactly canonicalized by the shared `aims_scope_csv` helper, same-host OS-observed PID/start marker/heartbeat facts, exactly the six untouched scaffold paths, one commit beyond the true merge-base, and empty artifact blobs. It refuses canonical or registered worktrees, malformed/legacy/other-host metadata, and ahead or diverged local refs; remote deletion uses an exact-OID lease and never creates or removes a worktree. Remote races or server rejection preserve state and never recreate the branch; post-delete worktree/ref races and failed exact-OID cleanup preserve state and report truthful `PARTIAL`. The default two-argument `--empty-only` form and its local-worktree requirement are unchanged.

### `aims publish <session-id>`
Merges the branch to `main`, appends a registry row to `SESSIONS.md`, marks the committed metadata `published`, then deletes the remote branch, worktree, and verified merged local branch. Complete committed session artifacts remain in `origin/main`.

`aims save` also keeps a private `refs/aims/published/<session-id>` publication sentinel. It survives
tracking-ref pruning, so a previously published but remotely deleted session branch is never recreated
by a later save.

### `aims artifacts <session-id>`
Prints (and creates) the session's directory in the shared large-file store. Requires
`AIMS_ARTIFACTS` to point at a mounted store — see [SHARED-STORE.md](SHARED-STORE.md). Git keeps
pointers; the store keeps bytes.

### `aims list [--handoff] [--stale] [--closed] [--project <project>]`
Lists active `ai/*` branches with project, handoff status, age, scope, parent lineage, and a STALE flag (>48h). `--closed` reads published metadata from `origin/main`; filters are read-only and may be combined.

### `aims doctor`
Checks git/bash/python3, the data repo, registry, and origin remote. It warns when the data repo path
is not recorded, when `$AIMS_HOME` differs from the recorded path, when there is more than one data
repo candidate, when the `pre-push` guard is missing or outdated, and when an agent rules block is
outdated or malformed (run `aims install` to refresh).

### `aims wire-agents [--check]`
Adds or refreshes one marker-delimited block of AIMS-only rules from `templates/AGENTS.md` in the
config file of each detected agent: `~/.claude/CLAUDE.md` (Claude Code), `~/.gemini/GEMINI.md` (Gemini
CLI), `~/.codex/AGENTS.md` and `~/AGENTS.md` (Codex), `~/AGENTS.md` (OpenCode). Symlinks are followed
to the real file, and each real file is wired once. It never prompts (`AIMS_YES` is accepted and
ignored for compatibility).

- All targets are checked first; unresolved Git conflict markers, a malformed block, or an unwritable
  file stop it before any write.
- Only the block is written. A file without a block gets it appended; a file with a block has exactly
  that block replaced; an unchanged block is not rewritten.
- The block states that the user's rules outside it take precedence.
- A target tracked by Git is still written and is reported with its repository, to be committed through
  a branch and pull request.
- Lines outside the block that mention AIMS are reported as a possible duplicate, never removed.
- Each modified file is copied to `~/.local/state/aims/backups/<UTC timestamp>/files/` (outside every
  repository) and listed in `manifest.tsv`: original path, real path, SHA-256 before (`-` when the file
  did not exist), SHA-256 after, backup copy.

`--check` prints the same plan (`would be added`, `would be refreshed`, `unchanged`, tracked files,
possible duplicates) without writing anything; it exits `1` if there is a blocker.

### `aims install-hooks`
Installs or refreshes the data repo's pre-push guard. The guard blocks ordinary pushes to `main`; `aims publish` supplies the explicit integration context that permits the push. Work not opted into AIMS pushes a branch and merges it through a pull request; the guard's message names both paths.

### `aims preflight [mode]`
Reports the current Git repository root and selected mode. This lightweight probe is intended for agent startup checks and refuses execution outside a Git repository.

### `aims version | -v | --version`
Prints the engine version from `VERSION`.

### `aims help | -h | --help`
Prints the public command and environment-variable contract. Unknown options and surplus arguments are rejected with exit status `2` before command-specific mutations.
