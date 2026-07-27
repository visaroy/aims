# AIMS and Agent Toolkit session handoff

## Scope

This comparison evaluates the `session-handoff` skill in [Softaworks Agent Toolkit](https://github.com/softaworks/agent-toolkit/tree/main/skills/session-handoff) against AIMS `v0.6.0`.

Source reviewed: `softaworks/agent-toolkit` commit `3027f20f3181758385a1bb8c022d4041dfb4de84` on 2026-07-27.

## Executive summary

The Agent Toolkit skill provides a strong documentation-oriented handoff workflow. AIMS already solves the harder transport and coordination problem: preserving complete work in Git, transferring it through `origin`, and safely adopting it on another host or with another agent.

AIMS should borrow the skill's handoff-readiness and context-quality ideas, but retain its Git-native, agent-neutral architecture. It should not adopt a Claude-specific storage directory or rely on a heuristic quality score as a release gate.

## Comparison

| Area | Agent Toolkit `session-handoff` | AIMS | Assessment |
|---|---|---|---|
| Primary artifact | Timestamped Markdown under `.claude/handoffs/` | `ai/<session-id>` branch plus `metadata.json`, worklog, commands, tests, prompts, and final summary | AIMS has a more durable, agent-neutral artifact model. |
| Creation | Python scaffold captures time, path, branch, recent commits, modified files, and optional predecessor | `aims start` creates an isolated worktree and session metadata, then pushes the branch | AIMS has stronger Git and isolation guarantees. |
| Transfer | The document must be available in the project checkout; no remote transfer protocol | `aims handoff` commits, scans, pushes, and marks the session as released; `aims adopt` fetches it from `origin` | AIMS is designed for cross-host and cross-agent transfer. |
| Concurrency | Manual process only | Adoption warns about a recently updated active branch; `status=handoff` explicitly releases the source writer | AIMS provides an explicit two-writer safety guard. |
| Environment | Free-form Markdown section | Structured `environment` metadata plus toolchain probing and host recommendation during adoption | AIMS can verify more of the target environment. |
| Secret handling | Regex scan of the handoff Markdown | Secret scan before checkpoints and handoffs, including tracked and untracked non-ignored files | AIMS has broader repository-level protection. |
| Content validation | Checks TODO markers, required sections, referenced files, potential secrets, and a 0-100 score | Validates session identity, worktree, branch, metadata, origin, and secret safety; it does not assess handoff narrative completeness | The skill contributes useful quality checks. |
| Staleness | Uses age, commits, changed files, branch mismatch, and missing references | `aims list` reports age; `aims adopt` detects a possible live writer | The skill contributes useful resume diagnostics. |
| Lineage | Markdown links through `Continues from` and `Supersedes` | Git commit history preserves one session lifecycle; separate sessions have no explicit continuation field | Explicit cross-session lineage is a possible future enhancement. |

## Useful ideas to adopt

### Handoff readiness report

Add a non-mutating command such as:

```bash
aims handoff check <session-id>
```

It should report whether the session has valid metadata and required artifacts, a complete environment declaration when relevant, a concrete next action or blocker, unresolved placeholders, a clean secret scan, and a branch/worktree/origin state that is safe to hand off.

Initially, this should be advisory. AIMS supports infrastructure, research, documentation, and code sessions, so a generic numeric quality threshold would be too rigid.

### Git-native delta report during adoption

Extend `aims adopt` to show a concise report covering the last handoff time, commits since the handoff boundary, changed paths, current source branch state, and the latest session author or host.

The report should use Git ancestry and diffs rather than time alone. A possible metadata field is `handoff_base_commit`, recorded before the handoff commit and used as the base for later change reporting.

### Optional concise handoff brief

Add an optional artifact at:

```text
sessions/work/<session-id>/handoff.md
```

AIMS should keep the existing worklog as a chronological record. The optional brief should be a compact resume map with current state, decisions and rationale, immediate next action, blockers, critical files or repositories, environment and verification state, and known risks.

### Explicit cross-session continuation

For new sessions that genuinely continue a completed or paused session, an optional `continues_from` field in `metadata.json` could provide discoverable lineage. It is not needed for the normal `handoff` to `adopt` path because that remains one session branch.

### Session-list filters

Consider filters such as:

```bash
aims list --handoff
aims list --stale
aims list --project <project>
```

These would provide the discoverability benefit of the toolkit's handoff listing without changing the AIMS storage model.

## Ideas not to adopt directly

- Do not store AIMS handoffs under `.claude/handoffs/`; AIMS supports multiple agents and must remain agent-neutral.
- Do not make a 0-100 documentation score a mandatory handoff gate; it is heuristic and easy to optimize superficially.
- Do not treat missing source-code paths on the target host as an automatic handoff failure. Cross-host adoption may intentionally require remote mode or environment preparation.
- Do not use elapsed time as the principal staleness signal when Git ancestry, branch divergence, and changed paths are available.
- Do not replace AIMS secret scanning with document-only regex checks.

## Recommended implementation order

1. Add advisory `aims handoff check <session-id>` with portable Bash tests.
2. Add Git-native post-handoff delta reporting to `aims adopt`.
3. Add an optional English `handoff.md` template under the existing session artifact directory.
4. Evaluate `continues_from` metadata and `aims list` filters after the first three changes are used in real sessions.
