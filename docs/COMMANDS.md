# AIMS commands

All commands operate on `AIMS_HOME` (default `~/.aims`). Session ids are
`<UTC-timestamp>-<project>-<topic>-<agent>`.

### `aims init [dir]`
Scaffold a data repo: `sessions/work/`, `.worktrees/`, `SESSIONS.md`, gitignored `credentials/`.

### `aims start <project> <topic> [agent] [--scope host:x,repo:y,...] [--continues-from <session-id>]`
Creates branch `ai/<id>` + worktree from `origin/main`, seeds `metadata.json` (incl. empty
`environment` block), verifies the branch is absent, pushes the start commit with a zero-OID lease,
and seeds the local `refs/aims/published/<id>` sentinel. `--continues-from` records an optional
validated predecessor session ID; it does not replace normal handoff/adopt of the same session branch.

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
Commits and pushes one selected local session, or every valid local session with `--all`, without changing its `active`/`handoff` status. It scans for secrets before staging. This is the primitive intended for an opt-in systemd user timer or macOS LaunchAgent; scheduling remains external so AIMS does not install a background service without explicit user consent.

### `aims brief <session-id>`  *(from `AIMS_HOME`)*
Creates an optional English `sessions/work/<session-id>/handoff.md` from the built-in template. It never overwrites an existing brief and does not replace the chronological `worklog.md`.

### `aims adopt <session-id> [--remote]`
Fetches an active remote session, prints an **adoption report** (environment, Git-native handoff delta, host probe, and recommendation), creates a worktree from the existing branch, logs the takeover, and seeds the local publication sentinel. `--remote` = report only. A published session is not an error: adopt reports that its branch was intentionally removed and points to `aims continue`.

### `aims status <session-id>`
Resolves a session against the shared source of truth. It reports `ACTIVE` for an existing `origin/ai/<session-id>` branch, `PUBLISHED` when complete artifacts exist in `origin/main`, and `NOT FOUND` only when neither source contains the ID.

### `aims continue <published-session-id> <new-topic> [agent] [--scope <csv>]`
Creates a new worktree from current `origin/main`, preserves the original project, and records `continues_from` in its metadata. It deliberately does not recreate a closed branch on an obsolete base.

### `aims conflicts --scope <csv>`
Read-only diagnostic for writable scopes. Exact `repo:`, `file:`, `host:`, and `service:` scopes conflict when equal; `path:` scopes conflict only when equal or one is a parent of the other. A `SAFE` result has no overlapping active remote scope.

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
Lists active `ai/*` branches with project, handoff status, age, scope, and a STALE flag (>48h). `--closed` reads published metadata from `origin/main`; filters are read-only and may be combined.

### `aims doctor`
Checks git/bash/python3, the data repo, registry, and origin remote.

### `aims wire-agents`
Detects supported local agents and installs the marker-delimited AIMS rules into their configuration files. It previews the files first and asks for confirmation unless `AIMS_YES=1`; backups are created once and repeated runs are idempotent.

### `aims install-hooks`
Installs or refreshes the data repo's pre-push guard. The guard blocks ordinary pushes to `main`; `aims publish` supplies the explicit integration context that permits the push.

### `aims preflight [mode]`
Reports the current Git repository root and selected mode. This lightweight probe is intended for agent startup checks and refuses execution outside a Git repository.

### `aims version | -v | --version`
Prints the engine version from `VERSION`.

### `aims help | -h | --help`
Prints the public command and environment-variable contract. Unknown options and surplus arguments are rejected with exit status `2` before command-specific mutations.
