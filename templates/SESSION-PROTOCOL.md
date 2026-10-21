# AIMS — AI Session Management System

**Version**: 4.2
**Last Updated**: 2026-07-04
**Author**: The AIMS authors
**Rename**: 2026-07-03 the system was renamed from SMS to AIMS; the old `sms-*` commands work as aliases of `aims *`
**v4.2 (2026-07-04)**: `--scope` in aims start, age+scope in aims list, automatic registry row in aims publish, pre-push guard on main, CONTEXT.md split (core + `context/ARCHIVE-*`)

## Core principle

AIMS v4 uses Git branches/worktrees instead of `.active` markers. A dirty `$AIMS_HOME` never blocks starting other work. The agent works in a separate checkout `$AIMS_HOME/.worktrees/<session-id>/` on the branch `ai/<session-id>` and commits+pushes its branch often.

## Where the agent's checkout is

```text
$AIMS_HOME/                         # main checkout, stable memory
$AIMS_HOME/.worktrees/<session-id>/  # agent checkout, branch ai/<session-id>
```

## Active session

Active session = the remote branch `origin/ai/<session-id>` exists.

There are no mandatory `.active` markers. Session presence and scope live in:

```text
sessions/work/<session-id>/metadata.json
```

## Session start

```bash
cd $AIMS_HOME
aims start <project> <topic> <agent> --scope host:server1,repo:my-repo   # scope is mandatory
```

The script:
1. creates a `session-id`,
2. creates the branch `ai/<session-id>` from `origin/main`,
3. creates the worktree `$AIMS_HOME/.worktrees/<session-id>/`,
4. creates `sessions/work/<session-id>/metadata.json` (with the given `scope`),
5. commits+pushes the agent's branch.

After the start the agent moves into the worktree and works only there.

**⚠️ cwd discipline**: EVERY command that edits session files must run in the worktree
(absolute paths or an explicit `cd` in the same command). Editing in `$AIMS_HOME` on main is an error;
the pre-push guard will block the push, but not the edit.

## Reading memory at start (progressive loading)

1. `CONTEXT.md` — ONLY the core (~20 KB): mandates + latest entries + a "how to load more" table
2. `<project>/STATE.md` — state and TODOs of your project (mandatory)
3. `context/ARCHIVE-*.md` — older history, ONLY when the session topic requires it: `grep -il '<topic>' $AIMS_HOME/context/`
4. Do NOT load whole archives or old sessions "just in case".

## Work during the session

The agent records current information in:

```text
sessions/work/<session-id>/
├── metadata.json
├── prompt-log.md
├── worklog.md
├── commands.md
├── tests.md
└── final-summary.md
```

Checkpoint:

```bash
./scripts/aims save
```

`aims save` commits+pushes the branch `ai/<session-id>`. It does not touch main.

## Session end

The agent completes `final-summary.md`, optionally updates the relevant `STATE.md`, `SESSIONS.md`, `CONTEXT.md` in its branch, then publishes:

```bash
cd $AIMS_HOME
./scripts/aims publish <session-id>
```

The script publishes through a separate publish worktree, merges the branch `ai/<session-id>` into `main`,
**automatically appends the registry row to `SESSIONS.md`** (the next `sNNN` is computed on the merged
tree — do NOT add the row by hand), pushes `main` (with `AIMS_PUBLISH=1` for the pre-push guard),
deletes the remote branch and the local worktree.

On a merge conflict the script cleans up after itself and prints instructions: in your worktree
`git fetch origin main && git rebase origin/main`, resolve the conflicts, `aims save`, retry publish.

## Session hygiene

- `aims list` shows the age of each session and flags `⚠️ STALE(>48h)` — publish or delete such sessions
  (`git push origin --delete ai/<sid>` + `git worktree remove`).
- Pre-push guard: `./scripts/aims install-hooks` installs a hook that blocks a direct push to `main`
  (shared by all worktrees). Run it once after a clone/restore.
- `CONTEXT.md` core: max ~20 KB / 10 entries; move the oldest entries 1:1 to `context/ARCHIVE-<year>-H<n>.md`.
  Do not paste command dumps or per-project content (those → `<project>/STATE.md`).

## Conflicts

Not blocking:
- a dirty `$AIMS_HOME`,
- another agent's active branch,
- another agent's unpublished session,
- the same project without an overlapping scope;
- a validly detected overlapping scope — AIMS prints a `WARN` and continues after admission serialization.

Diagnostics may point to the same host, VM/CT, code/IaC repo, file, service or public document, but
a validly detected overlap is advisory — do not stop for that reason alone. Still blocking:
- a malformed scope,
- an origin/Git/lease failure or an unverifiable recheck,
- adopting a session without `status=handoff` (except the explicitly read-only `--remote`).

## Listing active sessions

```bash
cd $AIMS_HOME
./scripts/aims list
```

## File rules

- `$AIMS_HOME` on `main` is for reading and the final publication.
- The agent does not work in the `$AIMS_HOME` checkout on main.
- The agent works in `$AIMS_HOME/.worktrees/<session-id>/`.
- `.worktrees/` is ignored by git.
- During work the agent prefers its own directory `sessions/work/<session-id>/`.
- Shared files (`STATE.md`, `SESSIONS.md`, `CONTEXT.md`) are updated only at the end of the session, in the agent's branch.

## Compatibility

The old `.active/.done` markers are legacy and do not block work. `scripts/session-preflight` is a legacy helper and must not block starting work in AIMS v4.

The commands `scripts/sms-start`, `sms-save`, `sms-publish`, `sms-list` are legacy aliases (since 2026-07-03) that call their `aims *` counterparts — agents with old instructions still work. New instructions use only `aims *`.

**Remember**: the branch is the session. The worktree is the agent's checkout. Main is not a place for an active agent to work.
