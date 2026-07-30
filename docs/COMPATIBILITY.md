# AIMS CLI compatibility

## `v1.0.0-rc.1` public contract

AIMS `v1.0.0-rc.1` is a release candidate for the `1.0` command-line contract. The supported public command names, documented arguments, environment variables, lifecycle order, and safety guarantees are the ones printed by `aims help` and described in [COMMANDS.md](COMMANDS.md).

The contract covers these commands: `init`, `start`, `save`, `rebase`, `handoff`, `checkpoint`, `brief`, `adopt`, `publish`, `list`, `artifacts`, `doctor`, `wire-agents`, `install-hooks`, `preflight`, `version`, and `help`.

For the commands and options documented in `COMMANDS.md`, AIMS guarantees that:

- valid invocations preserve their documented lifecycle and safety behavior;
- unknown options and surplus positional arguments fail with exit status `2` before command-specific mutation;
- `start`, `save`, `handoff`, `adopt`, and `publish` retain Git as the portable source of truth;
- session work remains portable through the configured `origin`, not an agent transcript or a machine-local worktree;
- safety refusals do not silently discard work or overwrite a concurrent remote writer.

## Compatibility policy

During the release-candidate period, fixes may strengthen validation, diagnostics, documentation, and test coverage without intentionally changing a documented valid invocation. New optional commands or options may be added without changing existing command semantics.

The stable `v1.0.0` release will preserve this documented command surface. After `v1.0.0`, an incompatible change to a documented command name, required argument, option, exit-status contract, or lifecycle guarantee requires a major version increment and a migration note in `CHANGELOG.md`.

## Scope

This policy covers the public AIMS engine and CLI. AIMS session content belongs to each user's private data repository, and individual agents remain responsible for project-specific rules, credentials, and operational decisions.
