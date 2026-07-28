# Test AIMS in under 10 minutes

**Author**: Dariusz Porczyński

**Last updated**: 2026-07-28

This acceptance test simulates two machines and two agents using disposable local directories. It exercises the complete AIMS lifecycle without changing `~/.aims`, agent configuration files, or a real remote repository.

## What it verifies

The test performs this sequence:

1. Initialize a disposable AIMS data repository for machine A.
2. Start a session as Claude Code and create a file.
3. Save and hand off the session through a local bare Git origin.
4. Clone the data repository as machine B and adopt the session as Codex.
5. Continue the work, save it, and publish the session.
6. Verify that both agents' changes reached `main` and the session branch was removed.

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
ENGINE="$PWD/bin/aims"
[ -x "$ENGINE" ] || { echo "Run this from the AIMS repository root" >&2; exit 1; }
LAB=$(mktemp -d "${TMPDIR:-/tmp}/aims-acceptance.XXXXXX")
trap 'rm -rf "$LAB"' EXIT
printf 'Disposable test directory: %s\n' "$LAB"

git init --bare "$LAB/origin.git" >/dev/null
AIMS_HOME="$LAB/machine-a" "$ENGINE" init "$LAB/machine-a"
git -C "$LAB/machine-a" remote add origin "$LAB/origin.git"
git -C "$LAB/machine-a" push -u origin main >/dev/null
git -C "$LAB/origin.git" symbolic-ref HEAD refs/heads/main

START_OUTPUT=$(AIMS_HOME="$LAB/machine-a" "$ENGINE" start demo "cross-agent handoff" claude --scope path:demo)
printf '%s\n' "$START_OUTPUT"
SESSION_ID=$(printf '%s\n' "$START_OUTPUT" | python3 -c 'import sys; print(next(line.split("=", 1)[1].strip() for line in sys.stdin if line.startswith("SESSION_ID=")))')
WORKTREE_A="$LAB/machine-a/.worktrees/$SESSION_ID"
printf 'created by Claude Code on machine A\n' > "$WORKTREE_A/demo.txt"
(cd "$WORKTREE_A" && AIMS_HOME="$LAB/machine-a" "$ENGINE" save)
(cd "$WORKTREE_A" && AIMS_HOME="$LAB/machine-a" "$ENGINE" handoff "continue with Codex on machine B")

git clone "$LAB/origin.git" "$LAB/machine-b" >/dev/null
AIMS_HOME="$LAB/machine-b" "$ENGINE" install-hooks
AIMS_HOME="$LAB/machine-b" "$ENGINE" adopt "$SESSION_ID"
WORKTREE_B="$LAB/machine-b/.worktrees/$SESSION_ID"
printf 'continued by Codex on machine B\n' >> "$WORKTREE_B/demo.txt"
(cd "$WORKTREE_B" && AIMS_HOME="$LAB/machine-b" "$ENGINE" save)
AIMS_HOME="$LAB/machine-b" "$ENGINE" publish "$SESSION_ID"

EXPECTED=$(printf 'created by Claude Code on machine A\ncontinued by Codex on machine B')
ACTUAL=$(git --git-dir="$LAB/origin.git" show main:demo.txt)
[ "$ACTUAL" = "$EXPECTED" ] || { printf 'Unexpected final content:\n%s\n' "$ACTUAL" >&2; exit 1; }
if git --git-dir="$LAB/origin.git" show-ref --verify --quiet "refs/heads/ai/$SESSION_ID"; then
  echo "Session branch still exists after publish" >&2
  exit 1
fi

printf '\nPASS: start -> save -> handoff -> adopt -> save -> publish\n'
printf '%s\n' "$ACTUAL"
)
```

## Expected final output

The command prints detailed Git and AIMS progress. Its final lines must be:

```text
PASS: start -> save -> handoff -> adopt -> save -> publish
created by Claude Code on machine A
continued by Codex on machine B
```

The subshell removes the disposable test directory on success or failure.

## Real two-machine test

After the disposable test passes, use a private Git repository as `origin` and repeat the lifecycle with the agents and machines you actually use:

1. Start and save a small task on machine A.
2. Run `aims handoff "continue on machine B"` from its session worktree.
3. On machine B, clone or update the same AIMS data repository and run `aims adopt <session-id>`.
4. Make one harmless change, run `aims save`, then `aims publish <session-id>`.
5. Confirm that machine A no longer owns the session and `origin/main` contains both sides of the work.

Never use a production code repository for a first test. Do not include credentials, private repository URLs, hostnames, IP addresses, or unsanitized `aims doctor` output in a public issue.

## Report feedback

Open an [AIMS alpha tester feedback issue](https://github.com/visaroy/aims/issues/new?template=tester-feedback.yml). Include the AIMS version, OS, Bash version, agents, topology, exact lifecycle steps, and sanitized diagnostics.
