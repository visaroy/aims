# AIMS — rules for AI agents

You (the agent) manage your work sessions with AIMS. The user does NOT run AIMS commands and does not
need to learn them — YOU translate their intent into `aims` commands automatically. Recognize the
intent regardless of wording or language.

## Intent → command

## Delegated agents

If `AIMS_SESSION_ID` is set, you are a delegate inside that existing session. Do not run `aims start`, `save`, `handoff`, `publish`, `abandon`, or other lifecycle commands. Work only in the parent-provided scope; the orchestrator owns lifecycle, commits, and validation.

| When the user (in any words/language) wants to… | You run |
|---|---|
| begin work on a task | collect writable scope, then run `aims start <project> <topic> <you> --scope <csv>` and work only in the printed worktree |
| checkpoint / "save the session" | `aims save` |
| switch to another machine / "hand off the session" | `aims handoff [note]` |
| take over / "continue / adopt session X" | `aims adopt <session-id>`, then continue from ARTIFACTS |
| finish / "save and close the session" | finalize the session files, then `aims publish <session-id>` |
| see what is active | `aims list` |

Examples of intent (all map to the same commands regardless of phrasing or language):
"save and close the session", "wrap this up", "zapisz i zamknij sesję", "hand this off to the laptop",
"pick up session 2026…-foo" — infer the intent and run the matching `aims` command.

## Hard rules

- Work only inside the session worktree that `aims start`/`aims adopt` prints. Never edit files in the
  data repo root directly for session work.
- Never `git push` to `main` directly — only `aims publish` integrates a session (a hook enforces this).
- When adopting a session, continue from **artifacts** (worklog + commits), not from any previous
  agent's context. Read the session's `worklog.md` and its `environment` block first; if a code repo
  or toolchain is missing on this machine, say so before coding.
- Secrets: put only the variable NAME and location into sessions/commits/logs — never the value.
- Large files (build outputs, dumps, datasets) go to the shared store via `aims artifacts <session-id>`
  (if `AIMS_ARTIFACTS` is configured), not into git.

## Definitions the user may use

- "save the session" = `aims save` (checkpoint, keep working).
- "hand off / przekaż sesję" = `aims handoff` (push everything, mark it released; do NOT merge).
- "save and close / zapisz i zamknij sesję" = finalize artifacts + `aims publish` (merge to main, done).
