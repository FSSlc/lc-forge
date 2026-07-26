#!/usr/bin/env bash
# Shared helpers for lc-forge scripts. Source this file; do not execute it.

_SCRIPTS_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${_SCRIPTS_COMMON_DIR}/../.." && pwd)"
DEFAULT_CHANNEL="${DEFAULT_CHANNEL:-https://prefix.dev/scns}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output}"

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: required command not found: $cmd" >&2
      return 1
    fi
  done
}

# Resolve a recipe directory to an absolute path under or outside the repo.
# Relative paths are resolved from REPO_ROOT.
resolve_recipe_dir() {
  local input="$1"
  local d

  if [[ -z "$input" ]]; then
    echo "Error: recipe directory is required" >&2
    return 1
  fi

  if [[ "$input" == /* ]]; then
    d="$input"
  else
    d="$REPO_ROOT/$input"
  fi

  if [[ ! -d "$d" ]]; then
    echo "Error: not a directory: $input" >&2
    return 1
  fi

  (cd "$d" && pwd)
}

fix_output_owner() {
  if [[ ! -d "$OUTPUT_DIR" || "${EUID:-$(id -u)}" -ne 0 ]]; then
    return 0
  fi

  # -h: do not follow symbolic links (prevents chown on files outside OUTPUT_DIR)
  chown -Rh "${HOST_UID:-1000}:${HOST_GID:-1000}" "$OUTPUT_DIR"
}

# Print channels from EXTRA_CHANNELS (space- and/or comma-separated).
extra_channels_from_env() {
  local raw="${EXTRA_CHANNELS:-}"
  local -a parts=()
  local part

  # Normalize commas to spaces, then split via read to avoid glob expansion
  raw="${raw//,/ }"
  read -ra parts <<<"$raw"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] && printf '%s\n' "$part"
  done
}

# Populate CHANNEL_ARGS with "-c <channel>" pairs:
# DEFAULT_CHANNEL, then EXTRA_CHANNELS, then any channels passed as arguments.
# Callers should expand "${CHANNEL_ARGS[@]}" into their command array.
CHANNEL_ARGS=()
build_channel_args() {
  local ch
  CHANNEL_ARGS=(-c "$DEFAULT_CHANNEL")

  while IFS= read -r ch; do
    [[ -n "$ch" ]] || continue
    CHANNEL_ARGS+=(-c "$ch")
  done < <(extra_channels_from_env)

  for ch in "$@"; do
    CHANNEL_ARGS+=(-c "$ch")
  done
}

# Convert meta.yaml -> recipe.yaml atomically.
# Succeeds only when crm exits 0 and stderr is empty or reports "0 errors".
# Temp files are cleaned up via EXIT trap even on interrupt.
crm_convert() {
  local meta_file="$1"
  local recipe_file="$2"
  local stderr_file recipe_tmp rc=0
  local _prev_trap _success=false

  if [[ ! -f "$meta_file" ]]; then
    echo "Missing meta.yaml: $meta_file" >&2
    return 1
  fi

  require_cmd crm || return 1

  stderr_file="$(mktemp)"
  recipe_tmp="$(mktemp)"

  # Save previous EXIT trap and install temp-file cleanup
  _prev_trap=$(trap -p EXIT)
  trap 'rm -f "$stderr_file" "$recipe_tmp"' EXIT

  # || rc=$? captures the exit code without leaking set -e state changes
  crm convert "$meta_file" >"$recipe_tmp" 2>"$stderr_file" || rc=$?

  if [[ -s "$stderr_file" ]]; then
    cat "$stderr_file" >&2
  fi

  # Success: stderr reports "0 errors", or rc == 0 with clean stderr.
  # crm may exit non-zero when warnings exist, but "0 errors" means the
  # conversion itself succeeded.
  if grep -q '0 errors' "$stderr_file" 2>/dev/null; then
    mv "$recipe_tmp" "$recipe_file"
    rm -f "$stderr_file"
    _success=true
  elif [[ $rc -eq 0 && ! -s "$stderr_file" ]]; then
    mv "$recipe_tmp" "$recipe_file"
    rm -f "$stderr_file"
    _success=true
  else
    rm -f "$stderr_file" "$recipe_tmp"
  fi

  # Restore previous EXIT trap
  if [[ -n "$_prev_trap" ]]; then
    eval "$_prev_trap"
  else
    trap - EXIT
  fi

  if $_success; then
    return 0
  fi
  if [[ $rc -ne 0 ]]; then
    return "$rc"
  fi
  return 1
}
