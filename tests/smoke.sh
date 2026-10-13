#!/usr/bin/env bash
# Smoke tests for cam. Uses a fake `claude` binary, so no network or login is
# needed. Run from the repository root:  ./tests/smoke.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export CAM_HOME="$HOME/.cam"
export SHELL=/bin/bash
unset CAM_ACCOUNT CAM_ACCOUNT_ACTIVE CAM_SHELL_INIT CLAUDE_CONFIG_DIR
# File-based logins by default, so a macOS run never touches the real Keychain.
export CAM_KEYCHAIN=0
mkdir -p "$HOME/.claude" "$SANDBOX/fakebin"

# A fake claude: reports which config dir it was given, and "logs in" by
# writing credentials and an oauthAccount, like the real one does.
cat > "$SANDBOX/fakebin/claude" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "auth" && "${2:-}" == "login" ]]; then
  echo '{"token":"fake"}' > "$CLAUDE_CONFIG_DIR/.credentials.json"
  python3 - "$CLAUDE_CONFIG_DIR/.claude.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["oauthAccount"] = {"emailAddress": "new@example.com"}
json.dump(d, open(p, "w"))
PY
  exit 0
fi
[[ "${1:-}" == "--version" ]] && { echo "0.0.0 (fake)"; exit 0; }
mkdir -p "$CLAUDE_CONFIG_DIR/projects/demo"
echo '{}' > "$CLAUDE_CONFIG_DIR/projects/demo/session-$$.jsonl"
echo "config=$CLAUDE_CONFIG_DIR account=${CAM_ACCOUNT_ACTIVE:-} args=$*"
EOF
chmod +x "$SANDBOX/fakebin/claude"

# A fake macOS `security`: one file per Keychain service under $SANDBOX/keychain.
mkdir -p "$SANDBOX/keychain"
cat > "$SANDBOX/fakebin/security" <<EOF
#!/usr/bin/env bash
kc="$SANDBOX/keychain"
EOF
cat >> "$SANDBOX/fakebin/security" <<'EOF'
svc="" show=0 hex=""
parse() { while (($#)); do case "$1" in -s) svc="$2"; shift ;; -X) hex="$2"; shift ;; -a) shift ;; -w) show=1 ;; esac; shift; done; }
cmd="${1:-}"; shift || true
case "$cmd" in
  -i) read -r line; eval "set -- $line"; cmd="$1"; shift; parse "$@"
      [[ "$cmd" == add-generic-password ]] || exit 1
      printf '%b' "$(sed 's/../\\x&/g' <<<"$hex")" > "$kc/$svc" ;;
  find-generic-password) parse "$@"; [[ -f "$kc/$svc" ]] || exit 44; if ((show)); then cat "$kc/$svc"; echo; fi ;;
  delete-generic-password) parse "$@"; [[ -f "$kc/$svc" ]] || exit 44; rm -f "$kc/$svc" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$SANDBOX/fakebin/security"
export PATH="$SANDBOX/fakebin:$PATH"

# An existing Claude Code login to import.
echo '{"token":"existing"}' > "$HOME/.claude/.credentials.json"
echo '{"oauthAccount":{"emailAddress":"me@example.com"},"mcpServers":{"x":{}}}' > "$HOME/.claude.json"
echo '{}' > "$HOME/.claude/settings.json"

"$ROOT/install.sh" >/dev/null
eval "$("$CAM_HOME/bin/cam" init bash)"

pass=0
check() { # check <description> <command…>
  local desc="$1"; shift
  if "$@"; then pass=$((pass + 1)); echo "ok   $desc"; else echo "FAIL $desc" >&2; exit 1; fi
}
contains() { grep -q -- "$2" <<<"$1"; }
real() { [[ -e "$1" && ! -L "$1" ]]; }  # exists and is not a symlink

check "cam is on PATH as the shim" [ "$(command -v claude)" = "$CAM_HOME/bin/claude" ]
check "version prints" contains "$(cam version)" "cam "

cam add personal --import 2>/dev/null
check "import copies credentials" grep -q existing "$CAM_HOME/accounts/personal/.credentials.json"
check "first account becomes default" [ "$(cam default)" = personal ]
check "list shows the email" contains "$(cam list)" "me@example.com"

cam add work 2>/dev/null
check "new account logs in" grep -q fake "$CAM_HOME/accounts/work/.credentials.json"
check "new account seeds MCP servers" grep -q mcpServers "$CAM_HOME/accounts/work/.claude.json"
check "new account drops the old identity" bash -c "! grep -q me@example.com '$CAM_HOME/accounts/work/.claude.json'"
check "projects is shared" [ -L "$CAM_HOME/accounts/work/projects" ]
check "settings.json is shared" [ -L "$CAM_HOME/accounts/work/settings.json" ]
check "credentials are private" [ ! -L "$CAM_HOME/accounts/work/.credentials.json" ]

out="$(claude --print hi)"
check "plain claude uses the default" contains "$out" "accounts/personal"

cam use work >/dev/null
out="$(claude)"
check "cam use switches the shell" contains "$out" "accounts/work"

cam use --default >/dev/null
out="$(claude)"
check "cam use --default clears it" contains "$out" "accounts/personal"

out="$(cam run work --resume)"
check "cam run picks the account and passes args" contains "$out" "accounts/work.*args=--resume"

check "sessions from both accounts land in ~/.claude" \
  [ "$(find "$HOME/.claude/projects/demo" -name '*.jsonl' | wc -l)" -ge 4 ]

out="$(CAM_ACCOUNT_ACTIVE=work claude)"
check "child claude processes keep their account" contains "$out" "accounts/work"

cam default work >/dev/null 2>&1
check "cam default sets the default" [ "$(cam default)" = work ]

cam rename work job 2>/dev/null
check "rename carries the default" [ "$(cam default)" = job ]

cam remove job -y 2>/dev/null
check "remove deletes the account" [ ! -d "$CAM_HOME/accounts/job" ]
check "remove keeps shared sessions" [ -d "$HOME/.claude/projects/demo" ]

# Isolated sessions: one account keeps its sessions out of the shared pool.
cam add solo --no-login --isolate-sessions 2>/dev/null
solo="$CAM_HOME/accounts/solo"
check "isolated account owns its projects" real "$solo/projects"
check "isolated account owns its history" real "$solo/history.jsonl"
check "isolated account still shares settings" [ -L "$solo/settings.json" ]
check "isolated account still shares skills" [ -L "$solo/skills" ]
check "list marks the isolated account" contains "$(cam list)" "isolated"

shared_before="$(find "$HOME/.claude/projects" -name '*.jsonl' | wc -l)"
cam run solo >/dev/null
check "isolated session stays out of ~/.claude" \
  [ "$(find "$HOME/.claude/projects" -name '*.jsonl' | wc -l)" -eq "$shared_before" ]
check "isolated session lands in the account" \
  [ "$(find "$solo/projects" -name '*.jsonl' | wc -l)" -eq 1 ]
cam sync 2>/dev/null
check "sync keeps the account isolated" real "$solo/projects"

echo '{"display":"solo prompt"}' > "$solo/history.jsonl"
cam isolate solo --off 2>/dev/null
check "isolate --off links projects again" [ -L "$solo/projects" ]
check "isolate --off merges isolated sessions" \
  [ "$(find "$HOME/.claude/projects" -name '*.jsonl' | wc -l)" -eq "$((shared_before + 1))" ]
check "isolate --off merges prompt history" grep -q "solo prompt" "$HOME/.claude/history.jsonl"

cam isolate personal 2>/dev/null
check "isolate turns an existing account private" real "$CAM_HOME/accounts/personal/projects"
check "isolating leaves shared sessions in place" [ -d "$HOME/.claude/projects/demo" ]
check "isolating starts with an empty session list" \
  [ "$(find "$CAM_HOME/accounts/personal/projects" -name '*.jsonl' | wc -l)" -eq 0 ]

# Tab completion: bash, driven the way readline would call it.
complete_words() { COMP_WORDS=("$@"); COMP_CWORD=$((${#COMP_WORDS[@]} - 1)); _cam_complete; echo "${COMPREPLY[*]}"; }
check "list --names prints bare names" [ "$(cam list --names | tr '\n' ' ')" = "personal solo " ]
check "completion offers subcommands" contains "$(complete_words cam is)" "isolate"
check "completion offers account names" [ "$(complete_words cam use so)" = solo ]
check "completion offers --default for use" contains "$(complete_words cam use '')" "--default"
check "completion offers add flags" contains "$(complete_words cam add --)" "--isolate-sessions"
check "completion stops after the account for run" [ -z "$(complete_words cam run solo '')" ]
if command -v zsh >/dev/null; then
  check "zsh completion registers" contains \
    "$(zsh -fc 'eval "$("$1" init zsh)"; print -r -- "$_comps[cam]"' _ "$CAM_HOME/bin/cam")" "_cam"
fi

# macOS: the login lives in the Keychain, keyed by the config directory.
kc_svc() { printf 'Claude Code-credentials-%s' "$(printf '%s' "$CAM_HOME/accounts/$1" | shasum -a 256 | cut -c1-8)"; }
export CAM_KEYCHAIN=1
mv "$HOME/.claude/.credentials.json" "$SANDBOX/credentials.bak"
cam add mac --import --no-login 2>/dev/null && kc_ok=1 || kc_ok=0
check "keychain: import fails cleanly with no login" [ "$kc_ok" = 0 ]
check "keychain: failed import leaves no account" [ ! -d "$CAM_HOME/accounts/mac" ]
echo '{"token":"from-keychain"}' > "$SANDBOX/keychain/Claude Code-credentials"
cam add mac --import 2>/dev/null
check "keychain: import copies the login item" grep -q from-keychain "$SANDBOX/keychain/$(kc_svc mac)"
check "keychain: import writes no credentials file" [ ! -e "$CAM_HOME/accounts/mac/.credentials.json" ]
check "keychain: list shows the account logged in" bash -c "! cam list | grep '^. *mac ' | grep -q no-login"
cam rename mac mac2 2>/dev/null
check "keychain: rename moves the login item" grep -q from-keychain "$SANDBOX/keychain/$(kc_svc mac2)"
check "keychain: rename drops the old item" [ ! -e "$SANDBOX/keychain/$(kc_svc mac)" ]
cam remove mac2 -y 2>/dev/null
check "keychain: remove deletes the login item" [ ! -e "$SANDBOX/keychain/$(kc_svc mac2)" ]
mv "$SANDBOX/credentials.bak" "$HOME/.claude/.credentials.json"
export CAM_KEYCHAIN=0

check "unknown account fails" bash -c "! cam run nope 2>/dev/null"
check "isolate on an unknown account fails" bash -c "! cam isolate nope 2>/dev/null"

echo "$pass checks passed"
