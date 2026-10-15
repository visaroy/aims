# Upgrading AIMS

This page is the single place to check before or after updating the AIMS engine. It covers both
the **engine** (`~/aims`, this repository) and your **data repo** (resolved by `aims home`: `$AIMS_HOME`,
the recorded `~/.config/aims/home`, a shell profile export, or `~/.aims` — your sessions,
`SESSIONS.md`, project state).

## For agents: how to update AIMS when asked

If the user asks you (the agent) to "update AIMS", "upgrade AIMS", "check for a new AIMS version",
or similar, do exactly this:

```bash
bash ~/aims/install.sh
aims version
```

`install.sh` restores the engine and then runs `aims install`, which reuses your data repo, refreshes
the guard and agent rules, and ends with `aims doctor`. `install.sh` always restores an exact official checkout from `origin/main` — it is not a partial
patch. Do not hand-edit files under `~/aims`; any local change there is discarded on the next
`install.sh` run by design (see "What `install.sh` does" below). Report the version before and
after and the installer's final report (including Git-tracked agent files that need a commit) to the
user.

Do **not**:
- edit `~/aims` files directly and expect them to persist;
- run `git pull` inside `~/aims` yourself instead of `install.sh` (it uses a different, safer
  reset+clean procedure — see below);
- assume a specific released version number; always read it from `aims version` after updating.

## For people: one command

```bash
bash ~/aims/install.sh
```

That's it. If the installer or `aims doctor` reports a problem, read its output — it names the exact
fix (for example, a missing `origin` remote on your data repo, or two data repo candidates).

## What `install.sh` does, precisely

Running `bash ~/aims/install.sh`:

1. Prints `🔄 Restoring a fresh, official AIMS version from the official GitHub repository…`.
2. Fetches `origin/main` from `https://github.com/visaroy/aims`.
3. Runs `git reset --hard origin/main`.
4. Runs `git clean -ffdx` — this **deletes every local tracked, untracked, and ignored file** in
   `~/aims` that is not part of the official `origin/main` tree, including nested worktrees such as
   `.slim/`.
5. Runs `aims install` from the restored engine: preflight, the `aims` command link at
   `$HOME/.local/bin/aims`, the data repo (reused), the recorded path, the guard, the agent rules, and
   the final report with `aims doctor` (see [`COMMANDS.md`](COMMANDS.md#aims-install---fresh)).
6. Refuses to run if `~/aims` is currently on a branch other than `main` — protects you from
   silently discarding your own experimental branch. Switch to `main` (or clone AIMS fresh
   elsewhere) if you were intentionally testing a feature branch.

This means `~/aims` is always disposable and reproducible: if anything in your local engine
checkout looks wrong, `bash install.sh` puts it back to the exact official state. It never changes
your data repo's content — your sessions, `SESSIONS.md`, and project state are untouched by an engine
update; only its `pre-push` hook is refreshed.

Piped from the web (`curl … | bash`), `install.sh` works on `~/aims` (or `$AIMS_DIR`): it restores an
existing checkout the same way, or clones it after you accept the MIT terms (`AIMS_ACCEPT=1` for a
non-interactive run). Running it from a checkout asks nothing.

## Checking your current version

```bash
aims version           # prints the installed engine version, e.g. 3.1.0
```

Compare it against the latest official release: <https://github.com/visaroy/aims/releases>. The
`CHANGELOG.md` in this repository lists every change per version, and each entry states whether a
migration step is needed.

## Migration notes by version

Read the entry for every version between your current one and the target — `CHANGELOG.md` is
cumulative, but this table highlights changes that need a decision, not just a passive update.

| Version | What changed that might affect you | Action needed |
|---|---|---|
| `3.1.0` | One installer: `install.sh` runs `aims install` (new), which reuses the data repo, records it in `~/.config/aims/home`, installs the guard, and wires agents without prompting. New `aims uninstall` and `aims home`. `aims init` and `bootstrap.sh` are deprecated but still work. Backups move from `*.aims-backup-*` next to the originals to `~/.local/state/aims/backups/`. | Run `bash ~/aims/install.sh` once. The 3.0 `install.sh` you start this upgrade with only restores and links the engine, so finish with `aims install` (or run `install.sh` a second time). Commit any agent file the report lists as Git-tracked through a branch and pull request. Optional: delete old `*.aims-backup-*` files after checking them; `AIMS_HOME` exports in your profiles can stay or go. |
| `3.0.0` | Valid detected scope overlaps are advisory: `aims start` warns and proceeds; handed-off `aims adopt` reports overlap diagnostics and proceeds. Added exact-match `dashboard:` scopes. | Update agent instructions to continue after a valid overlap `WARN`. Keep treating malformed scopes, origin/Git/lease failures, and non-handoff adoption as blocking. |
| `2.1.2` | `aims conflicts` no longer prints the raw Python error line for a legacy invalid-scope session alongside the `WARN:` line — cosmetic only. | None. |
| `2.1.1` | `aims conflicts`/`aims start` no longer fail entirely when one pre-existing session has invalid/legacy scope metadata; that session is now excluded from the result with a `WARN` instead. | None — this only removes a failure mode. If you see a `WARN` about a specific old session, it means that session predates mandatory `--scope` (before 2.0.0); publish it, fix its `metadata.json`, or run `aims abandon <id> --empty-only` if it is an unstarted scaffold. |
| `2.1.0` | `aims start` now takes a machine-local admission lock under `$AIMS_HOME/.locks/` and stamps an `observed` block (hostname, ancestor process, heartbeat) into every new session's `metadata.json`. New commands: `aims heartbeat`, `aims delegate-exec`. | None — additive. Existing sessions simply lack an `observed` block until their next `aims save`. If `$AIMS_HOME` lives on a network filesystem without reliable `mkdir`/rmdir semantics, keep it on a local filesystem (see `docs/ARCHITECTURE.md`). |
| `2.0.0` | `--scope` became **mandatory** for `aims start` and `aims continue`. Session admission is atomically serialized against a remote lease; local `aims adopt` now requires the source to have run `aims handoff` first (`--remote` remains read-only). | Add an explicit `--scope host:x,repo:y,...` to every `aims start`/`aims continue` invocation. If you have a scripted/automated caller that omits `--scope`, update it before upgrading past 2.0.0. |
| `1.1.0` | Published sessions became first-class discoverable: `aims status`, `aims continue`, `aims list --closed`. | None — additive. |
| `1.0.0` | Promoted to stable `1.0` CLI contract; `aims rebase` added for safe recovery from a publish merge conflict. | None — additive. |

For the full, line-by-line history see [`CHANGELOG.md`](../CHANGELOG.md). For the exact command
surface and safety guarantees currently in force, see
[`docs/COMPATIBILITY.md`](COMPATIBILITY.md).

## If something looks wrong after an update

1. `aims doctor` — checks `git`/`bash`/`python3` availability, your data repo's registry, `origin`
   remote, guard, recorded path, and agent rules blocks. Its output names the exact fix.
2. `aims version` — confirm you are actually on the version you expect; `bash install.sh` again if
   not.
3. Compare against a completely disposable install to isolate an environment-specific issue: see
   [`docs/TESTING.md`](TESTING.md) for the under-3-minute acceptance test, which exercises the full
   `start → save → handoff → adopt → save → publish` lifecycle in throwaway repositories.
4. If the problem is in the engine itself (not your data repo or environment), open an issue with
   the exact `aims version`, OS, and `aims doctor` output: <https://github.com/visaroy/aims/issues>.

## Uninstall

`aims uninstall` removes the marked AIMS blocks, the guard, the command link, and the recorded path,
and keeps your data repo; then delete the engine with `rm -rf ~/aims` if you want. Details:
[`COMMANDS.md`](COMMANDS.md#aims-uninstall).

## Rollback

`~/aims` is a normal git checkout. To pin an older release temporarily:

```bash
cd ~/aims
git fetch origin --tags
git checkout v2.1.0   # or any published tag from https://github.com/visaroy/aims/releases
```

This leaves `~/aims` on a detached, non-`main` ref, so `bash install.sh` will refuse to run until
you `git checkout main` again — this is the same guard that protects an intentional feature-branch
checkout, and it also protects a deliberate rollback from being silently overwritten by the next
`install.sh` you (or an agent) run out of habit.
