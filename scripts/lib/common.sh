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
  local part

  # Normalize commas to spaces
  raw="${raw//,/ }"
  # Short-circuit when empty to avoid unbound-variable issues with set -u
  [[ -z "$raw" ]] && return 0

  local -a parts=()
  # Split via read to avoid glob expansion
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

# 从 recipe 目录读取可选 args.txt（若存在）。
# [env] 段：每行 NAME=VALUE，导出为环境变量（覆盖继承值）。
# [args] 段：每行一个参数，写入 RECIPE_EXTRA_ARGS 数组。
# 空行与 # 注释忽略；无效行告警并跳过。
RECIPE_EXTRA_ARGS=()
load_recipe_args() {
  local recipe_dir="$1"
  local file="$recipe_dir/args.txt"
  RECIPE_EXTRA_ARGS=()
  [[ -f "$file" ]] || return 0

  local section="" line name value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == \[env\] ]]; then section=env; continue; fi
    if [[ "$line" == \[args\] ]]; then section=args; continue; fi
    case "$section" in
      env)
        name="${line%%=*}"
        if [[ "$name" == "$line" || ! "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
          echo "Warning: 忽略 args.txt 无效 env 行: $line" >&2
          continue
        fi
        value="${line#*=}"
        export "$name=$value"
        ;;
      args) RECIPE_EXTRA_ARGS+=("$line") ;;
      *) echo "Warning: 忽略 args.txt 中无段落标记的行: $line" >&2 ;;
    esac
  done <"$file"
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

  # Success requires a non-empty result on stdout. crm prints
  # "0 errors and 0 warnings were found." to stderr even when it aborts, so
  # checking stderr alone would install a zero-byte recipe.yaml, which then
  # makes rattler-build fail with "missing required field 'package'".
  # crm may exit non-zero when warnings exist, but "0 errors" means the
  # conversion itself succeeded.
  if [[ -s "$recipe_tmp" ]] &&
    { grep -q '0 errors' "$stderr_file" 2>/dev/null ||
      [[ $rc -eq 0 && ! -s "$stderr_file" ]]; }; then
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

# ---------------------------------------------------------------------------
# 构建 + AI 失败修复（rbuild.sh / cbuild.sh 共用）
# ---------------------------------------------------------------------------

# AI 配置来源：真实环境变量优先，其次仓库根 .env（示例见 .env.example）。
# 只认下列四个键，避免 .env 意外影响其它环境变量；无 .env 时静默返回。
load_ai_env_file() {
  local file="$REPO_ROOT/.env"
  local line key value

  [[ -f "$file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    # 去掉行首空白，跳过空行与整行注释
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
      '' | '#'*) continue ;;
    esac
    line="${line#export }"
    key="${line%%=*}"
    # 没有 = 的行不是赋值，忽略
    [[ "$key" == "$line" ]] && continue
    value="${line#*=}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    # 已有值（来自真实环境变量）不覆盖
    case "$key" in
      AI_API_BASE_URL) [[ -n "${AI_API_BASE_URL:-}" ]] || AI_API_BASE_URL="$value" ;;
      AI_API_KEY) [[ -n "${AI_API_KEY:-}" ]] || AI_API_KEY="$value" ;;
      AI_MODEL_NAME) [[ -n "${AI_MODEL_NAME:-}" ]] || AI_MODEL_NAME="$value" ;;
      AI_MAX_FIX_ROUNDS) [[ -n "${AI_MAX_FIX_ROUNDS:-}" ]] || AI_MAX_FIX_ROUNDS="$value" ;;
    esac
  done <"$file"
  return 0
}

load_ai_env_file

# 构建失败后最多调用 AI 修复的次数上限（含首次构建），默认 3。
# 与 import_recipe.py 的 AI_MAX_FIX_ROUNDS 同名同义。
AI_FIX_ROUNDS="${AI_MAX_FIX_ROUNDS:-3}"

# 调用方把完整构建命令放进该数组后调用 run_build_with_ai_fix。
BUILD_CMD=()

# AI 三件套是否齐备；不齐备时只报告构建失败，不调用 AI。
ai_configured() {
  [[ -n "${AI_API_BASE_URL:-}" && -n "${AI_API_KEY:-}" && -n "${AI_MODEL_NAME:-}" ]]
}

# 为一次构建分配日志路径：logs/build-<name>-<时间戳>.log（同秒重名时追加序号）。
make_build_log_path() {
  local name="$1"
  local dir="$REPO_ROOT/logs"
  local stamp candidate n=1
  stamp="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dir"
  candidate="$dir/build-$name-$stamp.log"
  while [[ -e "$candidate" ]]; do
    n=$((n + 1))
    candidate="$dir/build-$name-$stamp-$n.log"
  done
  printf '%s\n' "$candidate"
}

# 跑一次构建，输出同时写入日志文件（AI 需要日志尾部）。
_run_build_attempt() {
  local log_file="$1"
  local build_status
  "${BUILD_CMD[@]}" 2>&1 | tee "$log_file"
  # 紧跟管道读取，赋值命令本身不会覆盖它。
  build_status="${PIPESTATUS[0]}"
  return "$build_status"
}

# 请 AI 修一轮。退出码：0=已改文件，2=没有可用改动，其它=出错。
_ai_fix_round() {
  local recipe_dir="$1"
  local log_file="$2"
  python3 "$REPO_ROOT/scripts/import_recipe.py" \
    --fix-build "$recipe_dir" --fix-build-log "$log_file"
}

# run_build_with_ai_fix <recipe_dir> <log_file> <interactive:true|false> [rounds]
# 构建失败时调用 AI 修改 recipe 后重建，最多 rounds 次构建。
# interactive=true 时每轮修复前用 read 确认；否则直接调用 AI。
# 返回最后一次构建的退出码；AI 改动最终没能让构建通过时回滚。
run_build_with_ai_fix() {
  local recipe_dir="$1"
  local log_file="$2"
  local interactive="$3"
  local rounds="${4:-$AI_FIX_ROUNDS}"
  local backup_file="${log_file}.ai-fix-backup.json"
  local attempt=1 build_status=0 fix_status=0 answer="" ai_touched=false

  while :; do
    build_status=0
    _run_build_attempt "$log_file" || build_status=$?
    if [[ "$build_status" -eq 0 ]]; then
      rm -f "$backup_file"
      return 0
    fi
    if ((attempt >= rounds)); then
      echo "构建失败已达 $rounds 次上限，停止。" >&2
      break
    fi
    if [[ ! -f "$recipe_dir/recipe.yaml" ]]; then
      echo "AI 修复只支持单个 recipe 目录（$recipe_dir 无 recipe.yaml），跳过。" >&2
      break
    fi
    if ! ai_configured; then
      echo "AI 修复已跳过：未设置 AI_API_BASE_URL / AI_API_KEY / AI_MODEL_NAME。" >&2
      break
    fi
    if $interactive; then
      printf '第 %d/%d 次构建失败。调用 AI 修复 %s？[y/N] ' \
        "$attempt" "$rounds" "$recipe_dir" >&2
      read -r answer || answer=""
      case "$answer" in
        [yY] | [yY][eE][sS]) ;;
        *)
          echo "已取消 AI 修复，保留原始构建错误。" >&2
          break
          ;;
      esac
    fi

    echo "第 $attempt/$rounds 次构建失败，请求 AI 修复 $recipe_dir ..." >&2
    fix_status=0
    _ai_fix_round "$recipe_dir" "$log_file" || fix_status=$?
    if [[ "$fix_status" -eq 2 ]]; then
      echo "AI 未提出可用改动，保留原始构建错误。" >&2
      break
    fi
    if [[ "$fix_status" -ne 0 ]]; then
      echo "AI 修复失败（退出码 $fix_status），保留原始构建错误。" >&2
      break
    fi
    ai_touched=true
    attempt=$((attempt + 1))
  done

  if $ai_touched && [[ -f "$backup_file" ]]; then
    echo "AI 改动未能让 $recipe_dir 构建通过，回滚到修复前内容。" >&2
    python3 "$REPO_ROOT/scripts/import_recipe.py" --revert-fix "$backup_file" >&2 || true
  fi
  return "$build_status"
}
