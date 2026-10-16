# AIMS — AI Session Management System

**Author**: The AIMS authors · **Version**: 2026-07-17 · **Repo**: `<your-data-repo-url>`

The canonical AIMS documentation. The operating rules (enforced by agents) live in `AI.md`
(Rule #5, #16–#21). This file explains **how the system works as a whole**.

A Polish translation is available in [`docs/i18n/pl/AIMS.md`](i18n/pl/AIMS.md).

---

## 1. What AIMS is and why

A system for many AI agents (claude / codex / opencode / gemini) working on many machines (macOS, Linux),
where **every unit of work = a git branch** (`ai/<session-id>`) in an isolated worktree. The goal:
parallel work without conflicts, full history, portability between machines and agents, and
recoverability after a failure.

**Source of truth: `origin` (GitHub).** Machines do not connect to each other — each one only
**pushes/pulls to origin**. That is why "nobody can reach the Mac" is NOT a problem: the Mac pushes to
GitHub and the other machines pull from there. A session does not live "on machine X" — it lives on
origin; a machine is only the place of the last push.

## 2. Two layers — a fundamental distinction

| Layer | What it is | Where | Portable? |
|---|---|---|---|
| **Work** | branch `ai/<sid>`, worktree, session files, worklog, commits | origin (git) | ✅ YES — any machine, any agent |
| **Agent context** | transcript/reasoning (e.g. `~/.claude/…jsonl`) | local, `.gitignore` | ❌ NO — not portable, harness-specific |

**Consequence**: when you take over a session, you continue from the **ARTIFACTS** (worklog + commits +
plan), NEVER from the previous agent's head. That is why commits and the worklog must be a
self-sufficient handover. `claude --resume` restores the context layer, but it is a Claude Code feature,
NOT an AIMS mechanism (it does not work for codex/opencode/gemini and is tied to one machine).

## 3. Session lifecycle

```
                    aims start <project> <topic> <agent> --scope repo:project,path:src
                              │  (creates branch ai/<sid> + worktree from origin/main)
                              ▼
        ┌──────────────  WORK in the worktree  ──────────┐
        │  aims save  = checkpoint session files + push  │  (may be repeated)
        └──────────────────────┬─────────────────────────┘
                               │
          ┌────────────────────┼─────────────────────────┐
          ▼                    ▼                          ▼
   aims handoff         aims publish              (abandon)
   "hand to a machine"  "close, merge to main"    delete the branch
   status=handoff       registry sNNN=done        without merging
   push EVERYTHING      branch deleted from origin
          │
          ▼
   on the SECOND machine:  aims adopt <sid>
   (fetch from origin, worktree from the existing branch, continue)
```

## 4. Commands

| Command | Where to run it | What it does |
|---|---|---|
| `aims start <project> <topic> [agent] --scope <csv>` | `$AIMS_HOME` | New session with a mandatory scope; detected valid overlaps produce a warning but do not block, while a malformed scope and origin/Git/lease errors still block. |
| `aims save` | in the worktree | Checkpoint: `git add -A` (the WHOLE session worktree — STATE.md, session-*.md, code, artifacts) + commit + **push when ahead of origin**. Since the 2026-07-18 fix it no longer loses project files. |
| `aims handoff [note]` | in the worktree | **Hand over to another machine** (a USER command). `git add -A` (EVERYTHING), commit, push, `status=handoff`. Does NOT merge to main. |
| `aims handoff <sid>` | `$AIMS_HOME/.worktrees/` | Hands over one named local session without a manual `cd` into its directory. Validates that the worktree, branch `ai/<sid>`, and metadata agree, then performs the normal handoff. |
| `aims handoff-all [--yes]` | `$AIMS_HOME` | Hands over every valid local worktree. By default it asks you to type `HANDOFF`; `--yes` is for deliberate automation. Does NOT merge, does not remove worktrees, and does not force-push. |
| `aims checkpoint <sid>\|--all` | `$AIMS_HOME` | Safe checkpoint: secret scan, commit, and push without changing the session status. Intended as an explicit target for a user-level systemd timer or LaunchAgent, without installing such a service by itself. |
| `aims adopt <sid> [--remote]` | `$AIMS_HOME` (any machine) | Take over from origin: environment report + guards, worktree from the existing branch, ADOPTED entry. `--remote` = report only. |
| `aims publish <sid>` | `$AIMS_HOME` | Closure: merge branch → main, registry entry `sNNN`, delete the branch from origin. Works regardless of which agent started it. |
| `aims list` | `$AIMS_HOME` | Active `ai/*` branches with age, scope, and a STALE flag (>48h). |

## 5. The `environment` block — handing over the working environment

Every session's `metadata.json` contains `environment`. A session that touches code (not pure analysis)
MUST fill it in — it is the only way for the adopting agent to know what it needs before it starts
coding:

```json
"environment": {
  "code_repos": ["~/code/your-project"],  // code repos, USUALLY different from $AIMS_HOME
  "toolchain":  [],                                            // only tools needed LOCALLY
  "exec_host":  "",                                            // host where the environment lives; empty = portable
  "setup":      "git pull",                                    // preparation
  "test":       "CI: GitHub Actions (PR)"                      // "local: <cmd>" OR "CI: ..."
}
```

**The `test: local` vs `CI` distinction is critical.** A session may NOT have the toolchain locally
because it verifies through CI (a real case: Flutter code edited on a host without Flutter, builds green
in GitHub Actions). `aims adopt` reads this block, probes the current host (`command -v`), and
recommends local adoption vs remote (`--remote`) vs installing the missing tools.

## 6. Guards and safety

- **Live writer** (`aims adopt`): local adoption requires `status=handoff`; a valid overlap is only a
  diagnostic warning; after adoption AIMS atomically restores `status=active`, so a second local adopter
  is rejected. `--remote` remains read-only.
- **The origin boundary** (`aims adopt`): the report states plainly that it shows the PUSHED state —
  unpushed work on the source machine is not visible. Hence, before switching machines: `aims handoff`
  (push everything).
- **Refusal** (`aims adopt`): a merged/deleted session → there is nothing to adopt.
- **Push to `main` blocked** by the `pre-push` hook — only through `aims publish`.
- **`restore.sh` NEVER from a worktree** — only from the canonical `$AIMS_HOME` (running it from a
  worktree destroyed `$AIMS_HOME` on 2026-07-15).
- **NEVER copy `$AIMS_HOME`** between machines — only `git clone` + `restore.sh` (a copy = another
  machine's paths + silent drift).
- **Secrets**: put the variable NAME and its location into a session, NEVER the value (Rule #20).
  Secrets live in `$AIMS_HOME/credentials/*.env` (gitignored). `validate-no-secrets.sh` also scans `.md`.

## 7. Rules in AI.md (map)

| Rule | Topic |
|---|---|
| #5 | Session Protocol — start/save/publish, worktree isolation, scope conflicts |
| #16 | Documentation immediately after a change (inline: what, why, logic) |
| #17 | Tests before closing a session (unit + integration + manual acceptance) |
| #18 | Terminology: "documentation" vs "save the session" vs "save and close" — + "hand over the session" (handoff) |
| #19 | Code and repo conventions (build/lint/test, branches, naming) |
| #20 | Secrets — the name, not the value; the scanner sees `.md` |
| #21 | Adopting/continuing someone else's session — `aims adopt`; environment analysis; artifacts, not context |

## 8. Agent wiring (who reads the rules from where)

All 4 agents resolve their rules to a single `AI.md` (through `restore.sh`):

| Agent | Entry point | Mechanism |
|---|---|---|
| claude | `~/.claude/CLAUDE.md` → `../AI.md` | symlink |
| gemini | `~/.gemini/GEMINI.md` → `../AI.md` | symlink |
| codex | `~/.codex/AGENTS.md` → `AI.md` | global symlink (NOT `~/AGENTS.md` — codex does not look above the project root) |
| opencode | `~/.claude/CLAUDE.md` (fallback) + `instructions:[~/AGENTS.md, ~/.claude/CLAUDE.md]` | config + fallback |

`doctor.sh` verifies that every entry point actually resolves to `AI.md` (realpath).
