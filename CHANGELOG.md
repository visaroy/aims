# Changelog

## 1.1.0 — 2026-07-30
- Published sessions are now first-class discoverable records: `aims status <id>` distinguishes active, published, and unknown IDs; `aims adopt <published-id>` explains the closed state instead of incorrectly claiming an invalid ID.
- Added `aims continue <published-id> <topic>` to start a linked session from current `origin/main`, and `aims list --closed` to discover published session records without retaining stale work branches.
- `aims publish` marks metadata as `published`, preserves committed artifacts in main, and removes a verified merged local session branch so local Git history no longer contradicts `aims list`.
- Added `aims conflicts --scope` with deterministic exact and path-prefix overlap diagnostics for active remote sessions.
- Added a disposable lifecycle regression covering publication, status, friendly adoption, continuation, closed listing, local-branch cleanup, and scope diagnostics.

## 1.0.0 — 2026-07-30
- Promoted the independently tested `1.0` release to stable. The SHA-256 lease regression now skips only when the installed Git cannot clone or push SHA-256 repositories, while standard lifecycle coverage remains mandatory.
- Added an exact 30-second, reproducible agent-centric handoff demo and a tracked disposable under-3-minute acceptance test covering the complete session lifecycle.
- Added GitHub Actions quality, Ubuntu lifecycle, macOS Bash 3.2, and external-link jobs with a real status badge in the README.
- Added a public CLI contract test; documented commands now reject unknown flags and surplus arguments with exit status 2 before mutation.
- The installer-update regression now initializes a standalone temporary engine repository, so detached or shallow CI checkouts cannot affect it.
- `aims handoff-all` now canonicalizes `AIMS_HOME` before comparing Git worktree paths, including macOS `TMPDIR` and symlink-style inputs.
- `aims save` and direct `aims handoff` now reject tracked or untracked secret patterns before staging, metadata changes, commits, or pushes.
- Fixed `aims adopt` ancestry checks when the command is run outside the data repository by evaluating OIDs in the explicit repository/worktree.
- Updated the handoff comparison to current AIMS behavior, split agent and human tester responsibilities, and added public documentation privacy and local-link guards; allowed placeholders can no longer suppress real PII on the same line.
- Secret placeholder filtering is now per match, so a real credential beside an allowed placeholder is still rejected.
- Added a structured GitHub issue form for sanitized tester feedback; repository topics and the `tester-feedback` label now improve discovery and triage.
- Hardened tester onboarding after independent review: the acceptance test isolates `HOME`, XDG, and Git configuration; the public issue form now routes vulnerabilities to enabled private security advisories and collects more reproducible diagnostics.
- Added `aims rebase <session-id>` for clean, synchronized recovery from a publish merge conflict.
- `aims save` now protects rewritten session branches with a private exact-OID marker and
  `--force-with-lease`; unmarked divergence, remote advances, and deleted branches fail safely.
- Publish errors now distinguish session merge conflicts from main-push races and explain the safe
  merge alternative when a remote rejects rewritten-session force pushes.
- `aims save` now persists a local publication sentinel across tracking-ref pruning and refuses to
  recreate a previously published remote branch that was deleted.
- Force-push policy recovery is now executable: reset to the captured rewrite OID, merge `origin/main`,
  and save with an ordinary fast-forward push.
- Non-resumable pre-rebase startup failures now clear an unchanged rewrite marker with compare-and-swap,
  while active conflicts retain it for continue/abort recovery.
- Publication sentinels now share one lifecycle helper and are seeded by start, save, rebase, handoff,
  and adopt; adopt checkpoint push failures are fatal and retain the worktree.
- No-force recovery now saves rebased `HEAD` in a recovery ref and merges it back after resetting to
  the original remote tip, preserving unique resolved work.
- Existing session updates in save, handoff, and adopt now use exact observed-OID leases; initial branch
  creation asserts absence and uses a zero-OID lease, preventing deletion/recreation races.
- No-force recovery now preserves actual conflict resolutions in a tree-preserving merge and retains
  the recovery ref until ordinary save succeeds.
- Handoff and adopt now refuse pre-existing remote divergence when the fetched tip is not an ancestor
  of local `HEAD`; the harness covers both pre-fetch competing-writer cases.
- Adopt now requires the reused or created worktree to be exactly on `ai/<sid>` and checks the observed
  remote OID against that exact local branch/`HEAD`; stale local branches and wrong worktrees are covered.
- Added a portable two-clone shell integration harness for normal saves, managed rewrites, conflicts,
  competing writers, and failure guardrails.

## 0.7.0 — 2026-07-28
- Added advisory, non-mutating `aims handoff check <session-id>` readiness checks that keep transport blockers separate from contextual warnings.
- Added Git-native handoff delta reporting during adoption, optional concise handoff briefs, continuation metadata, and session-list filters.

## 0.6.1 — 2026-07-27
- Added an English comparison of AIMS and Softaworks Agent Toolkit session handoff practices, plus a documented AIMS roadmap for handoff readiness and adoption diagnostics.

## 0.6.0 — 2026-07-27
- Added `aims checkpoint <session-id>|--all`, targeted `aims handoff <session-id>`, and `aims handoff-all [--yes]` for explicit session preservation and cross-machine transfer through origin.
- Secret scanning now includes untracked, non-ignored files and runs on macOS Bash 3.2 without parser failures.
- `install.sh` restores the exact official `origin/main` engine and removes local engine state, including nested worktrees, before refreshing the command link.

## 0.5.8 — 2026-07-20
- init now installs the pre-push guard automatically, plus a new `aims install-hooks` command to (re)install it on an existing data repo — the "direct push to main is blocked" guarantee is now actually enforced on a fresh install, not just documented.
- pre-push hook allows the initial creation of main (seeding a new remote) and blocks only direct pushes to an existing main.
- aims-install-hooks: resolve an absolute hooks path so it works from any directory (previously relied on cwd being the repo).

## 0.5.7 — 2026-07-20
- README: new "Instructions for Your Agent" section — a copy-paste English prompt that has an AI agent review AIMS for security and install it (non-interactive, with remote setup and verification). Documented that re-running the installer updates AIMS.

## 0.5.6 — 2026-07-20
- publish: registry row no longer garbles columns when the project or topic contains spaces (parse metadata fields one per line instead of whitespace-splitting).

## 0.5.5 — 2026-07-20
- init/start/save/publish: fall back to a neutral commit identity (AIMS_GIT_NAME/EMAIL or "AIMS Agent <aims@localhost>") only when the data repo has no git identity, so a fresh machine no longer fails with "Author identity unknown"; a configured real identity is preserved. The check targets the data repo, not the current directory.

## 0.5.4 — 2026-07-20
- start/save/handoff/publish: fail fast with a clear, actionable message when the data repo has no 'origin' remote, instead of a cryptic git error; doctor's no-remote hint now names the exact `remote add` command. AIMS integrates sessions through origin, so a remote is required before starting sessions.

## 0.5.3 — 2026-07-20
- bootstrap.sh: license/liability consent gate (MIT, "AS IS", at-your-own-risk) shown before any change; accept interactively or with AIMS_ACCEPT=1 for unattended installs.
- wire-agents: detects installed agents and wires only those (no longer creates config files for absent agents), proposes the exact files and asks to confirm (skip with AIMS_YES=1), backs up each original once, and dedupes symlinked config files by realpath.

## 0.5.2 — 2026-07-20
- dev-setup.sh + hooks/pre-commit: pin an anonymous commit identity for the engine repo and block any commit that would leak a contributor's personal git identity into this public repo.

## 0.5.1 — 2026-07-19
- New docs/AGENTS-MEMORY.md: how AIMS consolidates rules and work across agents, and how to add your own rules alongside the AIMS block.

## 0.5.0 — 2026-07-19
- One-command setup: bootstrap.sh (curl | bash) installs engine, data repo, and wires agent rules.
- New: aims wire-agents / lib/aims-wire-agents — teaches Claude/Codex/opencode/Gemini to understand
  AIMS by writing an AIMS rules block into their config files (idempotent).
- templates/AGENTS.md rewritten as agent onboarding: natural-language intent -> aims command mapping.
- README: user-facing Install (agent + hardware/storage env), comparison table; Quick start/Commands
  reframed as agent reference.

## 0.4.2 — 2026-07-19
- COMPARISON.md: simplified emoji set to ✅ / ⚠️ / ❌ only.

## 0.4.0 — 2026-07-18
- Added docs/COMPARISON.md: AIMS vs. per-tool session resume (Claude Code, Codex CLI, opencode,
  Gemini CLI, Aider) — context layer vs. work layer, cross-machine and cross-tool portability.

## 0.3.0 — 2026-07-18
- Renamed AISHA -> AIMS (AI Multi-agent Sessions). Command, env vars (AIMS_HOME, AIMS_ARTIFACTS,
  AIMS_GIT_NAME/EMAIL), files and docs updated.

## 0.2.0 — 2026-07-18
- All engine code is English-only.
- Added `aims artifacts <id>` and `AIMS_ARTIFACTS` awareness in `doctor` and `adopt`.
- New `docs/SHARED-STORE.md` (NFS/SMB/GlusterFS/CephFS/MinIO/RustFS/Ceph RGW) + `docs/i18n/` structure.

## 0.1.0 — 2026-07-18
- Initial public extraction of the AIMS engine from a private data repo.
- Commands: init, start, save, handoff, adopt, publish, list, doctor.
- Portable `AIMS_HOME` data-repo model; pre-push main guard; secret scanner.
