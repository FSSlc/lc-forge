#!/bin/bash
set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

BASHRC="$HOME/.bashrc"
# shellcheck disable=SC2016 # Keep command substitution literal for future shell startup.
COMPLETION_LINE='eval "$(pixi completion --shell bash)"'
INSTALLER="$(mktemp)"
PIXI_BIN="$HOME/.pixi/bin/pixi"
PIXI_INSTALL_URL="https://pixi.sh/install.sh"
TOOLS=(
  rattler-build
  conda-recipe-manager
  rattler-index
  conda
  conda-build
)

cleanup() {
  rm -f "$INSTALLER"
}
trap cleanup EXIT

curl -fsSL "$PIXI_INSTALL_URL" -o "$INSTALLER"
sh "$INSTALLER"

touch "$BASHRC"
if ! grep -Fxq "$COMPLETION_LINE" "$BASHRC"; then
  printf '%s\n' "$COMPLETION_LINE" >> "$BASHRC"
fi

"$PIXI_BIN" global install -e tools "${TOOLS[@]}"
