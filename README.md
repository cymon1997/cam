# cam — Claude Account Manager

[![CI](https://github.com/cymon1997/cam/actions/workflows/ci.yml/badge.svg)](https://github.com/cymon1997/cam/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Use several [Claude Code](https://docs.claude.com/en/docs/claude-code/overview) accounts on one
machine and switch between them in one command, much like
[sdkman](https://sdkman.io) does for SDK versions.

```console
$ cam list
> personal         default             me@example.com
  work                                 me@company.com / Company Inc.

$ cam use work
work  (shell (CAM_ACCOUNT))  me@company.com / Company Inc.

$ claude            # now runs as work
$ claude --resume   # every session from every account is listed
```

- **Register as many accounts as you like.** Each one logs in once, and cam keeps its credentials.
- **Switch per shell, per command, or for the whole machine.** Use `cam use`, `cam run` or
  `cam default`.
- **Sessions are shared.** Conversations, history, settings, skills, agents, plugins and hooks
  live in one place, so any account can resume a session started by another one.
- **Or keep one account's sessions apart.** `cam isolate <name>` gives an account its own
  sessions and prompt history, while it still shares settings, skills and plugins.
- **Plain `claude` still works.** A small shim picks the right account, so your scripts, aliases
  and IDE integrations keep working.
- **A single bash script with no dependencies** beyond `bash` and `python3`, which reads the
  account email.

## Contents

- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Tutorial](#tutorial)
- [Command reference](#command-reference)
- [Recipes](#recipes)
- [What is shared and what is not](#what-is-shared-and-what-is-not)
- [Troubleshooting](#troubleshooting)
- [Uninstalling](#uninstalling)
- [Contributing](#contributing)
- [License](#license)

## How it works

Claude Code reads its login and state from a config directory. That directory is `~/.claude` by
default, and you can point it elsewhere with the `CLAUDE_CONFIG_DIR` environment variable. cam
gives every account its own config directory. Inside it, every entry except the login is a
symlink back to the shared `~/.claude`:

```
~/.cam/
├── bin/
│   ├── cam
│   └── claude -> cam           the shim: picks an account, then runs the real claude
├── default                      name of the default account
└── accounts/
    ├── personal/                CLAUDE_CONFIG_DIR for "personal"
    │   ├── .credentials.json    ← this account's login (private)
    │   ├── .claude.json         ← this account's identity, MCP servers, project trust (private)
    │   ├── projects -> ~/.claude/projects        ← sessions (shared)
    │   ├── history.jsonl -> ~/.claude/history.jsonl
    │   ├── settings.json -> ~/.claude/settings.json
    │   └── skills, agents, plugins, hooks, todos, plans … -> ~/.claude/…
    └── work/
        └── …same shape…
```

When you run `claude`, the shim at `~/.cam/bin/claude` resolves an account in this order:

1. `CAM_ACCOUNT_ACTIVE`, which cam sets on every `claude` it launches. Subagents and other child
   processes therefore keep their parent's account.
2. `CAM_ACCOUNT`, which `cam use` sets for the current shell.
3. The default account, set with `cam default`.

The shim refreshes the symlinks, sets `CLAUDE_CONFIG_DIR` and `exec`s the real `claude` binary.
If no account is registered, the shim passes straight through and Claude Code behaves as if cam
were not there.

## Requirements

- Linux. macOS should work but is not tested yet; see the
  [macOS note](#macos-and---import).
- `bash` 4 or later, `python3`, and `curl` for the one-line installer.
- [Claude Code](https://docs.claude.com/en/docs/claude-code/setup) installed and on your `PATH`.

## Installation

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/cymon1997/cam/main/install.sh | bash
```

### From a clone

```bash
git clone https://github.com/cymon1997/cam.git
cd cam
./install.sh
```

Both methods install to `~/.cam/bin`. Set `CAM_HOME` to install somewhere else. To update, run
the installer again. Your accounts are left alone.

### Enable shell integration

Add this line to `~/.zshrc` or `~/.bashrc`, then open a new shell:

```bash
eval "$(~/.cam/bin/cam init)"
```

This line does three things:

- puts `~/.cam/bin` first on your `PATH`, so `claude` goes through the shim;
- puts `cam` itself on your `PATH`;
- defines a small `cam` shell function, so `cam use` can change the current shell;
- turns on tab completion for subcommands, flags and your registered account names, so
  `cam use wo<Tab>` completes to `cam use work`. Names are read on every <Tab>, so a newly
  added account completes straight away.

Check the setup:

```bash
cam doctor
```

## Tutorial

This walkthrough takes you from one existing login to two accounts that share every session.

### 1. Keep the login you already have

If Claude Code is already logged in, import that login as your first account. The first account
you add becomes the default.

```console
$ cam add personal --import
Imported the current login into 'personal' (me@example.com).
'personal' is now the default.
```

### 2. Add a second account

```console
$ cam add work
Created account 'work'.
Starting login for 'work' …
```

Claude Code's normal login flow opens. Sign in with the other account. Your MCP servers and
trusted projects are copied over from your main config, so the new account is ready right away.

```console
$ cam list
> personal         default             me@example.com
  work                                 me@company.com / Company Inc.
```

### 3. Switch the current shell

```console
$ cam use work
work  (shell (CAM_ACCOUNT))  me@company.com / Company Inc.
$ claude
```

The switch only affects this shell. Other terminals keep using the default. Run
`cam use --default` to go back.

### 4. Run one command as another account

You don't need to switch to run something once as another account:

```bash
cam run personal                 # interactive session
cam run personal -p "summarise CHANGELOG.md"
cam run work --resume            # pick any session, then continue it as work
```

### 5. Change the machine-wide default

```console
$ cam default work
Default account: work
```

New terminals, editors and scripts that call `claude` now use `work`.

### 6. Continue a session with a different account

Sessions live in the shared `~/.claude/projects`, so a session is not tied to any account. If one
account hits its usage limit in the middle of a task, continue with another:

```bash
cam use personal
claude --continue      # most recent session in this directory, now as personal
```

### 7. Keep one account's sessions to itself

Sharing everything is the default. If an account's work must not show up in the other
accounts' `--resume` list, for example a client account, isolate it:

```console
$ cam isolate client
'client' now keeps its sessions to itself. It starts with an empty session list;
sessions in /home/me/.claude stay there for the other accounts.

$ cam list
> personal         default             me@example.com
  client                              me@client.com  [isolated]
```

You can also isolate an account when you create it with `cam add client --isolate-sessions`.

An isolated account keeps its own `projects/`, `sessions/`, `history.jsonl`, `file-history/`,
`todos/`, `plans/`, `session-env/`, `shell-snapshots/` and `paste-cache/`. Settings, `CLAUDE.md`,
skills, agents, commands, plugins and hooks are still shared. Per-project auto-memory lives
under `projects/`, so it is isolated too.

`cam isolate client --off` shares the account again. Its sessions are merged into the shared
pool, and its prompt history is appended to the shared one.

## Command reference

| Command | What it does |
|---|---|
| `cam add <name>` | Register an account and start its login. |
| `cam add <name> --import` | Register an account using the login currently in `~/.claude`. |
| `cam add <name> --no-login` | Register an account without logging in yet. |
| `cam add <name> --isolate-sessions` | Register an account whose sessions are not shared. Combines with the flags above. |
| `cam login <name>` | Log an account in again, for example after its token expires. |
| `cam list` | List accounts with their email and organisation. `>` marks the active account and `default` marks the default. |
| `cam list --names` | Print account names only, one per line. Used by tab completion; handy in scripts. |
| `cam use <name>` | Use `<name>` in this shell. |
| `cam use --default` | Clear the shell override and fall back to the default. |
| `cam default [name]` | Show the machine-wide default, or set it. |
| `cam current` | Show which account a plain `claude` would use right now, and why. |
| `cam run <name> [args…]` | Run `claude [args…]` once as `<name>`. |
| `cam env [name]` | Print `export CLAUDE_CONFIG_DIR=…` for use in scripts. |
| `cam rename <old> <new>` | Rename an account. The default follows it. |
| `cam remove <name> [-y]` | Delete an account's login. Shared sessions are kept. An isolated account's own sessions are deleted with it. |
| `cam isolate <name>` | Stop sharing `<name>`'s sessions and prompt history with other accounts. |
| `cam isolate <name> --off` | Share them again. The account's isolated sessions are merged into `~/.claude`. |
| `cam sync` | Refresh the shared symlinks for every account. |
| `cam doctor` | Show paths, the real `claude` binary, the shim state and the accounts. |
| `cam init [zsh\|bash]` | Print the shell integration snippet, including tab completion. |
| `cam version` | Print the cam version. |

### Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `CAM_HOME` | `~/.cam` | Where cam keeps its binary and accounts. |
| `CAM_SHARED_DIR` | `~/.claude` | The directory whose state every account shares. |
| `CAM_CLAUDE_BIN` | first `claude` on `PATH` that is not the shim | Path to the real Claude Code binary. |
| `CAM_ACCOUNT` | *(unset)* | Account for this shell. Set by `cam use`. |

## Recipes

**Two accounts side by side.** Accounts are separate config directories, so they can run at the
same time:

```bash
# terminal 1          # terminal 2
cam run personal      cam run work
```

**An account per project with [direnv](https://direnv.net).** Add an `.envrc` to the project:

```bash
export CAM_ACCOUNT=work
```

**Scripts and CI-like jobs.** Pin an account without the shim:

```bash
eval "$(cam env work)"
claude -p "…"
```

**Aliases:**

```bash
alias cw='cam run work'
alias cp1='cam run personal'
```

## What is shared and what is not

| Shared through `~/.claude` | Private to each account |
|---|---|
| `projects/`: session transcripts, `--resume` and `--continue` | `.credentials.json`: the login |
| `history.jsonl`: prompt history | `.claude.json`: identity, user-scope MCP servers, per-project trust |
| `settings.json`, `CLAUDE.md`, `keybindings.json` | caches, telemetry, stats, policy limits |
| `skills/`, `agents/`, `commands/`, `plugins/`, `hooks/`, `output-styles/` | the background daemon's state |
| `todos/`, `plans/`, `file-history/`, `shell-snapshots/`, `session-env/`, `ide/` | |

Anything Claude Code adds to `~/.claude` in a future version is shared automatically, unless it is
on the private list at the top of the `cam` script.

**Isolated accounts.** For an account under `cam isolate`, the session entries move to the
private column: `projects/`, `sessions/`, `history.jsonl`, `file-history/`, `todos/`, `plans/`,
`session-env/`, `shell-snapshots/` and `paste-cache/`. The list is `ISOLATED_DIRS` /
`ISOLATED_FILES` at the top of the `cam` script.

**Note on `.claude.json`.** This file mixes account identity with user-scope MCP servers and
project trust, so each account keeps its own copy. A new account starts with a copy of your main
`~/.claude.json`, minus the identity fields. An MCP server you add later with
`claude mcp add --scope user` is only added to the account you ran it under. Project-scope MCP
servers in `.mcp.json` are unaffected.

## Troubleshooting

**`claude` ignores `cam use`.** The shim is not first on your `PATH`. Run `cam doctor`. If it
reports `shim on PATH no`, add `eval "$(~/.cam/bin/cam init)"` to your shell rc and open a new
shell.

**`cam use` prints an `export …` line instead of switching.** The shell function is not loaded,
because a program cannot change its parent shell's environment by itself. Either load the shell
integration, or run `eval "$(cam use work)"`.

**An account says it is logged out.** Run `cam login <name>`.

**After `--import`, plain `~/.claude` asks me to log in again.** Importing copies your login into
the account. When the account refreshes its token, the old copy in `~/.claude` can stop working.
That copy is only used if you bypass cam, so either keep using cam or run `/login` there.

**I want to see what cam would run.** `cam current` shows the account and `cam doctor` shows the
real binary. `cam env <name>` prints the exact `CLAUDE_CONFIG_DIR`.

### macOS and `--import`

On macOS, Claude Code stores credentials in the Keychain instead of `~/.claude/.credentials.json`,
so `cam add <name> --import` has nothing to copy. Use `cam add <name>` and log in again instead.
Feedback from macOS users is welcome. Please open an issue.

## Uninstalling

```bash
# 1. Remove the `eval "$(… cam init)"` line from your shell rc.
# 2. Delete cam and its account logins. Your sessions in ~/.claude are not touched.
rm -rf ~/.cam
```

## Contributing

Issues and pull requests are welcome.

```bash
./tests/smoke.sh                       # runs against a fake claude: no network, no login
shellcheck cam install.sh tests/*.sh   # must be clean
```

CI runs both on every push and pull request. Please keep cam a single, dependency-free bash
script.

## License

[MIT](LICENSE) © cymon1997

cam is a community tool. It is not affiliated with or endorsed by Anthropic.
