# AIMS CLI compatibility

## `v2.1.1` public contract

AIMS `v2.1.1` is the stable `2.x` command-line contract. The supported public command names, documented arguments, environment variables, lifecycle order, and safety guarantees are the ones printed by `aims help` and described in [COMMANDS.md](COMMANDS.md). `start` and `continue` require non-empty scopes; admission is atomically serialized (a cross-machine git-ref lease) and additionally protected by a machine-local admission lock; active local adoption requires a handoff. `aims start` stamps OS-observed hostname/ancestor-process/heartbeat facts used only for read-only stale-conflict diagnosis in `aims conflicts`, never to bypass a real conflict. `aims conflicts` tolerates a pre-existing session with invalid or missing legacy scope metadata by warning about it and excluding it from the result, instead of failing the whole check.

The contract covers these commands: `init`, `start`, `save`, `rebase`, `handoff`, `checkpoint`, `brief`, `adopt`, `publish`, `abandon`, `heartbeat`, `delegate-exec`, `list`, `artifacts`, `doctor`, `wire-agents`, `install-hooks`, `preflight`, `version`, and `help`.

For the commands and options documented in `COMMANDS.md`, AIMS guarantees that:

- valid invocations preserve their documented lifecycle and safety behavior;
- unknown options and surplus positional arguments fail with exit status `2` before command-specific mutation;
- `start`, `save`, `handoff`, `adopt`, and `publish` retain Git as the portable source of truth;
- session work remains portable through the configured `origin`, not an agent transcript or a machine-local worktree;
- safety refusals do not silently discard work or overwrite a concurrent remote writer;
- diagnostic features (stale-conflict reclaim suggestions) never silently mutate state or override a real conflict.

## Compatibility policy

The stable `v2.0.0` release preserves this documented command surface; `v2.1.0` is additive (new commands and metadata fields, no removed or redefined command, argument, or exit-status contract). After `v2.0.0`, an incompatible change to a documented command name, required argument, option, exit-status contract, or lifecycle guarantee requires a major version increment and a migration note in `CHANGELOG.md`.

## Scope

This policy covers the public AIMS engine and CLI. AIMS session content belongs to each user's private data repository, and individual agents remain responsible for project-specific rules, credentials, and operational decisions.
