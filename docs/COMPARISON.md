# AIMS vs. per-tool session resume

AI coding CLIs each ship their own "resume the conversation" feature. They all solve the **same
layer** — an agent's local transcript — and in the **same way**: a per-machine file, namespaced by
the project directory, specific to that one tool. None of them move *work* between machines or between
different agents. That is the gap AIMS fills.

> Details below are accurate as of mid-2026 and evolve per version — treat them as the shape of each
> mechanism, not a frozen spec. Sources are linked at the bottom.

## The two layers, again

- **Agent context** — the running conversation/reasoning transcript. Local, tool-specific, not synced.
- **Work** — branches, commits, session artifacts. In AIMS this lives on a git remote and is portable.

"Resume" features operate on the **context** layer. AIMS operates on the **work** layer. They are
complementary, not competing.

## How each tool persists and resumes a session

| Tool | Where the transcript lives | Resume | Namespacing | Cross-machine | Cross-tool |
|---|---|---|---|---|---|
| **Claude Code** | `~/.claude/projects/<cwd-hash>/<uuid>.jsonl` | `claude --resume` / `--continue`; `--fork-session` | by working directory | ❌ not synced | ❌ Claude only |
| **OpenAI Codex CLI** | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (+ SQLite index) | `codex resume --last` / `codex resume <id>`; forking | by session id | ❌ not synced | ❌ Codex only |
| **opencode** | `~/.local/share/opencode/storage/session/<projectHash>/<id>.json` (+ messages) | continue/select session; `opencode share` → web link; `OPENCODE_DATA_DIR` configurable | by project hash | ⚠️ only if `OPENCODE_DATA_DIR` points at shared storage | ❌ opencode only |
| **Gemini CLI** | `~/.gemini/tmp/<project_hash>/chats/` (+ `checkpoints/`) | `gemini --resume`; `/chat save|list|resume|delete <tag>` | by project hash | ❌ not synced (30-day retention) | ❌ Gemini only |
| **Aider** | `.aider.chat.history.md` in the repo | `--restore-chat-history` replays it; auto-commits edits to git | by repo | ⚠️ travels *with the git repo* (history file is in-tree) | ❌ Aider only |

### What this table says

1. **Every tool stores the transcript as a local file keyed to the project path.** Move to another
   machine with a different home/path and the namespace no longer matches — the resume can't find it.
2. **Nothing is synced by default.** `~/.claude`, `~/.codex`, `~/.gemini`, `opencode`'s data dir are
   all machine-local (and typically gitignored). The context does not travel.
3. **Resume is tool-locked.** A Codex rollout means nothing to Gemini; a Claude `.jsonl` means nothing
   to opencode. Each format is private to its tool.
4. **Two partial exceptions prove the rule.** opencode can point `OPENCODE_DATA_DIR` at shared storage
   (so a second machine *could* read the same sessions), and Aider keeps its history file *inside the
   git repo* (so it rides along with a clone). Both move the transcript by putting it on a shared
   substrate — which is exactly AIMS's idea, applied to the *work* instead of the chat log.

## Where AIMS fits

AIMS deliberately does **not** persist agent context. It persists the **work** as a git branch on
`origin`, so it is portable in the two dimensions the per-tool resumers are not:

| | `claude --resume` | `aims adopt` |
|---|---|---|
| What it moves | ✅ full agent context | ✅ work artifacts (git) |
| Scope | ⚠️ same machine, Claude only | ✅ any machine, any agent |
| Medium | ⚠️ local `.jsonl` (not synced) | ✅ branch on `origin` |
| codex / opencode / gemini | ❌ N/A | ✅ works |

(`claude --resume` stands in for every tool's native resume — `codex resume`, `gemini --resume`,
opencode's session continue — they share the same shape.)

## Practical guidance

- **Same tool, same machine:** use that tool's native resume. `claude --resume` (or `codex resume`,
  `gemini --resume`) gives you the full prior context for free — cheaper than re-deriving from artifacts.
- **Another machine, or a different agent picks it up:** use `aims handoff` → `aims adopt`. The context
  won't transfer (that's a tool-local file), so you continue from the worklog and commits — which is
  why AIMS requires sessions to leave a self-sufficient handover.
- **Best of both:** on one machine, an agent can resume its own context *and* keep the work in AIMS, so
  a teammate or a different tool on another machine can still pick up the thread from git.

The one-line summary: **per-tool resume moves a conversation within one tool on one machine; AIMS moves
the work across machines and across tools.**

## Sources

- Claude Code — resume/continue and transcript storage (Anthropic docs).
- [Codex CLI: resume and fork commands](https://github.com/openai/codex/blob/main/codex-rs/cli/src/main.rs) · [thread persistence](https://github.com/openai/codex/tree/main/codex-rs/thread-store/src/local) · [resume how-to](https://inventivehq.com/knowledge-base/openai/how-to-resume-sessions)
- [opencode: database layer](https://github.com/anomalyco/opencode/tree/dev/packages/core/src/database) · [session and file storage](https://github.com/anomalyco/opencode/blob/dev/packages/opencode/src/storage/storage.ts)
- [Gemini CLI: session management](https://geminicli.com/docs/cli/session-management/) · [checkpointing](https://geminicli.com/docs/cli/checkpointing/)
- Aider — chat history & git integration (Aider docs).
