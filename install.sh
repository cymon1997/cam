#!/usr/bin/env bash
# Install or update cam.
#
#   curl -fsSL https://raw.githubusercontent.com/cymon1997/cam/main/install.sh | bash
#   ./install.sh            # from a local clone
#
# Environment:
#   CAM_HOME   where cam lives (default: ~/.cam)
#   CAM_REF    git ref to install when downloading (default: main)
set -euo pipefail

CAM_HOME="${CAM_HOME:-$HOME/.cam}"
CAM_REF="${CAM_REF:-main}"
RAW="https://raw.githubusercontent.com/cymon1997/cam/$CAM_REF/cam"

mkdir -p "$CAM_HOME/bin" "$CAM_HOME/accounts"

src_dir=""
# Piped through `curl | bash` there is no script file, so always download.
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -n "$src_dir" && -f "$src_dir/cam" && -f "$src_dir/install.sh" ]]; then
  cp "$src_dir/cam" "$CAM_HOME/bin/cam.new"
  echo "Installing cam from $src_dir"
else
  command -v curl >/dev/null || { echo "install.sh: curl is required" >&2; exit 1; }
  curl -fsSL "$RAW" -o "$CAM_HOME/bin/cam.new"
  echo "Downloaded cam ($CAM_REF)"
fi
chmod 755 "$CAM_HOME/bin/cam.new"
mv "$CAM_HOME/bin/cam.new" "$CAM_HOME/bin/cam"
ln -sfn cam "$CAM_HOME/bin/claude"

echo "Installed $("$CAM_HOME/bin/cam" version) to $CAM_HOME/bin"

rc=""
case "$(basename "${SHELL:-}")" in
  zsh) rc="$HOME/.zshrc" ;;
  bash) rc="$HOME/.bashrc" ;;
esac

if [[ -n "$rc" ]] && grep -q 'cam init' "$rc" 2>/dev/null; then
  echo "Shell integration already present in $rc."
else
  cat <<EOF

Next, enable shell integration by adding this line to ${rc:-your shell rc}:

  eval "\$($CAM_HOME/bin/cam init)"

then open a new shell and register your first account:

  cam add personal --import   # reuse the login Claude Code already has
  cam add work                # or log a new account in
EOF
fi
