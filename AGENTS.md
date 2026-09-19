# lc-forge

Personal conda/rattler-build recipe repository. Packages build into a custom
channel on prefix.dev (`scns`).

## Layout

- `recipes/` — successfully built recipes (no longer rebuilt by CI).
- `todo/` — recipes under active development. CI builds everything here on
  push/PR to `main` for `linux-64` and `linux-aarch64`.
- `only-meta.txt` — packages whose `meta.yaml` could **not** be auto-converted
  to `recipe.yaml`; CI builds them via `conda build` instead of `rattler-build`.
- `conda_build_config.yaml` — global build matrix, pinning, compiler versions
  (gcc 11, CentOS 7 sysroot / glibc 2.17).

## Workflow

1. `./scripts/prep.sh <pkg>` — clones conda-forge feedstock into `todo/<pkg>`,
   attempts `meta.yaml → recipe.yaml` conversion. Failing that, appends the
   package to `only-meta.txt` (no `recipe.yaml` is written).
2. Iterate in `todo/<pkg>`.
3. CI builds automatically on push/PR touching `todo/`. Successful builds are
   uploaded to `https://prefix.dev/scns`.
4. After CI succeeds, archive to `recipes/`:
   `mkdir -p recipes && git mv todo/<pkg> recipes/<pkg>`

## Commands

All scripts use `-r <recipe_dir>` (relative paths resolve from repo root).

| Task | Command |
|---|---|
| `meta.yaml` → `recipe.yaml` | `./scripts/crm.sh -r todo/<pkg>` |
| Render (conda) | `./scripts/crender.sh -r todo/<pkg>` |
| Render (rattler) | `./scripts/rrender.sh -r todo/<pkg>` |
| Build (conda) | `./scripts/cbuild.sh -r todo/<pkg>` |
| Build (rattler) | `./scripts/rbuild.sh -r todo/<pkg>` |
| Setup tools | `./scripts/setup_pixi.sh` |
| Docker env | `./scripts/start_img.sh` |

Flags: `-f` force rebuild, `-c <channel>` extra channels, `--` passthrough.
`EXTRA_CHANNELS` env var (space/comma-separated) adds channels without flags.

Docker container auto-injects `HOST_UID`/`HOST_GID`; build scripts call
`fix_output_owner` so `output/` files belong to the host user.

## Local build & debug

Local verification runs **inside Docker**, never on the macOS host:

| Platform | Container | rattler-build | Cost |
|---|---|---|---|
| linux-aarch64 | `pixi` (`./scripts/start_img.sh`) | 0.72.0 | native, ~30 s/recipe — iterate here first |
| linux-64 | `pixi-amd64` (`docker run --platform linux/amd64 ...`, see skill reference) | 0.76.1 | emulated, ~4 min/recipe — run before committing |

```bash
docker exec -w /Users/lc/Dev/own/lc-forge pixi       bash -lc './scripts/rbuild.sh -r todo/<pkg> -f'
docker exec -w /Users/lc/Dev/own/lc-forge pixi-amd64 bash -lc './scripts/rbuild.sh -r todo/<pkg> -f'
```

- `docker exec -w` requires an absolute path.
- A recipe counts as verified only when **both** platforms print `✔ all tests passed!`.
  Log to `output/<pkg>-build*.log`, and read the full log when the tail is not enough.
- `rattler-build` is not on the host `PATH`: use `~/.pixi/bin/rattler-build` (0.76.1) or
  `/tmp/rb-shim/rattler-build` for render-only checks.
- `scns` carries `linux-64`/`linux-aarch64` only and CI never falls back to conda-forge:
  before writing a recipe, confirm every build/host dependency exists in the channel
  (fetch `https://prefix.dev/scns/<subdir>/repodata.json` **from inside a container** —
  the host `curl` returns an empty 303) and report what is missing instead of guessing.
- Clean up scratch before reporting done: `output/*.log`,
  `output/bld/rattler-build_<pkg>_*`, `output/test/test_<pkg>*` (~500 MB each, gitignored).
- Recurring traps — full catalog in the `recipe-migrator` skill,
  `references/local-build-debug.md`: the 255-character `$PREFIX` placeholder vs
  `sun_path`/256-byte path buffers under `-Werror`; configure forcing `/etc` + `/var`
  without `--enable-strict-locations`; missing `crypt.h` (add `libxcrypt`) and absent
  `pam`; install hooks needing `mkdir -p "$PREFIX/etc/<dir>"` first; `sbin` not on the
  test environment's `PATH`; ncurses symlink loops that only appear on the macOS
  bind mount (CI is unaffected).

## Style

- Prefer `recipe.yaml` (v1 schema) over `meta.yaml`.
- All bash scripts: `set -Eeuo pipefail`, source `lib/common.sh` for shared
  helpers (`resolve_recipe_dir`, `build_channel_args`, `crm_convert`, etc).
- `output/` is gitignored. Final build authority is GitHub Actions, not local.

## CI

- Workflows: `.github/workflows/build.yml` (on push/PR), `import-recipe.yml`
  (manual trigger to fetch a recipe from conda-forge and build it).
- Runs in `ghcr.io/fsslc/pixi:latest` container.
- Default channel: `https://prefix.dev/scns`.

## 中文提示 (Chinese Prompts)

以下是上述文档的中文翻译和提示，便于中文用户参考和使用：

### 简介
个人 conda/rattler-build 配方仓库。包会被构建到 prefix.dev (`scns`) 上的自定义频道。

### 布局
- `recipes/` — 成功构建的配方（不再被 CI 重新构建）。
- `todo/` — 正在积极开发的配方。在推送到 `main` 的 push/PR 时，CI 会为 `linux-64` 和 `linux-aarch64` 构建所有内容。
- `only-meta.txt` — 其 `meta.yaml` 无法自动转换为 `recipe.yaml` 的包；CI 使用 `conda build` 而不是 `rattler-build` 构建它们。
- `conda_build_config.yaml` — 全局构建矩阵、pin、编译器版本（gcc 11，CentOS 7 sysroot / glibc 2.17）。

### 工作流
1. `./scripts/prep.sh <pkg>` — 将 conda-forge feedstock 克隆到 `todo/<pkg>`，尝试 `meta.yaml → recipe.yaml` 转换。如果失败，则将包追加到 `only-meta.txt`（不写入 `recipe.yaml`）。
2. 在 `todo/<pkg>` 中迭代。
3. CI 在推送/ PR 触及 `todo/` 时自动构建。成功构建上传到 `https://prefix.dev/scns`。
4. CI 成功后，归档到 `recipes/`：`mkdir -p recipes && git mv todo/<pkg> recipes/<pkg>`

### 命令
所有脚本使用 `-r <recipe_dir>`（相对路径从仓库根目录解析）。

| 任务 | 命令 |
|---|---|
| `meta.yaml` → `recipe.yaml` | `./scripts/crm.sh -r todo/<pkg>` |
| 渲染 (conda) | `./scripts/crender.sh -r todo/<pkg>` |
| 渲染 (rattler) | `./scripts/rrender.sh -r todo/<pkg>` |
| 构建 (conda) | `./scripts/cbuild.sh -r todo/<pkg>` |
| 构建 (rattler) | `./scripts/rbuild.sh -r todo/<pkg>` |
| 设置工具 | `./scripts/setup_pixi.sh` |
| Docker 环境 | `./scripts/start_img.sh` |

标志：`-f` 强制重建，`-c <channel>` 额外频道，`--` 传递参数。

`EXTRA_CHANNELS` 环境变量（空格/逗号分隔）添加频道而不使用标志。

Docker 容器自动注入 `HOST_UID`/`HOST_GID`；构建脚本调用 `fix_output_owner` 以使 `output/` 文件属于主机用户。

### 本地构建与调试

本地验证一律**在 Docker 容器里**做，不在 macOS 宿主机上做：

| 平台 | 容器 | rattler-build | 代价 |
|---|---|---|---|
| linux-aarch64 | `pixi`（`./scripts/start_img.sh`） | 0.72.0 | 原生执行，单个 recipe 约 30s —— 先在这里迭代 |
| linux-64 | `pixi-amd64`（`docker run --platform linux/amd64 ...`，建法见 skill 参考文档） | 0.76.1 | x86 仿真，单个 recipe 约 4min —— 提交前跑 |

```bash
docker exec -w /Users/lc/Dev/own/lc-forge pixi       bash -lc './scripts/rbuild.sh -r todo/<pkg> -f'
docker exec -w /Users/lc/Dev/own/lc-forge pixi-amd64 bash -lc './scripts/rbuild.sh -r todo/<pkg> -f'
```

- `docker exec -w` 必须给绝对路径。
- 只有**两个平台**都输出 `✔ all tests passed!` 才算验证通过。日志写到
  `output/<pkg>-build*.log`，只看尾部不够时读全量日志。
- 宿主机 `PATH` 里没有 `rattler-build`：只做渲染检查时用
  `~/.pixi/bin/rattler-build`（0.76.1）或 `/tmp/rb-shim/rattler-build`。
- `scns` 只有 `linux-64`/`linux-aarch64`，CI 也不会回落到 conda-forge：写 recipe 前先确认
  每个 build/host 依赖都在通道里（在**容器内**拉
  `https://prefix.dev/scns/<subdir>/repodata.json`，宿主机 curl 会拿到空的 303 重定向），
  缺什么就报告什么，不要猜。
- 收尾前清理临时文件：`output/*.log`、`output/bld/rattler-build_<pkg>_*`、
  `output/test/test_<pkg>*`（每个约 500MB，gitignored）。
- 反复踩到的坑——完整清单一律见 `recipe-migrator` skill 的
  `references/local-build-debug.md`：255 字符 `$PREFIX` 占位符与 `sun_path`/256 字节路径缓冲
  在 `-Werror` 下冲突；configure 不传 `--enable-strict-locations` 就把安装目录强设成
  `/etc` + `/var`；sysroot 缺 `crypt.h`（补 `libxcrypt`）、通道无 `pam`；安装钩子前需要先
  `mkdir -p "$PREFIX/etc/<dir>"`；测试环境 `PATH` 里没有 `sbin`；ncurses 软链自指环只在
  macOS bind mount 上出现（CI 不受影响）。

### 风格
- 优先使用 `recipe.yaml` (v1 schema) 而非 `meta.yaml`。
- 所有 bash 脚本：`set -Eeuo pipefail`，source `lib/common.sh` 以获取共享助手（`resolve_recipe_dir`、`build_channel_args`、`crm_convert` 等）。
- `output/` 被 gitignore。最终构建权限是 GitHub Actions，而非本地。

### CI
- 工作流：`.github/workflows/build.yml`（在 push/PR 上），`import-recipe.yml`（手动触发从 conda-forge 拉取配方并构建）。
- 在 `ghcr.io/fsslc/pixi:latest` 容器中运行。
- 默认频道：`https://prefix.dev/scns`。
