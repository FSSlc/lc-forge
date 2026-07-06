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
./scripts/crm.sh todo/<package>
```

渲染 recipe：

```bash
./scripts/crender.sh todo/<package>
./scripts/rrender.sh todo/<package>
```

本地构建 recipe：

```bash
./scripts/rbuild.sh -r todo/<package>
./scripts/cbuild.sh -r todo/<package>
```

强制重建可追加 `-f`，额外 channel 可追加 `-c <channel>`。构建输出默认写入 `output/`，正式结果以 GitHub Actions 为准。

## 脚本速查

| 脚本 | 用途 |
| --- | --- |
| `setup_pixi.sh` | 安装 pixi 和常用构建工具。 |
| `start_img.sh` | 启动 `ghcr.io/fsslc/pixi:<tag>` 容器。 |
| `prep.sh` | 从 conda-forge feedstock 准备 recipe。 |
| `crm.sh` | 转换 `meta.yaml` 为 `recipe.yaml`。 |
| `crender.sh` | 使用 `conda render` 渲染 recipe。 |
| `rrender.sh` | 使用 `rattler-build --render-only` 渲染 recipe。 |
| `cbuild.sh` | 使用 `conda build` 构建 recipe。 |
| `rbuild.sh` | 使用 `rattler-build` 构建 recipe。 |

## 维护提醒

- 提交前检查 source、license、test、run_exports 和 pinning。
- `scripts/prep.sh` 会访问网络，并可能覆盖已有 `todo/<package_name>`。
- `scripts/setup_pixi.sh` 会更新当前用户的 `~/.bashrc`。
- 修改脚本后可运行语法检查：

```bash
for f in scripts/*.sh; do bash -n "$f" || exit 1; done
```
