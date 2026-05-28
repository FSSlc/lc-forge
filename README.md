# lc-forge

`lc-forge` 是一个个人维护的 conda/rattler-build recipe 仓库，用来收集、改造和构建一批软件包。仓库里的核心内容是 `recipes/` 下的包构建配方，以及 `scripts/` 下用于准备、渲染、转换和构建 recipe 的辅助脚本。

默认构建配置来自 [conda_build_config.yaml](conda_build_config.yaml)，其中定义了编译器、sysroot、Python、BLAS、C/C++/Fortran/Go/Rust 等构建矩阵和 pinning 规则。默认依赖 channel 为 `https://prefix.dev/scns`。

当前待构建 recipe 使用 GitHub Actions 自动构建 `linux-64` 和 `linux-aarch64` 两种架构的 conda 包。

当前默认使用的编译器是默认 channel 中的 gcc 11.2.0 版本，构建环境是 centos 7.9 的环境，尽可能保证 glibc 2.17 的兼容性。

## 目录结构

- `recipes/`：已通过构建验证的 recipe 目录。每个子目录通常包含 `recipe.yaml`、`meta.yaml`、`build.sh`、patch 或其他构建文件。
- `scripts/`：本仓库的本地工作流脚本，包括 build、render、feedstock 准备和 Docker/pixi 环境启动。
- `conda_build_config.yaml`：全局构建变体和依赖 pinning 配置。
- `pkgs/`：本地源码包或缓存文件，通常不作为通用工作流入口。
- `output/`：构建输出目录，由脚本自动创建，已在 `.gitignore` 中忽略。
- `todo/`：待构建和待修复的 recipe 工作区。GitHub Actions 主要监听这个目录下的有效内容变化。

## 环境准备

推荐使用 pixi 提供 `rattler-build`、`conda-build`、`conda-recipe-manager` 等工具：

```bash
./scripts/setup_pixi.sh
```

该脚本会安装 pixi，并通过 `pixi global install -e tools` 安装以下工具：

- `rattler-build`
- `conda-recipe-manager`
- `rattler-index`
- `conda`
- `conda-build`

如果不想直接在宿主机安装工具，也可以启动预置 Docker 镜像：

```bash
./scripts/start_img.sh
```

指定镜像 tag：

```bash
./scripts/start_img.sh latest
```

如果本地已有名为 `pixi` 的容器并希望重建：

```bash
./scripts/start_img.sh --force latest
```

## 新 recipe 工作流

### 1. 准备到 `todo/`

从 conda-forge 克隆指定 feedstock，复制其中的 `recipe/` 到本仓库 `todo/<package_name>`，并在存在 `meta.yaml` 时尝试转换为 `recipe.yaml`：

```bash
./scripts/prep.sh <package_name>
```

示例：

```bash
./scripts/prep.sh zlib
```

说明：

- 包名只允许字母、数字、点、下划线和连字符。
- 原始 feedstock 会移动到仓库上级目录的 `../refers/` 下，方便后续参考。

### 2. 提交并让 GitHub Actions 构建

新 recipe 先保留在 `todo/<package_name>` 下，提交后由 GitHub Actions 构建。当前 workflow 会构建 `linux-64` 和 `linux-aarch64`，并且只在 `todo/` 下存在有效新增或修改时触发构建。

如果构建失败，下一次提交应继续修改 `todo/<package_name>` 下的 recipe、patch 或构建脚本，再次触发 GitHub Actions 构建。

如果构建成功，下一次提交再把该目录从 `todo/<package_name>` 移动到 `recipes/<package_name>`。纯粹从 `todo/` 移动到 `recipes/` 不会触发新的构建 action。

### 3. 成功后归档到 `recipes/`

构建成功后移动目录：

```bash
mkdir -p recipes
git mv todo/<package_name> recipes/<package_name>
```

`recipes/` 表示已通过当前自动构建流程的 recipe 集合；后续如果要重新构建或修复某个包，可以再把修改放回 `todo/` 或直接在 `todo/` 中准备新的修复版本。

## 本地辅助命令

### 转换 `meta.yaml` 到 `recipe.yaml`

对已有 recipe 目录执行转换：

```bash
./scripts/crm.sh todo/<package>
```

脚本会先写入临时文件，转换成功后再覆盖 `recipe.yaml`，避免转换失败时截断已有文件。

### 渲染 recipe

使用 `conda render`：

```bash
./scripts/crender.sh todo/<package>
```

使用 `rattler-build --render-only`：

```bash
./scripts/rrender.sh todo/<package>
```

### 本地构建 recipe

正式验证以 GitHub Actions 为准。本地构建脚本主要用于快速调试单个 recipe。

使用 `rattler-build` 构建，默认跳过已存在包：

```bash
./scripts/rbuild.sh -r todo/<package>
```

强制重新构建已存在包：

```bash
./scripts/rbuild.sh -r todo/<package> -f
```

追加额外 channel：

```bash
./scripts/rbuild.sh -r todo/<package> -c conda-forge -c https://prefix.dev/scns
```

使用 `conda build` 构建：

```bash
./scripts/cbuild.sh -r todo/<package>
```

强制重新构建已存在包：

```bash
./scripts/cbuild.sh -r todo/<package> -f
```

构建输出默认写入 `output/`。

## 脚本速查

| 脚本 | 用途 |
| --- | --- |
| `scripts/setup_pixi.sh` | 安装 pixi 和构建工具链。 |
| `scripts/start_img.sh` | 拉取并启动 `ghcr.io/fsslc/pixi:<tag>` 容器。 |
| `scripts/prep.sh` | 从 conda-forge feedstock 准备本地 recipe。 |
| `scripts/crm.sh` | 使用 `conda-recipe-manager` 转换 `meta.yaml` 到 `recipe.yaml`。 |
| `scripts/crender.sh` | 使用 `conda render` 渲染 recipe。 |
| `scripts/rrender.sh` | 使用 `rattler-build --render-only` 渲染 recipe。 |
| `scripts/cbuild.sh` | 使用 `conda build` 构建 recipe。 |
| `scripts/rbuild.sh` | 使用 `rattler-build` 构建 recipe。 |

## 开发和维护建议

新增或修改 recipe 时，推荐按以下顺序操作：

1. 使用 `scripts/prep.sh <package_name>` 将 recipe 准备到 `todo/<package_name>`。
2. 在 `todo/<package_name>` 下修改 `recipe.yaml`、`build.sh`、patch 等文件。
3. 提交 `todo/` 下的变更，让 GitHub Actions 构建新 recipe。
4. 如果 action 构建失败，下一次提交继续修复 `todo/<package_name>`。
5. 如果 action 构建成功，下一次提交将目录移动到 `recipes/<package_name>`。
6. 如果从旧 `meta.yaml` 迁移，先用 `scripts/crm.sh` 转换，再人工审查转换结果。

示例：

```bash
./scripts/prep.sh zlib
git add todo/zlib
git commit -m "Prepare zlib recipe for CI build"

# CI 成功后：
git mv todo/zlib recipes/zlib
git commit -m "Archive passing zlib recipe"
```

## 检查脚本

修改 `scripts/` 下脚本后，至少运行 Bash 语法检查：

```bash
for f in scripts/*.sh; do bash -n "$f" || exit 1; done
```

如果本机安装了 ShellCheck，建议再运行静态检查：

```bash
shellcheck scripts/*.sh
```

## 注意事项

- `scripts/setup_pixi.sh` 会修改当前用户的 `~/.bashrc`，但 completion 行会幂等写入。
- `scripts/start_img.sh` 使用固定容器名 `pixi`。如果已有同名容器，可使用 `--force` 删除并重建。
- `scripts/prep.sh` 会克隆网络仓库，并可能覆盖 `todo/<package_name>`。
- 构建脚本默认跳过已存在包；使用 `-f` 表示强制重建。
- 本仓库偏向本地维护和实验性质，提交 recipe 前应逐个检查 source、license、test、run_exports 和 pinning 是否符合目标 channel 的要求。
