# Test AIMS in under 3 minutes

**Last updated**: 2026-10-15

This page separates the automated acceptance test that an agent runs from the decisions and observations that belong to a human tester. The automated test simulates two machines and two agents using disposable local directories. It exercises the complete AIMS lifecycle without reading or changing the tester's normal `HOME`, Git configuration, `~/.aims`, agent configuration files, or a real remote repository.

## What it verifies

The test performs this sequence:

1. Initialize a disposable AIMS data repository for machine A.
2. Clone it as machine B before the session exists.
3. Start a session as Claude Code and create a file.
4. Save and hand off the session through a local bare Git origin.
5. Adopt the newly created branch on machine B as Codex.
6. Continue the work, save it, and publish the session.
7. Verify the final content, registry entry, worktree cleanup, and session-branch deletion.

Expected duration: under 3 minutes on a typical development machine.

The policy regression suite is separate and verifies the v3.0.0 admission contract: exact `dashboard:`
matching, advisory exact/path overlaps with successful starts, unrelated `SAFE` diagnostics, malformed
scope rejection, handed-off adoption diagnostics, and non-handoff adoption rejection.

```bash
bash tests/advisory-overlap-policy.sh
```

The installer suite (3.1.0) runs each scenario on a disposable `HOME` with fake agent executables and
local repositories only — no network:

| Test | Verifies |
|---|---|
| `tests/install-fresh-home.sh` | Empty `HOME`: creates and records `~/.aims`, guard, command link, agent blocks; a second run changes no file. |
| `tests/install-reuse-data-repo.sh` | Reuse from `$AIMS_HOME`, `~/.config/aims/home`, a profile export, and `~/.aims`; two candidates block without any change; choosing with `AIMS_HOME` is recorded. |
| `tests/install-preflight-blocker.sh` | Conflict markers, a malformed block, a non-repo data path, a foreign hook, a foreign command file, and a read-only target each stop the run before any change. |
| `tests/install-tracked-target.sh` | A symlinked, Git-tracked agent file is wired, reported for a pull request, and backed up outside its repo. |
| `tests/install-duplicate-policy.sh` | User-written AIMS text is kept and reported as a possible duplicate; the block is still added. |
| `tests/install-fresh-flag.sh` | `--fresh` refuses with no origin, dirty, or unpushed work, and otherwise moves the old repo aside. |
| `tests/uninstall.sh` | Install then uninstall restores every agent file byte for byte, keeps the data repo, and is idempotent. |
| `tests/install-update.sh` | `install.sh` restores the engine to `origin/main`, refuses a non-`main` branch, runs `aims install`, and works from a pipe. |
| `tests/bootstrap-shim.sh`, `tests/init-deprecated.sh` | The deprecated entry points keep working. |

```bash
for t in tests/install-*.sh tests/uninstall.sh tests/bootstrap-shim.sh tests/init-deprecated.sh; do bash "$t"; done
```

## For agents: isolated acceptance test

The agent runs this section, checks every assertion, and reports the exact result. A human does not need to memorize or type the lifecycle commands.

### Requirements

- macOS or Linux
- `git`, `bash`, and `python3`
- a local clone of the AIMS engine

Run the test from the root of the AIMS engine repository. It uses `bin/aims` from the current checkout, so it also works before installation.

### Acceptance command

```bash
bash tests/full-lifecycle.sh
```

### Expected final output

The command prints detailed Git and AIMS progress. Its final lines must be:

```text
PASS: isolated start -> save -> handoff -> adopt -> save -> publish
created by Claude Code on machine A
continued by Codex on machine B
```

Unless diagnostic `AIMS_KEEP_LAB=1` is set, the script's `EXIT` trap removes the disposable test directory on success, failure, or interruption.

### Isolation guarantees

- `HOME`, `XDG_CONFIG_HOME`, and `AIMS_HOME` point inside the temporary directory for both simulated machines.
- `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1` prevent Git from reading the tester's global or system configuration.
- A neutral `.invalid` commit identity is provided through `AIMS_GIT_NAME` and `AIMS_GIT_EMAIL`.
- Machine B is cloned before the session starts, so adoption must fetch the new remote session branch.
- The test uses no network connection, hosted repository, real credential, shell profile, or agent configuration.

## For human testers: real two-machine acceptance

After the disposable test passes, decide whether to run a real cross-machine check with a private Git repository as `origin`. Tell the agents what outcome you want; the agents should choose and run the AIMS commands.

1. Ask the agent on machine A to start and save a harmless test task.
2. Ask it to hand the session off to machine B.
3. Ask the agent on machine B to continue the handed-off session from the shared private origin.
4. Ask it to make one harmless change, save, and publish the session.
5. Confirm that the published result contains work from both agents and that machine A no longer owns the session.

Never use a production code repository for a first test. Do not include credentials, private repository URLs, hostnames, IP addresses, or unsanitized `aims doctor` output in a public issue.

### Report feedback

Open an [AIMS feedback issue](https://github.com/visaroy/aims/issues/new?template=tester-feedback.yml). Include the AIMS version, OS, Bash version, agents, topology, exact lifecycle steps, and sanitized diagnostics. Report suspected vulnerabilities through a [private GitHub security advisory](https://github.com/visaroy/aims/security/advisories/new).
