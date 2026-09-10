# AIMS architecture

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
| Two writers in one scope | required scope, atomically serialized admission with a second conflict check, immutable active metadata; lineage never exempts a child |
| Same-machine writers racing on one scope | a machine-local scope lock inside `aims start` itself (no caller cooperation required) narrows the admission race window before either writer reaches the git-level check |
| An unrelated orchestrator's subagent leaves an orphaned session | `aims start` stamps OS-observed hostname/ancestor-PID/heartbeat facts at creation; `aims conflicts` uses them only to *diagnose* a same-machine, dead-ancestor, zero-commit orphan and suggest `aims abandon --empty-only` — never to silently resolve the conflict |
| An orchestrator wants a delegated subprocess to never accidentally start a competing session | `aims delegate-exec` pre-registers the delegation durably before the child starts and propagates `AIMS_SESSION_ID` via its own `exec`, so the existing lifecycle guard blocks the child's own lifecycle commands — opt-in, and not required for the baseline guarantee above |
| Accidental push to main | `pre-push` hook blocks it |
