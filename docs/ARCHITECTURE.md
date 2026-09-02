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
| Two agents on one branch | adopt warns on recent activity; handoff marks release |
| Two delegated writers in one scope | parented children reject every overlap; an overlapping sibling additionally returns its reusable child session ID |
| Accidental push to main | `pre-push` hook blocks it |
