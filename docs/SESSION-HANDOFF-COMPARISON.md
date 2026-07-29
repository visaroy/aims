# AIMS and Agent Toolkit session handoff

## Scope

This comparison evaluates the `session-handoff` skill in [Softaworks Agent Toolkit](https://github.com/softaworks/agent-toolkit/tree/main/skills/session-handoff) against the current AIMS 0.7.0 implementation.

Sources reviewed:

- `softaworks/agent-toolkit` commit `3027f20f3181758385a1bb8c022d4041dfb4de84` on 2026-07-27.
- AIMS base commit `802a0434129ee372c68f2934e4dfdf23321124cf` plus the implementation changes documented in this comparison, reviewed together on 2026-07-28.

## Executive summary

The Agent Toolkit skill creates a structured Markdown handoff for a Claude-oriented workflow. AIMS manages the work itself: commits, metadata, worklog, optional brief, and session state move through a Git remote and can be adopted by a different agent on a different host.

AIMS does not transfer an agent's private transcript or hidden reasoning. It transfers explicit artifacts that another agent can inspect and verify.

The previous version of this document listed readiness checks, adoption deltas, concise briefs, continuation metadata, and list filters as proposed work. AIMS 0.7.0 now implements all five.

## Current comparison

| Area | Agent Toolkit `session-handoff` | AIMS 0.7.0 | Assessment |
|---|---|---|---|
| Primary artifact | Timestamped Markdown under `.claude/handoffs/` | `ai/<session-id>` branch plus metadata, worklog, commands, tests, prompts, final summary, and optional `handoff.md` | AIMS stores a complete, agent-neutral work record. |
| Creation | Python scaffold captures time, path, branch, recent commits, modified files, and optional predecessor | `aims start` creates an isolated worktree, structured metadata, and a remote session branch; `--continues-from` records explicit lineage | Both capture context; AIMS also creates an isolated unit of work. |
| Transfer | The handoff document must be present in the project checkout | `aims handoff` commits and pushes the complete worktree, records a Git boundary, and marks the writer as released | AIMS provides a remote transport and ownership transition. |
| Adoption | A person or Claude reads the handoff document | `aims adopt` fetches from `origin`, probes the declared environment, reports the Git delta since handoff, and creates or verifies the exact session worktree | AIMS supports different agents and hosts without copying local transcripts. |
| Concurrency | Manual process | Exact-OID leases, publication sentinels, rewrite markers, live-writer warnings, and deleted-branch guards preserve competing work | AIMS has stronger machine-enforced coordination. |
| Rebase recovery | Outside the skill's scope | `aims rebase` rebases a synchronized session onto `origin/main`; `aims save` publishes the rewrite only when the captured remote OID still matches | AIMS handles a common multi-session integration failure explicitly. |
| Readiness | Validates document sections, TODO markers, references, potential secrets, and a heuristic score | `aims handoff check` validates session identity, branch/worktree/origin state, metadata, secret safety, worklog guidance, and relevant environment fields | AIMS uses an advisory pass/warning/block model instead of a generic numeric score. |
| Concise resume map | The handoff document is the main artifact | `aims brief <session-id>` creates an optional `handoff.md` while preserving the chronological worklog | AIMS supports both a durable log and a short resume map. |
| Environment | Free-form Markdown | Structured `environment` metadata plus toolchain probes and local/remote recommendations during adoption | AIMS can verify target-host prerequisites. |
| Secret handling | Regex scan of handoff Markdown | Repository scan before readiness checks and checkpoints, including tracked and untracked non-ignored files | AIMS checks a broader surface. |
| Staleness and discovery | Age, commits, changed files, branch mismatch, missing references | `aims list` reports age and scope; `--handoff`, `--stale`, and `--project` filter remote sessions | Both help discovery; AIMS queries the shared Git source of truth. |
| Lineage | Markdown `Continues from` and `Supersedes` links | `aims start --continues-from <session-id>` writes structured continuation metadata | AIMS now exposes cross-session lineage without changing normal handoff/adopt semantics. |

## Features added since the previous comparison

### Advisory readiness check

```bash
aims handoff check <session-id>
```

The command is non-mutating. It blocks invalid session identity, branch/worktree/origin errors, unreadable metadata, and detected secrets. Missing next actions or relevant environment fields produce warnings rather than an arbitrary score.

### Git-native adoption delta

`aims handoff` records `handoff_base_commit`. During adoption, AIMS reports the comparison boundary, commits since that boundary, and changed paths. The report uses Git ancestry rather than elapsed time alone.

### Optional handoff brief

```bash
aims brief <session-id>
```

The command creates `sessions/work/<session-id>/handoff.md` from an English template and refuses to overwrite an existing brief.

### Explicit continuation metadata

```bash
aims start <project> <topic> <agent> --continues-from <session-id>
```

This records a relationship between separate sessions. A normal handoff and adoption remain one session branch and do not need a continuation link.

### Session-list filters

```bash
aims list --handoff
aims list --stale
aims list --project <project>
```

The filters can be combined and operate on remote `ai/*` branches.

## Design choices AIMS retains

- AIMS does not store handoffs under `.claude/`; the artifact format must work with Claude Code, Codex, opencode, Gemini, and future agents.
- AIMS does not use a mandatory 0-100 narrative score. Infrastructure, research, documentation, and code sessions need different evidence.
- Missing source paths on the adopting host are reported, not treated as automatic failure. The agent can prepare the host or use remote mode.
- Git ancestry and exact remote OIDs determine safety. Time is only a live-writer warning and staleness signal.
- The optional brief supplements the worklog and commits. It does not replace them.

## Remaining differences

The Agent Toolkit skill performs deeper prose-oriented checks within one handoff document, including placeholder and reference quality. AIMS checks operational readiness and repository safety, but its brief template remains intentionally lightweight. Teams that require stricter narrative fields can add project-specific checks without weakening AIMS's Git guards or agent-neutral storage model.
