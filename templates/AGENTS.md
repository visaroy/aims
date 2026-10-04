# AIMS — rules for AI agents

You (the agent) may manage the current work session with AIMS after the user explicitly opts the
current task into AIMS. A clear marker naming AIMS at the beginning, middle, or end — for example,
“This is an AIMS session”, “Use AIMS”, or “Save the AIMS session” — is sufficient session-scoped
consent. The user does not need to learn command syntax, and the agent may use the normal AIMS
lifecycle without separate consent for each operation. “Save and close the AIMS session” explicitly
authorizes final publication; session opt-in alone does not imply closure.

Mere discussion or documentation of AIMS, ordinary coding, or a new conversation is not consent.
Without a current-task marker, use native agent mechanisms and do not invoke AIMS. Do not install,
update, or repair the engine from session opt-in; engine changes require separate explicit permission,
and an absent engine requires asking the user.

AIMS is a caller-triggered CLI with no daemon and no implicit session creation. This instruction file
may call the CLI after current-task opt-in, but command behavior remains caller-triggered. An
externally configured scheduler is a separate opt-in integration and must not be configured or started
automatically.

## Explicit AIMS session → command

## Delegated agents

If `AIMS_SESSION_ID` is set, you are a delegate inside that existing session. Do not run `aims start`, `save`, `handoff`, `publish`, `abandon`, or other lifecycle commands. Work only in the parent-provided scope; the orchestrator owns lifecycle, commits, and validation.

## Delegating work to a subagent/subprocess

If the user has opted the current task into an AIMS session and you spawn a subagent, subprocess, or a separately invoked coding CLI to work on the same task/scope you already own, prefer `aims delegate-exec <your-session-id> -- <command...>` over invoking it directly. It guarantees the delegate inherits your session context (so it cannot accidentally start a competing session for the same scope) and durably records the delegation before the subprocess even starts, so an abruptly killed delegate still leaves a visible record for you to reconcile. If your host environment cannot invoke `aims delegate-exec` directly, AIMS still protects you: a machine-local admission lock and the existing scope-conflict check serialize admission, then warn and proceed for a valid overlap; malformed scopes and transport/lease failures remain blocking.

Once the user has explicitly opted the current task into an AIMS session, use this table for its
normal lifecycle. This session-scoped consent does not authorize engine installation, update, or
repair; those require separate explicit permission.

| During the opted-in AIMS session, when the user wants to… | You run |
|---|---|
| start the AIMS session for the task | collect writable scope, then run `aims start <project> <topic> <you> --scope <csv>` and work only in the printed worktree |
| checkpoint / save the AIMS session | `aims save` |
| hand off the AIMS session to another machine | `aims handoff [note]` |
| adopt AIMS session X | `aims adopt <session-id>`, then continue from ARTIFACTS |
| save and close the AIMS session X | finalize the session files, then `aims publish <session-id>` |
| install or update the AIMS engine | follow the documented installation or update procedure only for that request |
| see which AIMS sessions are active | `aims list` |

Examples of current-task opt-in markers:
"This is an AIMS session for the login bug", "Use AIMS for this task", "Save the AIMS session" —
use the normal lifecycle for this task. To finish, the user must explicitly say "save and close the
AIMS session". Do not turn a mere AIMS mention, documentation request, ordinary coding request, or
new conversation into an invocation.

## Hard rules

- Work only inside the session worktree that `aims start`/`aims adopt` prints. Never edit files in the
  data repo root directly for session work.
- Do not invoke AIMS without a clear current-task AIMS marker. Session opt-in covers the normal
  lifecycle, but engine installation/update/repair and external scheduler configuration/start remain
  separate explicit permissions.
- Inside an opted-in AIMS session, never `git push` to `main` directly — use `aims publish` only
  after the user requests closure/publication. For no-AIMS work, follow the target repository's
  normal branch/PR workflow; do not invoke AIMS or edit this data repo unless explicitly requested.
- A valid scope overlap reported by `aims start` or handed-off `aims adopt` is advisory: read the `WARN`
  and continue. Stop only for malformed scope metadata, origin/Git/lease failures, or a non-handoff
  local adoption refusal.
- When adopting a session, continue from **artifacts** (worklog + commits), not from any previous
  agent's context. Read the session's `worklog.md` and its `environment` block first; if a code repo
  or toolchain is missing on this machine, say so before coding.
- Secrets: put only the variable NAME and location into sessions/commits/logs — never the value.
- Large files (build outputs, dumps, datasets) go to the shared store via `aims artifacts <session-id>`
  (if `AIMS_ARTIFACTS` is configured), not into git.

## Definitions within an opted-in AIMS session

- "save the AIMS session" = `aims save` (checkpoint, keep working).
- "hand off the AIMS session" = `aims handoff` (push everything, mark it released; do NOT merge).
- "save and close the AIMS session" = finalize artifacts + `aims publish` (merge to main, done).
