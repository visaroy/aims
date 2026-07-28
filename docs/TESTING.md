# Test AIMS in under 10 minutes

**Author**: Dariusz Porczyński

**Last updated**: 2026-07-28

This acceptance test simulates two machines and two agents using disposable local directories. It exercises the complete AIMS lifecycle without reading or changing the tester's normal `HOME`, Git configuration, `~/.aims`, agent configuration files, or a real remote repository.

## What it verifies

The test performs this sequence:

1. Initialize a disposable AIMS data repository for machine A.
2. Clone it as machine B before the session exists.
3. Start a session as Claude Code and create a file.
4. Save and hand off the session through a local bare Git origin.
5. Adopt the newly created branch on machine B as Codex.
6. Continue the work, save it, and publish the session.
7. Verify the final content, registry entry, worktree cleanup, and session-branch deletion.

Expected duration: 3–10 minutes.

## Requirements

- macOS or Linux
- `git`, `bash`, and `python3`
- a local clone of the AIMS engine

Run the test from the root of the AIMS engine repository. It uses `bin/aims` from the current checkout, so it also works before installation.

## Copy-paste acceptance test

```bash
(
set -euo pipefail
ENGINE_ROOT=$(git rev-parse --show-toplevel)
ENGINE="$ENGINE_ROOT/bin/aims"
[ -x "$ENGINE" ] || { echo "AIMS engine not found at $ENGINE" >&2; exit 1; }
[ "$("$ENGINE" version)" = "$(cat "$ENGINE_ROOT/VERSION")" ] || { echo "Engine and VERSION do not match" >&2; exit 1; }

LAB=$(mktemp -d "${TMPDIR:-/tmp}/aims-acceptance.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
printf 'Disposable test directory: %s\n' "$LAB"

ORIGIN="$LAB/origin.git"
HOME_A="$LAB/home-a"
HOME_B="$LAB/home-b"
DATA_A="$HOME_A/.aims"
DATA_B="$HOME_B/.aims"
mkdir -p "$HOME_A/.config" "$HOME_B/.config"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export AIMS_GIT_NAME="AIMS Acceptance"
export AIMS_GIT_EMAIL="aims@example.invalid"
on_a() { HOME="$HOME_A" XDG_CONFIG_HOME="$HOME_A/.config" AIMS_HOME="$DATA_A" "$@"; }
on_b() { HOME="$HOME_B" XDG_CONFIG_HOME="$HOME_B/.config" AIMS_HOME="$DATA_B" "$@"; }

git init --bare "$ORIGIN" >/dev/null
git --git-dir="$ORIGIN" symbolic-ref HEAD refs/heads/main
on_a "$ENGINE" init "$DATA_A"
on_a git -C "$DATA_A" remote add origin "$ORIGIN"
on_a git -C "$DATA_A" push -u origin main >/dev/null
on_b git clone "$ORIGIN" "$DATA_B" >/dev/null
on_b "$ENGINE" install-hooks >/dev/null

START_OUTPUT=$(on_a "$ENGINE" start demo "cross-agent handoff" claude --scope path:demo)
printf '%s\n' "$START_OUTPUT"
SESSION_ID=$(printf '%s\n' "$START_OUTPUT" | python3 -c 'import sys; print(next(line.split("=", 1)[1].strip() for line in sys.stdin if line.startswith("SESSION_ID=")))')
[ -n "$SESSION_ID" ]
WORKTREE_A="$DATA_A/.worktrees/$SESSION_ID"
printf '%s\n' '# Worklog' '' '- Created acceptance artifact on machine A.' '- Next: adopt on machine B and publish.' > "$WORKTREE_A/sessions/work/$SESSION_ID/worklog.md"
printf 'created by Claude Code on machine A\n' > "$WORKTREE_A/demo.txt"
(cd "$WORKTREE_A" && on_a "$ENGINE" save)
test "$(git --git-dir="$ORIGIN" show "refs/heads/ai/$SESSION_ID:demo.txt")" = "created by Claude Code on machine A"
(cd "$WORKTREE_A" && on_a "$ENGINE" handoff "continue with Codex on machine B")

test "$(git --git-dir="$ORIGIN" show "refs/heads/ai/$SESSION_ID:sessions/work/$SESSION_ID/metadata.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])')" = "handoff"
on_b "$ENGINE" adopt "$SESSION_ID"
WORKTREE_B="$DATA_B/.worktrees/$SESSION_ID"
grep -Fx "created by Claude Code on machine A" "$WORKTREE_B/demo.txt"
printf 'continued by Codex on machine B\n' >> "$WORKTREE_B/demo.txt"
(cd "$WORKTREE_B" && on_b "$ENGINE" save)
on_b "$ENGINE" publish "$SESSION_ID"

EXPECTED=$(printf 'created by Claude Code on machine A\ncontinued by Codex on machine B')
ACTUAL=$(git --git-dir="$ORIGIN" show main:demo.txt)
[ "$ACTUAL" = "$EXPECTED" ] || { printf 'Unexpected final content:\n%s\n' "$ACTUAL" >&2; exit 1; }
git --git-dir="$ORIGIN" show main:SESSIONS.md | grep -F "$SESSION_ID" >/dev/null
if git --git-dir="$ORIGIN" show-ref --verify --quiet "refs/heads/ai/$SESSION_ID"; then
  echo "Session branch still exists after publish" >&2
  exit 1
fi
[ ! -d "$WORKTREE_B" ] || { echo "Adopted worktree still exists after publish" >&2; exit 1; }

printf '\nPASS: isolated start -> save -> handoff -> adopt -> save -> publish\n'
printf '%s\n' "$ACTUAL"
)
```

## Expected final output

The command prints detailed Git and AIMS progress. Its final lines must be:

```text
PASS: isolated start -> save -> handoff -> adopt -> save -> publish
created by Claude Code on machine A
continued by Codex on machine B
```

The subshell removes the disposable test directory on success, failure, or interruption.

## Isolation guarantees

- `HOME`, `XDG_CONFIG_HOME`, and `AIMS_HOME` point inside the temporary directory for both simulated machines.
- `GIT_CONFIG_GLOBAL=/dev/null` and `GIT_CONFIG_NOSYSTEM=1` prevent Git from reading the tester's global or system configuration.
- A neutral `.invalid` commit identity is provided through `AIMS_GIT_NAME` and `AIMS_GIT_EMAIL`.
- Machine B is cloned before the session starts, so adoption must fetch the new remote session branch.
- The test uses no network connection, hosted repository, real credential, shell profile, or agent configuration.

## Real two-machine test

After the disposable test passes, use a private Git repository as `origin` and repeat the lifecycle with the agents and machines you actually use:

1. Start and save a small task on machine A.
2. Run `aims handoff "continue on machine B"` from its session worktree.
3. On machine B, clone or update the same AIMS data repository and run `aims adopt <session-id>`.
4. Make one harmless change, run `aims save`, then `aims publish <session-id>`.
5. Confirm that machine A no longer owns the session and `origin/main` contains both sides of the work.

Never use a production code repository for a first test. Do not include credentials, private repository URLs, hostnames, IP addresses, or unsanitized `aims doctor` output in a public issue.

## Report feedback

Open an [AIMS alpha tester feedback issue](https://github.com/visaroy/aims/issues/new?template=tester-feedback.yml). Include the AIMS version, OS, Bash version, agents, topology, exact lifecycle steps, and sanitized diagnostics. Report suspected vulnerabilities through a [private GitHub security advisory](https://github.com/visaroy/aims/security/advisories/new).
