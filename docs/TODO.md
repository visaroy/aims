# AIMS TODO

This roadmap is intentionally limited to proposals that strengthen AIMS session transfer without changing its Git-native, agent-neutral design.

## Handoff quality and adoption diagnostics

### P1: Advisory handoff readiness check

- [x] Add `aims handoff check <session-id>`.
- [x] Verify session ID, matching `ai/<session-id>` branch, worktree, metadata, and `origin` availability.
- [x] Run the existing secret scanner without changing session state.
- [ ] Report missing session artifacts and unresolved placeholders as warnings.
- [x] Report whether a coding session has a useful `environment` declaration: repositories, toolchain, setup, and test instructions.
- [x] Report whether a concrete next action or blocker is present.
- [ ] Add Bash tests for valid, incomplete, mismatched, and secret-blocked sessions on GNU/Linux and macOS Bash 3.2.

### P1: Git-native adoption delta report

- [x] Record a stable handoff comparison boundary in session metadata.
- [x] Extend `aims adopt` to report commits and changed paths since that boundary.
- [ ] Include latest branch update, current handoff status, and source author or host where available.
- [x] Keep Git ancestry and branch divergence as the source of truth; time-based age is supplementary only.
- [ ] Add tests for no changes, later changes, and divergent branch states.

### P2: Optional concise handoff brief

- [x] Provide an English template for `sessions/work/<session-id>/handoff.md`.
- [x] Include current state, decisions and rationale, immediate next action, blockers, critical files or repositories, environment, verification, and risks.
- [x] Keep `worklog.md` as the chronological record; do not duplicate it mechanically.
- [ ] Keep the brief optional and validate it advisory-first.

### P3: Cross-session continuity and discovery

- [x] Evaluate optional `continues_from` metadata for a new session that continues another session.
- [x] Add `aims list --handoff`, `aims list --stale`, and `aims list --project <project>` if real session volume justifies them.
- [x] Preserve the normal `aims handoff` to `aims adopt` path as a continuation of the same branch, not a new linked session.

## Non-goals

- [ ] Do not add Claude-specific `.claude/handoffs/` storage.
- [ ] Do not require a generic numeric documentation score before handoff.
- [ ] Do not replace repository-level secret scanning with document-only regex checks.
- [ ] Do not treat a missing local code checkout on an adopting host as an automatic failure; remote mode and environment preparation remain valid paths.

## Related documentation

- [Session handoff comparison](SESSION-HANDOFF-COMPARISON.md)
- [AIMS architecture](ARCHITECTURE.md)
- [AIMS commands](COMMANDS.md)
