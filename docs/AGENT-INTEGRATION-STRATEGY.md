# AIMS agent integration strategy

## Decision

**Keep AIMS as an independent, agent-neutral CLI and add optional native adapters. Do not make a
skill or plugin the AIMS runtime.**

An AIMS adapter should make the workflow discoverable in an agent's native UI, supply the same
session rules, and optionally offer an explicit command. The adapter must call the installed `aims`
CLI; it must not reimplement session state, Git safety checks, handoff, adoption, or publishing.

This is a hybrid model:

- **AIMS core**: one public Bash CLI, one Git-backed data model, and one compatibility contract.
- **Universal fallback**: the marker-delimited rules block installed by `aims wire-agents`.
- **Native adapters**: opt-in packages for an agent's skills, plugins, commands, or extensions.

The core remains usable from a shell, CI, a new agent, or an agent whose extension mechanism changes.
An adapter is therefore an integration and distribution layer, not a required dependency.

## Why a skill alone is insufficient

A skill is valuable because it can match natural language such as "save the session" and explain the
correct lifecycle. It cannot provide the properties AIMS exists to guarantee:

- a remote Git branch and isolated worktree;
- secret scanning before a mutation;
- compare-and-swap branch updates and safe rebase recovery;
- an agent-neutral handoff that another machine can adopt; and
- an independently testable CLI contract.

A skill also runs only when its host discovers or enables it. Rules and discovery semantics differ by
agent and can change independently. Making AIMS *only* a skill would create four incompatible sources
of truth and make the workflow unavailable to future agents.

Conversely, a CLI alone is less discoverable than each agent's native workflow. Thin native adapters
are worth building because they reduce prompt repetition, make the expected lifecycle visible, and
can provide controlled shortcuts without weakening the core guards.

## Current integration baseline

AIMS already supports Claude Code, Codex CLI, OpenCode, and Gemini CLI through the portable
`aims wire-agents` mechanism. It writes one marker-delimited block from
[`templates/AGENTS.md`](../templates/AGENTS.md) into the applicable instruction files. Re-running the
command is idempotent and preserves user rules outside the markers.

This remains the installation baseline until a native adapter is proven for an agent. It is important
because it has no marketplace dependency and works for a user who has only one of the supported CLIs.

The local compatibility probe on 2026-07-30 found the following capabilities:

| Agent | Local version observed | Native capability relevant to AIMS | Adapter priority |
|---|---:|---|---|
| Claude Code | 2.1.220 | plugins and skills | High |
| OpenAI Codex CLI | 0.145.0 | plugins | High |
| OpenCode | 1.18.4 | plugins and agents | High |
| Gemini CLI | 0.52.0 | extensions, skills, and hooks | High |

Versions are evidence for planning, not a permanent compatibility promise. Each adapter release must
validate the exact supported versions against the official documentation and a clean installation.

## Adapter contract

Every adapter, regardless of host, must satisfy this contract.

### One canonical source

The intent-to-command mapping and hard rules must originate from one canonical AIMS-owned source. The
existing `templates/AGENTS.md` is the initial candidate. Native package files may add only
host-specific invocation metadata and UI wording; they must not fork lifecycle policy.

A generated-file check must fail if the canonical rules and rendered adapter content drift.

### Explicit, least-surprise actions

Adapters may expose the following actions:

| Intent | Allowed adapter action |
|---|---|
| Start work | Explain scope collection, then run `aims start` only after the agent has the project and topic. |
| Save | Run `aims save` only from the current AIMS worktree. |
| Handoff | Run `aims handoff [note]`; never merge or delete the worktree. |
| Adopt | Run `aims adopt <session-id>` and require reading artifacts before edits. |
| Finish | Complete session artifacts, test the work, then run `aims publish <session-id>`. |

An adapter must never silently run `aims publish`, bypass a confirmation prompt, use destructive Git
flags, relax secret scanning, or invoke an agent's unrestricted auto-approval mode. Hooks may provide
non-mutating reminders and diagnostics, but must not perform lifecycle mutations in the background.

### Portable output

All durable state remains in the AIMS data repository and the configured Git remote. Adapter-specific
state, transcripts, caches, and marketplace metadata remain optional local conveniences and must not
be required to hand off or adopt a session.

### Graceful fallback

If a plugin, skill, extension, or hook is unavailable, AIMS must still work through `aims` plus the
marker-delimited instruction block. Removing an adapter must not orphan an active session.

## Per-agent implementation plan

### Claude Code

**Preferred form:** an installable Claude Code plugin containing an `aims-session` skill. The skill
provides lifecycle guidance and calls the `aims` executable; the plugin is the discoverable packaging
layer.

**Optional additions:** a slash-command alias for explicit use and non-mutating `SessionStart` or
`Stop` hooks that remind the agent to run `aims preflight` or save unfinished work. Hooks are advisory
only.

**Fallback:** `~/.claude/CLAUDE.md` with the existing managed AIMS block.

**Acceptance evidence:** install into an isolated Claude configuration, invoke the skill and explicit
command, verify that the CLI creates a session worktree, and hand the session to a different supported
agent.

### OpenAI Codex CLI

**Preferred form:** a Codex plugin that exposes an AIMS skill or command wrapper while preserving the
same canonical rules.

**Fallback:** `~/.codex/AGENTS.md` plus project-level `AGENTS.md` where appropriate. The fallback
must remain documented because instruction discovery is available even when plugins are disabled or
not installed.

**Acceptance evidence:** test the plugin in an isolated Codex home, verify instruction discovery,
run a complete start/save/handoff lifecycle, and adopt from a different CLI. Do not depend on Codex
session resume: it carries Codex context, while AIMS carries the work.

### OpenCode

**Preferred form:** an OpenCode plugin containing an explicit AIMS command and agent instructions.
The command should invoke the system `aims` executable and print its result rather than duplicate its
logic.

**Fallback:** the managed `~/AGENTS.md` instruction block, with any OpenCode-specific configuration
kept outside the AIMS runtime model.

**Acceptance evidence:** install the plugin in an isolated OpenCode data directory, verify no plugin
is needed for `aims` itself, exercise one bounded command, and complete a cross-agent handoff.

### Gemini CLI

**Preferred form:** a Gemini CLI extension that distributes an AIMS skill. Gemini's skills are the
natural place for user-intent guidance; an extension is the packaging and installation mechanism.
Hooks, if used, are advisory and read-only.

**Fallback:** `~/.gemini/GEMINI.md` with the existing managed AIMS block.

**Acceptance evidence:** install in an isolated Gemini configuration, verify the skill is listed and
can execute the explicit AIMS workflow, then adopt its session from Claude Code, Codex CLI, or
OpenCode.

## Repository layout to implement

Do not add this layout until Phase 1 accepts the package formats. The intended shape is:

```text
adapters/
├── canonical/                       # generated from templates/AGENTS.md; no host state
├── claude-code/                     # plugin manifest, aims-session skill, optional advisory hooks
├── codex/                           # plugin manifest and generated skill/instruction payload
├── opencode/                        # plugin module and generated command/instruction payload
└── gemini-cli/                      # extension manifest and aims-session skill
scripts/
└── validate-adapters.sh             # renders, validates, and detects policy drift
```

Each adapter directory must include an English README with its supported host versions, installation
method, uninstall method, permissions, and exact fallback path.

## Delivery phases

### Phase 0 — capability and security specification

1. Record the supported host version range and official documentation URL for each agent.
2. Confirm each host's package schema, discovery rules, permission model, uninstall behavior, and
   non-interactive behavior in a disposable home directory.
3. Define an adapter manifest with: adapter version, supported AIMS version range, host version range,
   canonical rules digest, and explicit capabilities.
4. Write negative tests proving adapters cannot auto-publish, bypass AIMS guards, or store secrets.

**Exit criterion:** a reviewed compatibility matrix and a stable adapter contract; no runtime behavior
has changed.

### Phase 1 — canonical rules and universal test harness

1. Refactor the current rules template only if necessary to make it renderable without changing its
   meaning.
2. Add a renderer and drift validator that compare every adapter payload to the canonical source.
3. Add an isolated lifecycle test matrix: one host starts, another host adopts, a third host publishes.
4. Keep `aims wire-agents` as the default installer and verify its backups and idempotency.

**Exit criterion:** a package-independent integration test demonstrates that an AIMS handoff remains
portable across all four agents.

### Phase 2 — first native adapter

Build Claude Code first because its plugin and skill model directly fits the intent-guidance use case.
Ship it as **experimental and opt-in**, with a clear fallback to `aims wire-agents`. Test installation,
uninstall, disabled-plugin fallback, command execution, cross-agent handoff, and a clean host.

**Exit criterion:** an adapter release is useful without being necessary; all AIMS core tests and the
new adapter tests pass.

### Phase 3 — Codex, OpenCode, and Gemini adapters

Implement one adapter per pull request, using the same canonical rules and test harness. Do not make a
host-specific convenience feature part of the cross-agent contract. A failure or breaking change in one
host must not delay fixes in the CLI core or disable the other adapters.

**Exit criterion:** every released adapter has isolated install/uninstall tests and at least one
cross-agent handoff acceptance test.

### Phase 4 — release maintenance

1. Version adapters independently while declaring the compatible AIMS core range.
2. Run scheduled compatibility smoke tests against supported agent releases.
3. Treat host API changes as adapter maintenance, not a reason to change AIMS session artifacts.
4. Keep English documentation, changelog entries, and an explicit deprecation path for every adapter.

**Exit criterion:** a user can remove or skip any adapter and still use the documented AIMS lifecycle.

## Test matrix

The release gate for every adapter should include:

| Scenario | Required result |
|---|---|
| Clean installation | Adapter installs without modifying files outside its documented scope. |
| Existing user instructions | Managed content is marker-delimited; user content survives refresh and uninstall. |
| Plugin/extension disabled | The AIMS CLI and `aims wire-agents` fallback still work. |
| Start and save | A session branch, worktree, metadata, and remote checkpoint are created by the CLI. |
| Cross-agent handoff | Agent A hands off; agent B on a separate home directory adopts from `origin`. |
| Publish | Only explicit `aims publish` integrates the branch and cleans it up. |
| Safety negatives | No automatic publish, force push, secret disclosure, or permission bypass. |
| Upgrade and uninstall | Host-specific state is removed cleanly; an active AIMS session remains adoptable. |

## Documentation sources to verify before implementation

- [Claude Code plugins](https://code.claude.com/docs/en/plugins)
- [Claude Code skills](https://code.claude.com/docs/en/skills)
- [Codex AGENTS.md guidance](https://developers.openai.com/codex/guides/agents-md)
- [OpenCode plugins](https://opencode.ai/docs/plugins)
- [OpenCode skills](https://opencode.ai/docs/skills)
- [Gemini CLI extensions](https://geminicli.com/docs/extensions/)

These external interfaces evolve. The implementation must verify the current official documentation
and command-line behavior before each adapter is released; this strategy does not freeze third-party
APIs.

## Final recommendation

Use a skill in every supported agent **as an optional native front end**, but keep AIMS independent as
the **only runtime and source of truth**. This yields the usability benefit of native skills and plugins
without giving up the portability, safety, and cross-agent handoff that distinguish AIMS.
