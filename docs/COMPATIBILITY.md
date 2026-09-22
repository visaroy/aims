# AIMS CLI compatibility

## `v3.0.0` public contract

AIMS `v3.0.0` is the stable `3.x` command-line contract. The supported public command names, documented arguments, environment variables, lifecycle order, and safety guarantees are the ones printed by `aims help` and described in [COMMANDS.md](COMMANDS.md). `start` and `continue` require non-empty scopes; `dashboard:` is a valid exact-match scope kind; admission remains atomically serialized (a cross-machine git-ref lease) and additionally protected by a machine-local admission lock. Valid detected overlaps now print an advisory warning and proceed, while malformed scopes, origin/Git/lease failures, and unverifiable checks remain blocking. Active local adoption requires a handoff, and handed-off adoption includes advisory overlap diagnostics. `aims start` stamps OS-observed hostname/ancestor-process/heartbeat facts used only for read-only stale-conflict diagnosis in `aims conflicts`. `aims conflicts` tolerates a pre-existing session with invalid or missing legacy scope metadata by warning about it and excluding it from the result, instead of failing the whole check.

The contract covers these commands: `init`, `start`, `save`, `rebase`, `handoff`, `checkpoint`, `brief`, `adopt`, `publish`, `abandon`, `heartbeat`, `delegate-exec`, `list`, `artifacts`, `doctor`, `wire-agents`, `install-hooks`, `preflight`, `version`, and `help`.

For the commands and options documented in `COMMANDS.md`, AIMS guarantees that:

- valid invocations preserve their documented lifecycle and safety behavior;
- unknown options and surplus positional arguments fail with exit status `2` before command-specific mutation;
- `start`, `save`, `handoff`, `adopt`, and `publish` retain Git as the portable source of truth;
- session work remains portable through the configured `origin`, not an agent transcript or a machine-local worktree;
- safety refusals do not silently discard work or overwrite a concurrent remote writer;
- diagnostic features (stale-conflict reclaim suggestions) never silently mutate state or override a real conflict.

## Compatibility policy

The stable `v2.0.0` through `v2.1.2` releases preserved blocking overlap admission. `v3.0.0` intentionally changes that lifecycle guarantee: valid detected overlaps are advisory and no longer reject `aims start`; handed-off adoption reports them without rejecting the adoption. This is a major-version migration. Command names, required arguments, malformed-scope validation, origin/Git/lease failure handling, and the non-handoff adoption refusal remain unchanged.

## Scope

This policy covers the public AIMS engine and CLI. AIMS session content belongs to each user's private data repository, and individual agents remain responsible for project-specific rules, credentials, and operational decisions.
