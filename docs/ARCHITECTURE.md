# AIMS architecture

## Invocation model

AIMS is a caller-triggered CLI, not a daemon. It never creates a session implicitly, and lifecycle
commands are never run automatically. Consent is scoped to the current task: a clear marker naming
AIMS at the beginning, middle, or end — for example, “This is an AIMS session”, “Use AIMS”, or “Save
the AIMS session” — opts that task into the standard lifecycle. Agent instructions may then use the
normal lifecycle commands without separate consent for each operation. “Save and close the AIMS
session” explicitly authorizes final publication; session opt-in alone does not imply closure.

Mere discussion or documentation of AIMS, ordinary coding, or a new conversation is not consent. A
task without a current-task marker should use native agent mechanisms instead. Engine installation,
update, or repair remains a separate explicit permission, and an absent engine requires asking the
user rather than inferring permission from session opt-in. An explicit request to install AIMS is
consent to the complete installation described below — nothing more is done implicitly, and all of
it is reversible.

Externally configured schedulers, including systemd timers, LaunchAgents, and CI jobs, are separate
opt-in integrations. AIMS does not configure or start them automatically, and any scheduled command
is still subject to the user's explicit authorization of that integration.

## Source of truth: `origin`
Sessions live on a git remote, not on a machine. Every machine only pushes/pulls to `origin`.
No host needs inbound access to another — this is why handoff/adopt work across a laptop and a
locked-down server alike.

## Two layers
- **Work** (portable): branch `ai/<session-id>`, its worktree, `sessions/work/<id>/` files, commits.
- **Agent context** (not portable): the agent's transcript/reasoning, kept local and gitignored.

Continue from **artifacts**, never from the previous agent's context. This keeps AIMS agnostic to
which agent (Claude/Codex/opencode/Gemini) and which machine did the work.

## Lifecycle
```
aims start ─▶ work + aims save (checkpoint) ─┬─▶ aims handoff ─▶ (other machine) aims adopt ─▶ …
                                               └─▶ aims publish ─▶ merged to main, registry row, done
```

The diagram shows a possible explicitly requested lifecycle; it does not describe an automatic
background workflow.

## Engine vs data
- **Engine** (this repo, public): `bin/`, `lib/`, `hooks/`, `docs/`. No secrets, no private data.
- **Data repo** (private, per-user): sessions, `SESSIONS.md`, project state, `credentials/`
  (gitignored). Exactly one per user, resolved in this order: `$AIMS_HOME`, `~/.config/aims/home`,
  an `AIMS_HOME` export in a shell profile, `~/.aims`. Created only when none exists.

## Installation model
One entry point: `install.sh`, also reachable as `aims install`. Zero configuration, idempotent, safe
to run by any agent. The installer itself decides — deterministically, not by agent judgement:

| Step | Rule |
|---|---|
| Preflight | All conflict checks run before the first mutation. Only real blockers stop it: missing tools, unwritable paths, unresolved Git conflicts in a target file, or two different existing data repo candidates. |
| Engine | `~/aims` is restored to the official `origin/main` (the only place the installer resets or cleans) and `aims` is linked into `~/.local/bin`. |
| Data repo | Reuse the resolved existing repo; create `~/.aims` only when none exists. Record the path in `~/.config/aims/home`. Never touch its content. |
| Guard | Install or refresh the data repo `pre-push` hook. |
| Agent rules | Add or refresh one marked block with AIMS-only rules in each detected agent's real config file (symlinks resolved). User rules outside the block take precedence. Git-tracked targets are written and listed in the final report for integration via a branch and pull request. Existing user-written AIMS text is reported as a possible duplicate, not skipped. |
| Backups | Every modified file is copied under `~/.local/state/aims/backups/<UTC timestamp>/` with a manifest, outside every repository. |
| Report | Data repo used, files changed, tracked files needing a commit, backup location, `aims doctor`. |

`aims uninstall` reverses everything the installer owns (marked blocks, guard, command link, recorded
path) and keeps the data repo. `--fresh` replaces the data repo by moving the old one to
`<path>.aims-replaced-<UTC timestamp>`; it refuses while the old repo has uncommitted changes or
commits not on its `origin`. `aims init` remains in 3.x for compatibility (create or reuse a data repo
only) and is deprecated in favour of `aims install`; `bootstrap.sh` remains as a shim that runs
`install.sh`.

## Guards (why failures are loud)
| Risk | Guard |
|---|---|
| Uncommitted work destroyed on publish | `aims publish` refuses a dirty worktree |
| Local commits invisible to publish | `aims save` always pushes when ahead; publish refuses unpushed |
| "Empty" merge looks like success | publish warns + prints the full session diff |
| Two agents on one branch | local adopt requires `status=handoff`; `--remote` remains read-only |
| Valid overlapping scopes | required scope, atomically serialized admission with a second conflict check, explicit `WARN`, immutable active metadata; malformed scopes and transport/lease failures still block; lineage never exempts a child |
| Same-machine writers racing on one scope | a machine-local scope lock inside `aims start` itself (no caller cooperation required) narrows the admission race window before either writer reaches the git-level check |
| An unrelated orchestrator's subagent leaves an orphaned session | `aims start` stamps OS-observed hostname/ancestor-PID/heartbeat facts at creation; `aims conflicts` uses them only to *diagnose* a same-machine, dead-ancestor, zero-commit orphan and suggest `aims abandon --empty-only` — liveness is determined from the OS process start marker (not `kill -0`, which can return EPERM for a live protected process); never silently resolves the conflict |
| An orchestrator wants a delegated subprocess to never accidentally start a competing session | `aims delegate-exec` pre-registers the delegation durably before the child starts and propagates `AIMS_SESSION_ID` via its own `exec`, so the existing lifecycle guard blocks the child's own lifecycle commands — opt-in, and not required for the baseline guarantee above |
| Accidental push to main | `pre-push` hook blocks it |
| A second, silent data repo | the installer reuses the resolved existing repo and stops on ambiguity; `--fresh` moves the old repo aside and refuses while it holds unpushed work |
| Installer damaging user configuration | AIMS writes only inside its marked block, backs up every file outside all repositories, and `aims uninstall` reverts it |
