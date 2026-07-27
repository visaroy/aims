# Security Policy

## Design principles

AIMS is git-native and holds **no secrets of its own**. It operates on a separate,
user-owned *data repo*. The engine ships only shell scripts and documentation.

- **No network calls** except `git` to the user's configured `origin`. AIMS never contacts
  any third-party endpoint.
- **No credentials** in the engine. The data repo's `credentials/` directory is gitignored;
  values live outside git (OS keychain, vault, CI secrets).
- **Secret scanning**: `lib/validate-no-secrets.sh` scans tracked and untracked, non-ignored data-repo files for common token patterns (GitHub `ghp_`/`github_pat_`, GitLab `glpat-`/`glptt-`/`glrt-`, AWS `AKIA`, Slack `xox*`, private keys, generic `key=value`). Placeholders are filtered.
- **Handoff safety**: `aims handoff` and `aims handoff-all` run this scanner before staging changes; a blocked session is left intact and unpushed.
- **Direct push to `main` is blocked** by a `pre-push` hook; integration only via `aims publish`.
- **Handoff/adopt move git branches only**, never machine-to-machine access. Machines push/pull
  through `origin`; no host needs inbound access to another.

## What AIMS deliberately does NOT do

- Does not store, transmit, or log secret values.
- Does not execute code from sessions automatically.
- Does not require elevated privileges.

## Reporting a vulnerability

Open a private security advisory on the repository, or email the maintainer listed in the
repo profile. Please do not file public issues for undisclosed vulnerabilities.

## Auditor quick start

```bash
grep -rInE 'ghp_|glpat-|AKIA|BEGIN .*PRIVATE KEY' .        # should find only detector patterns
grep -rInE '10\.[0-9]|/home/[a-z]|/Users/[a-z]|@'          # no hardcoded hosts/users/emails
bash -n lib/*                                              # scripts parse clean
```
