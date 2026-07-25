#!/bin/bash
set -Eeuo pipefail

# shellcheck disable=SC1091 # common.sh is sourced via a runtime-computed path
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"
cd "$REPO_ROOT" || exit 1

# shellcheck disable=SC2016 # Keep command substitution literal for future shell startup.
COMPLETION_LINE_BASH='eval "$(pixi completion --shell bash)"'
# shellcheck disable=SC2016
COMPLETION_LINE_ZSH='eval "$(pixi completion --shell zsh)"'
INSTALLER=""
PIXI_BIN="${PIXI_BIN:-$HOME/.pixi/bin/pixi}"
PIXI_INSTALL_URL="${PIXI_INSTALL_URL:-https://pixi.sh/install.sh}"
TOOLS=(
  rattler-build
  conda-recipe-manager
  rattler-index
  conda
  conda-build
)

usage() {
  local tool
  echo "Usage: $0 [-h]"
  echo "  Install pixi (if missing) and global tools used by this repo."
  echo
  echo "Tools installed into the pixi global env 'tools':"
  for tool in "${TOOLS[@]}"; do
    echo "  - $tool"
  done
  echo
  echo "Notes:"
  echo "  - Adds pixi shell completion to ~/.bashrc and/or ~/.zshrc when present."
  echo "  - Ensures ~/.pixi/bin is on PATH for the current shell and future logins."
  echo "  - Safe to re-run; existing pixi installs are reused."
  exit "${1:-1}"
}

cleanup() {
  if [[ -n "${INSTALLER:-}" ]]; then
    rm -f "$INSTALLER"
  fi
}
trap cleanup EXIT

ensure_path_export() {
  local rc_file="$1"
  # shellcheck disable=SC2016 # Literal $HOME/$PATH for the rc file, not current shell.
  local export_line='export PATH="$HOME/.pixi/bin:$PATH"'

  touch "$rc_file"
  if ! grep -Fq '.pixi/bin' "$rc_file"; then
    printf '%s\n' "$export_line" >>"$rc_file"
  fi
}

ensure_completion() {
  local rc_file="$1"
  local completion_line="$2"

  touch "$rc_file"
  if ! grep -Fxq "$completion_line" "$rc_file"; then
    printf '%s\n' "$completion_line" >>"$rc_file"
  fi
}

case "${1:-}" in
  -h|--help) usage 0 ;;
  "") ;;
  *)
    echo "Unknown argument: $1" >&2
    usage
    ;;
esac

require_cmd curl

export PATH="$HOME/.pixi/bin:${PATH:-}"

if [[ -x "$PIXI_BIN" ]]; then
  echo "pixi already installed: $PIXI_BIN"
else
  echo "Installing pixi from $PIXI_INSTALL_URL ..."
  INSTALLER="$(mktemp)"
  curl -fsSL "$PIXI_INSTALL_URL" -o "$INSTALLER"
  sh "$INSTALLER"
fi

if [[ ! -x "$PIXI_BIN" ]]; then
  echo "Error: pixi binary not found at $PIXI_BIN after install" >&2
  exit 1
fi

# bash
if [[ -f "$HOME/.bashrc" || "${SHELL:-}" == *bash* ]]; then
  ensure_path_export "$HOME/.bashrc"
  ensure_completion "$HOME/.bashrc" "$COMPLETION_LINE_BASH"
fi

# zsh
if [[ -f "$HOME/.zshrc" || "${SHELL:-}" == *zsh* ]]; then
  ensure_path_export "$HOME/.zshrc"
  ensure_completion "$HOME/.zshrc" "$COMPLETION_LINE_ZSH"
fi

# Always ensure bashrc path when neither rc exists yet (common on fresh users)
if [[ ! -f "$HOME/.bashrc" && ! -f "$HOME/.zshrc" ]]; then
  ensure_path_export "$HOME/.bashrc"
  ensure_completion "$HOME/.bashrc" "$COMPLETION_LINE_BASH"
fi

echo "Installing global tools into pixi env 'tools' ..."
"$PIXI_BIN" global install -e tools "${TOOLS[@]}"

echo
echo "Done. Current shell PATH already includes $HOME/.pixi/bin."
echo "Open a new shell, or run: source ~/.bashrc   # or ~/.zshrc"
