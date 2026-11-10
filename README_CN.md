# lc-forge

个人维护的 conda/rattler-build recipe 仓库，用于收集、改造和构建软件包。

主要内容：

- `recipes/`：已通过构建验证的 recipe。
- `todo/`：待构建或待修复的 recipe，GitHub Actions 主要监听此目录。
- `scripts/`：本地准备、转换、渲染和构建脚本。
- `conda_build_config.yaml`：全局构建矩阵、pinning 和默认配置。
- `output/`：本地构建输出，已忽略提交。

默认依赖 channel 为 `https://prefix.dev/scns`。当前 CI 构建 `linux-64` 和 `linux-aarch64`，默认使用 gcc 11.2.0 与 CentOS 7.9 环境，以尽量保持 glibc 2.17 兼容性。

## 环境准备

推荐使用 pixi 安装构建工具：

```bash
./scripts/setup_pixi.sh
```

如需使用预置 Docker 镜像：

```bash
./scripts/start_img.sh [--force] [tag]
```

容器启动时会自动注入 `HOST_UID` / `HOST_GID`，与 `cbuild.sh` / `rbuild.sh` 中的 `fix_output_owner` 配合，确保 `output/` 目录属主与宿主机一致。可用 `IMAGE_REPO` 和 `CONTAINER_NAME` 环境变量覆盖默认镜像和容器名。

## Recipe 工作流

准备新 recipe：

```bash
./scripts/prep.sh <package_name>
```

该脚本会从 conda-forge feedstock 复制 recipe 到 `todo/<package_name>`，并在可用时尝试把 `meta.yaml` 转为 `recipe.yaml`。

提交 `todo/<package_name>` 后由 GitHub Actions 构建。构建失败时继续修改 `todo/` 下的 recipe；构建成功后再归档到 `recipes/`：

```bash
mkdir -p recipes
git mv todo/<package_name> recipes/<package_name>
```

## 常用命令

转换旧格式 recipe：

```bash
./scripts/crm.sh -r todo/<package>
```

渲染 recipe：

```bash
./scripts/crender.sh -r todo/<package>
./scripts/rrender.sh -r todo/<package>
```

本地构建 recipe：

```bash
./scripts/rbuild.sh -r todo/<package>
./scripts/cbuild.sh -r todo/<package>
```

所有 recipe 脚本统一用 `-r <recipe_dir>` 指定 recipe 目录。强制重建可追加 `-f`，额外 channel 可追加 `-c <channel>`，也可用环境变量 `EXTRA_CHANNELS`（空格或逗号分隔）统一附加 channel。`--` 之后的参数会透传给底层工具。构建输出默认写入 `output/`（可用 `OUTPUT_DIR` 覆盖），正式结果以 GitHub Actions 为准。

```bash
./scripts/rbuild.sh -r todo/<package> -c conda-forge -- --verbose
EXTRA_CHANNELS="conda-forge,bioconda" ./scripts/rrender.sh -r todo/<package>
```

构建失败时，`rbuild.sh` / `cbuild.sh` 会把构建日志交给 OpenAI 兼容接口（`AI_API_BASE_URL`、`AI_API_KEY`、`AI_MODEL_NAME`，任一缺失即不启用 AI 修复），由 AI 修改 recipe 后重建，默认总共构建 3 次。`-n <rounds>` 可改该上限（也可用环境变量 `AI_MAX_FIX_ROUNDS`），`-i` 则在每轮 AI 修复前先确认。每次尝试都会写入 `logs/build-<recipe>-<timestamp>.log`，也是交给 AI 的日志。AI 改动最终仍无法让构建通过时，recipe 回滚到修复前内容。该功能只支持单个 recipe 目录，`-r todo` 这类目录构建只报告失败、不调用 AI。

AI 配置优先取环境变量，其次取仓库根的 `.env`：把 `.env.example` 复制为 `.env`，填好 `AI_API_BASE_URL` / `AI_API_KEY` / `AI_MODEL_NAME`（可选 `AI_MAX_FIX_ROUNDS`）即可，无需再 export。已经在 shell 里导出的同名变量始终优先于 `.env`；文件里只认这四个键；`.env` 已被 git 忽略，不要提交真实密钥。

## 脚本速查

| 脚本 | 用途 |
| --- | --- |
| `setup_pixi.sh` | 安装 pixi 和常用构建工具（可重复执行）。 |
| `start_img.sh` | 启动 `ghcr.io/fsslc/pixi:<tag>` 容器。 |
| `prep.sh` | 从 conda-forge feedstock 准备 recipe。 |
| `crm.sh` | 转换 `meta.yaml` 为 `recipe.yaml`。 |
| `crender.sh` | 使用 `conda render` 渲染 recipe。 |
| `rrender.sh` | 使用 `rattler-build --render-only` 渲染 recipe。 |
| `cbuild.sh` | 使用 `conda build` 构建 recipe。 |
| `rbuild.sh` | 使用 `rattler-build` 构建 recipe。 |
| `lib/common.sh` | 脚本共享逻辑（路径解析、channel、crm convert 等）。 |

## 维护提醒

- 提交前检查 source、license、test、run_exports 和 pinning。
- `scripts/prep.sh` 会访问网络，并可能覆盖已有 `todo/<package_name>`。
- `scripts/setup_pixi.sh` 会更新当前用户的 `~/.bashrc` / `~/.zshrc`（PATH 与 completion）。
- 修改脚本后可运行语法检查：

```bash
for f in scripts/*.sh scripts/lib/*.sh; do bash -n "$f" || exit 1; done
```
