# AIMS commands

All commands operate on `AIMS_HOME` (default `~/.aims`). Session ids are
`<UTC-timestamp>-<project>-<topic>-<agent>`.

### `aims init [dir]`
Scaffold a data repo: `sessions/work/`, `.worktrees/`, `SESSIONS.md`, gitignored `credentials/`.

### `aims start <project> <topic> [agent] [--scope host:x,repo:y,...]`
Creates branch `ai/<id>` + worktree from `origin/main`, seeds `metadata.json` (incl. empty
`environment` block), pushes the start commit.

### `aims save`  *(run inside a worktree)*
`git add -A` (whole worktree) + commit + **push when the branch is ahead of origin**. Never leaves
work stranded.

### `aims handoff [note]`  *(inside a worktree)*
Guarantees `origin` has the complete session, sets `status=handoff`, and does not merge to main.

### `aims handoff <session-id>`  *(from `AIMS_HOME/.worktrees/`)*
Selects one local session by ID, then performs the same validated handoff from its worktree. It refuses a missing/mismatched worktree or metadata; it does not publish, merge, delete, reset, or force-push.

### `aims handoff-all [--yes]`  *(from `AIMS_HOME`)*
Finds valid local AIMS worktrees and hands each off. Without `--yes`, requires an interactive `HANDOFF` confirmation. It runs the secret scanner before each session, leaves every worktree in place, and reports blocked sessions without publishing them.

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

### `aims adopt <session-id> [--remote]`
Fetches from origin, prints an **adoption report** (environment + host probe + recommendation),
creates a worktree from the existing branch, logs the takeover. `--remote` = report only. Refuses a
merged/absent session; warns on a recent (possibly live) writer unless `status=handoff`.

### `aims publish <session-id>`
Merges the branch to `main`, appends a registry row to `SESSIONS.md`, deletes the branch. Refuses a
dirty or unpushed worktree; warns on an empty merge; prints the full session diff.

### `aims artifacts <session-id>`
Prints (and creates) the session's directory in the shared large-file store. Requires
`AIMS_ARTIFACTS` to point at a mounted store — see [SHARED-STORE.md](SHARED-STORE.md). Git keeps
pointers; the store keeps bytes.

### `aims list`
Active `ai/*` branches with age, scope, and a STALE flag (>48h).

### `aims doctor`
Checks git/bash/python3, the data repo, registry, and origin remote.
