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
user rather than inferring permission from session opt-in.

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
- **Data repo** (private, per-user): `AIMS_HOME` (default `~/.aims`) — sessions, `SESSIONS.md`,
  project state, `credentials/` (gitignored). Created by `aims init`.

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
