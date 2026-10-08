# Changelog

All notable changes to cam are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-10-09

### Added
- `cam add` (with `--import` and `--no-login`), `login`, `list`, `use`, `default`, `current`,
  `run`, `env`, `rename`, `remove`, `sync`, `doctor`, `init`, `version`.
- A `claude` shim that resolves the account per process, per shell or per machine.
- Shared `~/.claude` state across accounts (sessions, history, settings, skills, plugins …)
  with per-account credentials and `.claude.json`.
- `install.sh` for one-line install and update.
- Smoke tests against a fake `claude`, and CI with ShellCheck.
