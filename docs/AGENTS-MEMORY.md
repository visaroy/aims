# Agent memory & consolidation across agents

Different agents (Claude Code, Codex, opencode, Gemini) each keep their own private memory and
transcript. AIMS does **not** merge those. Instead it consolidates the two things that actually need
to be shared — **rules** and **work** — on a substrate every agent already understands: files and git.

## Three layers

| Layer | Shared across agents? | Mechanism |
|---|---|---|
| **Rules** (how to behave, which commands) | ✅ yes | `aims wire-agents` writes one AIMS block into each agent's config file |
| **Work** (what was done: sessions, decisions) | ✅ yes | sessions live on `origin`; any agent runs `aims adopt` and continues from artifacts |
| **Live context** (an agent's reasoning/transcript) | ❌ no, by design | stays local & tool-specific — see [COMPARISON.md](COMPARISON.md) |

## 1. Consolidate rules — one source, every agent

`aims wire-agents` (run by every `aims install`, or manually anytime) writes an identical,
marker-delimited AIMS block into each detected agent's config (symlinks followed to the real file):

- `~/AGENTS.md` — opencode & Codex (project/home)
- `~/.codex/AGENTS.md` — Codex global
- `~/.claude/CLAUDE.md` — Claude Code
- `~/.gemini/GEMINI.md` — Gemini CLI

Every agent then maps the same natural-language intent to the same `aims` command. Re-running
refreshes the block in place; it is idempotent. Each modified file is backed up under
`~/.local/state/aims/backups/`, and `aims uninstall` removes the block again.

### Add your own rules alongside AIMS

The AIMS block is delimited by markers:

```
<!-- >>> AIMS agent rules >>> -->
...AIMS content (managed by aims wire-agents)...
<!-- <<< AIMS agent rules <<< -->
```

Put **your** project rules **outside** those markers (above or below). `aims wire-agents` only touches
what is between them, so your rules survive every refresh, and the block itself states that your rules
take precedence. If your own text already mentions AIMS, the installer reports it as a possible
duplicate and leaves it alone. This is how you consolidate *your own*
conventions across all agents too: write them once per file (or share a snippet) outside the block.

## 2. Consolidate work — git is the shared memory

The durable "what happened" lives in each session's `worklog.md` + commits on `origin`, not in any
agent's transcript. So:

- Any agent, on any machine, runs `aims adopt <session-id>` and continues **from artifacts**.
- Hand a session between agents/machines with `aims handoff` → `aims adopt`.
- Because the record is git, it outlives the agent that created it and is readable by every tool.

This is deliberate: an agent must leave a self-sufficient handover (worklog + commits), never rely on
its private context travelling. See [ARCHITECTURE.md](ARCHITECTURE.md).

## 3. What stays private (and why)

Each agent's live transcript/reasoning is local, tool-specific, and not synced. Trying to merge those
across tools is brittle (incompatible formats, machine-bound paths). AIMS keeps the shared memory in
the two places that are portable — rules (files) and work (git) — and leaves the rest local.

## TL;DR

- **Same rules everywhere** → `aims wire-agents`.
- **Same work everywhere** → sessions on `origin`, `aims adopt`.
- **Private context** → stays with each agent, on purpose.
