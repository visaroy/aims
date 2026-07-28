# Changelog

## Unreleased
- Added advisory, non-mutating `aims handoff check <session-id>` readiness checks that keep transport blockers separate from contextual warnings.

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
