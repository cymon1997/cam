# Changelog

All notable changes to cam are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.4.0] — 2026-10-13

### Added
- macOS Keychain support. `cam add <name> --import` now imports a login that Claude Code keeps in
  the Keychain, and `cam list`, `cam rename` and `cam remove` handle an account's Keychain item.
  `CAM_KEYCHAIN=1|0` forces the behaviour on or off.

### Fixed
- A failed `cam add --import` no longer leaves an empty account directory behind.

## [0.3.0] — 2026-10-10

### Added
- Tab completion in bash and zsh, installed by `eval "$(cam init)"`: subcommands, flags, and
  registered account names for `use`, `run`, `login`, `default`, `env`, `rename`, `remove` and
  `isolate`. In zsh, subcommands are listed with descriptions.
- `cam list --names` prints bare account names, one per line.

## [0.2.0] — 2026-10-10

### Added
- `cam isolate <name> [--off]` and `cam add <name> --isolate-sessions`: an account can keep its
  sessions, prompt history, todos, plans and file history out of the shared `~/.claude`, while
  still sharing settings, skills, agents, plugins and hooks. `--off` merges them back.
- `cam list` marks isolated accounts with `[isolated]`.
- `cam remove` warns that deleting an isolated account also deletes its sessions.

## [0.1.0] — 2026-10-09

### Added
- `cam add` (with `--import` and `--no-login`), `login`, `list`, `use`, `default`, `current`,
  `run`, `env`, `rename`, `remove`, `sync`, `doctor`, `init`, `version`.
- A `claude` shim that resolves the account per process, per shell or per machine.
- Shared `~/.claude` state across accounts (sessions, history, settings, skills, plugins …)
  with per-account credentials and `.claude.json`.
- `install.sh` for one-line install and update.
- Smoke tests against a fake `claude`, and CI with ShellCheck.
